import EventKit
import Foundation

// What a day holds: appointments from the calendar, tasks with a time (blocks) and without (to fit in somewhere).
// Measures the load against the working hours, finds free gaps, fits untimed tasks into them, and – when the day is
// too full – proposes what to move: rule-based right away, better with the AI model. Nothing changes until applied.

/// An appointment on the day view (from Apple Calendar and subscribed feeds).
struct DayEvent: Identifiable, Equatable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var calendar: String
    /// Own event without other participants – Fenn may move it when you confirm.
    var movable: Bool

    var minutes: Int { max(0, Int(end.timeIntervalSince(start) / 60)) }
}

/// One proposed change: a task to another day or time, or an own appointment to another time.
struct DayChange: Identifiable, Equatable {
    /// `blocker`: the task is an appointment – it blocks its time instead of being a to-do.
    enum Target: Equatable { case task(UUID), event(DayEvent), blocker(UUID) }
    let id = UUID()
    var target: Target
    var title: String
    /// New start; a task without time gets the start of the day.
    var to: Date
    var timed: Bool
    var reason: String

    var summary: String {
        let when = timed ? TaskFormat.when(to) : TaskFormat.day(to)
        switch target {
        case .task: return tr("„\(title)“ → \(when)", "“\(title)” → \(when)")
        case .event: return tr("Termin „\(title)“ → \(when)", "Event “\(title)” → \(when)")
        case .blocker: return tr("„\(title)“ ist ein Termin – blockt Zeit, keine Aufgabe", "“\(title)” is an appointment – blocks time, not a task")
        }
    }
}

struct DayLoad {
    let day: Date
    let events: [DayEvent]
    /// Open tasks for the day (today: plus overdue ones).
    let tasks: [FennTask]
    let workStart: Date
    let workEnd: Date

    var timedTasks: [FennTask] { tasks.filter { $0.due.map(DayPlanner.hasTime) ?? false } }
    var untimedTasks: [FennTask] { tasks.filter { !($0.due.map(DayPlanner.hasTime) ?? false) } }
    var eventMinutes: Int { events.filter { !$0.isAllDay }.reduce(0) { $0 + DayPlanner.overlap($1.start, $1.end, workStart, workEnd) } }
    var taskMinutes: Int { tasks.reduce(0) { $0 + DayPlanner.minutes(of: $1) } }
    var capacityMinutes: Int { max(0, Int(workEnd.timeIntervalSince(workStart) / 60)) }
    /// Working time left after appointments (from now on, when it is today).
    var freeMinutes: Int { DayPlanner.gaps(in: self).reduce(0) { $0 + Int($1.duration / 60) } + timedTasks.reduce(0) { $0 + DayPlanner.minutes(of: $1) } }
    var plannedMinutes: Int { eventMinutes + taskMinutes }
    /// More to do than time left – with a little slack for small overruns.
    var isOverloaded: Bool { taskMinutes > Int(Double(freeMinutes) * 1.1) + 10 }
    var overloadMinutes: Int { max(0, taskMinutes - freeMinutes) }
}

@MainActor
enum DayPlanner {
    /// The day's appointments; the Mac sets its own source (calendar module incl. feeds).
    static var events: (Date) -> [DayEvent] = { TaskCalendarSync.shared.events(on: $0) }

    static var workHours: (start: Int, end: Int) {
        let defaults = UserDefaults.standard
        let start = defaults.object(forKey: "fenn.calendar.workStart") as? Int ?? 9
        let end = defaults.object(forKey: "fenn.calendar.workEnd") as? Int ?? 18
        return (start, max(start + 1, end))
    }

