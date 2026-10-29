import Foundation

// Business ideas and brainstorming: every idea is its own project folder in Fenn/ideas/<project>/ with
//   README.md      the idea canvas (pitch, problem, audience, solution, money, risks, next steps) – kept current by Fenn
//   brainstorm.md  the whole conversation, readable
//   idea.json      the same for the apps
// Any other .md/.txt file the person drops into the folder is read as context when brainstorming.

struct IdeaCanvas: Codable, Equatable {
    var pitch = ""
    var problem = ""
    var audience = ""
    var solution = ""
    var business = ""
    var competition = ""
    var risks = ""
    var nextSteps: [String] = []
    var questions: [String] = []

    /// The text fields in canvas order: key path, title, JSON key.
    static var fields: [(path: WritableKeyPath<IdeaCanvas, String>, title: String, key: String)] {
        [(\.problem, tr("Problem", "Problem"), "problem"), (\.audience, tr("Zielgruppe", "Audience"), "audience"),
         (\.solution, tr("Lösung", "Solution"), "solution"), (\.business, tr("Geschäftsmodell", "Business model"), "business"),
         (\.competition, tr("Wettbewerb & Alternativen", "Competition & alternatives"), "competition"),
         (\.risks, tr("Risiken & Annahmen", "Risks & assumptions"), "risks")]
    }

    var filledCount: Int {
        Self.fields.filter { !self[keyPath: $0.path].isEmpty }.count + (pitch.isEmpty ? 0 : 1) + (nextSteps.isEmpty ? 0 : 1)
    }

    /// New values from the model win; empty ones keep what was there.
    mutating func merge(_ update: [String: Any]) {
        func text(_ key: String) -> String? {
            (update[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        }
        func list(_ key: String) -> [String]? {
            let items = (update[key] as? [Any])?.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespaces).nilIfBlank }
            return items?.isEmpty == false ? Array(items!.prefix(8)) : nil
        }
        if let value = text("pitch") { pitch = value }
        for field in Self.fields { if let value = text(field.key) { self[keyPath: field.path] = value } }
        if let value = list("nextSteps") { nextSteps = value }
        if let value = list("questions") { questions = value }
    }
}

enum IdeaStatus: String, Codable, CaseIterable {
    case idea, exploring, building, parked

    var title: String {
        switch self {
        case .idea: return tr("Idee", "Idea")
        case .exploring: return tr("Wird geprüft", "Exploring")
        case .building: return tr("In Umsetzung", "Building")
        case .parked: return tr("Geparkt", "Parked")
        }
    }

    var symbol: String {
        switch self {
        case .idea: return "lightbulb"
        case .exploring: return "magnifyingglass"
        case .building: return "hammer"
        case .parked: return "moon.zzz"
        }
    }
}

struct IdeaMessage: Codable, Identifiable, Equatable {
    var id = UUID()
    /// "user" or "fenn"
    var role: String
    var text: String
    var date = Date()

    var isUser: Bool { role == "user" }
}

struct IdeaProject: Codable, Identifiable, Equatable {
    /// Also the folder name.
    var id: String
    var title: String
    var status = IdeaStatus.idea
    var created = Date()
    var updated = Date()
    var canvas = IdeaCanvas()
    var messages: [IdeaMessage] = []
}

