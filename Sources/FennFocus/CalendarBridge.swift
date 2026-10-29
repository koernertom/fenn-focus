import EventKit

enum CalendarTarget: String, CaseIterable, Identifiable {
    case reminders
    case calendar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reminders: return tr("Erinnerungen (im Kalender sichtbar)", "Reminders (shown in Calendar)")
        case .calendar: return tr("Kalender-Termine (30 min)", "Calendar events (30 min)")
        }
    }

    static let defaultsKey = "fenn.calendarTarget"
}

enum CalendarBridgeError: LocalizedError {
    case denied
    case noCalendar

    var errorDescription: String? {
        switch self {
        case .denied:
            return tr("Kein Zugriff auf Kalender/Erinnerungen – Systemeinstellungen › Datenschutz & Sicherheit.",
                      "No access to Calendar/Reminders – System Settings › Privacy & Security.")
        case .noCalendar:
            return tr("Kein Standard-Kalender bzw. keine Standard-Liste gefunden.", "No default calendar or list found.")
        }
    }
}

/// Puts to-dos into Apple Reminders (with due date) or as 30-minute blocks into Apple Calendar.
@MainActor
final class CalendarBridge {
    private let store = EKEventStore()

    func add(_ todos: [NoteTodo], to target: CalendarTarget) async throws {
        switch target {
        case .reminders:
            guard try await store.requestFullAccessToReminders() else { throw CalendarBridgeError.denied }
            guard let list = store.defaultCalendarForNewReminders() else { throw CalendarBridgeError.noCalendar }
            for todo in todos {
                let reminder = EKReminder(eventStore: store)
                reminder.title = todo.title
                reminder.calendar = list
                if let offset = todo.dayOffset, let day = Self.day(offset) {
                    reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: day)
                }
                try store.save(reminder, commit: false)
            }
        case .calendar:
            guard try await store.requestWriteOnlyAccessToEvents() else { throw CalendarBridgeError.denied }
            guard let calendar = store.defaultCalendarForNewEvents else { throw CalendarBridgeError.noCalendar }
            var nextStart: [Int: Date] = [:]
            for todo in todos {
                // "Später" lands the day after tomorrow; blocks on the same day follow each other.
                let offset = todo.dayOffset ?? 2
                let start = nextStart[offset] ?? Self.firstSlot(dayOffset: offset)
                let event = EKEvent(eventStore: store)
                event.title = todo.title
                event.calendar = calendar
                event.startDate = start
                event.endDate = start.addingTimeInterval(30 * 60)
                try store.save(event, span: .thisEvent, commit: false)
                nextStart[offset] = event.endDate
            }
        }
        try store.commit()
    }

    private static func day(_ offset: Int) -> Date? {
        Calendar.current.date(byAdding: .day, value: offset, to: Date())
    }

    /// Today: the next full hour. Other days: 09:00.
    private static func firstSlot(dayOffset: Int) -> Date {
        let calendar = Calendar.current
        if dayOffset == 0 {
            let hourStart = calendar.date(from: calendar.dateComponents([.year, .month, .day, .hour], from: Date())) ?? Date()
            return hourStart.addingTimeInterval(60 * 60)
        }
        let day = day(dayOffset) ?? Date()
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
    }
}