    static func load(on day: Date, tasks given: [FennTask]? = nil) -> DayLoad {
        let tasks = given ?? TaskStore.shared.tasks
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let isToday = cal.isDateInToday(day)
        let open = tasks.filter { task in
            guard !task.done, !task.isBlocker, let due = task.due else { return false }
            return cal.isDate(due, inSameDayAs: day) || (isToday && due < start)
        }
        // Tasks marked as appointments block their time like calendar events.
        let blockers = tasks.filter { !$0.done && $0.isBlocker && $0.due.map { cal.isDate($0, inSameDayAs: day) } == true }.compactMap { task -> DayEvent? in
            guard let due = task.due else { return nil }
            let timed = hasTime(due)
            return DayEvent(id: Self.blockerPrefix + task.id.uuidString, title: task.title, start: timed ? due : start,
                            end: timed ? due.addingTimeInterval(Double(task.estimateMinutes ?? 60) * 60) : start,
                            isAllDay: !timed, calendar: tr("Termin", "Appointment"), movable: false)
        }
        let taken = takenEvents
        let hours = workHours
        let workStart = cal.date(bySettingHour: hours.start, minute: 0, second: 0, of: start) ?? start
        let workEnd = cal.date(bySettingHour: hours.end, minute: 0, second: 0, of: start) ?? start
        let all = (events(day).filter { !taken.contains($0.id) } + blockers).sorted { $0.start < $1.start }
        return DayLoad(day: start, events: all, tasks: open.sorted { $0.rank < $1.rank }, workStart: workStart, workEnd: workEnd)
    }

    static let blockerPrefix = "task-"

    /// The task behind a blocker block on the day view.
    static func blockerTask(_ event: DayEvent) -> FennTask? {
        guard event.id.hasPrefix(blockerPrefix) else { return nil }
        let id = UUID(uuidString: String(event.id.dropFirst(blockerPrefix.count)))
        return TaskStore.shared.tasks.first { $0.id == id }
    }

    private static let takenKey = "fenn.day.eventsAsTasks"
    /// Calendar events turned into tasks – the task stands for them, so the event isn't shown twice.
    static var takenEvents: Set<String> { Set(UserDefaults.standard.stringArray(forKey: takenKey) ?? []) }

    /// "Das ist eine Aufgabe": a calendar event becomes a task at its time and length (the calendar stays as it is).
    static func takeAsTask(_ event: DayEvent) {
        var task = FennTask(title: event.title)
        task.due = event.isAllDay ? Calendar.current.startOfDay(for: event.start) : event.start
        task.estimateMinutes = event.isAllDay ? nil : max(15, event.minutes)
        TaskStore.shared.add(task)
        UserDefaults.standard.set(Array(takenEvents.union([event.id]).suffix(300)), forKey: takenKey)
    }