/// Ways to push an idea further – one tap each.
enum IdeaMode: String, CaseIterable, Identifiable {
    case expand, variations, critic, audience, money, mvp, names

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expand: return tr("Weiterdenken", "Develop it")
        case .variations: return tr("Varianten", "Variations")
        case .critic: return tr("Kritisch prüfen", "Challenge it")
        case .audience: return tr("Zielgruppe schärfen", "Sharpen audience")
        case .money: return tr("Geld verdienen", "Make money")
        case .mvp: return tr("MVP & nächste Schritte", "MVP & next steps")
        case .names: return tr("Namen finden", "Find names")
        }
    }

    var symbol: String {
        switch self {
        case .expand: return "sparkles"
        case .variations: return "square.grid.2x2"
        case .critic: return "exclamationmark.triangle"
        case .audience: return "person.2"
        case .money: return "eurosign.circle"
        case .mvp: return "flag"
        case .names: return "textformat"
        }
    }

    /// What the person "says" when tapping the mode.
    var prompt: String {
        switch self {
        case .expand: return tr("Denk die Idee weiter: Was wäre der stärkste Kern, und welche Frage sollte ich als Nächstes klären?", "Develop the idea: what's the strongest core, and which question should I answer next?")
        case .variations: return tr("Gib mir 8 deutlich unterschiedliche Varianten dieser Idee – andere Zielgruppen, Formate, Geschäftsmodelle.", "Give me 8 clearly different variations – other audiences, formats, business models.")
        case .critic: return tr("Sei ehrlicher Advocatus Diaboli: Woran scheitert die Idee am wahrscheinlichsten? Welche Annahmen sind am riskantesten und wie teste ich sie billig?", "Be an honest devil's advocate: how is this most likely to fail? Which assumptions are riskiest and how do I test them cheaply?")
        case .audience: return tr("Hilf mir, die Zielgruppe zu schärfen: Wer hat das Problem am stärksten, wo finde ich diese Leute und was zahlen sie heute dafür?", "Help me sharpen the audience: who has the problem worst, where do I find them and what do they pay today?")
        case .money: return tr("Welche 3–4 Geschäftsmodelle passen, mit grober Rechnung (Preis, Kunden, Umsatz)? Welches empfiehlst du zum Start?", "Which 3–4 business models fit, with rough numbers (price, customers, revenue)? Which one would you start with?")
        case .mvp: return tr("Was ist das kleinste MVP, das ich in 2 Wochen testen kann? Gib mir konkrete nächste Schritte.", "What's the smallest MVP I could test in 2 weeks? Give me concrete next steps.")
        case .names: return tr("Schlag 10 Namen vor (kurz, gut aussprechbar, Domain-tauglich) und sag zu jedem in 3 Wörtern, warum.", "Suggest 10 names (short, easy to say, domain-friendly), each with a 3-word reason.")
        }
    }
}

// MARK: - Files

enum IdeaFiles {
    static func root(in fenn: URL) -> URL { fenn.appendingPathComponent("ideas", isDirectory: true) }
    static func folder(_ id: String, in fenn: URL) -> URL { root(in: fenn).appendingPathComponent(id, isDirectory: true) }

    /// "Kaffee-Abo für Büros" → "kaffee-abo-fur-buros"
    static func slug(_ title: String) -> String {
        let folded = title.lowercased().replacingOccurrences(of: "ß", with: "ss").folding(options: .diacriticInsensitive, locale: Locale(identifier: "de_DE"))
        var slug = ""
        for character in folded {
            if character.isASCII && (character.isLetter || character.isNumber) { slug.append(character) } else if slug.last != "-" { slug.append("-") }
        }
        let trimmed = String(slug.trimmingCharacters(in: CharacterSet(charactersIn: "-")).prefix(48))
        return trimmed.isEmpty ? "idee" : trimmed
    }

    /// Every project folder; folders the person made by hand (only notes, no idea.json) show up too.
    static func load(from fenn: URL) -> [IdeaProject] { load(in: root(in: fenn)) }

    /// The archived ones in ideas/_archiv, newest first.
    static func loadArchived(from fenn: URL) -> [IdeaProject] { load(in: archiveRoot(in: fenn)) }

    static func archiveRoot(in fenn: URL) -> URL { root(in: fenn).appendingPathComponent("_archiv", isDirectory: true) }

