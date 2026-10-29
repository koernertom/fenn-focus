import Foundation

// Fenn as an agent: you say what you want, Fenn does it with tools – tasks, focus, notes, routines, navigation –
// and asks back when something important is unclear. Native tool calling for Claude, OpenAI-compatible servers
// and Fenn Brain; models without it (Apple, small local ones) get the same tools through a JSON protocol.

/// One thing Fenn can do.
struct AgentTool {
    let name: String
    let description: String
    /// JSON schema of the arguments: {"type": "object", "properties": …, "required": …}.
    let parameters: [String: Any]
    /// Tools that start something (a focus block, an app block, a mode) only run when the person's
    /// message actually asks for it – one of these words must be in it. Small models otherwise fire them while "planning the day".
    var needsIntent: [String]?
    let run: @MainActor ([String: Any]) async -> AgentToolResult

    init(_ name: String, _ description: String, properties: [String: [String: Any]] = [:], required: [String] = [],
         needsIntent: [String]? = nil, run: @escaping @MainActor ([String: Any]) async -> AgentToolResult) {
        self.name = name
        self.description = description
        self.parameters = ["type": "object", "properties": properties, "required": required]
        self.needsIntent = needsIntent
        self.run = run
    }

    /// Word beginnings that mean "do it now" (single words match the start of a word, phrases anywhere).
    static let startWords = ["start", "los", "beginn", "jetzt", "anfang", "fang an", "begin", "now", "go ahead"]

    func allowed(for message: String) -> Bool {
        guard let needsIntent else { return true }
        let lower = message.lowercased()
        let words = lower.split { !$0.isLetter }.map(String.init)
        return needsIntent.contains { stem in stem.contains(" ") ? lower.contains(stem) : words.contains { $0.hasPrefix(stem) } }
    }

    static func string(_ description: String, options: [String]? = nil) -> [String: Any] {
        var property: [String: Any] = ["type": "string", "description": description]
        if let options { property["enum"] = options }
        return property
    }

    static func number(_ description: String) -> [String: Any] { ["type": "number", "description": description] }
}

struct AgentToolResult {
    /// What the model reads back.
    var text: String
    /// A short line the person sees ("Aufgabe angelegt: …"); nil for pure lookups.
    var action: String?
    var symbol = "checkmark.circle.fill"

    static func done(_ action: String, symbol: String = "checkmark.circle.fill", detail: String? = nil) -> AgentToolResult {
        AgentToolResult(text: detail ?? action, action: action, symbol: symbol)
    }

    static func info(_ text: String) -> AgentToolResult { AgentToolResult(text: text, action: nil) }
}

struct AgentCall {
    let id: String
    let name: String
    let arguments: [String: Any]
}

/// The conversation as the model sees it, independent of the provider.
enum AgentEntry {
    case user(String)
    case assistant(String, [AgentCall])
    case result(AgentCall, String)
}

struct AgentStep {
    var text: String
    var calls: [AgentCall]
}

/// What the chat shows.
struct AgentItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case user
        case fenn
        case action(symbol: String)
        case question(options: [String])
        case error
    }
    let id = UUID()
    var kind: Kind
    var text: String
}

/// The three beats Fenn shows while it works: situation, reply, action.
enum FennLaborPhase: Int, Equatable {
    case reading, thinking, acting

    var title: String {
        switch self {
        case .reading: return tr("Situation", "Situation")
        case .thinking: return tr("Antwort", "Reply")
        case .acting: return tr("Aktion", "Action")
        }
    }
}

// MARK: - Agent

@MainActor
final class FennAgent: ObservableObject {
    static let shared = FennAgent()

    @Published private(set) var items: [AgentItem] = []
    @Published private(set) var isWorking = false
    /// What Fenn is doing right now ("Legt Aufgabe an …").
    @Published private(set) var status: String?
    /// Visible work steps: read the situation, think, then act. No invented wait.
    @Published private(set) var laborPhase: FennLaborPhase = .reading

    /// Set by each app: its tools and a few lines about the current situation.
    var tools: [AgentTool] = []
    /// Profile, data and matching notes for the latest message.
    var context: (String) -> String = { _ in "" }
    /// Called with each finished exchange (the Mac keeps a coach log).
    var onReply: (_ question: String, _ answer: String) -> Void = { _, _ in }
    var platform = "Mac"
    /// SOUL.md on the Mac; nil = default voice.
    var persona: () -> String? = { nil }
    /// Pomodoro and block rules run here even when no model is configured.
    var localCommand: ((String) -> String?)?

    private var entries: [AgentEntry] = []
    private static let maxSteps = 8

    var hasConversation: Bool { !items.isEmpty }

    /// The request in flight; "Neuer Chat", "Fertig" and "Stopp" drop it.
    private var run: Task<Void, Never>?
    /// Bumped whenever a request is dropped, so a late reply can't land in the new chat.
    private var generation = 0
    /// Where the running request's turn begins in `entries`.
    private var turnStart: Int?

    /// Starts a request that can be dropped again.
    func start(_ text: String) {
        run = Task { await send(text) }
    }

    /// Stops the running request. The chat stays; the half-done turn is forgotten by the model.
    func stop() {
        guard isWorking else { return }
        drop()
        items.append(AgentItem(kind: .error, text: tr("Gestoppt.", "Stopped.")))
    }

    func reset() {
        drop()
        entries = []
        items = []
    }

