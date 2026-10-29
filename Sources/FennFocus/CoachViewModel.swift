import Foundation
import FennFocusCore

struct CoachContext {
    /// SOUL.md content; nil falls back to the default persona.
    var persona: String?
    var text: String
    var sources: [String]
}

@MainActor
final class CoachViewModel: ObservableObject {
    @Published var messages: [CoachMessage] = []
    @Published var draft = ""
    @Published var isSending = false
    @Published var errorMessage: String?

    /// Builds persona + profile + matching second-brain notes for the question being asked.
    var contextProvider: (String) -> CoachContext = { _ in CoachContext(persona: nil, text: "", sources: []) }
    var onExchange: (_ question: String, _ answer: String) -> Void = { _, _ in }

    static let defaultPersona = """
    Du bist Fenn, ein warmer, direkter Begleiter für konzentriertes Arbeiten: Aufgaben, Termine, Fokus und Routinen. \
    Antworte kurz und konkret, mit einer klaren Empfehlung. Antworte auf Deutsch, außer der Nutzer schreibt Englisch.
    """

    /// Fixed regardless of what SOUL.md says.
    private static let safetyRule = """
    Du stellst keine Diagnosen. Bei Hinweisen auf Krisen oder anhaltende Überlastung empfiehlst du freundlich professionelle Hilfe.
    """

    private let client = AIClient()

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        draft = ""
        messages.append(CoachMessage(role: .user, text: text))
        isSending = true
        errorMessage = nil
        let context = contextProvider(text)
        let system = [context.persona ?? Self.defaultPersona, Self.safetyRule, context.text]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        Task {
            do {
                let reply = try await client.send(history: messages, system: system)
                messages.append(CoachMessage(role: .assistant, text: reply, sources: context.sources))
                onExchange(text, reply)
            } catch {
                errorMessage = error.localizedDescription
            }
            isSending = false
        }
    }
}