    private static func load(in base: URL) -> [IdeaProject] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey])) ?? []
        return folders.compactMap { folder -> IdeaProject? in
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  !folder.lastPathComponent.hasPrefix("_"), !folder.lastPathComponent.hasPrefix(".") else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let data = FennVault.read(folder.appendingPathComponent("idea.json")), var project = try? decoder.decode(IdeaProject.self, from: data) {
                project.id = folder.lastPathComponent
                return project
            }
            let modified = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            return IdeaProject(id: folder.lastPathComponent, title: folder.lastPathComponent.replacingOccurrences(of: "-", with: " ").capitalized,
                               created: modified, updated: modified)
        }
        .sorted { $0.updated > $1.updated }
    }

    static func save(_ project: IdeaProject, to fenn: URL) {
        let folder = folder(project.id, in: fenn)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(project) { _ = FennVault.write(data, to: folder.appendingPathComponent("idea.json")) }
        _ = FennVault.writeText(readme(project), to: folder.appendingPathComponent("README.md"))
        if !project.messages.isEmpty { _ = FennVault.writeText(brainstorm(project), to: folder.appendingPathComponent("brainstorm.md")) }
    }

    /// Out of sight, not gone: the folder moves to ideas/_archiv.
    static func archive(_ project: IdeaProject, in fenn: URL) {
        let archive = archiveRoot(in: fenn)
        try? FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        var target = archive.appendingPathComponent(project.id, isDirectory: true)
        if FileManager.default.fileExists(atPath: target.path) { target = archive.appendingPathComponent("\(project.id)-\(Int(Date().timeIntervalSince1970))") }
        try? FileManager.default.moveItem(at: folder(project.id, in: fenn), to: target)
    }

    /// Back from ideas/_archiv; returns the id it lives under now.
    @discardableResult
    static func restore(_ project: IdeaProject, in fenn: URL) -> String {
        var id = project.id
        var suffix = 2
        while FileManager.default.fileExists(atPath: folder(id, in: fenn).path) { id = project.id + "-\(suffix)"; suffix += 1 }
        try? FileManager.default.moveItem(at: archiveRoot(in: fenn).appendingPathComponent(project.id, isDirectory: true), to: folder(id, in: fenn))
        return id
    }

    /// The person's own notes in the project folder (not Fenn's files), shortened for the prompt.
    static func ownNotes(_ project: IdeaProject, in fenn: URL) -> String {
        let folder = folder(project.id, in: fenn)
        let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { ["md", "txt"].contains($0.pathExtension.lowercased()) && !["README.md", "brainstorm.md"].contains($0.lastPathComponent) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .prefix(5)
        return files.compactMap { file -> String? in
            guard let text = FennVault.readText(file)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            return "Datei \(file.lastPathComponent):\n\(text.prefix(3000))"
        }.joined(separator: "\n\n")
    }

    static func readme(_ project: IdeaProject) -> String {
        let canvas = project.canvas
        var lines = ["# \(project.title)", ""]
        if !canvas.pitch.isEmpty { lines += ["> \(canvas.pitch)", ""] }
        lines += ["Status: \(project.status.title), angelegt \(FennVault.dayKey(project.created)), zuletzt \(FennVault.dayKey(project.updated))", ""]
        for field in IdeaCanvas.fields where !canvas[keyPath: field.path].isEmpty {
            lines += ["## \(field.title)", canvas[keyPath: field.path], ""]
        }
        if !canvas.nextSteps.isEmpty { lines += ["## Nächste Schritte"] + canvas.nextSteps.map { "- [ ] \($0)" } + [""] }
        if !canvas.questions.isEmpty { lines += ["## Offene Fragen"] + canvas.questions.map { "- \($0)" } + [""] }
        lines += ["---", "_Fenn hält diese Seite beim Brainstormen aktuell. Eigene Notizen als weitere .md-Datei in diesen Ordner legen – Fenn liest sie mit._"]
        return lines.joined(separator: "\n")
    }

    static func brainstorm(_ project: IdeaProject) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "dd.MM.yyyy HH:mm"
        var lines = ["# Brainstorm – \(project.title)", ""]
        for message in project.messages {
            lines += ["## \(formatter.string(from: message.date)), \(message.isUser ? "Du" : "Fenn")", "", message.text, ""]
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Store

/// Ideas of this device's Fenn folder; the apps tell it how to reach the folder (`withRoot`).
@MainActor
final class IdeaStore: ObservableObject {
    static let shared = IdeaStore()

    @Published private(set) var projects: [IdeaProject] = []
    /// Ideas in ideas/_archiv – out of the list, one tap from coming back.
    @Published private(set) var archived: [IdeaProject] = []
    /// The project Fenn is answering in right now.
    @Published private(set) var thinking: String?
    @Published var errorMessage: String?
    /// Set by the app: runs the body with FennStorage.root.
    var withRoot: (_ body: (URL) -> Void) -> Void = { _ in }

    func reload() {
        withRoot { root in
            projects = IdeaFiles.load(from: root)
            archived = IdeaFiles.loadArchived(from: root)
        }
    }

    func project(_ id: String) -> IdeaProject? { projects.first { $0.id == id } }

    /// Finds a project by (part of) its title.
    func find(_ name: String) -> IdeaProject? {
        let query = name.lowercased()
        return projects.first { $0.title.lowercased() == query }
            ?? projects.first { $0.title.lowercased().contains(query) || query.contains($0.title.lowercased()) }
    }

    @discardableResult
    func create(title: String, pitch: String = "") -> IdeaProject {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var id = IdeaFiles.slug(clean)
        var suffix = 2
        while projects.contains(where: { $0.id == id }) { id = IdeaFiles.slug(clean) + "-\(suffix)"; suffix += 1 }
        var project = IdeaProject(id: id, title: clean.isEmpty ? tr("Neue Idee", "New idea") : clean)
        project.canvas.pitch = pitch.trimmingCharacters(in: .whitespacesAndNewlines)
        save(project)
        return project
    }

    func save(_ project: IdeaProject) {
        var project = project
        project.updated = Date()
        withRoot { IdeaFiles.save(project, to: $0) }
        projects.removeAll { $0.id == project.id }
        projects.insert(project, at: 0)
    }

    func archive(_ project: IdeaProject) {
        withRoot { IdeaFiles.archive(project, in: $0) }
        projects.removeAll { $0.id == project.id }
        reload()
    }

    func restore(_ project: IdeaProject) {
        withRoot { IdeaFiles.restore(project, in: $0) }
        reload()
    }

    /// One brainstorming turn: the person's text (or a mode), Fenn's answer, and the canvas updated from it.
    @discardableResult
    func send(_ text: String, to projectId: String) async -> String? {
        guard var project = project(projectId), thinking == nil else { return nil }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        project.messages.append(IdeaMessage(role: "user", text: clean))
        save(project)
        thinking = projectId
        errorMessage = nil
        defer { thinking = nil }
        var notes = ""
        withRoot { notes = IdeaFiles.ownNotes(project, in: $0) }
        do {
            let (reply, update) = try await IdeaCoach.reply(project, notes: notes)
            guard var current = self.project(projectId) else { return nil }
            current.messages.append(IdeaMessage(role: "fenn", text: reply))
            if let update { current.canvas.merge(update) }
            if current.status == .idea && current.messages.count >= 6 { current.status = .exploring }
            save(current)
            return reply
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}

// MARK: - Coach

enum IdeaCoach {
    static let system = """
    Du bist Fenn, ein erfahrener Sparringspartner für Geschäftsideen und Brainstorming. Du denkst mit, statt zu loben: \
    konkrete Vorschläge, ehrliche Einwände, gute Rückfragen. Du nutzt bekannte Werkzeuge (Jobs-to-be-done, Lean Canvas, \
    Riskiest Assumption Test, Pricing-Überschlag), ohne sie zu erklären. Antworte auf Deutsch, knapp und in Markdown \
    (kurze Absätze, Listen, **fett** für das Wichtigste). Duze die Person. Stelle am Ende höchstens eine gezielte Frage. \
    Erfinde keine Marktzahlen; wenn du schätzt, sag, dass es eine Schätzung ist.
    Antworte ausschließlich mit JSON: {"reply": "deine Antwort auf Deutsch in Markdown", "canvas": {"pitch": "", "problem": "", "audience": "", \
    "solution": "", "business": "", "competition": "", "risks": "", "nextSteps": [], "questions": []}}. \
    Im canvas nur Felder füllen, zu denen es jetzt etwas Neues oder Besseres gibt (jeweils 1–3 Sätze, pitch ein Satz); \
    den Rest leer lassen. nextSteps: höchstens 5 konkrete Schritte; questions: höchstens 4 offene Fragen. \
    Alle Texte – reply und canvas – auf Deutsch, auch wenn die Idee Fremdwörter enthält.
    """

    static func reply(_ project: IdeaProject, notes: String) async throws -> (String, [String: Any]?) {
        var context = ["Idee: \(project.title) (Status: \(project.status.title))"]
        let canvas = project.canvas
        if !canvas.pitch.isEmpty { context.append("Pitch: \(canvas.pitch)") }
        for field in IdeaCanvas.fields where !canvas[keyPath: field.path].isEmpty {
            context.append("\(field.title): \(canvas[keyPath: field.path])")
        }
        if !canvas.nextSteps.isEmpty { context.append("Nächste Schritte: " + canvas.nextSteps.joined(separator: "; ")) }
        if !notes.isEmpty { context.append("Eigene Notizen im Projektordner:\n\(notes)") }
        let recent = project.messages.suffix(14)
        var messages = recent.map { AIMessage(role: $0.isUser ? .user : .assistant, text: $0.text) }
        if let last = messages.indices.last {
            messages[last].text = "STAND DER IDEE:\n" + context.joined(separator: "\n") + "\n\nNACHRICHT:\n" + messages[last].text
                + tr("\n\n(Antworte auf Deutsch, als JSON wie vorgegeben.)", "\n\n(Answer in English, as the JSON described.)")
        }
        let raw = try await FennAI.complete(system: system, messages: messages, maxTokens: 3000, timeout: 180, json: true)
        let text = FennAI.stripThinking(raw)
        if let data = FennAI.json(in: text), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let reply = (object["reply"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !reply.isEmpty {
            return (reply, object["canvas"] as? [String: Any])
        }
        // No JSON: the whole answer is the reply, the canvas stays.
        return (text.trimmingCharacters(in: .whitespacesAndNewlines), nil)
    }
}

// MARK: - Fenn's tools

extension SharedAgentTools {
    /// Capture, list and brainstorm ideas; `open` shows a project (nil = the list) in the app.
    @MainActor
    static func ideas(open: @escaping (String?) -> Void) -> [AgentTool] {
        let store = IdeaStore.shared
        return [
            AgentTool("capture_idea", "Legt eine neue Geschäftsidee als eigenes Projekt (Ordner) an, z. B. wenn die Person sagt „ich hab eine Idee: …“.",
                      properties: ["title": AgentTool.string("Kurzer Name der Idee, 2–5 Wörter"),
                                   "pitch": AgentTool.string("Die Idee in einem Satz, so wie gesagt")],
                      required: ["title"]) { args in
                guard let title = (args["title"] as? String)?.trimmingCharacters(in: .whitespaces), !title.isEmpty else { return .info("Kein Titel.") }
                store.reload()
                if let existing = store.find(title) { open(existing.id); return .info("Die Idee „\(existing.title)“ gibt es schon – geöffnet.") }
                let project = store.create(title: title, pitch: args["pitch"] as? String ?? "")
                open(project.id)
                return .done(tr("Idee angelegt: \(project.title)", "Idea saved: \(project.title)"), symbol: "lightbulb",
                             detail: "Ordner ideas/\(project.id)")
            },
            AgentTool("list_ideas", "Listet die Ideen-Projekte mit Status und Pitch.") { _ in
                store.reload()
                guard !store.projects.isEmpty else { return .info("Noch keine Ideen.") }
                return .info(store.projects.prefix(15).map { "\($0.title) (\($0.status.title))\($0.canvas.pitch.isEmpty ? "" : ": \($0.canvas.pitch)")" }
                    .joined(separator: "\n"))
            },
            AgentTool("brainstorm_idea", "Brainstormt in einem Ideen-Projekt weiter (Frage, Gedanke, Wunsch); die Antwort landet im Projekt und wird zurückgegeben.",
                      properties: ["idea": AgentTool.string("Name der Idee"), "message": AgentTool.string("Was die Person dazu sagt oder wissen will")],
                      required: ["idea", "message"]) { args in
                store.reload()
                guard let project = (args["idea"] as? String).flatMap(store.find) else {
                    return .info("Keine passende Idee. Vorhanden: \(store.projects.map(\.title).joined(separator: ", ")). Frag nach oder lege sie mit capture_idea an.")
                }
                open(project.id)
                guard let reply = await store.send(args["message"] as? String ?? "", to: project.id) else {
                    return .info(store.errorMessage ?? "Keine Antwort.")
                }
                return .done(tr("Im Projekt „\(project.title)“ ergänzt", "Added to “\(project.title)”"), symbol: "lightbulb", detail: String(reply.prefix(1200)))
            },
        ]
    }
}

private extension String {
    var nilIfBlank: String? { isEmpty ? nil : self }
}
