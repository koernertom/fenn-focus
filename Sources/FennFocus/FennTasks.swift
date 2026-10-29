import Foundation
import SwiftUI

// To-dos with topic, priority, time frame and estimate. Stored locally and in `tasks/tasks.json` of the Fenn Focus folder
// (plus `tasks/Aufgaben.md` to read); dated tasks can also go to Apple Calendar (FennTaskCalendar).

enum TaskPriority: Int, Codable, CaseIterable, Identifiable, Comparable {
    case high = 1, medium = 2, low = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .high: return tr("Hoch", "High")
        case .medium: return tr("Mittel", "Medium")
        case .low: return tr("Niedrig", "Low")
        }
    }

    /// The stored name: German in files and for the agent, whatever the app language.
    var storedName: String {
        switch self {
        case .high: return "Hoch"
        case .medium: return "Mittel"
        case .low: return "Niedrig"
        }
    }

    var color: Color {
        switch self {
        case .high: return Fenn.accent
        case .medium: return Fenn.amber
        case .low: return Fenn.fg.opacity(0.3)
        }
    }

    static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool { lhs.rawValue < rhs.rawValue }

    init(storedName: String?) {
        switch storedName?.lowercased() {
        case "hoch", "high", "dringend", "urgent": self = .high
        case "niedrig", "low", "später", "later": self = .low
        default: self = .medium
        }
    }
}

/// How a task comes back once it's done.
enum TaskRepeat: String, Codable, CaseIterable, Identifiable {
    case daily, weekdays, weekly, monthly, yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: return tr("Täglich", "Daily")
        case .weekdays: return tr("Werktags", "Weekdays")
        case .weekly: return tr("Wöchentlich", "Weekly")
        case .monthly: return tr("Monatlich", "Monthly")
        case .yearly: return tr("Jährlich", "Yearly")
        }
    }

    /// The next date after `date` (same time of day).
    func next(after date: Date) -> Date {
        let calendar = Calendar.current
        switch self {
        case .daily: return calendar.date(byAdding: .day, value: 1, to: date) ?? date
        case .weekdays:
            var next = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            while calendar.isDateInWeekend(next) { next = calendar.date(byAdding: .day, value: 1, to: next) ?? next }
            return next
        case .weekly: return calendar.date(byAdding: .weekOfYear, value: 1, to: date) ?? date
        case .monthly: return calendar.date(byAdding: .month, value: 1, to: date) ?? date
        case .yearly: return calendar.date(byAdding: .year, value: 1, to: date) ?? date
        }
    }
}

struct FennTask: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var topic = ""
    var priority = TaskPriority.medium
    var start: Date?
    var due: Date?
    var estimateMinutes: Int?
    /// Focus minutes logged on this task.
    var spentMinutes = 0
    var done = false
    var doneAt: Date?
    var created = Date()
    var updated = Date()
    /// "mac" or "note"
    var source = TaskStore.device
    /// One of today's top three.
    var starred: Bool?
    /// Comes back after it's done: the next one is created with the next date.
    var repeatRule: TaskRepeat?
    /// The follow-up a repeating task created – removed again if it's reopened before anything happened to it.
    var repeatNextId: UUID?
    /// A reminder time (set by other Fenn apps sharing the folder; kept so it isn't lost on save).
    var remindAt: Date?
    /// An appointment rather than a to-do (birthday, doctor, a ride): it blocks its time in the day view,
    /// but isn't an open task – not in the home list, never overdue.
    var blocker: Bool?

    var isStarred: Bool { starred == true }
    var isBlocker: Bool { blocker == true }

    var isOverdue: Bool {
        guard !done, !isBlocker, let due else { return false }
        return Calendar.current.startOfDay(for: due) < Calendar.current.startOfDay(for: Date())
    }

    var isDueToday: Bool { due.map { Calendar.current.isDateInToday($0) } ?? false }

    /// Running now: start reached and due not passed.
    var isActiveToday: Bool {
        guard let start else { return isDueToday }
        let today = Calendar.current.startOfDay(for: Date())
        return Calendar.current.startOfDay(for: start) <= today && (due.map { Calendar.current.startOfDay(for: $0) >= today } ?? true)
    }

    /// Lower comes first: overdue and due today, then by priority, then by date.
    var rank: Double {
        var score = Double(priority.rawValue) * 10
        if let due {
            let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: due)).day ?? 0
            score += Double(max(-3, min(days, 14))) * 2
        } else {
            score += 20
        }
        return score
    }

    var topicTitle: String { topic.isEmpty ? tr("Ohne Thema", "No topic") : topic }
}

struct FocusSession: Codable, Identifiable, Equatable {
    var id = UUID()
    var start: Date
    var minutes: Int
    var taskId: UUID?
    var title: String
    var topic: String
    var device = TaskStore.device
}

/// What sits in `tasks/tasks.json`. Deleted tasks leave a dated tombstone so a device that still has them doesn't bring them back.
struct TaskFile: Codable, Equatable {
    var tasks: [FennTask] = []
    var deleted: [String: Date] = [:]
    var sessions: [FocusSession] = []

