import Foundation
import SwiftUI

// Routines after "Atomic Habits": separate from tasks, by time of day, each with the identity it votes for,
// a two-minute version that still counts and an anchor it stacks onto ("Nach dem Kaffee …").
// A streak only breaks after two missed days in a row – never miss twice. What Fenn already knows
// (check-in, review, focus block) ticks a routine off by itself.
// Stored in the sync folder as habits/habits.json (+ Routinen.md to read).

enum HabitTime: String, Codable, CaseIterable, Identifiable {
    case morning, afternoon, evening, anytime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .morning: return tr("Morgens", "Morning")
        case .afternoon: return tr("Nachmittags", "Afternoon")
        case .evening: return tr("Abends", "Evening")
        case .anytime: return tr("Jederzeit", "Anytime")
        }
    }

    var symbol: String {
        switch self {
        case .morning: return "sunrise"
        case .afternoon: return "sun.max"
        case .evening: return "moon.stars"
        case .anytime: return "clock"
        }
    }

    /// The hour the window closes; after that an open routine counts as "window passed" (not as missed – the day isn't over).
    var endHour: Int? {
        switch self {
        case .morning: return 12
        case .afternoon: return 18
        case .evening: return nil
        case .anytime: return nil
        }
    }

    var sortIndex: Int { HabitTime.allCases.firstIndex(of: self) ?? 0 }
}

/// Data Fenn already has that ticks a routine off by itself.
enum HabitAuto: String, Codable, CaseIterable, Identifiable {
    case checkIn, review, focus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .checkIn: return tr("Morgen-Check-in", "Morning check-in")
        case .review: return tr("Abend-Review", "Evening review")
        case .focus: return tr("Fokusblock", "Focus block")
        }
    }

    var symbol: String {
        switch self {
        case .checkIn: return "sun.horizon"
        case .review: return "moon"
        case .focus: return "timer"
        }
    }
}