    private func drop() {
        generation += 1
        run?.cancel()
        run = nil
        if let turnStart, turnStart <= entries.count { entries.removeSubrange(turnStart...) }
        turnStart = nil
        isWorking = false
        status = nil
        laborPhase = .reading
    }

    /// Takes over a finished exchange from elsewhere (e.g. the demo), so the chat shows it.
    func show(_ item: AgentItem) { items.append(item) }

    func send(_ raw: String) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isWorking else { return }
        items.append(AgentItem(kind: .user, text: text))
        entries.append(.user(text))
        trim()
        if let reply = localCommand?(text) {
            items.append(AgentItem(kind: .fenn, text: reply))
            entries.append(.assistant(reply, []))
            onReply(text, reply)
            return
        }
        guard FennAI.isConfigured else {
            items.append(AgentItem(kind: .error, text: AIError.notConfigured.localizedDescription))
            return
        }
        let turn = generation
        turnStart = entries.count - 1
        isWorking = true
        defer {
            if turn == generation { isWorking = false; status = nil; laborPhase = .reading; turnStart = nil; run = nil }
        }
        let all = (FennAI.prefersFewTools ? Self.focusTools(tools, for: text) : tools) + [Self.askTool]
        let system = system(for: text)
        var actedThisTurn = false
        var forceJSON = false
        // Each action runs once per request; the same call again only gets "already done".
        var done: [String: String] = [:]
        // Labor illusion: show care before the first model hop — value without inventing delay.
        laborPhase = .reading
        status = tr("Liest deine Situation …", "Reading your situation …")
        try? await Task.sleep(nanoseconds: 280_000_000)
        for _ in 0..<Self.maxSteps {
            guard turn == generation else { return }
            laborPhase = actedThisTurn ? .acting : .thinking
            status = actedThisTurn
                ? tr("Formuliert die Antwort …", "Writing the reply …")
                : tr("Denkt nach …", "Thinking …")
            var step: AgentStep
            do {
                step = try await FennAI.step(system: system, entries: entries, tools: all, forceJSON: forceJSON)
            } catch {
                if turn == generation { items.append(AgentItem(kind: .error, text: error.localizedDescription)) }
                return
            }
            guard turn == generation else { return }
            let said = Self.clean(step.text)
            // Small models like to say "done" without calling anything – one more try through the JSON protocol.
            if step.calls.isEmpty, !actedThisTurn, !forceJSON, Self.claimsAction(said) {
                forceJSON = true
                continue
            }
            step.text = said
            entries.append(.assistant(said, step.calls))
            if step.calls.isEmpty {
                if !said.isEmpty {
                    items.append(AgentItem(kind: .fenn, text: said))
                    onReply(text, said)
                }
                return
            }
            actedThisTurn = true
            // Text next to tool calls is "I'll do X" – the summary after the results says it better.
            var waitForAnswer = false
            for call in step.calls {
                if call.name == "ask_user" {
                    let question = (call.arguments["question"] as? String) ?? said
                    let options = (call.arguments["options"] as? [Any])?.compactMap { $0 as? String } ?? []
                    items.append(AgentItem(kind: .question(options: Array(options.prefix(4))), text: question))
                    entries.append(.result(call, "Frage gestellt. Die Antwort kommt als nächste Nachricht."))
                    waitForAnswer = true
                    continue
                }
                guard let tool = all.first(where: { $0.name == call.name }) else {
                    entries.append(.result(call, "Unbekanntes Werkzeug \(call.name)."))
                    continue
                }
                if !tool.allowed(for: text) {
                    entries.append(.result(call, "NICHT ausgeführt: Die Person hat nicht ausdrücklich darum gebeten. Nichts starten oder erstellen – "
                        + "schlag es höchstens vor, mit ask_user und einer Option wie „Jetzt starten“."))
                    continue
                }
                let signature = tool.needsIntent == nil ? "\(call.name)|\(Self.signature(call.arguments))" : call.name
                if let earlier = done[signature] {
                    entries.append(.result(call, "Schon erledigt in dieser Anfrage – nicht wiederholen. Ergebnis war: \(earlier)"))
                    continue
                }
                laborPhase = .acting
                status = Self.statusLine(for: tool)
                let result = await tool.run(call.arguments)
                guard turn == generation else { return }
                if result.action != nil { done[signature] = String(result.text.prefix(200)) }
                if let action = result.action { items.append(AgentItem(kind: .action(symbol: result.symbol), text: action)) }
                entries.append(.result(call, result.text))
            }
            if waitForAnswer { return }
        }
    }

    private static let fennRules = """
    - Tag planen, Überblick, „was steht an“: nur nachsehen (day_schedule, today_overview) und \
    einen kurzen Plan vorschlagen. Nichts starten, nichts anlegen. Aktionen danach per ask_user anbieten.
    - Werkzeuge, die etwas starten (Fokus, Sperre, Modus), nur, wenn die Person es ausdrücklich jetzt will.
    - Ist ein Tag zu voll: konkrete Verschiebungen vorschlagen (welche Aufgabe auf wann, welche Uhrzeit) und per ask_user fragen; \
    erst nach Zustimmung mit update_task umsetzen. Termine mit anderen Leuten nicht verschieben, nur vorschlagen.
    """

    private func system(for question: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EEEE, d. MMMM yyyy, HH:mm"
        return """
        \(persona() ?? "Du bist Fenn, ein warmer, direkter Begleiter für konzentriertes Arbeiten: Aufgaben, Termine, Fokus und Routinen.")

        Du bist als Agent in der Fenn-App auf dem \(platform) eingebaut. Die Person sagt dir, was sie gerade tun will – \
        du erledigst es mit deinen Werkzeugen, statt zu erklären, wo sie klicken muss.
        - Vieles ist diktiert: Füllwörter, Pausen-Reste und Einwürfe wie „äh“, „häh“, „warte mal“ oder ein abgebrochener Halbsatz \
        gehören nicht zur Bitte – überlies sie und nimm, was gemeint ist.
        - Ist klar, was gemeint ist: handeln, auch mehrere Werkzeuge nacheinander – aber nur das, worum gebeten wurde.
        \(Self.fennRules)
        - Jedes Werkzeug höchstens einmal pro Anfrage.
        - Fehlt etwas Wichtiges oder ist es mehrdeutig: ask_user mit einer kurzen Frage und 2–4 Antwortoptionen.
        - Nach dem Handeln: ein bis zwei kurze Sätze, was du getan hast. Keine Aufzählung der Werkzeuge.
        - Für Fragen zu Planung, Prioritäten oder Arbeitsweise antwortest du direkt, kurz und konkret; hol dir vorher Daten mit today_overview, wenn sie helfen.
        - Antworte auf \(tr("Deutsch", "English")), du-Form. Markdown nur sparsam (fett, kurze Listen). Keine Mittelpunkte (·) zwischen Wörtern, stattdessen Komma oder neuer Satz.

        Jetzt: \(formatter.string(from: Date())).
        \(context(question))
        """
    }

    /// Stable text of the arguments, to spot the same call twice.
    private static func signature(_ arguments: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys]) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Small local models pick better from a short list: only the tool groups the request (or the one before it) talks
    /// about, plus the overview. Nothing recognisable → every tool, so a "yes, do it" still works.
    static func focusTools(_ tools: [AgentTool], for text: String) -> [AgentTool] {
        let groups: [(words: [String], tools: [String])] = [
            (["aufgab", "task", "todo", "to-do", "erledig", "done", "abhak", "fällig", "deadline", "priorit"],
             ["add_tasks", "list_tasks", "complete_task", "update_task", "delete_task"]),
            (["heute", "morgen", "tag", "termin", "kalender", "plan", "woche", "zeit", "today", "tomorrow", "day", "meeting", "calendar", "schedule", "week"],
             ["day_schedule", "list_tasks"]),
            (["fokus", "focus", "pomodoro", "konzentr", "timer", "pause", "break", "ablenk", "distract", "sperr", "block"],
             ["start_focus", "stop_focus", "set_pomodoro", "block_distractions", "add_block_rule"]),
            (["routine", "gewohnheit", "habit"], ["list_habits", "check_habit", "add_habit"]),
            (["idee", "idea", "brainstorm", "einfall"], ["capture_idea", "list_ideas", "brainstorm_idea"]),
            (["modus", "mode", "freizeit", "feierabend", "erholung"], ["switch_mode"]),
            (["merk", "remember", "vergiss", "forget"], ["remember"]),
        ]
        let recent = FennAgent.shared.entries.reversed().compactMap { entry -> String? in
            if case .user(let said) = entry { return said }
            return nil
        }.prefix(2).joined(separator: " ")
        let said = (text + " " + recent).lowercased()
        let wanted = Set(groups.filter { group in group.words.contains { said.contains($0) } }.flatMap(\.tools))
        guard !wanted.isEmpty else { return tools }
        let always: Set<String> = ["today_overview", "open_section"]
        return tools.filter { wanted.contains($0.name) || always.contains($0.name) }
    }

    private static let askTool = AgentTool(
        "ask_user", "Stellt der Person eine Rückfrage, wenn etwas Wichtiges fehlt oder unklar ist. Danach wartest du auf die Antwort.",
        properties: ["question": AgentTool.string("Die Frage, kurz"),
                     "options": ["type": "array", "items": ["type": "string"], "description": "2–4 kurze Antwortvorschläge"]],
        required: ["question"]) { _ in .info("") }

    /// Drops reasoning that some local models write into the answer.
    static func clean(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("[thinking]")
                || first.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("thinking:") {
            lines.removeFirst()
        }
        return FennAI.stripThinking(lines.joined(separator: "\n")).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func claimsAction(_ text: String) -> Bool {
        let lower = text.lowercased()
        return ["angelegt", "eingetragen", "gestartet", "gesetzt", "erledigt", "gespeichert", "notiert", "hinzugefügt", "abgehakt",
                "gemacht:", "added", "logged", "started", "saved"].contains { lower.contains($0) }
    }

    private static func statusLine(for tool: AgentTool) -> String {
        let first = tool.description.components(separatedBy: CharacterSet(charactersIn: ".–(")).first ?? tool.description
        return first.trimmingCharacters(in: .whitespaces) + " …"
    }

    /// Keeps the conversation short; only cuts at a person's message so tool calls keep their results.
    private func trim() {
        guard entries.count > 40 else { return }
        var cut = entries.count - 30
        while cut < entries.count - 1 {
            if case .user = entries[cut] { break }
            cut += 1
        }
        entries.removeFirst(cut)
    }
}

