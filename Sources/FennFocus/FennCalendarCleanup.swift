import EventKit
import Foundation

/// Kalender-Einstellungen: everything Fenn put into Apple Calendar out again, in one go.
/// Only events with a fennfocus:// link in "Fenn Focus" are touched; the calendar is deleted only
/// when nothing of the person's own is left in it. Tasks in Fenn stay as they are.
@MainActor
enum FennCalendarCleanup {
    static let titles = [TaskCalendarSync.calendarTitle]

    struct Result {
        var events = 0
        var calendars = 0
    }

    static var hasAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    /// Switches every Fenn calendar writer off on this Mac and removes their entries.
    static func removeAll() throws -> Result {
        TaskCalendarSync.shared.disable()
        guard hasAccess else { return Result() }
        let store = TaskCalendarSync.shared.eventStore
        var result = Result()
        for calendar in store.calendars(for: .event) where titles.contains(calendar.title) && calendar.allowsContentModifications {
            var ownLeft = false
            for event in events(in: calendar, store: store) {
                if event.url?.scheme == "fennfocus" {
                    try store.remove(event, span: .thisEvent, commit: false)
                    result.events += 1
                } else {
                    ownLeft = true
                }
            }
            if !ownLeft {
                try store.removeCalendar(calendar, commit: false)
                result.calendars += 1
            }
        }
        try store.commit()
        return result
    }

    static func summary(_ result: Result) -> String {
        result.events == 0
            ? tr("Im Kalender stand nichts mehr von Fenn.", "There was nothing of Fenn's left in the calendar.")
            : tr("\(result.events) Termine entfernt", "\(result.events) events removed")
                + (result.calendars > 0 ? tr(", leere Fenn-Kalender gelöscht.", ", empty Fenn calendars deleted.") : ".")
    }

    /// Two years back and forward – EventKit searches at most four years at once.
    private static func events(in calendar: EKCalendar, store: EKEventStore) -> [EKEvent] {
        let cal = Calendar.current
        let from = cal.date(byAdding: .year, value: -2, to: Date()) ?? Date()
        let to = cal.date(byAdding: .year, value: 2, to: Date()) ?? Date()
        return store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: [calendar]))
    }
}
