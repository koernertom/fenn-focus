import Foundation
import Security
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Which model answers. Local first: a downloaded model run by Fenn Focus itself (MLX), Ollama, LM Studio or Apple's
/// on-device model. Cloud models are optional and use the person's own key: Claude, OpenRouter or any OpenAI-compatible
/// server. Chosen once in the settings; every feature goes through `FennAI`.
enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case fennBrain
    case ollama
    case lmStudio
    case apple
    case claude
    case openRouter
    case openAICompatible

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AIProvider(rawValue: raw) ?? .fennBrain
    }

    var title: String {
        switch self {
        case .claude: return "Claude"
        case .openRouter: return "OpenRouter"
        case .openAICompatible: return tr("OpenAI-kompatibel", "OpenAI-compatible")
        case .fennBrain: return tr("Eingebaut", "Built-in")
        case .ollama: return "Ollama"
        case .lmStudio: return "LM Studio"
        case .apple: return tr("Apple (auf dem Gerät)", "Apple (on device)")
        }
    }

    var detail: String {
        switch self {
        case .claude: return tr("Anthropic-API-Schlüssel, beste Qualität, liest Fotos", "Anthropic API key, best quality, reads photos")
        case .openRouter: return tr("Ein Schlüssel für Sprach- und Bildmodelle auf OpenRouter", "One key for language and vision models on OpenRouter")
        case .openAICompatible: return tr("OpenAI, vLLM, Groq … – eigene URL, Modell und Schlüssel", "OpenAI, vLLM, Groq … – your URL, model and key")
        case .fennBrain: return tr("Fenn Focus lädt ein offenes Modell und führt es selbst aus – offline, auf Apple Silicon", "Fenn Focus downloads an open model and runs it itself – offline, on Apple Silicon")
        case .ollama: return tr("Nutzt die Modelle deines Ollama auf diesem Mac", "Uses the models of your Ollama on this Mac")
        case .lmStudio: return tr("Nutzt das Modell, das in LM Studio geladen ist (lokaler Server an)", "Uses the model loaded in LM Studio (local server on)")
        case .apple: return tr("Apple Intelligence, offline – ohne Fotoanalyse", "Apple Intelligence, offline – no photo analysis")
        }
    }

    static var offered: [AIProvider] { allCases }

    /// Runs on this Mac (or the person's own server) – no key, no consent needed.
    var isLocalKind: Bool { [.fennBrain, .ollama, .lmStudio, .apple].contains(self) }

    var needsKey: Bool { self == .claude || self == .openRouter }
    var acceptsKey: Bool { self == .claude || self == .openAICompatible || self == .openRouter }
    var hasEndpoint: Bool { self == .openAICompatible || self == .ollama || self == .lmStudio }

    var defaultBaseURL: String {
        switch self {
        case .claude: return "https://api.anthropic.com"
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .openAICompatible: return "http://localhost:8000/v1"
        case .ollama: return "http://localhost:11434"
        case .lmStudio: return "http://localhost:1234/v1"
        case .fennBrain, .apple: return ""
        }
    }

    var defaultModel: String {
        switch self {
        case .claude: return "claude-sonnet-5"
        case .openRouter: return "google/gemini-2.5-flash"
        case .openAICompatible, .ollama, .lmStudio: return ""
        case .fennBrain: return "auto"
        case .apple: return ""
        }
    }

    /// Whether Fenn may send photos (screenshots, whiteboards). Depends on the model for the open ones.
    var canSeeImages: Bool { self != .apple && self != .fennBrain && self != .lmStudio }

    /// Keychain account for the key; Claude keeps the account used before providers existed.
    var keychainAccount: String? {
        switch self {
        case .claude: return "anthropic-api-key"
        case .openRouter: return "openrouter-api-key"
        case .openAICompatible: return "ai-openai-compatible-key"
        case .fennBrain, .ollama, .lmStudio, .apple: return nil
        }
    }
}