    /// Newest version of each task wins.
    static func merge(_ a: TaskFile, _ b: TaskFile) -> TaskFile {
        var deleted = a.deleted.merging(b.deleted) { max($0, $1) }
        var byId: [UUID: FennTask] = [:]
        for task in a.tasks + b.tasks {
            if let existing = byId[task.id] {
                if existing.updated >= task.updated { continue }
            }
            byId[task.id] = task
        }
        let cutoff = Date().addingTimeInterval(-60 * 86_400)
        deleted = deleted.filter { $0.value > cutoff }
        let tasks = byId.values
            .filter { task in deleted[task.id.uuidString].map { task.updated > $0 } ?? true }
            .sorted { $0.created < $1.created }
        var sessions: [UUID: FocusSession] = [:]
        for session in a.sessions + b.sessions { sessions[session.id] = session }
        return TaskFile(tasks: tasks, deleted: deleted, sessions: sessions.values.sorted { $0.start < $1.start })
    }
}

@MainActor
final class TaskStore: ObservableObject {
    static let shared = TaskStore()

    #if os(macOS)
    nonisolated static let device = "mac"
    #else
    nonisolated static let device = "iphone"
    #endif

    /// Set by each app: runs the body with the sync folder (security scope handled) – or not at all when none is connected.
    static var withFolder: (((URL) -> Void) -> Void)?

    @Published private(set) var tasks: [FennTask] = []
    @Published private(set) var sessions: [FocusSession] = []
    /// Fires when a task flips to done – counted in the day stats.
    var onTaskCompleted: () -> Void = {}
    /// The same moment with the task itself – for notices that name it.
    var onTaskDone: (FennTask) -> Void = { _ in }
    private var file = TaskFile()
    private var loaded = false

    private let localURL: URL = {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FennFocus", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(FennDemo.isOn ? "fenn-tasks-demo.json" : "fenn-tasks.json")
    }()

    private init() {}

    /// Local copy merged with the folder's – call when the app comes to the front or the tasks view opens.
    func reload() {
        if FennDemo.isOn {
            if !loaded {
                let tasks = TaskDemo.tasks()
                file = TaskFile(tasks: tasks, sessions: TaskDemo.sessions(tasks))
            }
            loaded = true
            publish()
            return
        }
        var merged = Self.read(localURL) ?? TaskFile()
        Self.withFolder? { root in
            let url = FennVault.url(.tasks, in: root)
            let shared = Self.read(url)
            if let shared { merged = TaskFile.merge(merged, shared) }
            // Tasks only this device has (made before the folder was connected, or overwritten by another device's
            // file) go back into the folder, so the other device sees them without waiting for the next edit here.
            if merged != shared && (shared != nil || !merged.tasks.isEmpty) {
                Self.write(merged, to: url)
                _ = FennVault.writeText(TaskOverview.markdown(merged.tasks), to: FennVault.url(.tasksOverview, in: root))
            }
        }
        loaded = true
        if merged != file {
            file = merged
            publish()
        }
    }

    private func ensureLoaded() { if !loaded { reload() } }

    private func publish() {
        tasks = file.tasks
        sessions = file.sessions
    }

    /// Writes locally and into the folder, merging with whatever another device wrote there in the meantime.
    func save() {
        publish()
        guard !FennDemo.isOn else { return }
        Self.write(file, to: localURL)
        Self.withFolder? { root in
            let url = FennVault.url(.tasks, in: root)
            if let shared = Self.read(url) { file = TaskFile.merge(file, shared) }
            Self.write(file, to: url)
            _ = FennVault.writeText(TaskOverview.markdown(file.tasks), to: FennVault.url(.tasksOverview, in: root))
        }
        publish()
    }

    // MARK: Editing

    func add(_ task: FennTask) {
        ensureLoaded()
        var task = task
        task.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.title.isEmpty else { return }
        task.created = Date()
        task.updated = Date()
        file.tasks.append(task)
        save()
    }

    func add(_ tasks: [FennTask]) {
        ensureLoaded()
        for var task in tasks where !task.title.trimmingCharacters(in: .whitespaces).isEmpty {
            task.created = Date()
            task.updated = Date()
            file.tasks.append(task)
        }
        save()
    }

    func update(_ task: FennTask) {
        ensureLoaded()
        guard let index = file.tasks.firstIndex(where: { $0.id == task.id }), file.tasks[index] != task else { return }
        var task = task
        task.updated = Date()
        file.tasks[index] = task
        save()
    }

