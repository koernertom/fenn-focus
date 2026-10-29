import Foundation

// Pomodoro clock and distraction rules, shared by the app and the widgets.
// Keep the copy in iOSApp/FennBlockMonitor/RhythmCore.swift identical.

public enum FennBlockNames {
    public static let manualStore = "fenn.block"
    public static let scheduleStore = "fenn.schedule"
    public static let manualActivity = "fenn.block"
    public static let rulesKey = "fenn.block.rules"
    public static let rulesSeededKey = "fenn.block.rules.seeded"
    public static let socialSelectionKey = "fenn.block.social.selection"
    public static let youTubeKey = "fenn.block.youtubeWeb"
    public static let endsAtKey = "fenn.block.endsAt"
    public static let activityNamesKey = "fenn.block.activityNames"
    public static let pendingVoiceKey = "fenn.pomodoro.pending"
    public static let voiceNotification = "fenn.pomodoro.voice"

    public static func ruleSelectionKey(_ id: UUID) -> String { "fenn.block.rule.\(id.uuidString).selection" }
}

public struct DistractionRule: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var startMinutes: Int
    public var endMinutes: Int
    /// Calendar weekday, Sunday = 1 … Saturday = 7.
    public var weekdays: [Int]
    public var enabled: Bool
    /// "social" uses the shared Social-Media selection; "custom" uses this rule's own apps.
    public var target: String

    public init(id: UUID = UUID(), title: String, startMinutes: Int, endMinutes: Int, weekdays: [Int], enabled: Bool, target: String) {
        self.id = id
        self.title = title
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.weekdays = weekdays
        self.enabled = enabled
        self.target = target
    }

    public var isSocial: Bool { target == "social" }

    public static let socialMorning = DistractionRule(
        id: UUID(uuidString: "6A8E0006-0008-4000-8000-000000000608")!,
        title: "Kein Social Media",
        startMinutes: 6 * 60,
        endMinutes: 8 * 60,
        weekdays: Array(1...7),
        enabled: true,
        target: "social"
    )

    public static func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
    }

    public var windowLabel: String { "\(Self.clock(startMinutes))–\(Self.clock(endMinutes))" }
}

public enum DistractionSchedule {
    /// Screen Time refuses windows shorter than this. Shorter rules still run while the app is open.
    public static let minimumDeviceMinutes = 15

    public static func isActive(_ rule: DistractionRule, at date: Date, calendar: Calendar = .current) -> Bool {
        guard rule.enabled, rule.endMinutes != rule.startMinutes else { return false }
        let weekday = calendar.component(.weekday, from: date)
        let minutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        if rule.endMinutes > rule.startMinutes {
            return rule.weekdays.contains(weekday) && minutes >= rule.startMinutes && minutes < rule.endMinutes
        }
        if minutes >= rule.startMinutes { return rule.weekdays.contains(weekday) }
        if minutes < rule.endMinutes {
            let yesterday = calendar.date(byAdding: .day, value: -1, to: date) ?? date
            return rule.weekdays.contains(calendar.component(.weekday, from: yesterday))
        }
        return false
    }

    /// When the current window ends, if the rule is active now.
    public static func windowEnd(_ rule: DistractionRule, from date: Date, calendar: Calendar = .current) -> Date? {
        guard isActive(rule, at: date, calendar: calendar) else { return nil }
        let startOfDay = calendar.startOfDay(for: date)
        let minutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        if rule.endMinutes > rule.startMinutes || minutes < rule.endMinutes {
            return calendar.date(byAdding: .minute, value: rule.endMinutes, to: startOfDay)
        }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        return calendar.date(byAdding: .minute, value: rule.endMinutes, to: tomorrow)
    }

    public struct Interval: Equatable, Sendable {
        public var start: DateComponents
        public var end: DateComponents
    }