struct AIConfig: Codable, Equatable {
    var provider: AIProvider
    var baseURL: String
    var model: String

    static let defaultsKey = "fenn.ai.config"

    /// Nothing chosen yet: a downloaded model if there is one, else Apple's on-device model, else the built-in choice
    /// (which offers the download). Never a cloud provider by default.
    static var fallback: AIConfig {
        if !FennAI.brainAvailable, FennAI.appleModelAvailable { return AIConfig(provider: .apple, baseURL: "", model: "") }
        return AIConfig(provider: .fennBrain, baseURL: "", model: AIProvider.fennBrain.defaultModel)
    }

    static var current: AIConfig {
        get {
            let saved = UserDefaults.standard.data(forKey: defaultsKey).flatMap { try? JSONDecoder().decode(AIConfig.self, from: $0) }
            guard let saved, AIProvider.offered.contains(saved.provider) else { return fallback }
            return saved
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: defaultsKey)
        }
    }

    var trimmedBase: String {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        return base.isEmpty ? provider.defaultBaseURL : base
    }

    var trimmedModel: String {
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.isEmpty ? provider.defaultModel : model
    }
}

struct AIMessage {
    enum Role: String { case user, assistant }
    var role: Role
    var text: String
    /// JPEG data; only sent to providers that can see images.
    var images: [Data] = []
}

enum AIError: LocalizedError {
    case notConfigured
    case cloudConsentMissing
    case imagesUnsupported
    case invalidResponse
    case http(Int, String)

    /// Worth a second try: a garbled answer or an overloaded server.
    var isRetryable: Bool {
        switch self {
        case .invalidResponse: return true
        case .http(let code, _): return code == 429 || code >= 500
        default: return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return tr("Kein KI-Modell eingerichtet. Wähle eins in den Einstellungen unter „KI-Modell“.",
                      "No AI model set up yet. Pick one in the settings under “AI model”.")
        case .cloudConsentMissing:
            return tr("Bevor Fenn Daten an \(AIConfig.current.provider.title) sendet, brauchst du einmal deine Zustimmung – unter „KI-Modell“.",
                      "Before Fenn sends data to \(AIConfig.current.provider.title), please agree once under “AI model”.")
        case .imagesUnsupported:
            return tr("Das gewählte Modell kann keine Fotos lesen. Beschreib es kurz in Worten.",
                      "The chosen model can't read photos. Describe it in a few words.")
        case .invalidResponse:
            return tr("Die Antwort des Modells war unvollständig. Versuch es noch einmal.",
                      "The model's reply was incomplete. Please try again.")
        case .http(let code, let message):
            let provider = AIConfig.current.provider
            if message.isEmpty { return tr("\(provider.title) antwortet nicht (HTTP \(code)).", "\(provider.title) isn't answering (HTTP \(code)).") }
            // Anthropic answers 403 when the key, its workspace or the network (VPN, region) isn't allowed.
            if provider == .claude, code == 403 {
                return tr("Claude lehnt die Anfrage ab (\(message), HTTP 403). Prüf in der Anthropic-Konsole Schlüssel, Workspace und Guthaben, und schalt ein VPN aus. Unter „KI-Modell“ kannst du die Verbindung testen.",
                          "Claude refuses the request (\(message), HTTP 403). Check key, workspace and credit in the Anthropic console, and turn off any VPN. You can test the connection under “AI model”.")
            }
            return "\(provider.title): \(message)" + (code > 0 ? " (HTTP \(code))" : "")
        }
    }
}

enum FennAI {
    // MARK: Keys

    private static let keychainService = "app.fennfocus"