    func toggle(_ id: UUID) {
        guard var task = file.tasks.first(where: { $0.id == id }) else { return }
        let wasDone = task.done
        task.done.toggle()
        task.doneAt = task.done ? Date() : nil
        if task.done, !wasDone, let rule = task.repeatRule {
            // The next one, with the next date – the finished one stays in the history.
            var next = task
            next.id = UUID()
            next.done = false
            next.doneAt = nil
            next.spentMinutes = 0
            next.repeatNextId = nil
            next.source = TaskStore.device
            let base = max(task.due ?? Date(), Calendar.current.startOfDay(for: Date()))
            let due = rule.next(after: base)
            if let start = task.start, let oldDue = task.due {
                next.start = due.addingTimeInterval(start.timeIntervalSince(oldDue))
            } else {
                next.start = nil
            }
            next.due = due
            next.remindAt = task.remindAt.map { rule.next(after: max($0, Date())) }
            next.created = Date()
            next.updated = next.created
            task.repeatNextId = next.id
            file.tasks.append(next)
        } else if !task.done, wasDone, let nextId = task.repeatNextId,
                  let next = file.tasks.first(where: { $0.id == nextId }), !next.done, next.updated.timeIntervalSince(next.created) < 1 {
            file.tasks.removeAll { $0.id == nextId }
            file.deleted[nextId.uuidString] = Date()
            task.repeatNextId = nil
        }
        update(task)
        if task.done, !wasDone { onTaskCompleted(); onTaskDone(task) }
    }

    /// Top three: starring a fourth takes the star from the least urgent one.
    func toggleStar(_ id: UUID) {
        ensureLoaded()
        guard var task = file.tasks.first(where: { $0.id == id }) else { return }
        task.starred = task.isStarred ? nil : true
        if task.isStarred {
            let others = file.tasks.filter { $0.isStarred && !$0.done && $0.id != id }.sorted { $0.rank < $1.rank }
            for extra in others.dropFirst(2) {
                if let index = file.tasks.firstIndex(where: { $0.id == extra.id }) {
                    file.tasks[index].starred = nil
                    file.tasks[index].updated = Date()
                }
            }
        }
        update(task)
    }

    func delete(_ id: UUID) {
        ensureLoaded()
        guard file.tasks.contains(where: { $0.id == id }) else { return }
        file.tasks.removeAll { $0.id == id }
        file.deleted[id.uuidString] = Date()
        save()
    }

    /// Minutes from the focus timer, on the task if one was picked.
    func logFocus(minutes: Int, taskId: UUID?, title: String, start: Date) {
        ensureLoaded()
        guard minutes > 0 else { return }
        var topic = ""
        if let taskId, let index = file.tasks.firstIndex(where: { $0.id == taskId }) {
            file.tasks[index].spentMinutes += minutes
            file.tasks[index].updated = Date()
            topic = file.tasks[index].topic
        }
        file.sessions.append(FocusSession(start: start, minutes: minutes, taskId: taskId, title: title, topic: topic))
        if file.sessions.count > 3000 { file.sessions.removeFirst(file.sessions.count - 3000) }
        save()
    }

    // MARK: Reading

    /// Where tasks are stored, for the UI.
    static var destination: String {
        FennCloudFolder.shared.isConnected ? tr("Fenn-Focus-Ordner, tasks/", "Fenn Focus folder, tasks/") : tr("In der App auf diesem Mac", "Inside the app on this Mac")
    }


    /// Open to-dos – appointments marked as blockers aren't among them.
    var open: [FennTask] { tasks.filter { !$0.done && !$0.isBlocker }.sorted { $0.rank < $1.rank } }

    /// Appointments kept as tasks (blockers), from today on – the past ones simply drop away.
    var blockers: [FennTask] {
        let today = Calendar.current.startOfDay(for: Date())
        return tasks.filter { !$0.done && $0.isBlocker && ($0.due.map { $0 >= today } ?? true) }
            .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
    }

    /// Appointment ↔ to-do.
    func setBlocker(_ id: UUID, _ on: Bool) {
        guard var task = tasks.first(where: { $0.id == id }) else { return }
        task.blocker = on ? true : nil
        if on { task.starred = nil }
        update(task)
    }

    /// What to do next: the starred top three, then overdue, due today or running now, then by priority.
    func next(_ count: Int) -> [FennTask] {
        let open = open
        let top = open.filter(\.isStarred)
        let now = open.filter { !$0.isStarred && ($0.isOverdue || $0.isDueToday || $0.isActiveToday) }
        return Array((top + now + open.filter { !top.contains($0) && !now.contains($0) }).prefix(count))
    }

    var starredOpen: [FennTask] { open.filter(\.isStarred) }

    /// Open and untouched for two weeks, with no date ahead – quietly slipping.
    func slipping(days: Int = 14, now: Date = Date()) -> [FennTask] {
        let cutoff = now.addingTimeInterval(Double(-days) * 86_400)
        return open.filter { task in
            guard !task.isStarred, task.updated < cutoff else { return false }
            if let due = task.due { return due < Calendar.current.startOfDay(for: now).addingTimeInterval(Double(-days / 2) * 86_400) }
            return true
        }
        .sorted { $0.updated < $1.updated }
    }

    /// Topics by how many open tasks they have.
    var topics: [String] {
        var counts: [String: Int] = [:]
        for task in tasks where !task.topic.isEmpty { counts[task.topic, default: 0] += task.done ? 0 : 1 }
        return counts.keys.sorted { counts[$0]! != counts[$1]! ? counts[$0]! > counts[$1]! : $0 < $1 }
    }

    func focusMinutes(in range: DateInterval) -> Int {
        sessions.filter { range.contains($0.start) }.reduce(0) { $0 + $1.minutes }
    }

