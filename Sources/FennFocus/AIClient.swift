import Foundation

/// Coach, advisor, plans and knowledge talk to whichever model is chosen under Connectors → AI model.
struct AIClient {
    func send(history: [CoachMessage], system: String, maxTokens: Int = 1024, timeout: TimeInterval = 90) async throws -> String {
        try await FennAI.complete(
            system: system,
            messages: history.map { AIMessage(role: $0.role == .user ? .user : .assistant, text: $0.text) },
            maxTokens: maxTokens,
            timeout: timeout
        )
    }
}
