import Combine
import EventKit
import Foundation

// Tasks with a date appear in Apple Calendar, in a calendar of their own ("Fenn Focus"). On by default once Fenn
// has calendar access; switching it off is remembered.
// All-day on the due day, or at the set time for the estimated length. Every event carries fennfocus://task/<id>,
// so each device finds and updates the same event instead of adding a second one. Done or deleted tasks leave the calendar.

@MainActor
final class TaskCalendarSync: ObservableObject {
    static let shared = TaskCalendarSync()
    static let calendarTitle = "Fenn Focus"
    private static let key = "fenn.tasks.calendar"

    @Published private(set) var isOn = TaskCalendarSync.storedChoice ?? TaskCalendarSync.accessGranted
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastCount: Int?

    /// Shared with the day view (FennDayPlanner): reading appointments, moving own ones.
    let eventStore = EKEventStore()
    private var watcher: AnyCancellable?

    var hasAccess: Bool { Self.accessGranted }
    private static var accessGranted: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    /// nil until the person switched the mirror on or off themselves.
    private static var storedChoice: Bool? { UserDefaults.standard.object(forKey: key) as? Bool }

    /// Asks for calendar access (the system dialog), then mirrors the tasks.
    func enable() async {
        errorMessage = nil
        let granted = (try? await eventStore.requestFullAccessToEvents()) ?? false
        guard granted else {
            errorMessage = tr("Kein Zugriff auf den Kalender – Einstellungen › Datenschutz › Kalender › Fenn: „Voller Zugriff“.",
                              "No calendar access – Settings › Privacy › Calendars › Fenn: “Full Access”.")
            return
        }
        isOn = true
        UserDefaults.standard.set(true, forKey: Self.key)
        start()
        sync()
    }

    /// Stops mirroring and takes Fenn's task entries out of the calendar again (the tasks themselves stay).
    func disable() {
        isOn = false
        UserDefaults.standard.set(false, forKey: Self.key)
        watcher = nil
        guard hasAccess, let calendar = existingCalendar() else { return }
        for event in events(in: calendar) where event.url?.scheme == "fennfocus" { try? eventStore.remove(event, span: .thisEvent, commit: false) }
        try? eventStore.commit()
        lastCount = nil
    }

    /// Called at launch: follows every change of the task list (debounced) while switched on.
    func start() {
        if Self.storedChoice == nil, hasAccess { isOn = true }
        guard isOn, hasAccess, !FennDemo.isOn else { return }
        watcher = TaskStore.shared.$tasks
            .dropFirst()
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.sync() }
    }

    func sync() {
        guard isOn, hasAccess, !FennDemo.isOn else { return }
        do {
            let calendar = try fennCalendar()
            var existing: [String: EKEvent] = [:]
            for event in events(in: calendar) + duplicateCalendars(of: calendar).flatMap(events(in:)) {
                guard let url = event.url, url.scheme == "fennfocus", url.host == "task" else { continue }
                let id = url.lastPathComponent
                if existing[id] != nil { try? eventStore.remove(event, span: .thisEvent, commit: false) } else { existing[id] = event }
            }
            var count = 0
            for task in TaskStore.shared.tasks where !task.done {
                guard let day = task.due ?? task.start else { continue }
                let event = existing.removeValue(forKey: task.id.uuidString) ?? EKEvent(eventStore: eventStore)
                if apply(task, day: day, to: event, calendar: calendar) {
                    try eventStore.save(event, span: .thisEvent, commit: false)
                }
                count += 1
            }
            // Done, deleted or without a date: out of the calendar.
            for event in existing.values { try? eventStore.remove(event, span: .thisEvent, commit: false) }
            try eventStore.commit()
            lastCount = count
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Private

    /// Fills the event from the task; false when nothing changed.
    private func apply(_ task: FennTask, day: Date, to event: EKEvent, calendar: EKCalendar) -> Bool {
        let cal = Calendar.current
        let parts = cal.dateComponents([.hour, .minute], from: day)
        let timed = (parts.hour ?? 0) != 0 || (parts.minute ?? 0) != 0
        let title = (task.priority == .high ? "‼️ " : "") + task.title
        let start = timed ? day : cal.startOfDay(for: day)
        let end = timed ? day.addingTimeInterval(Double(max(15, task.estimateMinutes ?? 30)) * 60) : start
        var lines = [tr("Priorität: \(task.priority.title)", "Priority: \(task.priority.title)")]
        if !task.topic.isEmpty { lines.append(tr("Thema: \(task.topic)", "Topic: \(task.topic)")) }
        if let estimate = task.estimateMinutes { lines.append(tr("Dauer: ~\(TaskFormat.duration(estimate))", "Estimate: ~\(TaskFormat.duration(estimate))")) }
        lines.append(tr("Aus Fenn – bearbeiten und abhaken in der App.", "From Fenn – edit and tick off in the app."))
        let notes = lines.joined(separator: "\n")
        let url = URL(string: "fennfocus://task/\(task.id.uuidString)")
        let unchanged = event.calendar == calendar && event.title == title && event.isAllDay == !timed
            && event.startDate == start && (timed ? event.endDate == end : true) && event.notes == notes && event.url == url
        guard !unchanged else { return false }
        event.calendar = calendar
        event.title = title
        event.isAllDay = !timed
        event.startDate = start
        event.endDate = end
        event.notes = notes
        event.url = url
        return true
    }

    private func events(in calendar: EKCalendar) -> [EKEvent] {
        let cal = Calendar.current
        let from = cal.date(byAdding: .day, value: -60, to: Date()) ?? Date()
        let to = cal.date(byAdding: .day, value: 700, to: Date()) ?? Date()
        return eventStore.events(matching: eventStore.predicateForEvents(withStart: from, end: to, calendars: [calendar]))
    }

    /// "Fenn Focus". If two devices created one each before iCloud synced, the fuller one wins – sync then empties
    /// the other, so both devices settle on the same calendar.
    private func existingCalendar() -> EKCalendar? {
        let found = eventStore.calendars(for: .event).filter { $0.title == Self.calendarTitle && $0.allowsContentModifications }
        guard found.count > 1 else { return found.first }
        return found.map { (calendar: $0, count: events(in: $0).count) }
            .max { ($0.count, $1.calendar.calendarIdentifier) < ($1.count, $0.calendar.calendarIdentifier) }?.calendar
    }

    private func duplicateCalendars(of main: EKCalendar) -> [EKCalendar] {
        eventStore.calendars(for: .event).filter {
            $0.title == Self.calendarTitle && $0.allowsContentModifications && $0.calendarIdentifier != main.calendarIdentifier
        }
    }

    /// "Fenn Focus" next to the default calendar (iCloud, Google …) so it shows on every device of that account.
    private func fennCalendar() throws -> EKCalendar {
        if let calendar = existingCalendar() { return calendar }
        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        calendar.title = Self.calendarTitle
        calendar.cgColor = CGColor(red: 0.21, green: 0.37, blue: 0.37, alpha: 1)
        guard let source = eventStore.defaultCalendarForNewEvents?.source ?? eventStore.sources.first(where: { $0.sourceType == .local }) else {
            throw CalendarError.noSource
        }
        calendar.source = source
        try eventStore.saveCalendar(calendar, commit: true)
        return calendar
    }

    enum CalendarError: LocalizedError {
        case noSource
        var errorDescription: String? { tr("Kein Kalenderkonto gefunden.", "No calendar account found.") }
    }
}