struct Habit: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var title: String
    var time = HabitTime.anytime
    /// Calendar weekdays 1 (Sunday) … 7 (Saturday); empty = every day.
    var weekdays: [Int] = []
    /// The identity every tick votes for: "jemand, der sich jeden Tag bewegt".
    var identity: String?
    /// The two-minute version that still counts on a bad day.
    var tiny: String?
    /// Habit stacking: after this (free text) …
    var anchor: String?
    /// … or after another routine.
    var anchorId: UUID?
    var symbol: String?
    /// A challenge of so many days (21, 30, 66); nil = ongoing.
    var lengthDays: Int?
    /// yyyy-MM-dd – the first day that counts.
    var startDay: String
    var auto: HabitAuto?
    var archivedAt: Date?
    var created = Date()
    var updated = Date()

    init(title: String, time: HabitTime = .anytime, startDay: String = FennVault.dayKey(Date())) {
        self.title = title
        self.time = time
        self.startDay = startDay
    }

    var isArchived: Bool { archivedAt != nil }

    var displaySymbol: String { symbol ?? auto?.symbol ?? Self.guessSymbol(title) ?? time.symbol }

    /// A picture from the title when none was picked.
    static func guessSymbol(_ title: String) -> String? {
        let lower = title.lowercased()
        let table: [([String], String)] = [
            (["wasser", "water", "trink", "drink"], "drop.fill"),
            (["lesen", "lese ", "read", "buch", "book"], "book.fill"),
            (["medit", "atem", "breath"], "leaf.fill"),
            (["journal", "schreib", "write", "tagebuch"], "pencil.line"),
            (["dehn", "stretch", "yoga", "mobil"], "figure.yoga"),
            (["spazier", "walk", "schritt", "step"], "figure.walk"),
            (["laufen", "running", "jogg"], "figure.run"),
            (["train", "workout", "gym", "kraft", "liegest", "push"], "dumbbell.fill"),
            // Before sleep: "Handy aus dem Schlafzimmer" is about the phone.
            (["handy", "phone", "screen", "bildschirm"], "iphone.slash"),
            (["schlaf", "sleep", "bett"], "bed.double.fill"),
            (["dank", "grat"], "heart.fill"),
            (["vitamin", "supplement", "tablette", "pill"], "pills.fill"),
            (["kalt", "cold", "dusch", "shower"], "snowflake"),
            (["aufräum", "tidy", "clean", "putz"], "sparkles"),
            (["kaffee", "coffee"], "cup.and.saucer.fill"),
            (["gemüse", "obst", "salat", "veg", "fruit"], "carrot.fill"),
            (["plan", "fokus", "focus", "lern", "learn"], "brain.head.profile"),
            (["sonne", "sun", "draußen", "outside", "licht", "light"], "sun.max.fill")
        ]
        return table.first { entry in entry.0.contains { lower.contains($0) } }?.1
    }

    /// "Nach dem Kaffee" – the anchor as it reads in a row.
    func anchorText(in habits: [Habit]) -> String? {
        if let anchorId, let other = habits.first(where: { $0.id == anchorId }) { return tr("Nach „\(other.title)“", "After “\(other.title)”") }
        guard let anchor = anchor?.trimmingCharacters(in: .whitespaces), !anchor.isEmpty else { return nil }
        let lower = anchor.lowercased()
        return lower.hasPrefix("nach ") || lower.hasPrefix("after ") || lower.hasPrefix("vor ") || lower.hasPrefix("before ") ? anchor : tr("Nach \(anchor)", "After \(anchor)")
    }

    /// Last day of a challenge, yyyy-MM-dd.
    var endDay: String? {
        guard let lengthDays, let start = HabitStore.date(startDay),
              let end = Calendar.current.date(byAdding: .day, value: lengthDays - 1, to: start) else { return nil }
        return FennVault.dayKey(end)
    }

    func isScheduled(on day: Date) -> Bool {
        let key = FennVault.dayKey(day)
        guard key >= startDay else { return false }
        if let endDay, key > endDay { return false }
        return weekdays.isEmpty || weekdays.contains(Calendar.current.component(.weekday, from: day))
    }

    var weekdaysText: String {
        guard !weekdays.isEmpty, weekdays.count < 7 else { return tr("täglich", "daily") }
        if Set(weekdays) == [2, 3, 4, 5, 6] { return tr("werktags", "weekdays") }
        if Set(weekdays) == [1, 7] { return tr("am Wochenende", "weekends") }
        let symbols = HabitStore.weekdaySymbols
        return HabitStore.weekdayOrder.filter(weekdays.contains).map { symbols[$0 - 1] }.joined(separator: " ")
    }
}

/// One day of one routine. Newest `at` wins when two devices disagree.
struct HabitMark: Codable, Equatable {
    var done: Bool
    /// Only the two-minute version – still counts.
    var tiny: Bool?
    /// Ticked off by Fenn from measured data.
    var auto: Bool?
    var at = Date()
}

struct HabitFile: Codable, Equatable {
    var habits: [Habit] = []
    var deleted: [String: Date] = [:]
    /// "<habit id>|yyyy-MM-dd" → mark
    var marks: [String: HabitMark] = [:]

    static func merge(_ a: HabitFile, _ b: HabitFile) -> HabitFile {
        var deleted = a.deleted.merging(b.deleted) { max($0, $1) }
        var byId: [UUID: Habit] = [:]
        for habit in a.habits + b.habits {
            if let existing = byId[habit.id], existing.updated >= habit.updated { continue }
            byId[habit.id] = habit
        }
        let cutoff = Date().addingTimeInterval(-120 * 86_400)
        deleted = deleted.filter { $0.value > cutoff }
        let habits = byId.values
            .filter { habit in deleted[habit.id.uuidString].map { habit.updated > $0 } ?? true }
            .sorted { $0.created < $1.created }
        var marks = a.marks
        for (key, mark) in b.marks where (marks[key]?.at ?? .distantPast) < mark.at { marks[key] = mark }
        let alive = Set(habits.map(\.id.uuidString))
        let oldest = FennVault.dayKey(Date().addingTimeInterval(-500 * 86_400))
        marks = marks.filter { key, _ in
            let parts = key.split(separator: "|")
            return parts.count == 2 && alive.contains(String(parts[0])) && String(parts[1]) >= oldest
        }
        return HabitFile(habits: habits, deleted: deleted, marks: marks)
    }
}