// MARK: - One model step with tools

extension FennAI {
    /// One step: the model either answers or asks for tool calls.
    static func step(system: String, entries: [AgentEntry], tools: [AgentTool], forceJSON: Bool = false,
                     config: AIConfig = .current) async throws -> AgentStep {
        guard isConfigured(config) else { throw AIError.notConfigured }
        if needsConsent(config) { throw AIError.cloudConsentMissing }
        if forceJSON { return try await jsonStep(system: system, entries: entries, tools: tools, config: config) }
        do {
            switch config.provider {
            case .claude: return try await claudeStep(system: system, entries: entries, tools: tools, config: config)
            case .openAICompatible, .openRouter, .lmStudio: return try await openAIStep(system: system, entries: entries, tools: tools, config: config)
            case .ollama: return try await ollamaStep(system: system, entries: entries, tools: tools, config: config)
            case .fennBrain: return try await brainStep(system: system, entries: entries, tools: tools, choice: config.trimmedModel)
            case .apple:
                // Apple's model has a small context window; a downloaded model handles the agent better when there is one.
                if brainAvailable { return try await brainStep(system: system, entries: entries, tools: tools, choice: "auto") }
                return try await jsonStep(system: system, entries: entries, tools: tools, config: config)
            }
        } catch AIError.http(let code, let message) where code == 400 && message.lowercased().contains("tool") {
            // The model can't do native tool calls – same tools through plain JSON.
            return try await jsonStep(system: system, entries: entries, tools: tools, config: config)
        }
    }

