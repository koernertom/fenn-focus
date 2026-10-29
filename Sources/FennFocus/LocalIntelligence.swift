import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

struct NoteTodo: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    /// 0 = today, 1 = tomorrow, nil = someday.
    var dayOffset: Int?

    var dayLabel: String {
        switch dayOffset {
        case 0: return tr("heute", "today")
        case 1: return tr("morgen", "tomorrow")
        default: return tr("später", "later")
        }
    }
}

struct NoteDigest: Codable, Equatable {
    var title: String
    var summary: String
    var todos: [NoteTodo]
    /// Which local engine produced it, shown to the user.
    var engine: String
}

/// Turns a note or transcript into title, summary and to-dos — on this Mac only.
/// Tries Apple Intelligence, then Fenn's Small Brain, then simple rules. Nothing goes to the cloud.
enum LocalIntelligence {
    private static let instructions = """
    Du wertest persönliche Notizen eines Menschen aus, der konzentriert arbeiten will, und antwortest in der Sprache der Notiz. \
    Titel höchstens sechs Wörter. Zusammenfassung ein bis zwei Sätze. \
    To-dos nur konkrete Aufgaben aus dem Text, knapp formuliert und ohne Zeitangabe im Titel. \
    day ist "heute", "morgen" oder "später".
    """

    static func digest(_ text: String) async -> NoteDigest {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), let digest = try? await appleDigest(text) {
            return digest
        }
        #endif
        if let digest = try? await brainDigest(text) {
            return digest
        }
        return heuristicDigest(text)
    }

    // MARK: Apple Intelligence

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func appleDigest(_ text: String) async throws -> NoteDigest? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        let session = LanguageModelSession(instructions: instructions)
        let draft = try await session.respond(to: text, generating: DigestDraft.self).content
        return NoteDigest(
            title: draft.title,
            summary: draft.summary,
            todos: draft.todos.map { NoteTodo(title: $0.title, dayOffset: offset(for: $0.day)) },
            engine: "Apple Intelligence"
        )
    }
    #endif

    // MARK: Fenn Brain

    private static func brainDigest(_ text: String) async throws -> NoteDigest? {
        guard LocalModels.isAvailable else { return nil }
        let system = instructions + """

        Antworte nur mit JSON: {"title": "…", "summary": "…", "todos": [{"title": "…", "day": "heute|morgen|später"}]}
        """
        struct Payload: Decodable {
            struct Todo: Decodable { let title: String; let day: String }
            let title: String
            let summary: String
            let todos: [Todo]
        }
        let reply = try await LocalBrainBridge.complete(system: system, messages: [AIMessage(role: .user, text: text)], maxTokens: 500, choice: "fast")
        guard let data = FennAI.json(in: reply) else { return nil }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return NoteDigest(
            title: payload.title,
            summary: payload.summary,
            todos: payload.todos.map { NoteTodo(title: $0.title, dayOffset: offset(for: $0.day)) },
            engine: "Fenn Brain"
        )
    }

    // MARK: Rules

    private static let todoMarkers = [
        "muss", "müssen", "sollte", "todo", "to-do", "nicht vergessen", "anrufen", "erledigen",
        "kaufen", "buchen", "checken", "prüfen", "anmelden", "- [ ]", "need to", "call", "buy", "book"
    ]

    static func heuristicDigest(_ text: String) -> NoteDigest {
        let sentences = text
            .components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let title = sentences.first.map { $0.split(separator: " ").prefix(6).joined(separator: " ") } ?? tr("Notiz", "Note")
        let todos = sentences.filter { sentence in
            let lower = sentence.lowercased()
            return todoMarkers.contains { lower.contains($0) }
        }.map { sentence -> NoteTodo in
            let lower = sentence.lowercased()
            let day = lower.contains("morgen") || lower.contains("tomorrow") ? 1 : (lower.contains("heute") || lower.contains("today") ? 0 : nil)
            return NoteTodo(title: sentence, dayOffset: day)
        }
        return NoteDigest(
            title: title,
            summary: sentences.prefix(2).joined(separator: ". "),
            todos: todos,
            engine: tr("Einfache Auswertung", "Basic rules")
        )
    }

    private static func offset(for day: String) -> Int? {
        switch day.lowercased() {
        case "heute", "today": return 0
        case "morgen", "tomorrow": return 1
        default: return nil
        }
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
private struct DigestDraft {
    @Guide(description: "Titel mit höchstens sechs Wörtern")
    var title: String
    @Guide(description: "Zusammenfassung in ein bis zwei Sätzen")
    var summary: String
    @Guide(description: "Konkrete Aufgaben aus der Notiz")
    var todos: [TodoDraft]
}

@available(macOS 26.0, *)
@Generable
private struct TodoDraft {
    @Guide(description: "Die Aufgabe, knapp formuliert")
    var title: String
    @Guide(description: "heute, morgen oder später")
    var day: String
}
#endif