    func doneCount(in range: DateInterval) -> Int {
        tasks.filter { $0.done && ($0.doneAt.map(range.contains) ?? false) }.count
    }

    /// Focus minutes per topic, biggest first.
    func minutesByTopic(in range: DateInterval) -> [(topic: String, minutes: Int)] {
        var result: [String: Int] = [:]
        for session in sessions where range.contains(session.start) {
            let topic = session.topic.isEmpty ? (session.taskId == nil ? tr("Freier Fokus", "Free focus") : tr("Ohne Thema", "No topic")) : session.topic
            result[topic, default: 0] += session.minutes
        }
        return result.map { ($0.key, $0.value) }.sorted { $0.minutes > $1.minutes }
    }

    // MARK: Files

    /// Two versions of tasks.json as one (Drive sync conflict); nil when either isn't a task file.
    nonisolated static func merged(_ a: Data, _ b: Data) -> Data? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let first = try? decoder.decode(TaskFile.self, from: a), let second = try? decoder.decode(TaskFile.self, from: b) else { return nil }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(TaskFile.merge(first, second))
    }

    private static func read(_ url: URL) -> TaskFile? {
        guard let data = FennVault.read(url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(TaskFile.self, from: data)
    }

    private static func write(_ file: TaskFile, to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(file) { _ = FennVault.write(data, to: url) }
    }
}

extension DateInterval {
    static var today: DateInterval { Calendar.current.dateInterval(of: .day, for: Date()) ?? DateInterval(start: Date(), duration: 86_400) }
    static var thisWeek: DateInterval { Calendar.current.dateInterval(of: .weekOfYear, for: Date()) ?? today }
    static var thisMonth: DateInterval { Calendar.current.dateInterval(of: .month, for: Date()) ?? today }
}

/// Sections of the task list: by topic (most urgent topic first) or by date (top 3, overdue, today, tomorrow …).
/// Appointment or to-do? A birthday, a doctor's visit or a bike ride blocks time but isn't work to tick off.
/// Rules right away; the AI model looks at the rest when it's set up. Suggestions only – the person decides.
enum TaskKindGuess {
    private static let words = [
        "geburtstag", "birthday", "jahrestag", "hochzeit", "wedding", "party", "feier", "termin", "appointment", "arzt", "zahnarzt",
        "doctor", "dentist", "friseur", "haircut", "physio", "massage", "meeting", "call mit", "telko", "essen mit", "mittag mit",
        "lunch with", "dinner", "abendessen", "frühstück mit", "konzert", "concert", "kino", "cinema", "theater", "urlaub", "vacation",
        "flug", "flight", "zug nach", "train to", "besuch", "visit", "abholen", "pick up", "fahrrad fahren", "radfahren", "rad fahren",
        "laufen gehen", "joggen", "gym", "fitnessstudio", "yoga", "schwimmen gehen",
    ]
    /// "Arzttermin vereinbaren", "Geburtstagsgeschenk kaufen" – that's work to do, not the appointment.
    private static let chores = [
        "vereinbar", "buchen", "planen", "organisier", "schreiben", "anrufen", "kaufen", "besorgen", "machen", "vorbereiten", "absagen",
        "geschenk", "book", "schedule", "plan ", "organize", "write", "call ", "buy", "prepare", "cancel", "gift",
    ]

    static func looksLikeBlocker(_ task: FennTask) -> Bool {
        let title = " " + task.title.lowercased() + " "
        return words.contains { title.contains(" " + $0) } && !chores.contains { title.contains($0) }
    }

    private static let dismissedKey = "fenn.tasks.kindDismissed"
    static var dismissed: Set<String> { Set(UserDefaults.standard.stringArray(forKey: dismissedKey) ?? []) }
    static func dismiss(_ ids: [UUID]) {
        UserDefaults.standard.set(Array((dismissed.union(ids.map(\.uuidString))).suffix(300)), forKey: dismissedKey)
    }

    /// Open tasks the rules take for appointments, without the ones the person already said no to.
    static func candidates(in tasks: [FennTask]) -> [FennTask] {
        let no = dismissed
        return tasks.filter { !$0.done && !$0.isBlocker && !no.contains($0.id.uuidString) && looksLikeBlocker($0) }
    }

    /// The AI model's view: which of these open tasks are appointments. Nil when no model is set up or it fails.
    @MainActor
    static func ai(_ tasks: [FennTask]) async -> [FennTask]? {
        let no = dismissed
        let pool = Array(tasks.filter { !$0.done && !$0.isBlocker && !no.contains($0.id.uuidString) }.prefix(40))
        guard !pool.isEmpty, FennAI.isConfigured, !FennAI.needsConsent() else { return nil }
        let lines = pool.enumerated().map { index, task in "\(index + 1). \(task.title)" }.joined(separator: "\n")
        let prompt = """
        Welche dieser Einträge sind Termine, Ereignisse oder Aktivitäten mit fester Zeit (Geburtstag, Arzt, Treffen, Sport, Reise) \
        statt Aufgaben, die man erledigt und abhakt? Im Zweifel ist es eine Aufgabe.
        \(lines)
        Antworte nur mit JSON: {"blocker": [Nummern]}
        """
        guard let reply = try? await FennAI.ask(prompt, system: "Du sortierst nüchtern Aufgaben und Termine.", maxTokens: 300, timeout: 60, json: true),
              let data = FennAI.json(in: reply),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let numbers = object["blocker"] as? [Int] else { return nil }
        return numbers.compactMap { pool.indices.contains($0 - 1) ? pool[$0 - 1] : nil }
    }
}