    static func apiKey(for provider: AIProvider) -> String? {
        guard let account = provider.keychainAccount else { return nil }
        var query = keyQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    static func setAPIKey(_ key: String?, for provider: AIProvider) {
        guard let account = provider.keychainAccount else { return }
        SecItemDelete(keyQuery(account) as CFDictionary)
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return }
        var attributes = keyQuery(account)
        attributes[kSecValueData as String] = Data(trimmed.utf8)
        // ThisDeviceOnly: keys never move into backups or onto another device.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    /// Other secrets the user pastes in (e.g. the USDA FoodData Central key), same Keychain rules as model keys.
    static func secret(_ account: String) -> String? {
        var query = keyQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let value = String(data: data, encoding: .utf8), !value.isEmpty else { return nil }
        return value
    }

    static func setSecret(_ value: String?, for account: String) {
        SecItemDelete(keyQuery(account) as CFDictionary)
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return }
        var attributes = keyQuery(account)
        attributes[kSecValueData as String] = Data(trimmed.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private static func keyQuery(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: account]
    }

    // MARK: State

    static var isConfigured: Bool { isConfigured(AIConfig.current) }

    static func isConfigured(_ config: AIConfig) -> Bool {
        switch config.provider {
        case .claude: return apiKey(for: .claude) != nil
        case .openRouter: return apiKey(for: .openRouter) != nil && !config.trimmedModel.isEmpty
        case .openAICompatible, .ollama, .lmStudio: return !config.trimmedModel.isEmpty
        case .fennBrain: return brainAvailable
        case .apple: return appleModelAvailable
        }
    }

    static var canSeeImages: Bool { AIConfig.current.provider.canSeeImages }

    /// Small on-device models get fewer tools per step (see `FennAgent.focusTools`).
    static var prefersFewTools: Bool { AIConfig.current.provider.isLocalKind }

    /// Shown next to results, e.g. "Claude, claude-sonnet-5" or "Ollama, qwen3.5:4b".
    static var engineLabel: String {
        let config = AIConfig.current
        return config.provider == .apple ? "Apple Intelligence" : "\(config.provider.title), \(config.trimmedModel)"
    }

    /// Local means nothing leaves the person's own devices or server.
    static var isLocal: Bool { isLocal(AIConfig.current) }

    static func isLocal(_ config: AIConfig) -> Bool {
        switch config.provider {
        case .apple, .fennBrain: return true
        case .claude, .openRouter: return false
        case .openAICompatible, .ollama, .lmStudio:
            let host = URL(string: config.trimmedBase)?.host ?? ""
            return host == "localhost" || host == "127.0.0.1" || host.hasSuffix(".local") || host.hasPrefix("192.168.") || host.hasPrefix("10.")
        }
    }

    // MARK: Consent

    /// Journal entries and notes are personal: a cloud model only gets them after an explicit yes,
    /// which can be withdrawn at any time. Local models (built-in, Ollama, LM Studio, Apple, your own network) need none.
    static let cloudConsentKey = "fenn.ai.cloudConsent.v1"

    static var hasCloudConsent: Bool {
        get { UserDefaults.standard.bool(forKey: cloudConsentKey) }
        set { UserDefaults.standard.set(newValue, forKey: cloudConsentKey) }
    }

    static func needsConsent(_ config: AIConfig = .current) -> Bool { !isLocal(config) && !hasCloudConsent }

    /// What exactly leaves the device – shown next to the consent switch.
    static func consentText(_ config: AIConfig = .current) -> String {
        tr("Fenn sendet deine Fragen und – je nach Funktion – Journal-Einträge, Ziele, Aufgaben, Notizen und Termine an \(config.provider.title), damit das Modell antworten kann. Der Anbieter verarbeitet sie nach seinen eigenen Datenschutzbestimmungen, ggf. außerhalb der EU. Widerruf jederzeit hier.",
           "Fenn sends your questions and – depending on the feature – journal entries, goals, tasks, notes and calendar events to \(config.provider.title) so the model can reply. The provider processes them under its own privacy policy, possibly outside the EU. Withdraw any time here.")
    }

    /// A model has been downloaded (or `-FennModelDir` points at one).
    static var brainAvailable: Bool { LocalModels.isAvailable }

    static var appleModelAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    // MARK: Completion

    /// One request, one reply. Callers that need JSON ask for it in the prompt and extract it with `json(in:)`.
    /// `json: true` marks replies that must be JSON (kept for callers; the prompt asks for it).
    static func complete(system: String, messages: [AIMessage], maxTokens: Int = 1024, timeout: TimeInterval = 90,
                         json: Bool = false, config: AIConfig = .current) async throws -> String {
        guard isConfigured(config) else { throw AIError.notConfigured }
        if needsConsent(config) { throw AIError.cloudConsentMissing }
        if messages.contains(where: { !$0.images.isEmpty }) && !config.provider.canSeeImages { throw AIError.imagesUnsupported }
        switch config.provider {
        case .claude: return try await claude(system: system, messages: messages, maxTokens: maxTokens, timeout: timeout, config: config)
        case .openAICompatible, .openRouter, .lmStudio: return try await openAI(system: system, messages: messages, maxTokens: maxTokens, timeout: timeout, config: config)
        case .ollama: return try await ollama(system: system, messages: messages, maxTokens: maxTokens, timeout: timeout, config: config)
        case .fennBrain:
            return stripThinking(try await LocalBrainBridge.complete(system: system, messages: messages, maxTokens: maxTokens, choice: config.trimmedModel))
        case .apple: return try await apple(system: system, messages: messages)
        }
    }

    /// Convenience for a single question.
    static func ask(_ prompt: String, system: String, images: [Data] = [], maxTokens: Int = 1024, timeout: TimeInterval = 90,
                    json: Bool = false) async throws -> String {
        try await complete(system: system, messages: [AIMessage(role: .user, text: prompt, images: images)], maxTokens: maxTokens,
                           timeout: timeout, json: json)
    }

    /// The first JSON object or array in a reply (models like to wrap it in prose or code fences).
    static func json(in reply: String) -> Data? {
        let open = reply.firstIndex { $0 == "{" || $0 == "[" }
        guard let open else { return nil }
        let closing: Character = reply[open] == "{" ? "}" : "]"
        guard let close = reply.lastIndex(of: closing), close > open else { return nil }
        return String(reply[open...close]).data(using: .utf8)
    }

    /// Checks the connection with a tiny request; returns a short human answer.
    static func test(_ config: AIConfig) async -> Result<String, Error> {
        do {
            let reply = try await complete(system: "Antworte mit genau einem Wort.", messages: [AIMessage(role: .user, text: "Sag: bereit")],
                                           maxTokens: 20, timeout: 60, config: config)
            return .success(reply.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40).description)
        } catch {
            return .failure(error)
        }
    }