    nonisolated static func hasTime(_ date: Date) -> Bool {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) != 0 || (parts.minute ?? 0) != 0
    }

    nonisolated static func minutes(of task: FennTask) -> Int { max(15, (task.estimateMinutes ?? 30) - min(task.spentMinutes, (task.estimateMinutes ?? 30) - 15)) }

    nonisolated static func overlap(_ a: Date, _ b: Date, _ c: Date, _ d: Date) -> Int {
        max(0, Int((min(b, d).timeIntervalSince(max(a, c))) / 60))
    }

    /// Free stretches of at least 15 min in the working hours: minus appointments and timed tasks, and minus the past.
    nonisolated static func gaps(in load: DayLoad, now: Date = FennDemo.now) -> [DateInterval] {
        var from = load.workStart
        if Calendar.current.isDate(load.day, inSameDayAs: now) { from = max(from, roundUp(now)) }
        guard from < load.workEnd else { return [] }
        var busy = load.events.filter { !$0.isAllDay }.map { DateInterval(start: $0.start, end: max($0.start, $0.end)) }
        busy += load.timedTasks.compactMap { task in task.due.map { DateInterval(start: $0, duration: Double(minutes(of: task)) * 60) } }
        busy.sort { $0.start < $1.start }
        var result: [DateInterval] = []
        var cursor = from
        for block in busy where block.end > cursor {
            if block.start > cursor { result.append(DateInterval(start: cursor, end: min(block.start, load.workEnd))) }
            cursor = max(cursor, block.end)
            if cursor >= load.workEnd { break }
        }
        if cursor < load.workEnd { result.append(DateInterval(start: cursor, end: load.workEnd)) }
        return result.filter { $0.duration >= 15 * 60 }
    }

    nonisolated static func roundUp(_ date: Date, to minutes: Int = 15) -> Date {
        let seconds = Double(minutes * 60)
        return Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / seconds).rounded(.up) * seconds)
    }

    /// Untimed tasks into the free gaps, most important first; what doesn't fit stays untimed.
    static func fitIntoGaps(_ load: DayLoad) -> [DayChange] {
        var gaps = gaps(in: load)
        var changes: [DayChange] = []
        for task in load.untimedTasks {
            let need = Double(minutes(of: task)) * 60
            guard let index = gaps.firstIndex(where: { $0.duration >= need }) else { continue }
            let start = gaps[index].start
            changes.append(DayChange(target: .task(task.id), title: task.title, to: start, timed: true,
                                     reason: tr("freie Lücke", "free slot")))
            let rest = DateInterval(start: start.addingTimeInterval(need), end: gaps[index].end)
            if rest.duration >= 15 * 60 { gaps[index] = rest } else { gaps.remove(at: index) }
        }
        return changes
    }

    /// Too much for the day: the least important tasks move to the next days that still have room.
    static func relieve(_ load: DayLoad) -> [DayChange] {
        guard load.isOverloaded else { return [] }
        var excess = load.overloadMinutes
        var changes: [DayChange] = []
        var extra: [Date: Int] = [:]
        // Low priority and far-off estimates first; high priority stays.
        for task in load.tasks.sorted(by: { ($0.priority.rawValue, minutes(of: $0)) > ($1.priority.rawValue, minutes(of: $1)) }) {
            guard excess > 0, task.priority != .high else { break }
            let need = minutes(of: task)
            var target = Calendar.current.date(byAdding: .day, value: 1, to: load.day) ?? load.day
            for _ in 0..<7 {
                let next = self.load(on: target)
                if next.freeMinutes - next.taskMinutes - (extra[target] ?? 0) >= need { break }
                target = Calendar.current.date(byAdding: .day, value: 1, to: target) ?? target
            }
            extra[target, default: 0] += need
            excess -= need
            changes.append(DayChange(target: .task(task.id), title: task.title, to: target, timed: false,
                                     reason: tr("\(task.priority.title), dort ist Luft", "\(task.priority.title), room there")))
        }
        return changes
    }

    // MARK: AI

    static func suggest(_ load: DayLoad) async throws -> (summary: String, changes: [DayChange]) {
        let clock = DateFormatter()
        clock.dateFormat = "HH:mm"
        let dayKey = FennVault.dayKey(load.day)
        let events = load.events.filter { !$0.isAllDay }.map { event in
            "- \(clock.string(from: event.start))–\(clock.string(from: event.end)) \(event.title) [\(event.movable ? "verschiebbar" : "fix")]"
        }
        let tasks = load.tasks.map { task in
            var line = "- \(task.title), Priorität \(task.priority.storedName), ~\(minutes(of: task)) min"
            if let due = task.due, hasTime(due) { line += ", geplant \(clock.string(from: due))" }
            if let due = task.due, due < load.day { line += ", überfällig" }
            if !task.topic.isEmpty { line += ", #\(task.topic)" }
            return line
        }
        let gaps = gaps(in: load).map { "\(clock.string(from: $0.start))–\(clock.string(from: $0.end))" }
        let tomorrow = self.load(on: Calendar.current.date(byAdding: .day, value: 1, to: load.day) ?? load.day)
        let weekday = DateFormatter()
        weekday.locale = Locale(identifier: "de_DE")
        weekday.dateFormat = "EEEE"
        let nextDays = (1...3).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: load.day) }
            .map { "\(FennVault.dayKey($0)) = \(weekday.string(from: $0))" }.joined(separator: ", ")
        let prompt = """
        Tag: \(dayKey) (\(weekday.string(from: load.day))). Nächste Tage: \(nextDays). Arbeitszeit \(clock.string(from: load.workStart))–\(clock.string(from: load.workEnd)).
        Termine:
        \(events.isEmpty ? "keine" : events.joined(separator: "\n"))
        Aufgaben:
        \(tasks.isEmpty ? "keine" : tasks.joined(separator: "\n"))
        Freie Lücken: \(gaps.isEmpty ? "keine" : gaps.joined(separator: ", "))
        Aufgaben-Zeit \(load.taskMinutes) min, freie Zeit \(load.freeMinutes) min. Morgen frei: \(max(0, tomorrow.freeMinutes - tomorrow.taskMinutes)) min.

        Mach einen realistischen Plan: Wichtiges bleibt heute und bekommt eine Uhrzeit in einer freien Lücke; was nicht passt, \
        verschiebst du auf einen der nächsten Tage (niedrige Priorität zuerst). Termine nur verschieben, wenn sie „verschiebbar“ \
        sind und es wirklich Luft schafft. Ist eine „Aufgabe“ in Wahrheit ein Termin oder eine Aktivität mit fester Zeit \
        (Geburtstag, Arzt, Treffen, Sport), nenn sie unter "blocker" – sie blockt dann Zeit und ist keine Aufgabe mehr. \
        Antworte ausschließlich mit JSON: {"summary": "1–2 Sätze auf Deutsch, du-Form", \
        "tasks": [{"title": "exakter Aufgabentitel", "day": "YYYY-MM-DD", "time": "HH:MM oder leer", "reason": "kurz"}], \
        "events": [{"title": "exakter Termintitel", "time": "HH:MM", "reason": "kurz"}], "blocker": ["exakter Aufgabentitel"]}
        """
        let reply = try await FennAI.ask(prompt, system: "Du bist Fenn, ein nüchterner Tagesplaner. Nur realistische, wenige Änderungen.",
                                         maxTokens: 1500, timeout: 120, json: true)
        guard let data = FennAI.json(in: reply), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UnreadablePlan()
        }
        var changes: [DayChange] = []
        var blocked = Set<UUID>()
        for title in object["blocker"] as? [String] ?? [] {
            guard let task = load.tasks.first(where: { $0.title.lowercased() == title.lowercased() }), blocked.insert(task.id).inserted else { continue }
            changes.append(DayChange(target: .blocker(task.id), title: task.title, to: task.due ?? load.day, timed: false, reason: ""))
        }
        for item in object["tasks"] as? [[String: Any]] ?? [] {
            guard let title = item["title"] as? String,
                  let task = load.tasks.first(where: { $0.title.lowercased() == title.lowercased() })
                      ?? load.tasks.first(where: { $0.title.lowercased().contains(title.lowercased()) }), !blocked.contains(task.id) else { continue }
            let day = (item["day"] as? String).flatMap(AgentDates.day) ?? load.day
            var to = Calendar.current.startOfDay(for: day)
            var timed = false
            if let time = item["time"] as? String, let at = at(time, on: day) { to = at; timed = true }
            if let due = task.due, timed == hasTime(due), due == to { continue }
            changes.append(DayChange(target: .task(task.id), title: task.title, to: to, timed: timed, reason: item["reason"] as? String ?? ""))
        }
        for item in object["events"] as? [[String: Any]] ?? [] {
            guard let title = item["title"] as? String, let event = load.events.first(where: { $0.title == title && $0.movable }),
                  let time = item["time"] as? String, let to = at(time, on: load.day), to != event.start else { continue }
            changes.append(DayChange(target: .event(event), title: event.title, to: to, timed: true, reason: item["reason"] as? String ?? ""))
        }
        return ((object["summary"] as? String) ?? "", changes)
    }

    nonisolated static func at(_ time: String, on day: Date) -> Date? {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day)
    }

    /// Carries out one change; false when an appointment couldn't be moved.
    @discardableResult
    static func apply(_ change: DayChange) -> Bool {
        switch change.target {
        case .task(let id):
            guard var task = TaskStore.shared.tasks.first(where: { $0.id == id }) else { return false }
            task.due = change.timed ? change.to : Calendar.current.startOfDay(for: change.to)
            if let start = task.start, let due = task.due, start > due { task.start = Calendar.current.startOfDay(for: due) }
            TaskStore.shared.update(task)
            return true
        case .event(let event):
            return TaskCalendarSync.shared.move(event, to: change.to)
        case .blocker(let id):
            TaskStore.shared.setBlocker(id, true)
            return true
        }
    }

    /// Moves a task block to a new time on the day view (15-minute steps).
    static func reschedule(_ task: FennTask, to start: Date) {
        var copy = task
        copy.due = roundUp(start.addingTimeInterval(-7 * 60), to: 15)
        TaskStore.shared.update(copy)
    }
}