    /// Repeating Screen Time intervals. Empty when the window is under 15 minutes (the app enforces those itself).
    public static func deviceIntervals(for rule: DistractionRule) -> [Interval] {
        guard rule.enabled else { return [] }
        if rule.endMinutes > rule.startMinutes {
            let length = rule.endMinutes - rule.startMinutes
            guard length >= minimumDeviceMinutes else { return [] }
            return [Interval(start: components(rule.startMinutes), end: components(rule.endMinutes))]
        }
        var result: [Interval] = []
        let untilMidnight = 24 * 60 - rule.startMinutes
        if untilMidnight >= minimumDeviceMinutes {
            result.append(Interval(start: components(rule.startMinutes), end: DateComponents(hour: 23, minute: 59)))
        }
        if rule.endMinutes >= minimumDeviceMinutes {
            result.append(Interval(start: DateComponents(hour: 0, minute: 0), end: components(rule.endMinutes)))
        }
        return result
    }

    public static func activityNames(for rule: DistractionRule) -> [String] {
        let prefix = String(rule.id.uuidString.prefix(8)).lowercased()
        return deviceIntervals(for: rule).enumerated().map { "fenn.s.\(prefix).\($0.offset)" }
    }

    public static func seed(_ rules: [DistractionRule], seeded: Bool) -> (rules: [DistractionRule], seeded: Bool) {
        if seeded { return (rules, true) }
        if rules.contains(where: { $0.id == DistractionRule.socialMorning.id }) { return (rules, true) }
        return (rules + [DistractionRule.socialMorning], true)
    }

    private static func components(_ minutes: Int) -> DateComponents {
        DateComponents(hour: minutes / 60, minute: minutes % 60)
    }
}

public struct DistractionVoiceDraft: Equatable, Sendable {
    public var startMinutes: Int
    public var endMinutes: Int
    public var social: Bool
    public var weekdays: [Int]
    public var title: String

    public init(startMinutes: Int, endMinutes: Int, social: Bool, weekdays: [Int], title: String) {
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.social = social
        self.weekdays = weekdays
        self.title = title
    }
}

public enum DistractionVoice {
    public static func parse(_ raw: String) -> DistractionVoiceDraft? {
        var text = raw.lowercased()
        text = text.replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: "—", with: "-")
        text = text.replacingOccurrences(of: " bis ", with: " - ")
        guard let times = match(#"(\d{1,2})(?:[:.](\d{2}))?\s*(?:uhr)?\s*-\s*(\d{1,2})(?:[:.](\d{2}))?"#, in: text),
              times.count >= 4,
              let startHour = Int(times[1]), let endHour = Int(times[3]),
              startHour <= 23, endHour <= 23 else { return nil }
        let startMinute = Int(times[2]) ?? 0
        let endMinute = Int(times[4]) ?? 0
        guard startMinute < 60, endMinute < 60 else { return nil }
        let social = ["social", "soziale", "sozialen", "instagram", "tiktok", "facebook", "snapchat", "twitter", "reddit"]
            .contains { text.contains($0) }
        let blocking = social || ["sperr", "block", "kein", "keine", "ohne", "regel", "ablenk", "no social"].contains { text.contains($0) }
        guard blocking else { return nil }
        let start = startHour * 60 + startMinute
        let end = endHour * 60 + endMinute
        guard start != end else { return nil }
        let days = weekdays(in: text)
        return DistractionVoiceDraft(
            startMinutes: start,
            endMinutes: end,
            social: social,
            weekdays: days,
            title: social ? "Kein Social Media" : "Sperre"
        )
    }

    private static func weekdays(in text: String) -> [Int] {
        if text.contains("wochenende") || text.contains("weekend") { return [1, 7] }
        if text.contains("werktag") || text.contains("wochentag") || text.contains("weekday")
            || text.contains("montag bis freitag") || text.contains("mo-fr") || text.contains("mo bis fr") {
            return [2, 3, 4, 5, 6]
        }
        let named: [(String, Int)] = [
            ("sonntag", 1), ("sunday", 1), ("montag", 2), ("monday", 2), ("dienstag", 3), ("tuesday", 3),
            ("mittwoch", 4), ("wednesday", 4), ("donnerstag", 5), ("thursday", 5), ("freitag", 6), ("friday", 6),
            ("samstag", 7), ("saturday", 7),
        ]
        let found = named.filter { text.contains($0.0) }.map(\.1)
        return found.isEmpty ? Array(1...7) : Array(Set(found)).sorted()
    }
}