    /// Model names the server offers (Ollama, LM Studio, OpenRouter, OpenAI-compatible servers); empty when unknown.
    static func availableModels(_ config: AIConfig) async -> [String] {
        switch config.provider {
        case .fennBrain:
            return ["auto"] + LocalModels.installed.map(\.id)
        case .ollama:
            guard let url = URL(string: config.trimmedBase + "/api/tags"),
                  let (data, _) = try? await URLSession.shared.data(for: request(url, timeout: 4)),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["models"] as? [[String: Any]] else { return [] }
            return models.compactMap { $0["name"] as? String }.sorted()
        case .openAICompatible, .openRouter, .lmStudio:
            guard let url = URL(string: config.trimmedBase + "/models") else { return [] }
            var req = request(url, timeout: 8)
            authorize(&req, config: config)
            guard let (data, _) = try? await URLSession.shared.data(for: req),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["data"] as? [[String: Any]] else { return [] }
            return models.compactMap { $0["id"] as? String }.sorted()
        case .claude:
            return ["claude-sonnet-5", "claude-opus-5-5", "claude-haiku-4-5-20251001"]
        case .apple:
            return []
        }
    }

    // MARK: Providers

    private static func claude(system: String, messages: [AIMessage], maxTokens: Int, timeout: TimeInterval, config: AIConfig) async throws -> String {
        guard let key = apiKey(for: .claude), let url = URL(string: config.trimmedBase + "/v1/messages") else { throw AIError.notConfigured }
        var req = request(url, timeout: timeout, method: "POST")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let body: [String: Any] = [
            "model": config.trimmedModel,
            "max_tokens": maxTokens,
            "system": system,
            "messages": messages.map { message -> [String: Any] in
                guard !message.images.isEmpty else { return ["role": message.role.rawValue, "content": message.text] }
                let images: [[String: Any]] = message.images.map {
                    ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": $0.base64EncodedString()]]
                }
                return ["role": message.role.rawValue, "content": images + [["type": "text", "text": message.text]]]
            }
        ]
        let json = try await post(req, body: body)
        guard let content = json["content"] as? [[String: Any]],
              let text = content.first(where: { $0["type"] as? String == "text" })?["text"] as? String else { throw AIError.invalidResponse }
        return text
    }