@MainActor
final class HabitStore: ObservableObject {
    static let shared = HabitStore()

    /// Set by each app: runs the body with the sync folder – or not at all when none is connected.
    static var withFolder: (((URL) -> Void) -> Void)?

    @Published private(set) var habits: [Habit] = []
    @Published private(set) var marks: [String: HabitMark] = [:]
    /// Fires once per routine and day when it's done (by hand or measured) – counted in the day stats.
    var onHabitDone: (Habit) -> Void = { _ in }
    /// Each app answers: did the measured data reach this on that day?
    var autoCheck: ((HabitAuto, Date) -> Bool)?

    private var file = HabitFile()
    private var loaded = false
    /// Days already counted for a routine, so un- and re-ticking doesn't count twice.
    private var credited: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "fenn.habits.credited") ?? [])

    private let localURL: URL = {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FennFocus", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(FennDemo.isOn ? "fenn-habits-demo.json" : "fenn-habits.json")
    }()

    private init() {}

    // MARK: Loading and saving

    func reload() {
        if FennDemo.isOn {
            if !loaded { file = HabitDemo.file() }
            loaded = true
            publish()
            return
        }
        var merged = Self.read(localURL) ?? HabitFile()
        Self.withFolder? { root in
            if let shared = Self.read(Self.url(in: root)) { merged = HabitFile.merge(merged, shared) }
        }
        loaded = true
        if merged != file {
            file = merged
            publish()
        }
    }

    private func ensureLoaded() { if !loaded { reload() } }

    private func publish() {
        habits = file.habits
        marks = file.marks
    }

    func save() {
        publish()
        guard !FennDemo.isOn else { return }
        Self.write(file, to: localURL)
        Self.withFolder? { root in
            let url = Self.url(in: root)
            if let shared = Self.read(url) { file = HabitFile.merge(file, shared) }
            Self.write(file, to: url)
            _ = FennVault.writeText(overview(), to: root.appendingPathComponent("habits/Routinen.md"))
        }
        publish()
    }

    static func url(in root: URL) -> URL { root.appendingPathComponent("habits/habits.json") }

    // MARK: Editing

    func add(_ habit: Habit) {
        ensureLoaded()
        var habit = habit
        habit.title = habit.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !habit.title.isEmpty else { return }
        habit.created = Date()
        habit.updated = Date()
        file.habits.append(habit)
        save()
    }

    func update(_ habit: Habit) {
        ensureLoaded()
        guard let index = file.habits.firstIndex(where: { $0.id == habit.id }), file.habits[index] != habit else { return }
        var habit = habit
        habit.updated = Date()
        file.habits[index] = habit
        save()
    }

    func delete(_ id: UUID) {
        ensureLoaded()
        file.habits.removeAll { $0.id == id }
        file.deleted[id.uuidString] = Date()
        for index in file.habits.indices where file.habits[index].anchorId == id {
            file.habits[index].anchorId = nil
            file.habits[index].updated = Date()
        }
        save()
    }

    func archive(_ id: UUID, _ archived: Bool = true) {
        guard var habit = file.habits.first(where: { $0.id == id }) else { return }
        habit.archivedAt = archived ? Date() : nil
        if !archived, habit.endDay.map({ $0 < FennVault.dayKey(Date()) }) == true {
            // A finished challenge comes back as an ongoing routine from today.
            habit.lengthDays = nil
        }
        update(habit)
    }

    /// Ticks off (or reopens) a routine for a day. `tiny`: only the two-minute version.
    func toggle(_ habit: Habit, on day: Date = Date(), tiny: Bool = false) {
        ensureLoaded()
        let key = Self.key(habit.id, day)
        let wasDone = file.marks[key]?.done == true
        if wasDone && !tiny {
            file.marks[key] = HabitMark(done: false)
        } else {
            file.marks[key] = HabitMark(done: true, tiny: tiny ? true : nil)
        }
        save()
        if !wasDone { credit(habit, day) }
    }

    private func credit(_ habit: Habit, _ day: Date) {
        guard Calendar.current.isDateInToday(day) else { return }
        let key = Self.key(habit.id, day)
        guard !credited.contains(key) else { return }
        credited.insert(key)
        let today = FennVault.dayKey(Date())
        credited = credited.filter { $0.hasSuffix(today) }
        UserDefaults.standard.set(Array(credited), forKey: "fenn.habits.credited")
        onHabitDone(habit)
    }

    /// Ticks off what the measured data already shows – today and yesterday. A routine someone reopened by hand stays open.
    func applyAuto() {
        ensureLoaded()
        guard let autoCheck else { return }
        var changed: [Habit] = []
        for offset in [-1, 0] {
            guard let day = Calendar.current.date(byAdding: .day, value: offset, to: Date()) else { continue }
            for habit in file.habits where !habit.isArchived && habit.isScheduled(on: day) {
                guard let auto = habit.auto, file.marks[Self.key(habit.id, day)] == nil,
                      autoCheck(auto, day) else { continue }
                file.marks[Self.key(habit.id, day)] = HabitMark(done: true, auto: true)
                if offset == 0 { changed.append(habit) }
            }
        }
        guard file.marks != marks else { return }
        save()
        for habit in changed { credit(habit, Date()) }
    }

    /// Challenges past their last day move to the archive on their own.
    func archiveFinished() {
        let today = FennVault.dayKey(Date())
        let finished = file.habits.filter { !$0.isArchived && ($0.endDay.map { $0 < today } ?? false) }
        guard !finished.isEmpty else { return }
        for habit in finished {
            guard let index = file.habits.firstIndex(where: { $0.id == habit.id }) else { continue }
            file.habits[index].archivedAt = Date()
            file.habits[index].updated = Date()
        }
        save()
    }

    // MARK: Reading

    var active: [Habit] { habits.filter { !$0.isArchived } }
    var archived: [Habit] { habits.filter(\.isArchived).sorted { ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) } }

    func mark(_ habit: Habit, on day: Date = Date()) -> HabitMark? { marks[Self.key(habit.id, day)] }
    func isDone(_ habit: Habit, on day: Date = Date()) -> Bool { mark(habit, on: day)?.done == true }

    /// Today's routines by time of day; a stacked one right after its anchor.
    func today(_ day: Date = Date()) -> [Habit] {
        let list = active.filter { $0.isScheduled(on: day) }
        var ordered: [Habit] = []
        func place(_ habit: Habit) {
            guard !ordered.contains(habit) else { return }
            ordered.append(habit)
            for next in list where next.anchorId == habit.id { place(next) }
        }
        for habit in list.sorted(by: { $0.time.sortIndex != $1.time.sortIndex ? $0.time.sortIndex < $1.time.sortIndex : $0.created < $1.created })
            where habit.anchorId == nil || !list.contains(where: { $0.id == habit.anchorId }) {
            place(habit)
        }
        return ordered
    }

    func doneToday(_ day: Date = Date()) -> Int { today(day).filter { isDone($0, on: day) }.count }

    /// The time window is over and it's still open – "die 2-Minuten-Version zählt auch".
    func windowPassed(_ habit: Habit, now: Date = Date()) -> Bool {
        guard let end = habit.time.endHour, !isDone(habit, on: now), habit.isScheduled(on: now) else { return false }
        return Calendar.current.component(.hour, from: now) >= end
    }

    /// Done days in a row; one missed day doesn't break it, two in a row do (never miss twice).
    func streak(_ habit: Habit, now: Date = Date()) -> Int {
        var count = 0
        var misses = 0
        for (offset, day) in scheduledDays(habit, back: 400, from: now).enumerated() {
            if isDone(habit, on: day) {
                count += 1
                misses = 0
            } else if offset == 0 && Calendar.current.isDate(day, inSameDayAs: now) {
                continue // today is still open
            } else {
                misses += 1
                if misses >= 2 { break }
            }
        }
        return count
    }

    /// The longest streak so far.
    func best(_ habit: Habit, now: Date = Date()) -> Int {
        var best = 0
        var current = 0
        var misses = 0
        for day in scheduledDays(habit, back: 400, from: now).reversed() {
            if isDone(habit, on: day) {
                current += 1
                misses = 0
            } else if !Calendar.current.isDate(day, inSameDayAs: now) {
                misses += 1
                if misses >= 2 { current = 0 }
            }
            best = max(best, current)
        }
        return best
    }

    /// The last scheduled day before today was missed – today is the one that must not slip.
    func missedLast(_ habit: Habit, now: Date = Date()) -> Bool {
        guard !isDone(habit, on: now) else { return false }
        let days = scheduledDays(habit, back: 14, from: now).filter { !Calendar.current.isDate($0, inSameDayAs: now) }
        guard let last = days.first else { return false }
        return !isDone(habit, on: last)
    }

    /// Every tick, all time – each one a vote for the identity.
    func votes(_ habit: Habit) -> Int {
        let prefix = habit.id.uuidString + "|"
        return marks.filter { $0.key.hasPrefix(prefix) && $0.value.done }.count
    }

    /// Share of scheduled days done, per week (oldest first). One routine or – with nil – all of them.
    func consistency(_ habit: Habit? = nil, weeks: Int = 8, now: Date = Date()) -> [Double?] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start else { return [] }
        let list = habit.map { [$0] } ?? habits
        return (0..<weeks).reversed().map { back -> Double? in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -back, to: thisWeek) else { return nil }
            var planned = 0
            var done = 0
            for offset in 0..<7 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: start), day <= today else { continue }
                for item in list where item.isScheduled(on: day) && (item.archivedAt.map { calendar.startOfDay(for: $0) >= day } ?? true) {
                    let finished = isDone(item, on: day)
                    // Today only counts once it's done – an open morning isn't a miss yet.
                    if calendar.isDate(day, inSameDayAs: today) && !finished { continue }
                    planned += 1
                    if finished { done += 1 }
                }
            }
            return planned == 0 ? nil : Double(done) / Double(planned)
        }
    }

    /// "Tag 12 von 30"
    func challengeDay(_ habit: Habit, now: Date = Date()) -> (day: Int, of: Int)? {
        guard let length = habit.lengthDays, let start = Self.date(habit.startDay) else { return nil }
        let day = (Calendar.current.dateComponents([.day], from: start, to: Calendar.current.startOfDay(for: now)).day ?? 0) + 1
        return (min(max(day, 1), length), length)
    }

    /// Newest first, only days the routine was planned.
    private func scheduledDays(_ habit: Habit, back: Int, from now: Date) -> [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        return (0..<back).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
            .filter { habit.isScheduled(on: $0) }
    }

    // MARK: Markdown (for people and models)

    func overview() -> String {
        var lines = ["# Routinen", "", "_Von Fenn geschrieben – bearbeiten in der App._", ""]
        for time in HabitTime.allCases {
            let items = active.filter { $0.time == time }
            guard !items.isEmpty else { continue }
            lines.append("## \(time.title)")
            for habit in items {
                var line = "- [\(isDone(habit) ? "x" : " ")] **\(habit.title)**, \(habit.weekdaysText), Serie \(streak(habit))"
                if let anchor = habit.anchorText(in: habits) { line += ", \(anchor)" }
                if let tiny = habit.tiny, !tiny.isEmpty { line += ", 2 Min: \(tiny)" }
                if let identity = habit.identity, !identity.isEmpty { line += ", Ich bin \(identity)" }
                if let challenge = challengeDay(habit) { line += ", Tag \(challenge.day)/\(challenge.of)" }
                if let auto = habit.auto { line += ", automatisch: \(auto.title)" }
                lines.append(line)
            }
            lines.append("")
        }
        let done = archived
        if !done.isEmpty {
            lines.append("## Archiv")
            for habit in done { lines.append("- \(habit.title), beste Serie \(best(habit)), \(votes(habit)) Mal") }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// One line per routine for the agent's context.
    var facts: String {
        let list = today()
        guard !list.isEmpty else { return "" }
        let items = list.map { habit in "\(habit.title) (\(habit.time.title), \(isDone(habit) ? "erledigt" : "offen"), Serie \(streak(habit)))" }
        return "Routinen heute: " + items.joined(separator: "; ")
    }

    // MARK: Helpers

    nonisolated static func key(_ id: UUID, _ day: Date) -> String { "\(id.uuidString)|\(FennVault.dayKey(day))" }
    nonisolated static func date(_ key: String) -> Date? { FennVault.dayFormatter.date(from: key) }

    /// Monday first.
    nonisolated static let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]
    /// Index = Calendar weekday - 1 (Sunday first).
    nonisolated static var weekdaySymbols: [String] {
        tr("So Mo Di Mi Do Fr Sa", "Su Mo Tu We Th Fr Sa").split(separator: " ").map(String.init)
    }

    private static func read(_ url: URL) -> HabitFile? {
        guard let data = FennVault.read(url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(HabitFile.self, from: data)
    }

    private static func write(_ file: HabitFile, to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(file) { _ = FennVault.write(data, to: url) }
    }
}

// MARK: - Starting points

/// Small, concrete routines to start from – each already with an anchor, a two-minute version and the identity.
enum HabitTemplates {
    static var all: [Habit] {
        [
            make(tr("Ein Glas Wasser", "A glass of water"), .morning, anchor: tr("dem Aufstehen", "getting up"),
                 tiny: tr("Ein paar Schlucke", "A few sips"), identity: tr("jemand, der gut für seinen Körper sorgt", "someone who looks after their body")),
            make(tr("Tag planen", "Plan the day"), .morning, anchor: tr("dem Wasser", "the water"),
                 tiny: tr("Die eine wichtigste Aufgabe notieren", "Write down the one task that matters most"),
                 identity: tr("jemand, der seinen Tag selbst bestimmt", "someone who decides how their day goes")),
            make(tr("Ein Fokusblock am Vormittag", "One focus block before noon"), .morning,
                 tiny: tr("10 Minuten an der wichtigsten Aufgabe", "10 minutes on the most important task"),
                 identity: tr("jemand, der Tiefenarbeit schützt", "someone who protects deep work"), auto: .focus),
            make(tr("Morgen-Check-in", "Morning check-in"), .morning, anchor: tr("dem ersten Kaffee", "the first coffee"),
                 tiny: tr("Nur die Energie antippen", "Just tap your energy"), identity: tr("jemand, der bewusst in den Tag startet", "someone who starts the day on purpose"), auto: .checkIn),
            make(tr("Posteingang leeren", "Clear the inbox"), .afternoon, tiny: tr("Fünf Mails beantworten oder archivieren", "Answer or archive five emails"),
                 identity: tr("jemand, der den Überblick behält", "someone who keeps the overview")),
            make(tr("10 Minuten lesen", "Read for 10 minutes"), .evening, anchor: tr("dem Zähneputzen", "brushing teeth"),
                 tiny: tr("Eine Seite", "One page"), identity: tr("jemand, der jeden Tag dazulernt", "someone who learns every day")),
            make(tr("Handy aus dem Schlafzimmer", "Phone out of the bedroom"), .evening, tiny: tr("Handy in den Flur legen", "Put the phone in the hallway"),
                 identity: tr("jemand, der abends abschaltet", "someone who switches off at night")),
            make(tr("Feierabend-Ritual", "Shutdown ritual"), .evening, anchor: tr("der letzten Mail", "the last email"),
                 tiny: tr("Die erste Aufgabe für morgen notieren", "Note tomorrow's first task"),
                 identity: tr("jemand, der Arbeit und Freizeit trennt", "someone who keeps work and free time apart")),
            make(tr("10 Minuten an die frische Luft", "10 minutes outside"), .anytime, tiny: tr("Einmal ums Haus", "Once around the block"),
                 identity: tr("jemand, der Pausen ernst nimmt", "someone who takes breaks seriously")),
            make(tr("Abend-Review", "Evening review"), .evening, tiny: tr("Ein Satz zum Tag", "One sentence about the day"),
                 identity: tr("jemand, der aus jedem Tag lernt", "someone who learns from every day"), auto: .review),
        ]
    }

    private static func make(_ title: String, _ time: HabitTime, anchor: String? = nil, tiny: String, identity: String, auto: HabitAuto? = nil) -> Habit {
        var habit = Habit(title: title, time: time)
        habit.anchor = anchor
        habit.tiny = tiny
        habit.identity = identity
        habit.auto = auto
        return habit
    }
}

enum HabitDemo {
    static func file() -> HabitFile {
        let templates = HabitTemplates.all
        var habits = [templates[0], templates[1], templates[2], templates[5], templates[7]]
        let calendar = Calendar.current
        let start = FennVault.dayKey(calendar.date(byAdding: .day, value: -60, to: Date()) ?? Date())
        for index in habits.indices { habits[index].startDay = start }
        habits[1].anchorId = habits[0].id
        habits[1].anchor = nil
        habits[4].lengthDays = 30
        habits[4].startDay = FennVault.dayKey(calendar.date(byAdding: .day, value: -11, to: Date()) ?? Date())
        var marks: [String: HabitMark] = [:]
        let rates = [0.95, 0.8, 0.7, 0.6, 0.85]
        for back in 1...60 {
            guard let day = calendar.date(byAdding: .day, value: -back, to: Date()) else { continue }
            for (index, habit) in habits.enumerated() where habit.isScheduled(on: day) {
                // Deterministic "random" so the demo looks the same every launch.
                let noise = Double((back * 37 + index * 11) % 100) / 100
                marks[HabitStore.key(habit.id, day)] = HabitMark(done: noise < rates[index] + Double(back) * 0.002, tiny: noise > 0.9 ? true : nil)
            }
        }
        marks[HabitStore.key(habits[0].id, Date())] = HabitMark(done: true)
        return HabitFile(habits: habits, marks: marks)
    }
}

// MARK: - Shared pieces of UI

/// Consistency over the last weeks as quiet bars – empty weeks as a hairline.
struct HabitConsistencyBars: View {
    let values: [Double?]
    var height: CGFloat = 44

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                VStack(spacing: 4) {
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Fenn.fg.opacity(0.07))
                        if let value {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(index == values.count - 1 ? Fenn.accent : Fenn.accent.opacity(0.55))
                                .frame(height: max(3, height * value))
                        }
                    }
                    .frame(height: height)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("Beständigkeit der letzten \(values.count) Wochen", "Consistency over the last \(values.count) weeks"))
        .accessibilityValue(values.map { $0.map { "\(Int($0 * 100)) %" } ?? "–" }.joined(separator: ", "))
    }
}