public struct PomodoroSettings: Codable, Equatable, Sendable {
    public var totalMinutes: Int
    public var workMinutes: Int
    public var breakMinutes: Int

    public init(totalMinutes: Int, workMinutes: Int, breakMinutes: Int) {
        self.totalMinutes = totalMinutes
        self.workMinutes = workMinutes
        self.breakMinutes = breakMinutes
    }

    public static let starter = PomodoroSettings(totalMinutes: 8 * 60, workMinutes: 50, breakMinutes: 10)

    public func clamped() -> PomodoroSettings {
        PomodoroSettings(
            totalMinutes: min(24 * 60, max(1, totalMinutes)),
            workMinutes: min(12 * 60, max(1, workMinutes)),
            breakMinutes: min(3 * 60, max(1, breakMinutes))
        )
    }
}

public struct PomodoroSnapshot: Codable, Equatable, Sendable {
    public var settings: PomodoroSettings
    public var phase: String
    public var pausedKind: String?
    public var phaseStartedAt: Date?
    public var phaseEndsAt: Date?
    public var sessionStartedAt: Date?
    public var sessionEndsAt: Date?
    public var pausedRemaining: TimeInterval?
    public var sessionRemaining: TimeInterval?
    public var focusedSeconds: TimeInterval
    public var completedWorkBlocks: Int

    public init(settings: PomodoroSettings, phase: String, pausedKind: String? = nil, phaseStartedAt: Date? = nil,
                phaseEndsAt: Date? = nil, sessionStartedAt: Date? = nil, sessionEndsAt: Date? = nil,
                pausedRemaining: TimeInterval? = nil, sessionRemaining: TimeInterval? = nil,
                focusedSeconds: TimeInterval = 0, completedWorkBlocks: Int = 0) {
        self.settings = settings
        self.phase = phase
        self.pausedKind = pausedKind
        self.phaseStartedAt = phaseStartedAt
        self.phaseEndsAt = phaseEndsAt
        self.sessionStartedAt = sessionStartedAt
        self.sessionEndsAt = sessionEndsAt
        self.pausedRemaining = pausedRemaining
        self.sessionRemaining = sessionRemaining
        self.focusedSeconds = focusedSeconds
        self.completedWorkBlocks = completedWorkBlocks
    }
}

public enum PomodoroClock {
    public static func begin(_ settings: PomodoroSettings, at now: Date) -> PomodoroSnapshot {
        let settings = settings.clamped()
        let sessionEnd = now.addingTimeInterval(TimeInterval(settings.totalMinutes * 60))
        let work = min(TimeInterval(settings.workMinutes * 60), max(1, sessionEnd.timeIntervalSince(now)))
        return PomodoroSnapshot(
            settings: settings,
            phase: "work",
            phaseStartedAt: now,
            phaseEndsAt: now.addingTimeInterval(work),
            sessionStartedAt: now,
            sessionEndsAt: sessionEnd
        )
    }

    /// Moves a running snapshot forward to `now`, finishing every block whose end has passed.
    public static func catchUp(_ snapshot: PomodoroSnapshot, now: Date) -> PomodoroSnapshot {
        var snap = snapshot
        guard snap.phase == "work" || snap.phase == "break", let sessionEnds = snap.sessionEndsAt else { return snap }
        var guardrail = 0
        while let end = snap.phaseEndsAt, now >= end, guardrail < 2000 {
            guardrail += 1
            if snap.phase == "work" {
                if let started = snap.phaseStartedAt { snap.focusedSeconds += max(0, end.timeIntervalSince(started)) }
                snap.completedWorkBlocks += 1
                if end >= sessionEnds { snap.phase = "done"; snap.phaseEndsAt = nil; snap.phaseStartedAt = nil; break }
                let breakLen = min(TimeInterval(snap.settings.breakMinutes * 60), sessionEnds.timeIntervalSince(end))
                if breakLen < 1 { snap.phase = "done"; snap.phaseEndsAt = nil; snap.phaseStartedAt = nil; break }
                snap.phase = "break"
                snap.phaseStartedAt = end
                snap.phaseEndsAt = end.addingTimeInterval(breakLen)
            } else {
                if end >= sessionEnds { snap.phase = "done"; snap.phaseEndsAt = nil; snap.phaseStartedAt = nil; break }
                let workLen = min(TimeInterval(snap.settings.workMinutes * 60), sessionEnds.timeIntervalSince(end))
                if workLen < 1 { snap.phase = "done"; snap.phaseEndsAt = nil; snap.phaseStartedAt = nil; break }
                snap.phase = "work"
                snap.phaseStartedAt = end
                snap.phaseEndsAt = end.addingTimeInterval(workLen)
            }
        }
        return snap
    }