    private static func openAI(system: String, messages: [AIMessage], maxTokens: Int, timeout: TimeInterval, config: AIConfig) async throws -> String {
        guard let url = URL(string: config.trimmedBase + "/chat/completions") else { throw AIError.notConfigured }
        var req = request(url, timeout: timeout, method: "POST")
        authorize(&req, config: config)
        let chat: [[String: Any]] = [["role": "system", "content": system]] + messages.map { message in
            guard !message.images.isEmpty else { return ["role": message.role.rawValue, "content": message.text] }
            let images: [[String: Any]] = message.images.map {
                ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\($0.base64EncodedString())"]]
            }
            return ["role": message.role.rawValue, "content": [["type": "text", "text": message.text]] + images]
        }
        let json = try await post(req, body: ["model": config.trimmedModel, "max_tokens": maxTokens, "messages": chat])
        guard let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = messageText(message["content"]) else { throw AIError.invalidResponse }
        return stripThinking(text)
    }

    /// Ollama's own API: thinking off, the model kept warm for 30 minutes, Qwen's non-thinking sampling.
    private static func ollama(system: String, messages: [AIMessage], maxTokens: Int, timeout: TimeInterval, config: AIConfig) async throws -> String {
        let chat: [[String: Any]] = [["role": "system", "content": system]] + messages.map { message in
            var entry: [String: Any] = ["role": message.role.rawValue, "content": message.text]
            if !message.images.isEmpty { entry["images"] = message.images.map { $0.base64EncodedString() } }
            return entry
        }
        let json = try await ollamaChat(["messages": chat, "options": ollamaOptions(maxTokens: maxTokens)], timeout: timeout, config: config)
        guard let message = json["message"] as? [String: Any], let text = message["content"] as? String else { throw AIError.invalidResponse }
        return stripThinking(text)
    }

    static func ollamaOptions(maxTokens: Int) -> [String: Any] {
        ["num_predict": maxTokens, "num_ctx": 8192, "temperature": 0.7, "top_p": 0.8, "top_k": 20]
    }

    /// POST /api/chat, without streaming. Models that can't switch thinking off get the request again without `think`.
    static func ollamaChat(_ body: [String: Any], timeout: TimeInterval, config: AIConfig) async throws -> [String: Any] {
        guard let url = URL(string: config.trimmedBase + "/api/chat") else { throw AIError.notConfigured }
        var body = body
        body["model"] = config.trimmedModel
        body["stream"] = false
        body["keep_alive"] = "30m"
        body["think"] = false
        do {
            return try await post(request(url, timeout: timeout, method: "POST"), body: body)
        } catch AIError.http(let code, let message) where code == 400 && message.lowercased().contains("think") {
            body["think"] = nil
            return try await post(request(url, timeout: timeout, method: "POST"), body: body)
        }
    }

