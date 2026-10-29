import AppKit
import EventKit
import Foundation

/// One appointment from any source, reduced to what the day view and the slot planner need.
struct AgendaEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendar: String
    /// Teams, Zoom, Meet or Webex link found in URL, location or notes.
    let joinURL: URL?

    var interval: DateInterval { DateInterval(start: start, end: max(start, end)) }
}

/// A calendar feed by link (e.g. Outlook "Publish calendar" or Google "secret address in iCal format").
struct ICSFeed: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var url: String
}

/// Work calendar for the Mac – optional, off until switched on. Reads every calendar macOS knows
/// (iCloud, Google, Microsoft Exchange/Outlook incl. Teams meetings – added under System Settings › Internet
/// Accounts) through EventKit, plus optional ICS links, and finds free time for focus.
/// Nothing leaves the Mac except the ICS requests to the links you add.
@MainActor
final class WorkCalendar: ObservableObject {
    static let shared = WorkCalendar()

    struct CalendarInfo: Identifiable, Equatable {
        let id: String
        let title: String
        let account: String
    }

    @Published var enabled = FennDemo.isOn || UserDefaults.standard.bool(forKey: Keys.enabled) {
        didSet { UserDefaults.standard.set(enabled, forKey: Keys.enabled) }
    }
    @Published private(set) var accessDenied = false
    @Published private(set) var events: [AgendaEvent] = []
    @Published private(set) var calendars: [CalendarInfo] = []
    @Published private(set) var feedErrors: [UUID: String] = [:]
    @Published var excluded = Set(UserDefaults.standard.stringArray(forKey: Keys.excluded) ?? []) {
        didSet { UserDefaults.standard.set(Array(excluded), forKey: Keys.excluded); Task { await refresh() } }
    }
    @Published var feeds: [ICSFeed] = (UserDefaults.standard.data(forKey: Keys.feeds).flatMap { try? JSONDecoder().decode([ICSFeed].self, from: $0) }) ?? [] {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(feeds), forKey: Keys.feeds) }
    }
    @Published var workStart = UserDefaults.standard.object(forKey: Keys.workStart) as? Int ?? 9 {
        didSet { UserDefaults.standard.set(workStart, forKey: Keys.workStart) }
    }
    @Published var workEnd = UserDefaults.standard.object(forKey: Keys.workEnd) as? Int ?? 18 {
        didSet { UserDefaults.standard.set(workEnd, forKey: Keys.workEnd) }
    }

    private enum Keys {
        static let enabled = "fenn.calendar.enabled", excluded = "fenn.calendar.excluded", feeds = "fenn.calendar.feeds"
        static let workStart = "fenn.calendar.workStart", workEnd = "fenn.calendar.workEnd"
    }

    private let store = EKEventStore()
    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
            Task { @MainActor in await WorkCalendar.shared.refresh() }
        }
    }

    var hasEventKitAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    /// Switches the calendar on; the first time macOS asks for access.
    func enable() async {
        enabled = true
        if EKEventStore.authorizationStatus(for: .event) != .fullAccess {
            let granted = (try? await store.requestFullAccessToEvents()) ?? false
            accessDenied = !granted
        }
        await refresh()
    }

    func disable() {
        enabled = false
        events = []
    }

    /// Today and the next 7 days from EventKit and the ICS links.
    func refresh() async {
        guard enabled else { return }
        if FennDemo.isOn { events = Self.demoEvents(); calendars = []; return }
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 8, to: start) ?? start
        var all: [AgendaEvent] = []
        if hasEventKitAccess {
            accessDenied = false
            let eventCalendars = store.calendars(for: .event)
            calendars = eventCalendars.map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title, account: $0.source.title) }
                .sorted { ($0.account, $0.title) < ($1.account, $1.title) }
            let used = eventCalendars.filter { !excluded.contains($0.calendarIdentifier) }
            if !used.isEmpty {
                let predicate = store.predicateForEvents(withStart: start, end: end, calendars: used)
                all += store.events(matching: predicate).map { event in
                    AgendaEvent(id: event.calendarItemIdentifier + "\(event.startDate.timeIntervalSince1970)",
                                title: event.title ?? tr("Termin", "Event"), start: event.startDate, end: event.endDate,
                                isAllDay: event.isAllDay, calendar: event.calendar.title,
                                joinURL: Self.joinLink(in: [event.url?.absoluteString, event.location, event.notes]))
                }
            }
        }
        for feed in feeds {
            do {
                all += try await ICSCalendar.events(from: feed, between: start, and: end)
                feedErrors[feed.id] = nil
            } catch {
                feedErrors[feed.id] = error.localizedDescription
            }
        }
        events = all.sorted { $0.start < $1.start }
    }

    func events(on day: Date) -> [AgendaEvent] {
        events.filter { Calendar.current.isDate($0.start, inSameDayAs: day) || ($0.start < day && $0.end > day) }
    }

    /// Busy time on a day (all-day entries don't block).
    func busy(on day: Date) -> [DateInterval] {
        events(on: day).filter { !$0.isAllDay }.map(\.interval)
    }

    /// Screenshots and demos: a plausible workday around the current time, no calendar access needed.
    private static func demoEvents() -> [AgendaEvent] {
        let now = Date()
        let quarter = Date(timeIntervalSinceReferenceDate: ceil(now.timeIntervalSinceReferenceDate / 900) * 900)
        let teams = URL(string: "https://teams.microsoft.com/l/meetup-join/demo")
        func event(_ title: String, _ offsetMinutes: Double, _ length: Double, _ calendar: String, _ join: URL? = nil) -> AgendaEvent {
            let start = quarter.addingTimeInterval(offsetMinutes * 60)
            return AgendaEvent(id: title, title: title, start: start, end: start.addingTimeInterval(length * 60), isAllDay: false, calendar: calendar, joinURL: join)
        }
        return [
            event(tr("Weekly Sync, Produkt", "Weekly sync, Product"), 15, 45, "Outlook", teams),
            event("Pitch Q4 Review", 120, 60, "Outlook", teams),
            event(tr("1:1 mit Lara", "1:1 with Lara"), 210, 30, "Outlook", teams),
            event(tr("Kundentermin Nordlicht", "Client call Nordlicht"), 24 * 60 - 120, 60, "iCloud"),
            event("Planning Sprint 42", 24 * 60 + 30, 90, "Outlook", teams)
        ]
    }

    // MARK: Helpers

    /// The first meeting link among the fields: Teams, Zoom, Google Meet, Webex.
    nonisolated static func joinLink(in fields: [String?]) -> URL? {
        let pattern = #"https://[^\s"<>]*(teams\.microsoft\.com|teams\.live\.com|zoom\.us|meet\.google\.com|webex\.com)[^\s"<>]*"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        for text in fields.compactMap({ $0 }) {
            if let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range, in: text) { return URL(string: String(text[range])) }
        }
        return nil
    }

    static func openInternetAccounts() {
        let urls = ["x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension", "x-apple.systempreferences:com.apple.preferences.internetaccounts"]
        for string in urls { if let url = URL(string: string), NSWorkspace.shared.open(url) { return } }
    }

    static func openCalendarPrivacy() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") { NSWorkspace.shared.open(url) }
    }
}