    public static func pause(_ snapshot: PomodoroSnapshot, at now: Date) -> PomodoroSnapshot {
        var snap = catchUp(snapshot, now: now)
        guard snap.phase == "work" || snap.phase == "break" else { return snap }
        if snap.phase == "work", let started = snap.phaseStartedAt {
            snap.focusedSeconds += max(0, now.timeIntervalSince(started))
        }
        snap.pausedKind = snap.phase
        snap.pausedRemaining = max(0, snap.phaseEndsAt?.timeIntervalSince(now) ?? 0)
        snap.sessionRemaining = max(0, snap.sessionEndsAt?.timeIntervalSince(now) ?? 0)
        snap.phase = "paused"
        snap.phaseStartedAt = nil
        snap.phaseEndsAt = nil
        return snap
    }

    public static func resume(_ snapshot: PomodoroSnapshot, at now: Date) -> PomodoroSnapshot {
        var snap = snapshot
        guard snap.phase == "paused" else { return catchUp(snap, now: now) }
        let phaseLeft = max(1, snap.pausedRemaining ?? 60)
        let sessionLeft = max(phaseLeft, snap.sessionRemaining ?? phaseLeft)
        snap.phase = snap.pausedKind ?? "work"
        snap.phaseStartedAt = now
        snap.phaseEndsAt = now.addingTimeInterval(min(phaseLeft, sessionLeft))
        snap.sessionEndsAt = now.addingTimeInterval(sessionLeft)
        snap.pausedRemaining = nil
        snap.sessionRemaining = nil
        return snap
    }

    public static func retarget(_ snapshot: PomodoroSnapshot, totalMinutes: Int, at now: Date) -> PomodoroSnapshot {
        var snap = snapshot
        let total = min(24 * 60, max(1, totalMinutes))
        snap.settings.totalMinutes = total
        guard let start = snap.sessionStartedAt else { return snap }
        let end = start.addingTimeInterval(TimeInterval(total * 60))
        snap.sessionEndsAt = end
        if snap.phase == "paused" {
            snap.sessionRemaining = max(0, end.timeIntervalSince(now))
        } else if let phaseEnd = snap.phaseEndsAt, phaseEnd > end {
            snap.phaseEndsAt = end
        }
        if now >= end, snap.phase == "work" || snap.phase == "break" {
            return catchUp(snap, now: now)
        }
        return snap
    }

    public static func clock(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds.rounded(.up)))
        if whole >= 3600 { return String(format: "%d:%02d:%02d", whole / 3600, whole % 3600 / 60, whole % 60) }
        return String(format: "%02d:%02d", whole / 60, whole % 60)
    }
}

public struct PomodoroVoiceChange: Codable, Equatable, Sendable {
    public var totalMinutes: Int?
    public var workMinutes: Int?
    public var breakMinutes: Int?
    public var start: Bool

    public init(totalMinutes: Int? = nil, workMinutes: Int? = nil, breakMinutes: Int? = nil, start: Bool = false) {
        self.totalMinutes = totalMinutes
        self.workMinutes = workMinutes
        self.breakMinutes = breakMinutes
        self.start = start
    }

    public var changesAnything: Bool { start || totalMinutes != nil || workMinutes != nil || breakMinutes != nil }
}

