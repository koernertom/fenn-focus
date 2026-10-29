import Foundation

/// What Fenn learns about the person in the first-run questions – the part that turns the app into *their* assistant.
/// Every answer is kept the moment it is given (user defaults right away, `profile/profile.md` a moment later), so
/// quitting halfway loses nothing and the agent knows it from the next question on. All of it can be changed later.
struct PersonProfile: Codable, Equatable {
    var name = ""
    var role = ""
    var focusTime: FocusTime?
    var helpWith: [Help] = []
    var goal = ""
    var distractions: [Distraction] = []
    var tone: Tone?
    /// Free text: anything else Fenn should know.
    var note = ""

    enum FocusTime: String, Codable, CaseIterable, Identifiable {
        case earlyMorning, morning, afternoon, evening
        var id: String { rawValue }
        var title: String {
            switch self {
            case .earlyMorning: return tr("Früh (bis 9)", "Early (before 9)")
            case .morning: return tr("Vormittags", "Late morning")
            case .afternoon: return tr("Nachmittags", "Afternoon")
            case .evening: return tr("Abends", "Evening")
            }
        }
        var symbol: String {
            switch self {
            case .earlyMorning: return "sunrise.fill"
            case .morning: return "sun.max.fill"
            case .afternoon: return "sun.haze.fill"
            case .evening: return "moon.stars.fill"
            }
        }
        /// What Fenn says when this is picked.
        var reaction: String {
            switch self {
            case .earlyMorning: return tr("Ein Frühaufsteher! Dann gehören die ersten Stunden dir.", "An early bird! Then the first hours are yours.")
            case .morning: return tr("Dann halte ich dir die Vormittage frei.", "Then I'll keep your mornings clear.")
            case .afternoon: return tr("Gut – Meetings lieber morgens, Fokus am Nachmittag.", "Good – meetings in the morning, focus in the afternoon.")
            case .evening: return tr("Eine Nachteule – ich plane deine Fokuszeit abends ein.", "A night owl – I'll plan your focus time for the evening.")
            }
        }
    }

    enum Help: String, Codable, CaseIterable, Identifiable {
        case focus, overview, planning, routines, ideas, meetings
        var id: String { rawValue }
        var title: String {
            switch self {
            case .focus: return tr("Dranbleiben, ohne abzuschweifen", "Staying on one thing")
            case .overview: return tr("Überblick über meine Aufgaben", "An overview of my tasks")
            case .planning: return tr("Meinen Tag planen", "Planning my day")
            case .routines: return tr("Routinen aufbauen", "Building routines")
            case .ideas: return tr("Ideen und Notizen festhalten", "Keeping ideas and notes")
            case .meetings: return tr("Zeit zwischen Terminen nutzen", "Using the time between meetings")
            }
        }
        var symbol: String {
            switch self {
            case .focus: return "timer"
            case .overview: return "checklist"
            case .planning: return "calendar"
            case .routines: return "repeat"
            case .ideas: return "lightbulb"
            case .meetings: return "person.2"
            }
        }
        var reaction: String {
            switch self {
            case .focus: return tr("Darin bin ich gut – ich halte dir den Rücken frei.", "I'm good at that – I'll cover your back.")
            case .overview: return tr("Ich sortiere, du entscheidest.", "I sort, you decide.")
            case .planning: return tr("Jeden Morgen ein Plan, der zu deinen Terminen passt.", "Every morning a plan that fits your meetings.")
            case .routines: return tr("Klein anfangen, dranbleiben – ich erinnere dich.", "Start small, keep going – I'll remind you.")
            case .ideas: return tr("Sag sie mir einfach, ich halte sie fest.", "Just tell me, I'll keep them.")
            case .meetings: return tr("Ich zeig dir, was in die Lücken passt.", "I'll show you what fits in the gaps.")
            }
        }
    }

    enum Distraction: String, Codable, CaseIterable, Identifiable {
        case mail, chat, social, news, phone, meetings
        var id: String { rawValue }
        var title: String {
            switch self {
            case .mail: return tr("E-Mails", "Email")
            case .chat: return tr("Team-Chat", "Team chat")
            case .social: return tr("Social Media", "Social media")
            case .news: return tr("Nachrichten", "News")
            case .phone: return tr("Das Handy", "My phone")
            case .meetings: return tr("Zu viele Termine", "Too many meetings")
            }
        }
        var symbol: String {
            switch self {
            case .mail: return "envelope.fill"
            case .chat: return "bubble.left.and.bubble.right.fill"
            case .social: return "heart.text.square.fill"
            case .news: return "newspaper.fill"
            case .phone: return "iphone"
            case .meetings: return "calendar.badge.exclamationmark"
            }
        }
    }

    enum Tone: String, Codable, CaseIterable, Identifiable {
        case short, warm, coach
        var id: String { rawValue }
        var title: String {
            switch self {
            case .short: return tr("Kurz und direkt", "Short and direct")
            case .warm: return tr("Freundlich, mit etwas mehr Erklärung", "Friendly, with a bit more explanation")
            case .coach: return tr("Fordernd – halt mich an meine Pläne", "Demanding – hold me to my plans")
            }
        }
        var symbol: String {
            switch self {
            case .short: return "bolt.fill"
            case .warm: return "face.smiling.inverse"
            case .coach: return "figure.run"
            }
        }
        /// How a reply sounds in this tone.
        var sample: String {
            switch self {
            case .short: return tr("Erledigt. Fokus läuft bis 10:30.", "Done. Focus runs until 10:30.")
            case .warm: return tr("Hab ich gemacht! Dein Fokusblock läuft bis 10:30 – danach eine kleine Pause?", "Done! Your focus block runs until 10:30 – a short break after?")
            case .coach: return tr("Läuft bis 10:30. Und diesmal kein Mail-Check zwischendurch.", "Runs until 10:30. And no email check in between this time.")
            }
        }
    }