enum TaskGroups {
    struct Group { let title: String; let tasks: [FennTask] }

    static func make(_ tasks: [FennTask], by grouping: String, now: Date = Date()) -> [Group] {
        if grouping == "date" { return byDate(tasks, now: now) }
        let groups = Dictionary(grouping: tasks) { $0.topicTitle }
        return groups.keys.sorted { (groups[$0]?.first?.rank ?? 99) < (groups[$1]?.first?.rank ?? 99) }.map { Group(title: $0, tasks: groups[$0] ?? []) }
    }

    private static func byDate(_ tasks: [FennTask], now: Date) -> [Group] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let weekEnd = calendar.dateInterval(of: .weekOfYear, for: now)?.end ?? today.addingTimeInterval(7 * 86_400)
        var buckets: [(String, [FennTask])] = [
            (tr("Top 3", "Top 3"), []), (tr("Überfällig", "Overdue"), []), (tr("Heute", "Today"), []), (tr("Morgen", "Tomorrow"), []),
            (tr("Diese Woche", "This week"), []), (tr("Später", "Later"), []), (tr("Ohne Datum", "No date"), []), (tr("Erledigt", "Done"), []),
        ]
        for task in tasks {
            let index: Int
            if task.done { index = 7 }
            else if task.isStarred { index = 0 }
            else if task.isOverdue { index = 1 }
            else if let due = task.due {
                let day = calendar.startOfDay(for: due)
                index = day <= today ? 2 : calendar.isDateInTomorrow(due) ? 3 : day < weekEnd ? 4 : 5
            } else { index = 6 }
            buckets[index].1.append(task)
        }
        return buckets.filter { !$0.1.isEmpty }.map { title, list in
            Group(title: title, tasks: title == tr("Erledigt", "Done") ? list : list.sorted { ($0.due ?? .distantFuture, $0.rank) < ($1.due ?? .distantFuture, $1.rank) })
        }
    }
}

// MARK: - Readable overview

/// `tasks/Aufgaben.md`: open tasks by topic, then what got done in the last 14 days.
enum TaskOverview {
    static func markdown(_ tasks: [FennTask]) -> String {
        let open = tasks.filter { !$0.done }.sorted { $0.rank < $1.rank }
        let groups = Dictionary(grouping: open) { $0.topicTitle }
        var lines = ["# \(tr("Aufgaben", "Tasks"))", "", "_\(tr("Von Fenn gepflegt – bearbeiten in Fenn Focus.", "Kept by Fenn – edit in Fenn Focus."))_", ""]
        for topic in groups.keys.sorted() {
            lines.append("## \(topic)")
            for task in groups[topic] ?? [] { lines.append("- [ ] \(line(task))") }
            lines.append("")
        }
        let recent = tasks.filter { $0.done && ($0.doneAt ?? .distantPast) > Date().addingTimeInterval(-14 * 86_400) }
        if !recent.isEmpty {
            lines.append("## \(tr("Erledigt (14 Tage)", "Done (14 days)"))")
            for task in recent.sorted(by: { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }) { lines.append("- [x] \(line(task))") }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func line(_ task: FennTask) -> String {
        var parts = [(task.isStarred ? "★ " : "") + task.title, "\(task.priority.title)"]
        if let rule = task.repeatRule { parts.append("\(rule.title)") }
        if let start = task.start, let due = task.due { parts.append("\(FennVault.dayKey(start)) → \(FennVault.dayKey(due))") }
        else if let due = task.due { parts.append("\(tr("bis", "due")) \(FennVault.dayKey(due))") }
        if let estimate = task.estimateMinutes { parts.append("~\(TaskFormat.duration(estimate))") }
        if task.spentMinutes > 0 { parts.append("\(TaskFormat.duration(task.spentMinutes)) \(tr("Fokus", "focus"))") }
        return parts.joined(separator: ", ")
    }
}

enum TaskFormat {
    /// 45 → "45 min", 90 → "1:30 h", 120 → "2 h"
    static func duration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) h" : String(format: "%d:%02d h", minutes / 60, minutes % 60)
    }

    /// "heute", "morgen", "Fr.", "3. Okt."
    static func day(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return tr("heute", "today") }
        if calendar.isDateInTomorrow(date) { return tr("morgen", "tomorrow") }
        if calendar.isDateInYesterday(date) { return tr("gestern", "yesterday") }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: date)).day ?? 99
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: tr("de_DE", "en_GB"))
        formatter.dateFormat = (0..<7).contains(days) ? "EEE" : "d. MMM"
        return formatter.string(from: date)
    }
}