    private static func apple(system: String, messages: [AIMessage]) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            let session = LanguageModelSession(instructions: system)
            let transcript = messages.map { ($0.role == .user ? "" : "Fenn: ") + $0.text }.joined(separator: "\n\n")
            return try await session.respond(to: transcript).content
        }
        #endif
        throw AIError.notConfigured
    }

    // MARK: HTTP

    static func request(_ url: URL, timeout: TimeInterval, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        return request
    }

    /// The person's own key for OpenRouter or an OpenAI-compatible server; LM Studio needs none.
    static func authorize(_ request: inout URLRequest, config: AIConfig) {
        guard config.provider == .openRouter || config.provider == .openAICompatible else { return }
        if let key = apiKey(for: config.provider) { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        if config.provider == .openRouter { request.setValue("Fenn Focus", forHTTPHeaderField: "X-Title") }
    }

    /// Chat replies are a string, or a list of parts when a vision model answers.
    private static func messageText(_ content: Any?) -> String? {
        if let text = content as? String { return text }
        if let parts = content as? [[String: Any]] {
            let text = parts.compactMap { $0["text"] as? String }.joined()
            return text.isEmpty ? nil : text
        }
        return nil
    }

    static func post(_ request: URLRequest, body: [String: Any]) async throws -> [String: Any] {
        var request = request
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where [.unsupportedURL, .cannotFindHost, .cannotConnectToHost, .badURL].contains(error.code) {
            throw AIError.http(0, tr("Server nicht erreichbar – prüf die Adresse (\(request.url?.host ?? "?")) und ob der Server läuft.",
                                     "Server not reachable – check the address (\(request.url?.host ?? "?")) and that the server is running."))
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let error = json["error"]
            let message = (error as? [String: Any])?["message"] as? String ?? error as? String ?? ""
            throw AIError.http(status, message)
        }
        return json
    }

    /// Reasoning models sometimes prepend <think>…</think>.
    static func stripThinking(_ text: String) -> String {
        guard let end = text.range(of: "</think>") else { return text }
        return String(text[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Observable wrapper for the settings screens on both platforms.
@MainActor
final class AISettings: ObservableObject {
    static let shared = AISettings()

    @Published var config: AIConfig = .current
    @Published private(set) var isConfigured = FennAI.isConfigured
    @Published private(set) var testResult: String?
    @Published private(set) var testFailed = false
    @Published private(set) var isTesting = false
    @Published private(set) var models: [String] = []
    @Published var cloudConsent = FennAI.hasCloudConsent {
        didSet { FennAI.hasCloudConsent = cloudConsent; testResult = nil }
    }

    var needsConsent: Bool { !FennAI.isLocal(config) }

    func select(_ provider: AIProvider) {
        guard provider != config.provider else { return }
        config = AIConfig(provider: provider, baseURL: provider.defaultBaseURL, model: provider.defaultModel)
        save()
        Task { await loadModels() }
    }

    func save() {
        AIConfig.current = config
        isConfigured = FennAI.isConfigured(config)
        testResult = nil
    }

    func hasKey(_ provider: AIProvider) -> Bool { FennAI.apiKey(for: provider) != nil }

    func setKey(_ key: String) {
        FennAI.setAPIKey(key, for: config.provider)
        save()
        Task { await loadModels(); await test() }
    }

    func removeKey() {
        FennAI.setAPIKey(nil, for: config.provider)
        save()
    }

    func test() async {
        save()
        isTesting = true
        switch await FennAI.test(config) {
        case .success(let reply):
            testResult = tr("Verbunden – Antwort: „\(reply)“", "Connected – reply: “\(reply)”")
            testFailed = false
        case .failure(let error):
            testResult = error.localizedDescription
            testFailed = true
        }
        isTesting = false
    }

    /// Ollama or LM Studio without a model chosen yet get the best one they have (docs/MODELS.md order).
    func loadModels() async {
        models = await FennAI.availableModels(config)
        if (config.provider == .ollama || config.provider == .lmStudio), config.trimmedModel.isEmpty, let pick = LocalServers.pick(models) {
            config.model = pick
            save()
        }
    }
}