extension TaskFormat {
    /// "heute 14:30", "Fr. 09:00", or just the day when there's no time.
    static func when(_ date: Date) -> String {
        guard DayPlanner.hasTime(date) else { return day(date) }
        let clock = DateFormatter()
        clock.dateFormat = "HH:mm"
        return "\(day(date)) \(clock.string(from: date))"
    }
}

// MARK: - Calendar access for the day view

extension TaskCalendarSync {
    /// The day's appointments from Apple Calendar – without Fenn's own task calendar.
    func events(on day: Date) -> [DayEvent] {
        guard hasAccess, !FennDemo.isOn else { return FennDemo.isOn ? DayPlanner.demoEvents(day) : [] }
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        let calendars = eventStore.calendars(for: .event).filter { $0.title != Self.calendarTitle }
        guard !calendars.isEmpty else { return [] }
        return eventStore.events(matching: eventStore.predicateForEvents(withStart: start, end: end, calendars: calendars)).map { event in
            DayEvent(id: event.calendarItemIdentifier + "|\(event.startDate.timeIntervalSince1970)", title: event.title ?? tr("Termin", "Event"),
                     start: event.startDate, end: event.endDate, isAllDay: event.isAllDay, calendar: event.calendar.title,
                     movable: event.calendar.allowsContentModifications && !(event.hasAttendees) && !event.hasRecurrenceRules)
        }
        .sorted { $0.start < $1.start }
    }