// MARK: - Free time for focus

enum FreeTime {
    /// Longest free stretch in working hours today – offered as a focus block.
    static func focusWindow(busy: [DateInterval], workHours: Range<Int>, now: Date = Date()) -> DateInterval? {
        let calendar = Calendar.current
        guard !calendar.isDateInWeekend(now),
              let open = calendar.date(bySettingHour: workHours.lowerBound, minute: 0, second: 0, of: now),
              let close = calendar.date(bySettingHour: workHours.upperBound, minute: 0, second: 0, of: now) else { return nil }
        var cursor = max(open, now)
        // After work hours (or before a late event) there's no window left – DateInterval must never end before it starts.
        guard cursor < close else { return nil }
        var best: DateInterval?
        for event in busy.sorted(by: { $0.start < $1.start }) where event.end > cursor {
            let end = min(event.start, close)
            if event.start > cursor, end > cursor, end.timeIntervalSince(cursor) > (best?.duration ?? 0) {
                best = DateInterval(start: cursor, end: end)
            }
            cursor = max(cursor, event.end)
            if cursor >= close { break }
        }
        if cursor < close, close.timeIntervalSince(cursor) > (best?.duration ?? 0) { best = DateInterval(start: cursor, end: close) }
        return (best?.duration ?? 0) >= 45 * 60 ? best : nil
    }
}

// MARK: - ICS links

/// Minimal iCalendar reader for published calendar links: single and simply repeating events
/// (daily/weekly with interval, weekdays, until/count), time zones by TZID, all-day dates.
enum ICSCalendar {
    enum Failure: LocalizedError {
        case badURL, unreadable
        var errorDescription: String? {
            switch self {
            case .badURL: return tr("Ungültiger Link.", "Invalid link.")
            case .unreadable: return tr("Kein Kalender unter diesem Link.", "No calendar at this link.")
            }
        }
    }

    static func events(from feed: ICSFeed, between start: Date, and end: Date) async throws -> [AgendaEvent] {
        let string = feed.url.replacingOccurrences(of: "webcal://", with: "https://")
        guard let url = URL(string: string), url.scheme == "https" || url.scheme == "http" else { throw Failure.badURL }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let text = String(data: data, encoding: .utf8), text.contains("BEGIN:VCALENDAR") else { throw Failure.unreadable }
        return parse(text, calendar: feed.name, between: start, and: end)
    }

    static func parse(_ text: String, calendar name: String, between rangeStart: Date, and rangeEnd: Date) -> [AgendaEvent] {
        // Unfold continuation lines.
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n ", with: "").replacingOccurrences(of: "\n\t", with: "")
            .components(separatedBy: "\n")
        var result: [AgendaEvent] = []
        var fields: [String: (params: String, value: String)]?
        for line in lines {
            if line == "BEGIN:VEVENT" { fields = [:]; continue }
            if line == "END:VEVENT", let event = fields {
                result += expand(event, calendar: name, between: rangeStart, and: rangeEnd)
                fields = nil
                continue
            }
            guard fields != nil, let colon = line.firstIndex(of: ":") else { continue }
            let head = line[..<colon]
            let value = String(line[line.index(after: colon)...])
            let parts = head.split(separator: ";", maxSplits: 1)
            let key = String(parts[0]).uppercased()
            if fields?[key] == nil { fields?[key] = (parts.count > 1 ? String(parts[1]) : "", value) }
        }
        return result
    }