/// The subtitle of a routine row: anchor, streak or the gentle nudge when the window has passed or yesterday slipped.
enum HabitLine {
    @MainActor
    static func subtitle(_ habit: Habit, store: HabitStore, now: Date = Date()) -> (text: String, warn: Bool)? {
        let done = store.mark(habit, on: now)
        if done?.done == true {
            if done?.auto == true { return (tr("Automatisch erkannt, \(habit.auto?.title ?? "")", "Detected, \(habit.auto?.title ?? "")"), false) }
            if done?.tiny == true { return (tr("2-Minuten-Version – zählt", "Two-minute version – counts"), false) }
        } else {
            if store.windowPassed(habit, now: now) {
                if let tiny = habit.tiny { return (tr("Mini-Version: \(tiny)", "Mini version: \(tiny)"), true) }
                return (tr("\(habit.time.title) vorbei", "\(habit.time.title) is over"), true)
            }
            if store.missedLast(habit, now: now) {
                return (tr("Letztes Mal ausgelassen", "Missed last time"), true)
            }
        }
        var parts: [String] = []
        if let anchor = habit.anchorText(in: store.habits) { parts.append(anchor) }
        if let challenge = store.challengeDay(habit) { parts.append(tr("Tag \(challenge.day) von \(challenge.of)", "Day \(challenge.day) of \(challenge.of)")) }
        let streak = store.streak(habit, now: now)
        if streak >= 2 { parts.append(tr("\(streak) in Serie", "\(streak) in a row")) }
        if parts.isEmpty, let auto = habit.auto { parts.append(tr("automatisch: \(auto.title)", "automatic: \(auto.title)")) }
        return parts.isEmpty ? nil : (parts.joined(separator: ", "), false)
    }
}
