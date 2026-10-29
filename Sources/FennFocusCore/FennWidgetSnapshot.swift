import Foundation

/// What the Mac desktop widgets show. Written by the host into the App Group, read by the widget extension.
public struct FennWidgetSnapshot: Codable, Equatable {
    public var day: String
    public var german: Bool
    /// Today's finished focus time and blocks.
    public var focusMinutes: Int
    public var focusBlocks: Int
    public var tasksDone: Int
    /// Days in a row with a focus block, a finished task or a routine.
    public var streak: Int
    public var blockedUntil: Date?
    public var updated: Date
    /// Today's remaining meetings, earliest first.
    public var events: [FennWidgetEvent]?
    public var tasks: [FennWidgetTask]?
    public var goals: [String]?
    public var habits: [FennWidgetHabit]?
    /// Running or paused Pomodoro, or an idle clock with the current lengths.
    public var pomodoro: PomodoroSnapshot?
    public var focusTitle: String?

    public init(
        day: String, german: Bool, focusMinutes: Int, focusBlocks: Int, tasksDone: Int, streak: Int,
        blockedUntil: Date?, updated: Date, events: [FennWidgetEvent]?, tasks: [FennWidgetTask]?, goals: [String]?,
        habits: [FennWidgetHabit]?, pomodoro: PomodoroSnapshot?, focusTitle: String?
    ) {
        self.day = day
        self.german = german
        self.focusMinutes = focusMinutes
        self.focusBlocks = focusBlocks
        self.tasksDone = tasksDone
        self.streak = streak
        self.blockedUntil = blockedUntil
        self.updated = updated
        self.events = events
        self.tasks = tasks
        self.goals = goals
        self.habits = habits
        self.pomodoro = pomodoro
        self.focusTitle = focusTitle
    }

    public static let placeholder = FennWidgetSnapshot(
        day: "", german: true, focusMinutes: 95, focusBlocks: 2, tasksDone: 3, streak: 12, blockedUntil: nil, updated: Date(),
        events: [
            FennWidgetEvent(title: "Weekly Nordlicht", start: Date().addingTimeInterval(25 * 60), end: Date().addingTimeInterval(85 * 60), canJoin: true),
            FennWidgetEvent(title: "Design Review", start: Date().addingTimeInterval(3 * 3600), end: Date().addingTimeInterval(4 * 3600), canJoin: false)
        ],
        tasks: [
            FennWidgetTask(id: "1", title: "Angebotsentwurf schicken", done: false, detail: "heute, 45 min", high: true),
            FennWidgetTask(id: "2", title: "Q4-Pitch-Deck", done: false, detail: "morgen", high: true),
            FennWidgetTask(id: "3", title: "Reisekosten abrechnen", done: true, detail: nil, high: false)
        ],
        goals: ["Q4-Pitch bis Freitag"],
        habits: [
            FennWidgetHabit(id: "1", title: "Ein Glas Wasser", done: true, detail: "Nach dem Aufstehen", streak: 61, symbol: "drop"),
            FennWidgetHabit(id: "2", title: "Tag planen", done: false, detail: "Morgens", streak: 51, symbol: "sunrise"),
            FennWidgetHabit(id: "3", title: "10 Minuten lesen", done: false, detail: "Abends", streak: 40, symbol: "book")
        ],
        pomodoro: PomodoroSnapshot(settings: .starter, phase: "work", phaseStartedAt: Date(), phaseEndsAt: Date().addingTimeInterval(50 * 60),
                                   sessionStartedAt: Date(), sessionEndsAt: Date().addingTimeInterval(8 * 3600)),
        focusTitle: "Fokus"
    )

    public static var empty: FennWidgetSnapshot {
        FennWidgetSnapshot(
            day: "-", german: Locale.current.language.languageCode?.identifier != "en",
            focusMinutes: 0, focusBlocks: 0, tasksDone: 0, streak: 0, blockedUntil: nil, updated: Date(),
            events: nil, tasks: nil, goals: nil, habits: nil, pomodoro: nil, focusTitle: nil
        )
    }

    public var withoutDayValues: FennWidgetSnapshot {
        var copy = self
        copy.focusMinutes = 0
        copy.focusBlocks = 0
        copy.tasksDone = 0
        copy.events = nil
        copy.habits = nil
        return copy
    }

    public func sameContent(as other: FennWidgetSnapshot) -> Bool {
        var left = self
        var right = other
        left.updated = .distantPast
        right.updated = .distantPast
        return left == right
    }

    /// Team-prefixed: on macOS such a group needs no provisioning profile, so the sandboxed widgets of a
    /// DMG build (signed with the Apple Development certificate) can read it without a prompt.
    /// From the Info.plist (`FENN_APP_GROUP` in Config/Base.xcconfig): the team-prefixed group shared with the widgets.
    public static let groupID = Bundle.main.object(forInfoDictionaryKey: "FennAppGroup") as? String ?? "app.fennfocus"

    public static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent("fenn-widget.json")
    }

    public static func load() -> FennWidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(FennWidgetSnapshot.self, from: data)
    }

    public func save() {
        guard let url = Self.url else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(self) { try? data.write(to: url, options: .atomic) }
    }
}

public struct FennWidgetEvent: Codable, Equatable, Sendable {
    public var title: String
    public var start: Date
    public var end: Date
    /// Has a Teams, Zoom, Meet or Webex link.
    public var canJoin: Bool

    public init(title: String, start: Date, end: Date, canJoin: Bool) {
        self.title = title
        self.start = start
        self.end = end
        self.canJoin = canJoin
    }
}

public struct FennWidgetTask: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var done: Bool
    public var detail: String?
    public var high: Bool

    public init(id: String, title: String, done: Bool, detail: String?, high: Bool) {
        self.id = id
        self.title = title
        self.done = done
        self.detail = detail
        self.high = high
    }
}

public struct FennWidgetHabit: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var done: Bool
    public var detail: String?
    public var streak: Int
    public var symbol: String

    public init(id: String, title: String, done: Bool, detail: String?, streak: Int, symbol: String) {
        self.id = id
        self.title = title
        self.done = done
        self.detail = detail
        self.streak = streak
        self.symbol = symbol
    }
}

/// Ticks from the widget wait here until the host applies them to the real stores.
public enum FennWidgetActions {
    public static let pingName = "app.fennfocus.widget.actions" as CFString

    public static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: FennWidgetSnapshot.groupID)?
            .appendingPathComponent("fenn-widget-actions.json")
    }

    public static func enqueue(_ id: String) {
        guard let url else { return }
        var queue = (try? JSONDecoder().decode([String].self, from: Data(contentsOf: url))) ?? []
        queue.append(id)
        if let data = try? JSONEncoder().encode(queue) { try? data.write(to: url, options: .atomic) }
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(pingName), nil, nil, true)
    }

    public static func drain() -> [String] {
        guard let url, let data = try? Data(contentsOf: url), let queue = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        try? FileManager.default.removeItem(at: url)
        var counts: [String: Int] = [:]
        for id in queue { counts[id, default: 0] += 1 }
        return counts.filter { $0.value % 2 == 1 }.map(\.key)
    }
}
