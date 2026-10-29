import Foundation

/// One day of work: what the streak, the widgets and the routines' auto-ticks read.
struct DayRecord: Codable, Equatable {
    /// yyyy-MM-dd
    var day: String
    var focusBlocks = 0
    var tasksCompleted: Int? = nil
    var habitsDone: Int? = nil

    /// Anything done that day – a focus block, a finished task or a routine.
    var isActive: Bool { focusBlocks > 0 || (tasksCompleted ?? 0) > 0 || (habitsDone ?? 0) > 0 }
}

/// Local daily history in `stats/days.json`: focus blocks, finished tasks and routines per day.
@MainActor
final class MetricsStore: ObservableObject {
    @Published private(set) var days: [String: DayRecord] = [:]

    private var url: URL { FennStorage.url(.dayStats) }
    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    init() {
        reload()
    }

    /// Reads `stats/days.json` from the current storage root (again after the sync folder changes).
    func reload() {
        guard let data = FennVault.read(url), let stored = try? JSONDecoder().decode([DayRecord].self, from: data) else { return }
        var merged = days
        for record in stored { merged[record.day] = record }
        days = merged
    }

    static func key(_ date: Date) -> String { dayFormatter.string(from: date) }

    func record(for date: Date) -> DayRecord {
        let key = Self.key(date)
        return days[key] ?? DayRecord(day: key)
    }

    func record(_ day: String) -> DayRecord {
        days[day] ?? DayRecord(day: day)
    }

    /// Oldest first, one record per calendar day (empty days included).
    func records(lastDays count: Int, endingDaysAgo offset: Int = 0) -> [DayRecord] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<count).reversed().compactMap { index in
            calendar.date(byAdding: .day, value: -(index + offset), to: today).map(record(for:))
        }
    }

    /// Consecutive active days up to today (today counts once something is done, yesterday keeps it alive until then).
    var streakDays: Int {
        var streak = 0
        var date = Date()
        if !record(for: date).isActive {
            date = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
        }
        while record(for: date).isActive {
            streak += 1
            date = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
        }
        return streak
    }

    func logFocusBlock() {
        update(Date()) { $0.focusBlocks += 1 }
    }

    func logHabitDone() {
        update(Date()) { $0.habitsDone = ($0.habitsDone ?? 0) + 1 }
    }

    func logTaskDone() {
        update(Date()) { $0.tasksCompleted = ($0.tasksCompleted ?? 0) + 1 }
    }

    func save() {
        let sorted = days.values.sorted { $0.day < $1.day }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(sorted) {
            FennVault.write(data, to: url)
        }
    }

    private func update(_ date: Date, _ change: (inout DayRecord) -> Void) {
        var record = record(for: date)
        change(&record)
        days[record.day] = record
        save()
    }
}