    private static func expand(_ fields: [String: (params: String, value: String)], calendar name: String,
                               between rangeStart: Date, and rangeEnd: Date) -> [AgendaEvent] {
        guard let startField = fields["DTSTART"], let (start, allDay) = date(startField.value, params: startField.params) else { return [] }
        if fields["STATUS"]?.value.uppercased() == "CANCELLED" { return [] }
        var duration: TimeInterval = allDay ? 86_400 : 3_600
        if let endField = fields["DTEND"], let (end, _) = date(endField.value, params: endField.params) { duration = end.timeIntervalSince(start) }
        let title = (fields["SUMMARY"]?.value ?? tr("Termin", "Event")).replacingOccurrences(of: "\\,", with: ",").replacingOccurrences(of: "\\n", with: " ")
        let join = WorkCalendar.joinLink(in: [fields["URL"]?.value, fields["LOCATION"]?.value, fields["DESCRIPTION"]?.value.replacingOccurrences(of: "\\n", with: " ")])
        let uid = fields["UID"]?.value ?? UUID().uuidString

        var starts: [Date] = [start]
        if let rule = fields["RRULE"]?.value { starts = occurrences(of: rule, from: start, until: rangeEnd) }
        return starts.filter { $0 < rangeEnd && $0.addingTimeInterval(duration) > rangeStart }.map { occurrence in
            AgendaEvent(id: uid + "\(occurrence.timeIntervalSince1970)", title: title, start: occurrence,
                        end: occurrence.addingTimeInterval(duration), isAllDay: allDay, calendar: name, joinURL: join)
        }
    }

    /// DAILY / WEEKLY with INTERVAL, BYDAY, UNTIL, COUNT – enough for typical meeting series.
    private static func occurrences(of rule: String, from start: Date, until limit: Date) -> [Date] {
        var parts: [String: String] = [:]
        for item in rule.split(separator: ";") {
            let pair = item.split(separator: "=", maxSplits: 1)
            if pair.count == 2 { parts[String(pair[0]).uppercased()] = String(pair[1]) }
        }
        let calendar = Calendar.current
        let interval = Int(parts["INTERVAL"] ?? "1") ?? 1
        let until = parts["UNTIL"].flatMap { date($0, params: "")?.0 } ?? limit
        let count = parts["COUNT"].flatMap(Int.init) ?? Int.max
        let weekdays: [Int] = (parts["BYDAY"] ?? "").split(separator: ",").compactMap { code in
            ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7][String(code.suffix(2))]
        }
        var result: [Date] = []
        var produced = 0
        switch parts["FREQ"] {
        case "DAILY":
            var date = start
            while date <= min(until, limit) && produced < count {
                result.append(date); produced += 1
                date = calendar.date(byAdding: .day, value: interval, to: date) ?? limit.addingTimeInterval(1)
            }
        case "WEEKLY":
            let days = weekdays.isEmpty ? [calendar.component(.weekday, from: start)] : weekdays
            var weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: start)) ?? start
            let time = calendar.dateComponents([.hour, .minute, .second], from: start)
            while weekStart <= min(until, limit) && produced < count {
                for weekday in days.sorted(by: { (($0 + 5) % 7) < (($1 + 5) % 7) }) {
                    var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: weekStart)
                    components.weekday = weekday
                    components.hour = time.hour; components.minute = time.minute; components.second = time.second
                    guard let date = calendar.date(from: components), date >= start, date <= min(until, limit), produced < count else { continue }
                    result.append(date); produced += 1
                }
                weekStart = calendar.date(byAdding: .weekOfYear, value: interval, to: weekStart) ?? limit.addingTimeInterval(1)
            }
        default:
            result = [start]
        }
        return result
    }

    /// 20260924T090000Z, 20260924T090000 with TZID=…, or VALUE=DATE:20260924.
    private static func date(_ value: String, params: String) -> (Date, Bool)? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if value.count == 8 {
            formatter.dateFormat = "yyyyMMdd"
            formatter.timeZone = .current
            return formatter.date(from: value).map { ($0, true) }
        }
        formatter.dateFormat = value.hasSuffix("Z") ? "yyyyMMdd'T'HHmmss'Z'" : "yyyyMMdd'T'HHmmss"
        if value.hasSuffix("Z") {
            formatter.timeZone = TimeZone(identifier: "UTC")
        } else if let tzid = params.components(separatedBy: ";").first(where: { $0.uppercased().hasPrefix("TZID=") })?.dropFirst(5) {
            formatter.timeZone = TimeZone(identifier: String(tzid).trimmingCharacters(in: CharacterSet(charactersIn: "\""))) ?? .current
        } else {
            formatter.timeZone = .current
        }
        return formatter.date(from: value).map { ($0, false) }
    }
}