    private static func claudeStep(system: String, entries: [AgentEntry], tools: [AgentTool], config: AIConfig) async throws -> AgentStep {
        guard let key = apiKey(for: .claude), let url = URL(string: config.trimmedBase + "/v1/messages") else { throw AIError.notConfigured }
        var req = request(url, timeout: 90, method: "POST")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        // Consecutive blocks of the same role go into one message (tool results + the next question).
        var messages: [[String: Any]] = []
        func add(_ role: String, _ blocks: [[String: Any]]) {
            if let last = messages.last, last["role"] as? String == role, var content = last["content"] as? [[String: Any]] {
                content += blocks
                messages[messages.count - 1]["content"] = content
            } else {
                messages.append(["role": role, "content": blocks])
            }
        }
        for entry in entries {
            switch entry {
            case .user(let text): add("user", [["type": "text", "text": text]])
            case .assistant(let text, let calls):
                var blocks: [[String: Any]] = text.isEmpty ? [] : [["type": "text", "text": text]]
                blocks += calls.map { ["type": "tool_use", "id": $0.id, "name": $0.name, "input": $0.arguments] }
                if !blocks.isEmpty { add("assistant", blocks) }
            case .result(let call, let text):
                add("user", [["type": "tool_result", "tool_use_id": call.id, "content": text.isEmpty ? "ok" : text]])
            }
        }
        let body: [String: Any] = [
            "model": config.trimmedModel, "max_tokens": 1500, "system": system, "messages": messages,
            "tools": tools.map { ["name": $0.name, "description": $0.description, "input_schema": $0.parameters] },
        ]
        let json = try await post(req, body: body)
        guard let content = json["content"] as? [[String: Any]] else { throw AIError.invalidResponse }
        let text = content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n")
        let calls = content.filter { $0["type"] as? String == "tool_use" }.compactMap { block -> AgentCall? in
            guard let id = block["id"] as? String, let name = block["name"] as? String else { return nil }
            return AgentCall(id: id, name: name, arguments: block["input"] as? [String: Any] ?? [:])
        }
        return AgentStep(text: text, calls: calls)
    }

    /// OpenAI's chat format with `tools`.
    private static func brainStep(system: String, entries: [AgentEntry], tools: [AgentTool], choice: String) async throws -> AgentStep {
        let step = try await LocalBrainBridge.step(system: system, entries: entries, tools: tools, choice: choice)
        // Small models sometimes write the call as text instead of the tool format.
        if step.calls.isEmpty, let fallback = parseJSONCalls(step.text, tools: tools), !fallback.calls.isEmpty { return fallback }
        return AgentStep(text: stripThinking(step.text), calls: step.calls)
    }

    /// Ollama's native tools API: arguments arrive as objects, results go back as role "tool" with the tool's name.
    private static func ollamaStep(system: String, entries: [AgentEntry], tools: [AgentTool], config: AIConfig) async throws -> AgentStep {
        var messages: [[String: Any]] = [["role": "system", "content": system]]
        for entry in entries {
            switch entry {
            case .user(let text): messages.append(["role": "user", "content": text])
            case .assistant(let text, let calls):
                var message: [String: Any] = ["role": "assistant", "content": text]
                if !calls.isEmpty { message["tool_calls"] = calls.map { ["function": ["name": $0.name, "arguments": $0.arguments]] } }
                messages.append(message)
            case .result(let call, let text):
                messages.append(["role": "tool", "content": text.isEmpty ? "ok" : text, "tool_name": call.name])
            }
        }
        let toolSpecs = tools.map { ["type": "function", "function": ["name": $0.name, "description": $0.description, "parameters": $0.parameters]] }
        let json = try await ollamaChat(["messages": messages, "tools": toolSpecs, "options": ollamaOptions(maxTokens: 1500)], timeout: 120, config: config)
        guard let message = json["message"] as? [String: Any] else { throw AIError.invalidResponse }
        let text = stripThinking(message["content"] as? String ?? "")
        let calls = ((message["tool_calls"] as? [[String: Any]]) ?? []).enumerated().compactMap { index, raw -> AgentCall? in
            guard let function = raw["function"] as? [String: Any], let name = function["name"] as? String else { return nil }
            return AgentCall(id: "ollama-\(index)-\(UUID().uuidString.prefix(6))", name: name, arguments: function["arguments"] as? [String: Any] ?? [:])
        }
        if calls.isEmpty, let fallback = parseJSONCalls(text, tools: tools), !fallback.calls.isEmpty { return fallback }
        return AgentStep(text: text, calls: calls)
    }