    var isEmpty: Bool { self == PersonProfile() }
}

@MainActor
final class PersonProfileStore: ObservableObject {
    static let shared = PersonProfileStore()

    private static let defaultsKey = "fennfocus.profile.v1"
    /// Where the first-run questions were left, so the next launch continues there.
    static let stepKey = "fennfocus.onboarding.step"

    @Published var profile: PersonProfile {
        didSet {
            guard profile != oldValue else { return }
            UserDefaults.standard.set(try? JSONEncoder().encode(profile), forKey: Self.defaultsKey)
            scheduleWrite()
        }
    }

    private var pendingWrite: Task<Void, Never>?

    private init() {
        profile = UserDefaults.standard.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode(PersonProfile.self, from: $0) } ?? PersonProfile()
    }

    /// First name for greetings: the one given here, else the Mac account's.
    var firstName: String {
        let given = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !given.isEmpty { return given.split(separator: " ").first.map(String.init) ?? given }
        // Handles both "Mara Jensen" and directory-style "Jensen, Mara".
        let full = NSFullUserName()
        let parts = full.split(separator: ",", maxSplits: 1)
        let fromAccount = parts.count == 2 ? parts[1] : Substring(full)
        return fromAccount.split(separator: " ").first.map(String.init) ?? ""
    }

    /// The goal goes into goals.md as its own heading (once), so widgets and the agent see it like any other goal.
    func commitGoal() {
        let goal = profile.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !goal.isEmpty, !FennDemo.isOn else { return }
        let url = FennStorage.url(.goals)
        var text = FennVault.readText(url) ?? "# \(tr("Ziele", "Goals"))\n"
        guard !text.contains("## \(goal)") else { return }
        if !text.hasSuffix("\n") { text += "\n" }
        text += "\n## \(goal)\n_\(tr("gesetzt am", "set on")) \(Date().formatted(.iso8601.year().month().day()))_\n"
        _ = FennVault.writeText(text, to: url)
    }

    // MARK: profile.md

    private static let blockStart = "<!-- fenn-focus:about -->"
    private static let blockEnd = "<!-- /fenn-focus:about -->"

    /// Typing shouldn't rewrite the file on every key – the defaults already hold each answer.
    func scheduleWrite() {
        pendingWrite?.cancel()
        pendingWrite = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.writeProfile()
        }
    }

    /// Replaces Fenn's block in profile.md and leaves everything the person wrote around it alone.
    func writeProfile() {
        guard !FennDemo.isOn else { return }
        let url = FennStorage.url(.profile)
        let existing = FennVault.readText(url) ?? ""
        let block = Self.blockStart + "\n" + markdown + "\n" + Self.blockEnd
        let text: String
        if let start = existing.range(of: Self.blockStart), let end = existing.range(of: Self.blockEnd), start.lowerBound < end.upperBound {
            text = existing.replacingCharacters(in: start.lowerBound..<end.upperBound, with: block)
        } else {
            text = block + (existing.isEmpty ? "\n" : "\n\n" + existing)
        }
        _ = FennVault.writeText(text, to: url)
    }

    /// German in the file (like tasks and journal), so the agent reads the same thing whatever the app language.
    private var markdown: String {
        let p = profile
        let calendar = WorkCalendar.shared
        var lines = ["# Über mich", "_Aus den Fragen beim Einrichten von Fenn Focus – ändern unter Verbindungen › Über dich._", ""]
        if !p.name.isEmpty { lines.append("- Name: \(p.name)") }
        if !p.role.isEmpty { lines.append("- Mache beruflich: \(p.role)") }
        lines.append("- Arbeitszeit: \(calendar.workStart)–\(calendar.workEnd) Uhr")
        if let focus = p.focusTime { lines.append("- Beste Zeit für konzentrierte Arbeit: \(german(focus))") }
        if !p.helpWith.isEmpty { lines.append("- Fenn soll vor allem helfen bei: " + p.helpWith.map(german).joined(separator: ", ")) }
        if !p.goal.isEmpty { lines.append("- Wichtigstes Ziel gerade: \(p.goal)") }
        if !p.distractions.isEmpty { lines.append("- Lenkt mich am meisten ab: " + p.distractions.map(german).joined(separator: ", ")) }
        if let tone = p.tone { lines.append("- So soll Fenn antworten: \(german(tone))") }
        if !p.note.isEmpty { lines.append("- Außerdem: \(p.note)") }
        return lines.joined(separator: "\n")
    }

    private func german(_ value: PersonProfile.FocusTime) -> String {
        ["earlyMorning": "früh morgens", "morning": "vormittags", "afternoon": "nachmittags", "evening": "abends"][value.rawValue] ?? value.rawValue
    }

    private func german(_ value: PersonProfile.Help) -> String {
        ["focus": "dranbleiben ohne abzuschweifen", "overview": "Überblick über Aufgaben", "planning": "Tag planen",
         "routines": "Routinen aufbauen", "ideas": "Ideen und Notizen festhalten", "meetings": "Zeit zwischen Terminen nutzen"][value.rawValue] ?? value.rawValue
    }

    private func german(_ value: PersonProfile.Distraction) -> String {
        ["mail": "E-Mails", "chat": "Team-Chat", "social": "Social Media", "news": "Nachrichten", "phone": "das Handy",
         "meetings": "zu viele Termine"][value.rawValue] ?? value.rawValue
    }

    private func german(_ value: PersonProfile.Tone) -> String {
        ["short": "kurz und direkt", "warm": "freundlich, mit etwas mehr Erklärung",
         "coach": "fordernd – hält mich an meine Pläne"][value.rawValue] ?? value.rawValue
    }
}