    /// Moves an own appointment (same length) – only ones without participants and repeats.
    func move(_ event: DayEvent, to start: Date) -> Bool {
        guard hasAccess, event.movable else { return false }
        let id = String(event.id.split(separator: "|").first ?? "")
        let found = (eventStore.calendarItem(withIdentifier: id) as? EKEvent).flatMap { $0.startDate == event.start ? $0 : nil }
            ?? eventStore.events(matching: eventStore.predicateForEvents(withStart: event.start.addingTimeInterval(-60), end: event.end.addingTimeInterval(60), calendars: nil))
                .first { $0.title == event.title && $0.startDate == event.start }
        guard let target = found, !target.hasAttendees else { return false }
        let length = target.endDate.timeIntervalSince(target.startDate)
        target.startDate = start
        target.endDate = start.addingTimeInterval(length)
        do {
            try eventStore.save(target, span: .thisEvent, commit: true)
            return true
        } catch {
            return false
        }
    }
}

extension DayPlanner {
    /// Demo appointments so the day view isn't empty in screenshots.
    nonisolated static func demoEvents(_ day: Date) -> [DayEvent] {
        guard Calendar.current.isDateInToday(day) else { return [] }
        func at(_ hour: Int, _ minute: Int = 0) -> Date { Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day }
        return [
            DayEvent(id: "demo-0", title: "Daily", start: at(9, 15), end: at(9, 30), isAllDay: false, calendar: tr("Arbeit", "Work"), movable: false),
            DayEvent(id: "demo-1", title: "Weekly Nordlicht", start: at(10), end: at(11), isAllDay: false, calendar: tr("Arbeit", "Work"), movable: false),
            DayEvent(id: "demo-2", title: tr("Mittag mit Jana", "Lunch with Jana"), start: at(12, 30), end: at(13, 30), isAllDay: false, calendar: tr("Privat", "Personal"), movable: true),
            DayEvent(id: "demo-3", title: "Design Review", start: at(15), end: at(16), isAllDay: false, calendar: tr("Arbeit", "Work"), movable: false),
        ]
    }
}

/// The model's day plan couldn't be read.
struct UnreadablePlan: LocalizedError {
    var errorDescription: String? {
        tr("Das Modell hat keinen lesbaren Plan geliefert. Nochmal versuchen oder ein größeres Modell wählen.",
           "The model didn't return a readable plan. Try again or pick a larger model.")
    }
}
