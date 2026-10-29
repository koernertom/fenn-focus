import Foundation

/// One turn in the Coach conversation. Sent verbatim as Anthropic Messages API history.
struct CoachMessage: Identifiable, Equatable {
    enum Role: String {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    var text: String
    let date: Date
    /// Files from the second brain that went into this reply's context.
    var sources: [String]

    init(id: UUID = UUID(), role: Role, text: String, date: Date = Date(), sources: [String] = []) {
        self.id = id
        self.role = role
        self.text = text
        self.date = date
        self.sources = sources
    }
}
