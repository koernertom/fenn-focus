import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers

/// Runs a downloaded model (see `LocalModels`) with MLX on Apple Silicon – nothing leaves the Mac.
/// A model loads on first use and stays in memory; under 24 GB only one stays loaded at a time.
actor LocalBrain {
    static let shared = LocalBrain()

    struct Reply: Sendable {
        var text: String
        var calls: [ToolCall]
    }

    private var containers: [String: ModelContainer] = [:]
    private var loading: [String: Task<ModelContainer, Error>] = [:]

    func container(_ choice: String) async throws -> ModelContainer {
        guard let (id, directory) = LocalModels.resolve(choice) else { throw AIError.notConfigured }
        if let ready = containers[id] { return ready }
        if let running = loading[id] { return try await running.value }
        if ProcessInfo.processInfo.physicalMemory < 24 * 1024 * 1024 * 1024 { containers.removeAll() }
        MLX.GPU.set(cacheLimit: 256 * 1024 * 1024)
        let task = Task { try await LLMModelFactory.shared.loadContainer(from: directory, using: TransformersTokenizerLoader()) }
        loading[id] = task
        defer { loading[id] = nil }
        let container = try await task.value
        containers[id] = container
        return container
    }

    /// One turn: the conversation so far (system first), optional tools in OpenAI function format.
    func respond(_ messages: [Chat.Message], tools: [ToolSpec]? = nil, choice: String, maxTokens: Int = 1200) async throws -> Reply {
        let container = try await container(choice)
        // Qwen 3.5/3.8 think out loud by default – Fenn wants the answer, not the scratchpad (faster, fewer loops).
        let input = UserInput(chat: messages, tools: tools, additionalContext: ["enable_thinking": false])
        let prepared = try await container.prepare(input: input)
        // Qwen's recommended sampling for non-thinking use.
        var parameters = GenerateParameters(maxTokens: maxTokens, temperature: 0.7, topP: 0.8)
        parameters.topK = 20
        var text = ""
        var calls: [ToolCall] = []
        for await event in try await container.generate(input: prepared, parameters: parameters, tools: tools) {
            try Task.checkCancellation()
            switch event {
            case .chunk(let chunk): text += chunk
            case .toolCall(let call): calls.append(call)
            case .info, .rejectedToolCall: break
            }
        }
        return Reply(text: text, calls: calls)
    }

    func unload() {
        containers.removeAll()
        MLX.GPU.clearCache()
    }
}

/// swift-transformers' tokenizer behind mlx-swift-lm's protocol (what the MLXHuggingFace macro would generate).
struct TransformersTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        TransformersTokenizer(try await Tokenizers.AutoTokenizer.from(modelFolder: directory))
    }
}

private struct TransformersTokenizer: MLXLMCommon.Tokenizer {
    let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) { self.upstream = upstream }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] { upstream.encode(text: text, addSpecialTokens: addSpecialTokens) }
    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String { upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens) }
    func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }
    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(messages: [[String: any Sendable]], tools: [[String: any Sendable]]?,
                           additionalContext: [String: any Sendable]?) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(messages: messages, tools: tools, additionalContext: additionalContext)
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}

// MARK: - Bridges for FennAI and the agent

enum LocalBrainBridge {
    /// A plain completion (notes, summaries, the agent's JSON fallback).
    static func complete(system: String, messages: [AIMessage], maxTokens: Int, choice: String) async throws -> String {
        let chat: [Chat.Message] = [.system(system)] + messages.map { $0.role == .user ? .user($0.text) : .assistant($0.text) }
        let reply = try await LocalBrain.shared.respond(chat, choice: choice, maxTokens: maxTokens)
        return reply.text
    }

    /// One agent step with native tool calls (the model family's own format, parsed by mlx-swift-lm).
    static func step(system: String, entries: [AgentEntry], tools: [AgentTool], choice: String) async throws -> AgentStep {
        var chat: [Chat.Message] = [.system(system)]
        for entry in entries {
            switch entry {
            case .user(let text): chat.append(.user(text))
            case .assistant(let text, let calls):
                let mapped = calls.map { ToolCall(function: .init(name: $0.name, arguments: $0.arguments.mapValues { Self.sendable($0) })) }
                chat.append(.assistant(text, toolCalls: mapped.isEmpty ? nil : mapped))
            case .result(let call, let text): chat.append(.tool(text, id: call.id, name: call.name))
            }
        }
        let specs: [ToolSpec] = tools.map { tool in
            ["type": "function", "function": ["name": tool.name, "description": tool.description,
                                              "parameters": Self.sendable(tool.parameters)] as [String: any Sendable]]
        }
        let reply = try await LocalBrain.shared.respond(chat, tools: specs, choice: choice)
        let calls = reply.calls.enumerated().map { index, call in
            AgentCall(id: "brain-\(index)-\(UUID().uuidString.prefix(6))", name: call.function.name,
                      arguments: Self.plain(call.function.arguments))
        }
        return AgentStep(text: reply.text, calls: calls)
    }

    /// The parsed arguments back as plain Foundation values for the tools.
    private static func plain(_ arguments: [String: JSONValue]) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(arguments),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }

    /// JSON-ish values from the agent's [String: Any] world into Sendable ones for the chat template.
    private static func sendable(_ value: Any) -> any Sendable {
        switch value {
        case let string as String: return string
        case let bool as Bool: return bool
        case let int as Int: return int
        case let double as Double: return double
        case let array as [Any]: return array.map { sendable($0) }
        case let dict as [String: Any]: return dict.mapValues { sendable($0) }
        default: return String(describing: value)
        }
    }
}
