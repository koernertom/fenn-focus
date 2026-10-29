import Foundation

/// The ways to journal: how you feel, plan the day, review it, set goals, or just write.
enum JournalKind: String, Codable, CaseIterable, Identifiable {
    case checkIn
    case planDay
    case review
    case goals
    /// Whatever is on your mind, no questions.
    case free

    var id: String { rawValue }

    /// The ones you write yourself.
    static var writable: [JournalKind] { [.checkIn, .planDay, .review, .goals, .free] }

    var title: String {
        switch self {
        case .checkIn: return tr("Check-in", "Check-in")
        case .planDay: return tr("Tag planen", "Plan the day")
        case .review: return tr("Tag reviewen", "Review the day")
        case .goals: return tr("Ziele setzen", "Set goals")
        case .free: return tr("Frei schreiben", "Free writing")
        }
    }

    var subtitle: String {
        switch self {
        case .checkIn: return tr("Wie geht's dir – antippen", "How are you – just tap")
        case .planDay: return tr("Fenn schlägt deine Top 3 vor", "Fenn suggests your top 3")
        case .review: return tr("Dein Tag in Zahlen – antippen", "Your day in numbers – just tap")
        case .goals: return tr("Ziele passend zu dir", "Goals that fit you")
        case .free: return tr("Was dir durch den Kopf geht", "Whatever's on your mind")
        }
    }

    var symbol: String {
        switch self {
        case .checkIn: return "heart.text.square"
        case .planDay: return "sunrise"
        case .review: return "moon.stars"
        case .goals: return "flag.checkered"
        case .free: return "square.and.pencil"
        }
    }

    /// Fixed opening questions; Fenn adds one follow-up based on the answers.
    var questions: [String] {
        switch self {
        case .checkIn:
            return [tr("Was beschäftigt dich gerade am meisten?", "What's on your mind the most right now?"),
                    tr("Was brauchst du heute, um gut arbeiten zu können?", "What do you need today to work well?")]
        case .planDay:
            return [tr("Was ist heute das Wichtigste – was muss passieren, damit der Tag gut war?", "What matters most today – what has to happen for the day to be good?"),
                    tr("Wann ist heute dein Fokusblock – und woran arbeitest du darin?", "When is your focus block today – and what will you work on?"),
                    tr("Was könnte dazwischenkommen, und wie gehst du damit um?", "What could get in the way, and how will you handle it?")]
        case .review:
            return [tr("Was lief heute gut?", "What went well today?"),
                    tr("Was war schwierig – und was lernst du daraus?", "What was hard – and what do you learn from it?"),
                    tr("Wofür bist du heute dankbar?", "What are you grateful for today?")]
        case .goals:
            return [tr("Welches Ziel willst du erreichen? So konkret wie möglich.", "Which goal do you want to reach? As specific as possible."),
                    tr("Warum ist dir das wichtig?", "Why does it matter to you?"),
                    tr("Bis wann – und woran merkst du, dass du es geschafft hast?", "By when – and how will you know you've made it?"),
                    tr("Was ist der erste kleine Schritt diese Woche?", "What's the first small step this week?")]
        case .free:
            return [tr("Was geht dir durch den Kopf?", "What's on your mind?")]
        }
    }

    /// Suggested by time of day: check-in and plan in the morning, review in the evening.
    static func suggested(at date: Date = Date()) -> JournalKind {
        let hour = Calendar.current.component(.hour, from: date)
        if hour >= 18 { return .review }
        if hour < 11 { return .planDay }
        return .checkIn
    }
}

/// 1–5 scales for the check-in.
enum CheckInScale: String, Codable, CaseIterable, Identifiable, CodingKeyRepresentable {
    case mood, energy, stress, sleep, focus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mood: return tr("Stimmung", "Mood")
        case .energy: return tr("Energie", "Energy")
        case .stress: return tr("Stress", "Stress")
        case .sleep: return tr("Schlaf", "Sleep")
        case .focus: return tr("Konzentration", "Focus")
        }
    }

    var symbol: String {
        switch self {
        case .mood: return "face.smiling"
        case .energy: return "bolt.fill"
        case .stress: return "waveform.path"
        case .sleep: return "bed.double.fill"
        case .focus: return "scope"
        }
    }

    /// For stress, low is good.
    var lowIsGood: Bool { self == .stress }
}

struct JournalAnswer: Codable, Equatable, Hashable {
    var question: String
    var answer: String
    /// Asked by Fenn as a follow-up.
    var isFollowUp = false
}

struct JournalEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: JournalKind
    var date = Date()
    var scales: [CheckInScale: Int] = [:]
    var answers: [JournalAnswer] = []
    /// Day plan: up to three priorities.
    var priorities: [String] = []
    /// Fenn's short reflection or recommendation.
    var reflection: String?

    var day: String { FennVault.dayKey(date) }
}