    private static func openAIStep(system: String, entries: [AgentEntry], tools: [AgentTool], config: AIConfig) async throws -> AgentStep {
        guard let url = URL(string: config.trimmedBase + "/chat/completions") else { throw AIError.notConfigured }
        var req = request(url, timeout: 90, method: "POST")
        authorize(&req, config: config)
        var messages: [[String: Any]] = [["role": "system", "content": system]]
        for entry in entries {
            switch entry {
            case .user(let text): messages.append(["role": "user", "content": text])
            case .assistant(let text, let calls):
                var message: [String: Any] = ["role": "assistant", "content": text]
                if !calls.isEmpty {
                    message["tool_calls"] = calls.map { call -> [String: Any] in
                        let arguments = String(data: (try? JSONSerialization.data(withJSONObject: call.arguments)) ?? Data("{}".utf8), encoding: .utf8) ?? "{}"
                        return ["type": "function", "id": call.id, "function": ["name": call.name, "arguments": arguments]]
                    }
                }
                messages.append(message)
            case .result(let call, let text):
                messages.append(["role": "tool", "content": text.isEmpty ? "ok" : text, "tool_call_id": call.id])
            }
        }
        let toolSpecs = tools.map { ["type": "function", "function": ["name": $0.name, "description": $0.description, "parameters": $0.parameters]] }
        let body: [String: Any] = ["model": config.trimmedModel, "messages": messages, "tools": toolSpecs, "max_tokens": 1500]
        let json = try await post(req, body: body)
        let message = (json["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any]
        guard let message else { throw AIError.invalidResponse }
        let text = stripThinking(message["content"] as? String ?? "")
        let calls = ((message["tool_calls"] as? [[String: Any]]) ?? []).compactMap { raw -> AgentCall? in
            guard let function = raw["function"] as? [String: Any], let name = function["name"] as? String else { return nil }
            var arguments: [String: Any] = [:]
            if let object = function["arguments"] as? [String: Any] { arguments = object }
            else if let string = function["arguments"] as? String, let data = string.data(using: .utf8),
                    let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { arguments = object }
            return AgentCall(id: raw["id"] as? String ?? "call_\(UUID().uuidString.prefix(8))", name: name, arguments: arguments)
        }
        // Some local models write the call as JSON text instead of using tool_calls.
        if calls.isEmpty, let fallback = parseJSONCalls(text, tools: tools), !fallback.calls.isEmpty { return fallback }
        return AgentStep(text: text, calls: calls)
    }

    /// For models without native tool calling: the tools are described in the prompt, the reply is JSON.
    private static func jsonStep(system: String, entries: [AgentEntry], tools: [AgentTool], config: AIConfig) async throws -> AgentStep {
        let catalog = tools.map { tool -> String in
            let properties = (tool.parameters["properties"] as? [String: [String: Any]]) ?? [:]
            let args = properties.keys.sorted().map { key in "\(key): \(properties[key]?["description"] as? String ?? "")" }.joined(separator: "; ")
            return "- \(tool.name)(\(args)): \(tool.description)"
        }.joined(separator: "\n")
        let protocolText = """
        \(system)

        Werkzeuge:
        \(catalog)

        Antworte IMMER nur mit einem JSON-Objekt: {"say": "Text an die Person oder leer", "calls": [{"tool": "name", "args": {…}}]}.
        Ohne Werkzeug: "calls": []. Nach Ergebnissen von Werkzeugen fasst du in "say" kurz zusammen.
        """
        var messages: [AIMessage] = []
        for entry in entries {
            switch entry {
            case .user(let text): messages.append(AIMessage(role: .user, text: text))
            case .assistant(let text, let calls):
                let payload: [String: Any] = ["say": text, "calls": calls.map { ["tool": $0.name, "args": $0.arguments] }]
                let json = (try? JSONSerialization.data(withJSONObject: payload)).flatMap { String(data: $0, encoding: .utf8) } ?? text
                messages.append(AIMessage(role: .assistant, text: json))
            case .result(let call, let text):
                let line = "Ergebnis von \(call.name): \(text.isEmpty ? "ok" : text)"
                if let last = messages.last, last.role == .user { messages[messages.count - 1].text += "\n" + line }
                else { messages.append(AIMessage(role: .user, text: line)) }
            }
        }
        let reply = try await complete(system: protocolText, messages: messages, maxTokens: 1200, json: true, config: config)
        return parseJSONCalls(reply, tools: tools) ?? AgentStep(text: reply, calls: [])
    }

    private static func parseJSONCalls(_ reply: String, tools: [AgentTool]) -> AgentStep? {
        guard let data = json(in: reply), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let names = Set(tools.map(\.name))
        var calls: [AgentCall] = []
        let rawCalls = (object["calls"] as? [[String: Any]]) ?? (object["tool"] != nil ? [object] : [])
        for raw in rawCalls {
            guard let name = (raw["tool"] ?? raw["name"]) as? String, names.contains(name) else { continue }
            let args = (raw["args"] ?? raw["arguments"] ?? raw["parameters"]) as? [String: Any] ?? [:]
            calls.append(AgentCall(id: "call_\(UUID().uuidString.prefix(8))", name: name, arguments: args))
        }
        let say = (object["say"] as? String) ?? (object["reply"] as? String) ?? ""
        guard !calls.isEmpty || object["say"] != nil || object["reply"] != nil else { return nil }
        return AgentStep(text: say, calls: calls)
    }
}

// MARK: - Tools every app shares (tasks live in the shared TaskStore)

enum SharedAgentTools {
    @MainActor
    static var tasks: [AgentTool] {
        [
            AgentTool("add_tasks", "Legt eine oder mehrere neue Aufgaben an (mit Thema, Priorität, Fälligkeit, Dauer, wenn genannt). Relative Angaben wie morgen oder Freitag rechnest du vom heutigen Datum in JJJJ-MM-TT um. Nicht für Aufgaben, die es schon gibt.",
                      properties: ["tasks": ["type": "array", "description": "Die Aufgaben", "items": [
                        "type": "object",
                        "properties": [
                            "title": AgentTool.string("Kurzer Titel"),
                            "topic": AgentTool.string("Thema, z. B. Arbeit, Privat oder ein Projekt"),
                            "priority": AgentTool.string("Priorität", options: ["hoch", "mittel", "niedrig"]),
                            "due": AgentTool.string("Fällig am, JJJJ-MM-TT"),
                            "estimate_minutes": AgentTool.number("Geschätzte Minuten"),
                        ],
                        "required": ["title"]]]],
                      required: ["tasks"]) { args in
                let raw = (args["tasks"] as? [[String: Any]]) ?? (args["title"] != nil ? [args] : [])
                let parsed = raw.compactMap { item -> FennTask? in
                    guard let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespaces), !title.isEmpty else { return nil }
                    var task = FennTask(title: title)
                    task.topic = (item["topic"] as? String) ?? ""
                    task.priority = TaskPriority(storedName: ((item["priority"] as? String) ?? "mittel").capitalized)
                    task.due = (item["due"] as? String).flatMap(AgentDates.day)
                    task.estimateMinutes = (item["estimate_minutes"] as? NSNumber)?.intValue
                    return task
                }
                let existing = Set(TaskStore.shared.open.map { $0.title.lowercased() })
                let tasks = parsed.filter { !existing.contains($0.title.lowercased()) }
                guard !tasks.isEmpty else { return .info(parsed.isEmpty ? "Keine Aufgabe erkannt." : "Gibt es schon als offene Aufgabe – nichts Neues angelegt.") }
                TaskStore.shared.add(tasks)
                let titles = tasks.map(\.title).joined(separator: ", ")
                return .done(tasks.count == 1 ? tr("Aufgabe angelegt: \(titles)", "Task added: \(titles)") : tr("\(tasks.count) Aufgaben angelegt: \(titles)", "\(tasks.count) tasks added: \(titles)"),
                             symbol: "checklist")
            },
            AgentTool("list_tasks", "Zeigt offene Aufgaben (nach Priorität), heute fällige oder heute erledigte.",
                      properties: ["filter": AgentTool.string("Welche", options: ["offen", "heute", "erledigt_heute"])]) { args in
                let store = TaskStore.shared
                store.reload()
                let list: [FennTask]
                switch args["filter"] as? String {
                case "heute": list = store.open.filter { $0.isDueToday || $0.isOverdue }
                case "erledigt_heute": list = store.tasks.filter { $0.done && $0.doneAt.map(Calendar.current.isDateInToday) == true }
                default: list = Array(store.open.prefix(15))
                }
                if list.isEmpty { return .info("Keine Aufgaben.") }
                return .info(list.map { task in
                    var line = "- \(task.title)"
                    if !task.topic.isEmpty { line += " [\(task.topic)]" }
                    line += " (\(task.priority.storedName)"
                    if let due = task.due { line += ", fällig \(AgentDates.key(due))" }
                    if let minutes = task.estimateMinutes { line += ", \(minutes) min" }
                    return line + ")"
                }.joined(separator: "\n"))
            },
            AgentTool("complete_task", "Hakt eine offene Aufgabe als erledigt ab.",
                      properties: ["title": AgentTool.string("Titel oder ein eindeutiger Teil davon")], required: ["title"]) { args in
                let query = ((args["title"] as? String) ?? "").lowercased()
                let store = TaskStore.shared
                let matches = store.open.filter { $0.title.lowercased().contains(query) || query.contains($0.title.lowercased()) }
                guard let task = matches.first, !query.isEmpty else { return .info("Keine offene Aufgabe passt zu „\(query)“.") }
                if matches.count > 1, !matches.contains(where: { $0.title.lowercased() == query }) {
                    return .info("Mehrere passen: " + matches.prefix(4).map(\.title).joined(separator: "; ") + ". Frag nach, welche gemeint ist.")
                }
                store.toggle(task.id)
                return .done(tr("Erledigt: \(task.title)", "Done: \(task.title)"), symbol: "checkmark.circle.fill")
            },
            AgentTool("day_schedule", "Zeigt einen Tag nach Stunden: Termine, Aufgaben mit Uhrzeit, Aufgaben ohne Uhrzeit, freie Lücken, Auslastung – und Vorschläge, falls der Tag zu voll ist. Nur ansehen.",
                      properties: ["day": AgentTool.string("JJJJ-MM-TT, Standard heute")]) { args in
                let day = (args["day"] as? String).flatMap(AgentDates.day) ?? Date()
                let load = DayPlanner.load(on: day)
                let clock = DateFormatter()
                clock.dateFormat = "HH:mm"
                var lines = ["Tag \(AgentDates.key(day)), Arbeitszeit \(DayPlanner.workHours.start)–\(DayPlanner.workHours.end) Uhr. Aufgaben \(load.taskMinutes) min, frei \(load.freeMinutes) min\(load.isOverloaded ? " – ZU VOLL" : "")."]
                lines += load.events.map { "Termin \($0.isAllDay ? "ganztägig" : "\(clock.string(from: $0.start))–\(clock.string(from: $0.end))") \($0.title)\($0.movable ? " (verschiebbar)" : "")" }
                lines += load.timedTasks.map { "Aufgabe \(clock.string(from: $0.due!)) \($0.title) (~\(DayPlanner.minutes(of: $0)) min, \($0.priority.storedName))" }
                lines += load.untimedTasks.map { "Aufgabe ohne Uhrzeit: \($0.title) (~\(DayPlanner.minutes(of: $0)) min, \($0.priority.storedName))" }
                lines.append("Freie Lücken: " + DayPlanner.gaps(in: load).map { "\(clock.string(from: $0.start))–\(clock.string(from: $0.end))" }.joined(separator: ", "))
                let proposals = DayPlanner.relieve(load) + DayPlanner.fitIntoGaps(load)
                if !proposals.isEmpty {
                    lines.append("Vorschläge (erst nach Zustimmung mit update_task umsetzen): " + proposals.prefix(6).map(\.summary).joined(separator: "; "))
                }
                return .info(lines.joined(separator: "\n"))
            },
            AgentTool("update_task", "Ändert eine bestehende Aufgabe: Titel, Priorität, Tag/Thema, Datum (verschieben), Uhrzeit oder Dauer. Nur die genannten Felder.",
                      properties: ["task": AgentTool.string("Titel der Aufgabe oder ein eindeutiger Teil davon"),
                                   "new_title": AgentTool.string("Neuer Titel, falls umbenannt"),
                                   "priority": AgentTool.string("Neue Priorität", options: ["hoch", "mittel", "niedrig"]),
                                   "topic": AgentTool.string("Neuer Tag bzw. Thema"),
                                   "due": AgentTool.string("Neues Datum JJJJ-MM-TT, oder \"keins\" zum Entfernen"),
                                   "time": AgentTool.string("Uhrzeit HH:MM, falls genannt"),
                                   "estimate_minutes": AgentTool.number("Geschätzte Minuten")],
                      required: ["task"]) { args in
                guard case .found(var task) = SharedAgentTools.match(args["task"] as? String, in: TaskStore.shared.tasks) else {
                    return .info(SharedAgentTools.matchProblem(args["task"] as? String))
                }
                if let title = (args["new_title"] as? String)?.trimmingCharacters(in: .whitespaces), !title.isEmpty { task.title = title }
                if let priority = args["priority"] as? String { task.priority = TaskPriority(storedName: priority.capitalized) }
                if let topic = args["topic"] as? String { task.topic = topic.trimmingCharacters(in: CharacterSet(charactersIn: "# ")) }
                if let due = args["due"] as? String {
                    task.due = ["keins", "none", "kein", ""].contains(due.lowercased()) ? nil : AgentDates.day(due) ?? task.due
                }
                if let time = args["time"] as? String, let day = task.due ?? AgentDates.day(AgentDates.key(Date())) {
                    let parts = time.split(separator: ":").compactMap { Int($0) }
                    if parts.count == 2 { task.due = Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day) }
                }
                if let minutes = (args["estimate_minutes"] as? NSNumber)?.intValue { task.estimateMinutes = minutes }
                TaskStore.shared.update(task)
                var detail = [task.priority.title]
                if !task.topic.isEmpty { detail.append("#\(task.topic)") }
                if let due = task.due { detail.append(TaskFormat.day(due)) }
                return .done(tr("Geändert: \(task.title), \(detail.joined(separator: ", "))", "Updated: \(task.title), \(detail.joined(separator: ", "))"),
                             symbol: "pencil")
            },
            AgentTool("delete_task", "Löscht eine Aufgabe endgültig – nur wenn die Person das ausdrücklich will (sonst complete_task).",
                      properties: ["task": AgentTool.string("Titel der Aufgabe oder ein eindeutiger Teil davon")], required: ["task"],
                      needsIntent: ["lösch", "entfern", "weg", "streich", "delete", "remove"]) { args in
                guard case .found(let task) = SharedAgentTools.match(args["task"] as? String, in: TaskStore.shared.tasks) else {
                    return .info(SharedAgentTools.matchProblem(args["task"] as? String))
                }
                TaskStore.shared.delete(task.id)
                return .done(tr("Gelöscht: \(task.title)", "Deleted: \(task.title)"), symbol: "trash")
            },
        ]
    }