// MARK: - Capture

/// Turns spoken or typed text into tasks: the connected AI model if there is one, otherwise simple rules
/// ("morgen", "bis Freitag", "30 min", "wichtig", "#Thema").
enum TaskCapture {
    struct Result {
        var tasks: [FennTask]
        /// Anything worth keeping as a note beyond the tasks.
        var note: String?
    }

    static func structure(_ text: String, topics: [String]) async -> Result {
        await model(text, topics: topics) ?? rules(text, topics: topics)
    }

    /// Only the connected AI model – nil when there is none, it needs consent first, or the reply didn't fit.
    static func model(_ text: String, topics: [String]) async -> Result? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, FennAI.isConfigured, !FennAI.needsConsent(),
              var result = try? await ai(text, topics: topics), !result.tasks.isEmpty || result.note != nil else { return nil }
        // Explicit words beat the model: "bis Freitag", "45 min", "wichtig" are read by rules, which don't miscount weekdays.
        if result.tasks.count == 1 {
            let ruled = parse(text, topics: topics)
            if let due = ruled.due { result.tasks[0].due = due }
            if let estimate = ruled.estimateMinutes { result.tasks[0].estimateMinutes = estimate }
            if ruled.priority != .medium { result.tasks[0].priority = ruled.priority }
            if let start = result.tasks[0].start, let due = result.tasks[0].due, start > due { result.tasks[0].start = nil }
        }
        return result
    }

    private struct Draft: Decodable {
        struct Item: Decodable {
            var title: String
            var topic: String?
            var priority: String?
            var start: String?
            var due: String?
            var estimate: Int?
        }
        var tasks: [Item]
        var note: String?
    }

    private static func ai(_ text: String, topics: [String]) async throws -> Result {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EEEE yyyy-MM-dd"
        // Small models get weekdays wrong – so they get the next two weeks spelled out.
        let calendar = Calendar.current
        let days = (0..<14).compactMap { calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: Date())) }
            .map { formatter.string(from: $0) }.joined(separator: ", ")
        let system = """
        Du machst aus gesprochenen oder getippten Gedanken Aufgaben. Antworte nur mit JSON:
        {"tasks":[{"title":"…","topic":"…","priority":"hoch|mittel|niedrig","start":"YYYY-MM-DD oder null","due":"YYYY-MM-DD oder null","estimate":Minuten oder null}],"note":null}
        Titel knapp, als Tätigkeit, ohne Datum oder Dauer, nah am Wortlaut. Thema möglichst aus: \(topics.isEmpty ? "Arbeit, Privat" : topics.joined(separator: ", ")) – nur wenn nichts passt ein neues kurzes Thema.
        Priorität hoch nur bei "wichtig", "dringend", Deadline heute/morgen. Schätzung nur, wenn genannt oder offensichtlich.
        "note" bleibt null, außer der Text enthält Gedanken oder Infos, die keine Aufgabe sind – dann diese in einem Satz.
        Kalender (heute zuerst): \(days). "bis Freitag" = der nächste Freitag aus dieser Liste.
        Sprache der Eingabe beibehalten.
        """
        let reply = try await FennAI.ask(text, system: system, maxTokens: 900, timeout: 40, json: true)
        guard let data = FennAI.json(in: reply) else { return Result(tasks: []) }
        let draft = try JSONDecoder().decode(Draft.self, from: data)
        let tasks = draft.tasks.map { item in
            FennTask(title: item.title, topic: item.topic ?? "", priority: TaskPriority(storedName: item.priority),
                     start: item.start.flatMap(parseDay), due: item.due.flatMap(parseDay), estimateMinutes: item.estimate)
        }
        let note = draft.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Result(tasks: tasks, note: note?.isEmpty == false && note?.lowercased() != "null" ? note : nil)
    }

    /// A to-do found in a note, with the note's day ("heute", "morgen") as due date.
    static func task(from todo: NoteTodo, topics: [String]) -> FennTask {
        var task = parse(todo.title, topics: topics)
        if task.title.isEmpty { task.title = todo.title }
        if task.due == nil, let offset = todo.dayOffset {
            task.due = Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: Date()))
        }
        task.source = "note"
        return task
    }

    static func parseDay(_ text: String) -> Date? {
        FennVault.dayFormatter.date(from: String(text.prefix(10)))
    }

    // MARK: Rules

    private static let highWords = ["wichtig", "dringend", "asap", "sofort", "urgent", "important", "prio hoch", "!!"]
    private static let lowWords = ["irgendwann", "unwichtig", "wenn zeit", "someday", "low prio", "prio niedrig"]
    private static let fillers = ["ich muss noch", "ich muss", "ich sollte", "nicht vergessen", "todo:", "to-do:", "aufgabe:", "i need to", "i have to", "remember to", "don't forget to"]
    private static let topicHints: [(String, [String])] = [
        ("Arbeit", ["meeting", "präsentation", "kunde", "kunden", "bericht", "mail", "e-mail", "projekt", "call", "angebot", "rechnung", "deck", "review", "team", "chef", "report", "client", "slides"]),
        ("Privat", ["einkaufen", "arzt", "termin beim", "steuer", "wohnung", "geburtstag", "mama", "papa", "groceries", "doctor"])
    ]

    /// One task per line (or per ";"); markers are taken out of the title.
    static func rules(_ text: String, topics: [String]) -> Result {
        let lines = text.components(separatedBy: CharacterSet(charactersIn: "\n;"))
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " -•*[]\t")) }
            .filter { !$0.isEmpty }
        let tasks = lines.map { parse($0, topics: topics) }.filter { !$0.title.isEmpty }
        return Result(tasks: tasks)
    }

    static func parse(_ line: String, topics: [String]) -> FennTask {
        var title = " " + line + " "
        let lower = title.lowercased()
        var task = FennTask(title: "")

        if let tag = line.range(of: #"#[\p{L}0-9_-]+"#, options: .regularExpression) {
            task.topic = String(line[tag].dropFirst())
            title = title.replacingOccurrences(of: String(line[tag]), with: " ")
        } else if let known = topics.first(where: { lower.contains($0.lowercased()) }) {
            task.topic = known
        } else if let hint = topicHints.first(where: { hint in hint.1.contains { lower.contains($0) } }) {
            task.topic = topics.first { $0.lowercased() == hint.0.lowercased() } ?? hint.0
        }

        if lowWords.contains(where: { lower.contains($0) }) { task.priority = .low }
        else if highWords.contains(where: { lower.contains($0) }) { task.priority = .high }
        for word in lowWords + highWords { title = title.replacingOccurrences(of: word, with: " ", options: .caseInsensitive) }

        if let match = title.range(of: #"(?i)\b(ca\.?\s*)?(\d+(?:[.,]\d+)?)\s*(minuten|min|m|stunden|stunde|std|h|hours|hour)\b"#, options: .regularExpression) {
            let chunk = String(title[match])
            let number = Double(chunk.replacingOccurrences(of: ",", with: ".").components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted).joined()) ?? 0
            let isHours = chunk.lowercased().range(of: #"(stunde|std|h\b|hour)"#, options: .regularExpression) != nil
            task.estimateMinutes = Int((isHours ? number * 60 : number).rounded())
            title.replaceSubrange(match, with: " ")
        }

        if let (date, range) = findDate(in: title) {
            task.due = date
            title.replaceSubrange(range, with: " ")
        }

        var clean = title.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        for filler in fillers where clean.lowercased().hasPrefix(filler) { clean = String(clean.dropFirst(filler.count)).trimmingCharacters(in: .whitespaces) }
        for tail in [" bis", " am", " by", " on", " für", " for", ","] where clean.lowercased().hasSuffix(tail) {
            clean = String(clean.dropLast(tail.count)).trimmingCharacters(in: .whitespaces)
        }
        clean = clean.trimmingCharacters(in: CharacterSet(charactersIn: " .,:"))
        task.title = clean.prefix(1).uppercased() + clean.dropFirst()
        return task
    }

    private static let weekdays: [(String, Int)] = [
        ("montag", 2), ("dienstag", 3), ("mittwoch", 4), ("donnerstag", 5), ("freitag", 6), ("samstag", 7), ("sonntag", 1),
        ("monday", 2), ("tuesday", 3), ("wednesday", 4), ("thursday", 5), ("friday", 6), ("saturday", 7), ("sunday", 1)
    ]

    private static func findDate(in text: String) -> (Date, Range<String.Index>)? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let relative: [(String, Int)] = [("übermorgen", 2), ("morgen", 1), ("heute", 0), ("tomorrow", 1), ("today", 0)]
        for (word, offset) in relative {
            if let range = text.range(of: #"(?i)\b(bis |am |by )?"# + word + #"\b"#, options: .regularExpression),
               let date = calendar.date(byAdding: .day, value: offset, to: today) {
                return (date, range)
            }
        }
        if let range = text.range(of: #"(?i)\b(nächste|kommende|next) woche\b|\bnext week\b"#, options: .regularExpression),
           let date = calendar.nextDate(after: today, matching: DateComponents(weekday: 6), matchingPolicy: .nextTime)
            .flatMap({ calendar.date(byAdding: .day, value: 7, to: $0) }) {
            return (date, range)
        }
        if let range = text.range(of: #"(?i)\b(ende der woche|diese woche|end of week|this week)\b"#, options: .regularExpression),
           let date = calendar.nextDate(after: today.addingTimeInterval(-1), matching: DateComponents(weekday: 6), matchingPolicy: .nextTime) {
            return (date, range)
        }
        for (name, weekday) in weekdays {
            if let range = text.range(of: #"(?i)\b(bis |am |by |on )?"# + name + #"\b"#, options: .regularExpression),
               let date = calendar.nextDate(after: today, matching: DateComponents(weekday: weekday), matchingPolicy: .nextTime) {
                return (date, range)
            }
        }
        if let range = text.range(of: #"\b(bis |am )?(\d{1,2})\.(\d{1,2})\.(\d{2,4})?"#, options: .regularExpression) {
            let digits = text[range].components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }.compactMap(Int.init)
            if digits.count >= 2 {
                var components = DateComponents(month: digits[1], day: digits[0])
                components.year = digits.count > 2 ? (digits[2] < 100 ? 2000 + digits[2] : digits[2]) : calendar.component(.year, from: today)
                if var date = calendar.date(from: components) {
                    if digits.count == 2, date < today, let next = calendar.date(byAdding: .year, value: 1, to: date) { date = next }
                    return (date, range)
                }
            }
        }
        return nil
    }
}

// MARK: - Demo

enum TaskDemo {
    static func tasks() -> [FennTask] {
        let day: (Int) -> Date = { Calendar.current.date(byAdding: .day, value: $0, to: Calendar.current.startOfDay(for: Date()))! }
        func task(_ title: String, _ topic: String, _ priority: TaskPriority, start: Int? = nil, due: Int?, estimate: Int?, spent: Int = 0, doneDaysAgo: Int? = nil) -> FennTask {
            var task = FennTask(title: title, topic: topic, priority: priority, start: start.map(day), due: due.map(day), estimateMinutes: estimate, spentMinutes: spent)
            if let doneDaysAgo { task.done = true; task.doneAt = day(-doneDaysAgo).addingTimeInterval(15 * 3600) }
            task.source = "demo"
            return task
        }
        let en = tr("de", "en") == "en"
        var tasks = [
            task(en ? "Q4 pitch deck for Nordlicht" : "Q4-Pitch-Deck für Nordlicht", en ? "Client Nordlicht" : "Kunde Nordlicht", .high, start: -2, due: 1, estimate: 240, spent: 150),
            task(en ? "Send offer draft" : "Angebotsentwurf schicken", en ? "Client Nordlicht" : "Kunde Nordlicht", .high, due: 0, estimate: 45),
            task(en ? "Review onboarding flow" : "Onboarding-Flow reviewen", en ? "Website relaunch" : "Website-Relaunch", .medium, start: 0, due: 3, estimate: 90, spent: 25),
            task(en ? "Write release notes" : "Release Notes schreiben", en ? "Website relaunch" : "Website-Relaunch", .low, due: 5, estimate: 30),
            task(en ? "Book train to the Munich workshop" : "Zug zum Workshop in München buchen", en ? "Team" : "Team", .medium, due: 2, estimate: 15),
            task(en ? "Tax documents to advisor" : "Steuerunterlagen an Berater", en ? "Private" : "Privat", .medium, due: 6, estimate: 60),
            task(en ? "Plan team workshop" : "Team-Workshop planen", en ? "Team" : "Team", .medium, start: 4, due: 9, estimate: 120),
            task(en ? "Budget review" : "Budget-Review", en ? "Client Nordlicht" : "Kunde Nordlicht", .medium, due: -1, estimate: 60, spent: 70, doneDaysAgo: 1),
            task(en ? "Fix contact form bug" : "Kontaktformular-Bug fixen", en ? "Website relaunch" : "Website-Relaunch", .high, due: -1, estimate: 90, spent: 110, doneDaysAgo: 0),
            task(en ? "1:1 notes" : "1:1-Notizen", en ? "Team" : "Team", .low, due: 0, estimate: 20, spent: 15, doneDaysAgo: 0),
            task(en ? "Invoice September" : "Rechnung September", en ? "Private" : "Privat", .medium, due: -2, estimate: 20, spent: 20, doneDaysAgo: 2),
            task(en ? "Weekly review" : "Wochenrückblick", en ? "Private" : "Privat", .medium, due: 4, estimate: 30),
            task(en ? "Cancel old phone contract" : "Alten Handyvertrag kündigen", en ? "Private" : "Privat", .low, due: nil, estimate: 20)
        ]
        tasks[0].starred = true
        tasks[1].starred = true
        tasks[11].repeatRule = .weekly
        let old = Date().addingTimeInterval(-24 * 86_400)
        tasks[12].created = old
        tasks[12].updated = old
        return tasks
    }

    static func sessions(_ tasks: [FennTask]) -> [FocusSession] {
        let calendar = Calendar.current
        var sessions: [FocusSession] = []
        let pattern: [(daysAgo: Int, hour: Int, index: Int, minutes: Int)] = [
            (0, 8, 0, 50), (0, 10, 8, 25), (0, 11, 2, 25),
            (1, 9, 0, 50), (1, 13, 7, 45), (1, 15, 8, 50),
            (2, 9, 0, 50), (2, 14, 10, 20), (2, 16, 7, 25),
            (3, 8, 8, 35), (3, 10, 2, 50), (4, 9, 0, 25), (4, 11, 7, 50)
        ]
        for item in pattern {
            let task = tasks[item.index]
            let day = calendar.date(byAdding: .day, value: -item.daysAgo, to: calendar.startOfDay(for: Date()))!
            sessions.append(FocusSession(start: day.addingTimeInterval(Double(item.hour) * 3600), minutes: item.minutes,
                                         taskId: task.id, title: task.title, topic: task.topic, device: "demo"))
        }
        return sessions
    }
}