enum JournalMarkdown {
    /// One Markdown file per day, entries in order.
    static func render(_ entries: [JournalEntry]) -> String {
        guard let first = entries.first else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: tr("de_DE", "en_US"))
        formatter.dateFormat = "EEEE, d. MMMM yyyy"
        var lines = ["# Journal, \(formatter.string(from: first.date))", ""]
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            lines.append("## \(heading(entry.kind)), \(entry.date.formatted(date: .omitted, time: .shortened))")
            if !entry.scales.isEmpty {
                lines.append(CheckInScale.allCases.compactMap { scale in entry.scales[scale].map { "\(scale.title) \($0)/5" } }.joined(separator: ", "))
                lines.append("")
            }
            if !entry.priorities.isEmpty {
                lines.append("**\(tr("Prioritäten", "Priorities"))**")
                lines += entry.priorities.map { "- [ ] \($0)" }
                lines.append("")
            }
            for answer in entry.answers where !answer.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("**\(answer.isFollowUp ? "Fenn: " : "")\(answer.question)**")
                lines.append(answer.answer.trimmingCharacters(in: .whitespacesAndNewlines))
                lines.append("")
            }
            if let reflection = entry.reflection, !reflection.isEmpty {
                lines.append("> Fenn: \(reflection.replacingOccurrences(of: "\n", with: "\n> "))")
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Headings are fixed German keys so the Mac can find them regardless of language.
    static func heading(_ kind: JournalKind) -> String {
        switch kind {
        case .checkIn: return "Check-in"
        case .planDay: return "Tagesplan"
        case .review: return "Rückblick"
        case .goals: return "Ziele"
        case .free: return "Notiz"
        }
    }

    /// Open priorities of the latest day plan in a day's file.
    static func priorities(in markdown: String) -> [String] {
        var result: [String] = []
        var inPlan = false
        for line in markdown.components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                inPlan = line.hasPrefix("## Tagesplan")
                if inPlan { result = [] }
            } else if inPlan, line.hasPrefix("- [ ] ") {
                result.append(String(line.dropFirst(6)))
            }
        }
        return result
    }

    /// A goal entry as a block for profile/goals.md.
    static func goalBlock(_ entry: JournalEntry) -> String {
        let answers = entry.answers.filter { !$0.answer.isEmpty }
        guard let goal = answers.first?.answer else { return "" }
        var lines = ["", "## \(goal.components(separatedBy: "\n").first ?? goal)", "_\(tr("gesetzt am", "set on")) \(entry.day)_", ""]
        for answer in answers.dropFirst() { lines.append("- **\(answer.question)** \(answer.answer)") }
        return lines.joined(separator: "\n") + "\n"
    }
}

/// Fenn's follow-up question and short reflection, through whichever model is set up.
enum JournalCoach {
    static let system = """
    Du bist Fenn, ein warmer, klarer Begleiter für Menschen, die konzentriert arbeiten wollen. Du hilfst beim Journaling über Arbeit, Fokus und Verfassung. \
    Keine Diagnosen. Bei Hinweisen auf Krisen, anhaltende Niedergeschlagenheit oder starke Schmerzen empfiehlst du freundlich \
    professionelle Hilfe (Ärztin, Therapeut, in Deutschland Telefonseelsorge 0800 111 0 111). \
    Sprache wie der Nutzer, du-Form, kurz.
    """

    /// One open question that goes a level deeper. Nil when no model is set up.
    static func followUp(for entry: JournalEntry) async -> String? {
        guard FennAI.isConfigured else { return nil }
        let prompt = """
        Journal-Art: \(entry.kind.title)
        \(context(entry))

        Stell genau EINE offene Rückfrage (höchstens 20 Wörter), die hilft, besser zu verstehen, wie es der Person geht, \
        oder die den Plan bzw. das Ziel schärft. Nur die Frage, ohne Einleitung.
        """
        guard let reply = try? await FennAI.ask(prompt, system: system, maxTokens: 120, timeout: 45) else { return nil }
        let question = reply.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"„“")))
        return question.isEmpty ? nil : question
    }

    /// Two or three sentences: what Fenn noticed and one concrete recommendation for today or tomorrow.
    static func reflection(for entry: JournalEntry, recentContext: String) async -> String? {
        guard FennAI.isConfigured else { return nil }
        let prompt = """
        Journal-Art: \(entry.kind.title)
        \(context(entry))

        Letzte Tage (Aufgaben, Fokus, frühere Einträge):
        \(recentContext.isEmpty ? "keine Daten" : recentContext)

        Antworte in höchstens drei Sätzen: was dir auffällt und eine konkrete Empfehlung für den Tag, den Fokus oder die Pausen.
        Erfinde keine Zahlen, die oben nicht stehen.
        """
        return try? await FennAI.ask(prompt, system: system, maxTokens: 300, timeout: 60).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func context(_ entry: JournalEntry) -> String {
        var lines: [String] = []
        if !entry.scales.isEmpty {
            lines.append(CheckInScale.allCases.compactMap { scale in entry.scales[scale].map { "\(scale.title) \($0)/5" } }.joined(separator: ", "))
        }
        if !entry.priorities.isEmpty { lines.append("Prioritäten: " + entry.priorities.joined(separator: "; ")) }
        for answer in entry.answers where !answer.answer.isEmpty { lines.append("\(answer.question) → \(answer.answer)") }
        return lines.joined(separator: "\n")
    }
}