    /// Routines (habits): separate from tasks, ticked off per day.
    @MainActor
    static var habits: [AgentTool] {
        [
            AgentTool("list_habits", "Zeigt die Routinen (Habits) von heute mit Tageszeit, erledigt/offen und Serie – oder alle.",
                      properties: ["which": AgentTool.string("Welche", options: ["heute", "alle"])]) { args in
                let store = HabitStore.shared
                store.reload()
                let list = (args["which"] as? String) == "alle" ? store.active : store.today()
                if list.isEmpty { return .info("Keine Routinen\((args["which"] as? String) == "alle" ? "" : " für heute").") }
                return .info(list.map { habit in
                    var line = "- \(habit.title) (\(habit.time.title), \(habit.weekdaysText), \(store.isDone(habit) ? "heute erledigt" : "heute offen"), Serie \(store.streak(habit))"
                    if let anchor = habit.anchorText(in: store.habits) { line += ", \(anchor)" }
                    if let tiny = habit.tiny { line += ", 2-Minuten-Version: \(tiny)" }
                    return line + ")"
                }.joined(separator: "\n"))
            },
            AgentTool("add_habit", "Legt eine neue tägliche Routine (Habit) an – getrennt von Aufgaben. Nach Atomic Habits möglichst mit Anker (nach welcher Gewohnheit), 2-Minuten-Version und Identität. Nicht für einmalige Aufgaben.",
                      properties: ["title": AgentTool.string("Kurzer Titel, z. B. Tag planen"),
                                   "time": AgentTool.string("Tageszeit", options: ["morgens", "nachmittags", "abends", "jederzeit"]),
                                   "anchor": AgentTool.string("Nach welcher bestehenden Gewohnheit, z. B. dem ersten Kaffee"),
                                   "tiny": AgentTool.string("2-Minuten-Version, z. B. eine Seite lesen"),
                                   "identity": AgentTool.string("Identität, beginnend mit 'jemand, der …'"),
                                   "weekdays": AgentTool.string("Wochentage, z. B. Mo,Mi,Fr – leer für täglich"),
                                   "days": AgentTool.number("Als Challenge über so viele Tage (z. B. 30); leer für fortlaufend")],
                      required: ["title"]) { args in
                let store = HabitStore.shared
                store.reload()
                guard let title = (args["title"] as? String)?.trimmingCharacters(in: .whitespaces), !title.isEmpty else { return .info("Kein Titel.") }
                if store.active.contains(where: { $0.title.lowercased() == title.lowercased() }) { return .info("Die Routine „\(title)“ gibt es schon.") }
                let times: [String: HabitTime] = ["morgens": .morning, "nachmittags": .afternoon, "abends": .evening, "jederzeit": .anytime]
                var habit = Habit(title: title, time: times[(args["time"] as? String) ?? ""] ?? .anytime)
                habit.anchor = (args["anchor"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                habit.tiny = (args["tiny"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                habit.identity = (args["identity"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                habit.lengthDays = (args["days"] as? NSNumber)?.intValue
                if let raw = args["weekdays"] as? String, !raw.isEmpty {
                    let names = ["so": 1, "su": 1, "mo": 2, "di": 3, "tu": 3, "mi": 4, "we": 4, "do": 5, "th": 5, "fr": 6, "sa": 7]
                    let days = raw.lowercased().split(whereSeparator: { ",; ".contains($0) }).compactMap { names[String($0.prefix(2))] }
                    habit.weekdays = Set(days).count == 7 ? [] : Array(Set(days)).sorted()
                }
                let lower = title.lowercased()
                if lower.contains("fokus") || lower.contains("focus") { habit.auto = .focus }
                else if lower.contains("check-in") { habit.auto = .checkIn }
                else if lower.contains("review") || lower.contains("rückblick") { habit.auto = .review }
                store.add(habit)
                var detail = [habit.time.title, habit.weekdaysText]
                if let anchor = habit.anchorText(in: store.habits) { detail.append(anchor) }
                return .done(tr("Routine angelegt: \(title), \(detail.joined(separator: ", "))", "Routine added: \(title), \(detail.joined(separator: ", "))"),
                             symbol: "repeat")
            },
            AgentTool("check_habit", "Hakt eine Routine für heute ab (auch nur die 2-Minuten-Version).",
                      properties: ["title": AgentTool.string("Titel der Routine oder ein Teil davon"),
                                   "tiny": AgentTool.string("Nur die 2-Minuten-Version?", options: ["ja", "nein"])],
                      required: ["title"]) { args in
                let store = HabitStore.shared
                store.reload()
                let query = ((args["title"] as? String) ?? "").lowercased()
                let matches = store.active.filter { $0.title.lowercased().contains(query) || query.contains($0.title.lowercased()) }
                guard let habit = matches.first, !query.isEmpty else { return .info("Keine Routine passt zu „\(query)“.") }
                if store.isDone(habit) { return .info("„\(habit.title)“ ist heute schon abgehakt.") }
                store.toggle(habit, tiny: (args["tiny"] as? String) == "ja")
                return .done(tr("Abgehakt: \(habit.title), Serie \(store.streak(habit))", "Ticked off: \(habit.title), streak \(store.streak(habit))"), symbol: "checkmark.seal.fill")
            },
        ]
    }

    enum Match { case found(FennTask), none, several([FennTask]) }

    /// Finds one task by (part of) its title – open ones first.
    static func match(_ query: String?, in tasks: [FennTask]) -> Match {
        let query = (query ?? "").lowercased().trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return .none }
        let sorted = tasks.sorted { !$0.done && $1.done }
        if let exact = sorted.first(where: { $0.title.lowercased() == query }) { return .found(exact) }
        let matches = sorted.filter { $0.title.lowercased().contains(query) || query.contains($0.title.lowercased()) }
        let open = matches.filter { !$0.done }
        if open.count == 1 { return .found(open[0]) }
        if open.isEmpty, matches.count == 1 { return .found(matches[0]) }
        return matches.isEmpty ? .none : .several(Array((open.isEmpty ? matches : open).prefix(4)))
    }

    @MainActor
    static func matchProblem(_ query: String?) -> String {
        switch match(query, in: TaskStore.shared.tasks) {
        case .several(let tasks): return "Mehrere passen: " + tasks.map(\.title).joined(separator: "; ") + ". Frag nach, welche gemeint ist."
        default: return "Keine Aufgabe passt zu „\(query ?? "")“."
        }
    }
}

enum AgentDates {
    static func day(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(text.prefix(10)))
    }

    static func key(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