public enum PomodoroVoice {
    public static func parse(_ raw: String) -> PomodoroVoiceChange? {
        let text = raw.lowercased()
        let hasPomo = text.contains("pomodoro")
        let hasFocus = text.contains("fokus") || text.contains("focus")
        let hasWorkLabel = text.contains("arbeits") || text.contains("work minute")
            || match(#"\d+\s*(?:minuten|min|minutes|stunden|stunde|hours|hour|h)\s*arbeit"#, in: text) != nil
        let hasBreakLabel = text.contains("pausen") || text.contains("break minute")
            || match(#"\d+\s*(?:minuten|min|minutes)\s*pause"#, in: text) != nil
        let hasTotalLabel = text.contains("gesamt") || text.contains("fenster") || text.contains("insgesamt") || text.contains("total")
        guard hasPomo || hasFocus || hasWorkLabel || hasBreakLabel || hasTotalLabel else { return nil }

        var change = PomodoroVoiceChange()
        if let ratio = match(#"(\d+)\s*/\s*(\d+)"#, in: text), let work = Int(ratio[1]), let brk = Int(ratio[2]) {
            change.workMinutes = work
            change.breakMinutes = brk
        }
        if let hours = match(#"(\d+)\s*(?:stunden|stunde|hours|hour|h)\s*arbeit"#, in: text), let value = Int(hours[1]) {
            change.workMinutes = value * 60
        } else if let mins = match(#"(\d+)\s*(?:minuten|min|minutes)\s*arbeit"#, in: text), let value = Int(mins[1]) {
            change.workMinutes = value
        } else if let labeled = match(#"arbeits?(?:minuten|zeit|minutes)?\s*(?:auf\s+)?(\d+)"#, in: text), let value = Int(labeled[1]) {
            change.workMinutes = value
        }
        if let mins = match(#"(\d+)\s*(?:minuten|min|minutes)\s*pause"#, in: text), let value = Int(mins[1]) {
            change.breakMinutes = value
        } else if let labeled = match(#"pausen?(?:minuten|zeit|minutes)?\s*(?:auf\s+)?(\d+)"#, in: text), let value = Int(labeled[1]) {
            change.breakMinutes = value
        }
        if let labeled = match(#"(?:gesamt(?:dauer)?|fenster|insgesamt|total|session(?:dauer)?)\s*(?:auf\s+)?(\d+)\s*(stunden|stunde|hours|hour|h|minuten|min|minutes)?"#, in: text),
           let value = Int(labeled[1]) {
            change.totalMinutes = unit(labeled.count > 2 ? labeled[2] : "", value: value, nearbyHours: text.contains("stunde") || text.contains("hour"))
        } else if let hours = match(#"(\d+)\s*(?:stunden|stunde|hours|hour|h)\b"#, in: text), let value = Int(hours[1]),
                  match(#"(\d+)\s*(?:stunden|stunde|hours|hour|h)\s*arbeit"#, in: text) == nil,
                  (hasPomo || hasFocus || hasTotalLabel) {
            change.totalMinutes = value * 60
        }
        if change.workMinutes == nil, let mins = match(#"(\d+)\s*(?:minuten|min|minutes)\b"#, in: text), let value = Int(mins[1]),
           (hasFocus || hasPomo), !hasBreakLabel, change.breakMinutes == nil {
            let aroundPause = text.contains("pause")
            if !aroundPause { change.workMinutes = value }
        }
        let asking = text.contains("?") || text.hasPrefix("wie ") || text.hasPrefix("how ") || text.contains(" wie ") || text.contains(" how ")
        let start = !asking && match(#"\b(starte|starten|start|begin|leg los|fang an|jetzt starten|start now)\b"#, in: text) != nil
        change.start = start
        guard change.changesAnything else { return nil }
        return change
    }

    private static func unit(_ raw: String, value: Int, nearbyHours: Bool) -> Int {
        let unit = raw.lowercased()
        if unit.hasPrefix("stunde") || unit.hasPrefix("hour") || unit == "h" { return value * 60 }
        if unit.hasPrefix("min") { return value }
        if nearbyHours && value <= 24 { return value * 60 }
        return value
    }
}

private func match(_ pattern: String, in text: String) -> [String]? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
    let range = NSRange(text.startIndex..., in: text)
    guard let found = regex.firstMatch(in: text, options: [], range: range) else { return nil }
    return (0..<found.numberOfRanges).map { index in
        guard let slice = Range(found.range(at: index), in: text) else { return "" }
        return String(text[slice])
    }
}
