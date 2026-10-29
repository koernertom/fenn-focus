import AppIntents
import AppKit
import FennFocusCore
import SwiftUI
import WidgetKit

// Desktop widgets in Fenn's clay look ("Knet-Optik"): puffy surfaces lit from the top left,
// pressed-in tracks, the clay icons and Fenn Grün – beige on light, deep green on dark. Compiled by the widget
// extension and by the app (for the QA gallery, -FennQAWidgetGallery), so all helpers live inside `DesktopClay`.

enum DesktopClay {
    static func dynamic(_ light: (Double, Double, Double), _ dark: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let c = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }

    static let ink = dynamic((0.12, 0.17, 0.16), (0.95, 0.93, 0.89))
    static let soft = ink.opacity(0.58)
    static let sage = dynamic((0.25, 0.42, 0.38), (0.48, 0.66, 0.60))
    static let sageLight = dynamic((0.47, 0.62, 0.56), (0.62, 0.78, 0.71))
    static let onSage = dynamic((0.98, 0.97, 0.94), (0.04, 0.15, 0.14))
    static let canvasTop = dynamic((0.95, 0.92, 0.87), (0.07, 0.23, 0.22))
    static let canvasBottom = dynamic((0.90, 0.86, 0.79), (0.04, 0.16, 0.15))
    static let surfaceTop = dynamic((0.99, 0.97, 0.93), (0.13, 0.33, 0.31))
    static let surfaceBottom = dynamic((0.93, 0.89, 0.82), (0.08, 0.25, 0.23))
    static let track = dynamic((0.86, 0.81, 0.73), (0.03, 0.13, 0.12))
    static let lightEdge = dynamic((1, 1, 1), (0.55, 0.75, 0.70))

    static func t(_ s: FennWidgetSnapshot, _ de: String, _ en: String) -> String { s.german ? de : en }
    static func ratio(_ v: Double, _ target: Double) -> Double { target > 0 ? min(1, v / target) : 0 }

    static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func today(_ entry: FennDesktopEntry) -> (Bool, FennWidgetSnapshot) {
        let isToday = entry.snapshot.day.isEmpty || entry.snapshot.day == dayKey(Date())
        return (isToday, isToday ? entry.snapshot : entry.snapshot.withoutDayValues)
    }

    /// SF symbol → clay icon (same table as the app).
    static func art(for symbol: String) -> String? {
        let table: [String: String] = [
            "drop": "Food-water", "drop.fill": "Food-water", "book": "Clay-books", "book.fill": "Clay-books",
            "pencil": "Set-pen", "pencil.line": "Set-pen", "figure.walk": "Clay-footprints",
            "bed.double": "Clay-bed", "bed.double.fill": "Clay-bed", "iphone.slash": "Page-block", "lock": "Page-block",
            "heart": "Set-heart", "heart.fill": "Set-heart", "snowflake": "Clay-snowflake", "sparkles": "Set-sparkles",
            "cup.and.saucer": "Food-coffee", "brain.head.profile": "Clay-brain", "sun.max": "Clay-sun", "sunrise": "Page-today",
            "moon": "Clay-moon", "moon.stars": "Clay-moon", "clock": "Page-focus", "timer": "Page-focus",
            "flame": "Clay-campfire", "water.waves": "Clay-wave",
        ]
        return table[symbol]
    }

    struct Icon: View {
        let name: String?
        var symbol: String = "circle"
        var size: CGFloat = 26
        @Environment(\.colorScheme) private var scheme
        var body: some View {
            if let name, NSImage(named: name) != nil {
                Image(name).resizable().interpolation(.high).scaledToFit().frame(width: size, height: size)
                    .shadow(color: .black.opacity(0.12), radius: 1.5, x: 1, y: 1.5)
                    .background { if scheme == .dark { Circle().fill(Color(red: 0.75, green: 0.88, blue: 0.83).opacity(0.22)).blur(radius: size * 0.22) } }
            } else {
                Image(systemName: symbol).font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(DesktopClay.sage)
                    .frame(width: size, height: size).desktopClayPad(radius: size * 0.32)
            }
        }
    }

    struct Background: View {
        var glow: Color? = nil
        var body: some View {
            ZStack {
                LinearGradient(colors: [canvasTop, canvasBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [lightEdge.opacity(0.22), .clear], center: UnitPoint(x: 0.15, y: 0.05), startRadius: 0, endRadius: 220)
                if let glow { RadialGradient(colors: [glow.opacity(0.45), .clear], center: .center, startRadius: 0, endRadius: 120) }
                Grain().opacity(0.5)
            }
        }
    }

    struct Grain: View {
        var body: some View {
            Canvas { g, size in
                var seed: UInt64 = 0x9E3779B97F4A7C15
                func next() -> Double {
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    return Double(seed >> 33) / Double(1 << 31)
                }
                for _ in 0..<260 {
                    let x = next() * size.width, y = next() * size.height, r = 0.4 + next() * 0.7
                    let dark = next() < 0.5
                    g.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(dark ? .black.opacity(0.10) : .white.opacity(0.16)))
                }
            }
        }
    }

    struct Tube: View {
        var value: Double
        var height: CGFloat = 10
        var body: some View {
            GeometryReader { proxy in
                let width = max(height, proxy.size.width * min(1, max(0, value)))
                ZStack(alignment: .leading) {
                    Capsule().fill(track)
                        .overlay(Capsule().stroke(LinearGradient(colors: [.black.opacity(0.18), .clear], startPoint: .top, endPoint: .bottom), lineWidth: 1.2))
                    if value > 0 {
                        Capsule().fill(LinearGradient(colors: [sageLight, sage], startPoint: .top, endPoint: .bottom))
                            .overlay(alignment: .top) {
                                Capsule().fill(.white.opacity(0.35)).frame(height: height * 0.28).padding(.horizontal, height * 0.4).padding(.top, height * 0.16)
                            }
                            .frame(width: width)
                            .shadow(color: .black.opacity(0.15), radius: 1, x: 0, y: 1)
                    }
                }
            }
            .frame(height: height)
        }
    }

    struct Tick: View {
        let done: Bool
        var size: CGFloat = 22
        var body: some View {
            ZStack {
                if done {
                    Circle().fill(LinearGradient(colors: [sageLight, sage], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(Circle().stroke(LinearGradient(colors: [.white.opacity(0.55), .clear], startPoint: .topLeading, endPoint: .center), lineWidth: 1.2))
                        .shadow(color: .black.opacity(0.18), radius: 1.5, x: 1, y: 2)
                    Image(systemName: "checkmark").font(.system(size: size * 0.42, weight: .heavy)).foregroundStyle(onSage)
                } else {
                    Circle().fill(track)
                        .overlay(Circle().stroke(LinearGradient(colors: [.black.opacity(0.2), .white.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.4))
                }
            }
            .frame(width: size, height: size)
        }
    }

    static func label(_ text: String) -> some View {
        Text(text.uppercased()).font(.system(size: 10.5, weight: .bold, design: .rounded)).tracking(0.9).foregroundStyle(soft)
            .lineLimit(1).minimumScaleFactor(0.7)
    }

    static func number(_ value: String, size: CGFloat) -> some View {
        Text(value).font(.system(size: size, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(ink)
            .shadow(color: lightEdge.opacity(0.5), radius: 0, x: -0.6, y: -0.6)
            .shadow(color: .black.opacity(0.12), radius: 1, x: 0.8, y: 1.2)
    }

    static func button(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 12.5, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
            .foregroundStyle(onSage)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity).frame(height: 30)
            .desktopClayPad(radius: 15, fill: [sageLight, sage])
    }
}

struct DesktopClayPad: ViewModifier {
    var radius: CGFloat
    var fill: [Color]? = nil
    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LinearGradient(colors: fill ?? [DesktopClay.surfaceTop, DesktopClay.surfaceBottom], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(LinearGradient(colors: [DesktopClay.lightEdge.opacity(0.7), .clear, .black.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.2))
                .shadow(color: .black.opacity(0.14), radius: 3, x: 1.5, y: 2.5)
        )
    }
}

extension View {
    func desktopClayPad(radius: CGFloat = 16, fill: [Color]? = nil) -> some View { modifier(DesktopClayPad(radius: radius, fill: fill)) }
}

// MARK: - Entries

struct FennDesktopEntry: TimelineEntry {
    let date: Date
    let snapshot: FennWidgetSnapshot
}

struct FennDesktopProvider: TimelineProvider {
    func placeholder(in context: Context) -> FennDesktopEntry {
        FennDesktopEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (FennDesktopEntry) -> Void) {
        let snapshot = context.isPreview ? FennWidgetSnapshot.placeholder : (FennWidgetSnapshot.load() ?? .empty)
        completion(FennDesktopEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FennDesktopEntry>) -> Void) {
        let snapshot = FennWidgetSnapshot.load() ?? .empty
        let entries = Self.entries(for: snapshot)
        let refresh = entries.last?.date.addingTimeInterval(30 * 60) ?? Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }

    /// One entry per Pomodoro phase so the countdown flips from work to break while Fenn is closed.
    private static func entries(for snapshot: FennWidgetSnapshot) -> [FennDesktopEntry] {
        guard var clock = snapshot.pomodoro, clock.phase == "work" || clock.phase == "break" else {
            return [FennDesktopEntry(date: Date(), snapshot: snapshot)]
        }
        var entries: [FennDesktopEntry] = []
        var when = Date()
        clock = PomodoroClock.catchUp(clock, now: when)
        var steps = 0
        while (clock.phase == "work" || clock.phase == "break"), steps < 48, let end = clock.phaseEndsAt, end > when {
            var copy = snapshot
            copy.pomodoro = clock
            entries.append(FennDesktopEntry(date: when, snapshot: copy))
            when = end
            clock = PomodoroClock.catchUp(clock, now: end.addingTimeInterval(0.05))
            steps += 1
        }
        var tail = snapshot
        tail.pomodoro = clock
        entries.append(FennDesktopEntry(date: when, snapshot: tail))
        return entries.isEmpty ? [FennDesktopEntry(date: Date(), snapshot: snapshot)] : entries
    }
}

// MARK: - Today

/// The working day at a glance: the next meeting, focus time so far, tasks done and routines.
struct FennTodayDesktopView: View {
    @Environment(\.widgetFamily) private var envFamily
    let entry: FennDesktopEntry
    var familyOverride: WidgetFamily? = nil
    private var family: WidgetFamily { familyOverride ?? envFamily }
    private typealias C = DesktopClay

    var body: some View {
        let (isToday, s) = C.today(entry)
        Group {
            switch family {
            case .systemSmall: small(s, isToday: isToday)
            case .systemMedium: medium(s, isToday: isToday)
            default: large(s, isToday: isToday)
            }
        }
        .widgetURL(URL(string: "fennfocus://today"))
        .containerBackground(for: .widget) { C.Background() }
    }

    private static func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }

    private func focusLabel(_ minutes: Int) -> String { String(format: "%d:%02d", minutes / 60, minutes % 60) }

    private func nextMeeting(_ s: FennWidgetSnapshot, isToday: Bool, titleSize: CGFloat) -> some View {
        let next = isToday ? s.events?.first : nil
        return HStack(spacing: 8) {
            C.Icon(name: "Page-today", symbol: "calendar", size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(next?.title ?? (isToday ? C.t(s, "Keine Termine mehr", "No more meetings") : C.t(s, "Öffne Fenn", "Open Fenn")))
                    .font(.system(size: titleSize, weight: .bold, design: .rounded)).foregroundStyle(C.ink)
                    .lineLimit(2).minimumScaleFactor(0.8)
                if let next {
                    Text(Self.time(next.start) + (next.canJoin ? C.t(s, ", mit Link", ", with link") : ""))
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded)).foregroundStyle(C.soft).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .desktopClayPad(radius: 14)
    }

    private func small(_ s: FennWidgetSnapshot, isToday: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                C.label(C.t(s, "Heute", "Today"))
                Spacer()
                Image("FennAvatarStone").resizable().scaledToFit().frame(width: 30, height: 30)
                    .shadow(color: .black.opacity(0.15), radius: 2, x: 1, y: 2)
            }
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                C.number(focusLabel(s.focusMinutes), size: 20)
                Text(C.t(s, "Fokus", "focus")).font(.system(size: 10.5, weight: .semibold, design: .rounded)).foregroundStyle(C.soft)
            }
            Spacer(minLength: 0)
            nextMeeting(s, isToday: isToday, titleSize: 12)
        }
    }

    private func medium(_ s: FennWidgetSnapshot, isToday: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                C.label(C.t(s, "Als Nächstes", "Next up"))
                Spacer(minLength: 0)
                nextMeeting(s, isToday: isToday, titleSize: 14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            figures(s).frame(width: 124)
        }
    }

    private func large(_ s: FennWidgetSnapshot, isToday: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                C.label(C.t(s, "Dein Tag", "Your day"))
                Spacer()
                Image("FennAvatarStone").resizable().scaledToFit().frame(width: 30, height: 30)
            }
            figures(s)
            C.label(C.t(s, "Termine", "Meetings"))
            let events = isToday ? (s.events ?? []) : []
            if events.isEmpty {
                Text(isToday ? C.t(s, "Heute keine Termine mehr.", "No more meetings today.") : C.t(s, "Öffne Fenn", "Open Fenn"))
                    .font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(C.soft)
            }
            ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                HStack(spacing: 10) {
                    Text(Self.time(event.start)).font(.system(size: 12, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(C.sage)
                        .frame(width: 48, alignment: .leading)
                    Text(event.title).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(C.ink).lineLimit(1)
                    Spacer(minLength: 0)
                    if event.canJoin { Image(systemName: "video.fill").font(.system(size: 10)).foregroundStyle(C.sage) }
                }
                .padding(9)
                .desktopClayPad(radius: 14)
            }
            Spacer(minLength: 0)
        }
    }

    private func figures(_ s: FennWidgetSnapshot) -> some View {
        let habits = s.habits ?? []
        let done = habits.filter(\.done).count
        return VStack(alignment: .leading, spacing: 8) {
            row(C.t(s, "Fokus", "Focus"), focusLabel(s.focusMinutes), art: "Page-focus")
            row(C.t(s, "Erledigt", "Done"), "\(s.tasksDone)", art: "Page-tasks")
            if !habits.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    row(C.t(s, "Routinen", "Routines"), "\(done)/\(habits.count)", art: "Page-habits")
                    C.Tube(value: Double(done) / Double(habits.count), height: 7)
                }
            }
            if s.streak > 0 {
                row(C.t(s, "Serie", "Streak"), "\(s.streak)", art: "Clay-campfire")
            }
        }
    }

    private func row(_ title: String, _ value: String, art: String) -> some View {
        HStack(spacing: 5) {
            C.Icon(name: art, size: 15)
            Text(title).font(.system(size: 10.5, weight: .semibold, design: .rounded)).foregroundStyle(C.soft)
            Spacer(minLength: 0)
            Text(value).font(.system(size: 12, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(C.ink)
        }
    }
}

// MARK: - Tasks

struct FennTasksDesktopView: View {
    @Environment(\.widgetFamily) private var envFamily
    let entry: FennDesktopEntry
    var familyOverride: WidgetFamily? = nil
    private var family: WidgetFamily { familyOverride ?? envFamily }
    private var s: FennWidgetSnapshot { entry.snapshot }
    private typealias C = DesktopClay
    private var limit: Int { family == .systemSmall || family == .systemMedium ? 3 : 7 }

    var body: some View {
        let tasks = Array((s.tasks ?? []).prefix(limit))
        let open = (s.tasks ?? []).filter { !$0.done }.count
        let small = family == .systemSmall
        let large = family == .systemLarge || family == .systemExtraLarge
        VStack(alignment: .leading, spacing: small ? 7 : 8) {
            HStack(spacing: 7) {
                C.Icon(name: "Page-tasks", size: small ? 24 : 28)
                C.label(C.t(s, "Aufgaben", "Tasks"))
                Spacer()
                Text("\(open)").font(.system(size: 13, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(C.ink)
                    .frame(minWidth: 26, minHeight: 22).desktopClayPad(radius: 11)
            }
            if !small, let goals = s.goals, !goals.isEmpty {
                ForEach(goals.prefix(large ? 3 : 1), id: \.self) { goal in
                    HStack(spacing: 6) {
                        C.Icon(name: nil, symbol: "target", size: 16)
                        Text(goal).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(C.ink.opacity(0.8)).lineLimit(1)
                    }
                }
            }
            if tasks.isEmpty {
                Spacer(minLength: 0)
                Text(C.t(s, "Nichts offen.", "Nothing open.")).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(C.soft)
            }
            ForEach(tasks) { task in
                HStack(spacing: 9) {
                    Button(intent: ToggleMacTaskIntent(taskId: task.id)) { C.Tick(done: task.done, size: small ? 20 : 22) }
                        .buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(task.title).font(.system(size: small ? 12 : 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(task.done ? C.soft : C.ink).strikethrough(task.done, color: C.soft).lineLimit(1)
                        if !small, let detail = task.detail, !task.done {
                            Text(detail).font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(C.soft).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    if task.high && !task.done && !small { Circle().fill(C.sage).frame(width: 6, height: 6) }
                }
                .padding(large ? 9 : 0)
                .background { if large { Color.clear.desktopClayPad(radius: 14) } }
            }
            Spacer(minLength: 0)
        }
        .widgetURL(URL(string: "fennfocus://tasks"))
        .containerBackground(for: .widget) { C.Background() }
    }
}

struct ToggleMacTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Aufgabe abhaken"
    static var isDiscoverable = false

    @Parameter(title: "Aufgabe") var taskId: String

    init() {}
    init(taskId: String) { self.taskId = taskId }

    func perform() async throws -> some IntentResult {
        if var snapshot = FennWidgetSnapshot.load(), let index = snapshot.tasks?.firstIndex(where: { $0.id == taskId }) {
            snapshot.tasks?[index].done.toggle()
            snapshot.save()
        }
        FennWidgetActions.enqueue(taskId)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Habits

struct FennHabitsDesktopView: View {
    @Environment(\.widgetFamily) private var envFamily
    let entry: FennDesktopEntry
    var familyOverride: WidgetFamily? = nil
    private var family: WidgetFamily { familyOverride ?? envFamily }
    private typealias C = DesktopClay
    private var limit: Int { family == .systemSmall ? 3 : (family == .systemMedium ? 4 : 8) }

    var body: some View {
        let (isToday, s) = C.today(entry)
        let all = s.habits ?? []
        let done = all.filter(\.done).count
        let shown = Array(all.sorted { !$0.done && $1.done }.prefix(limit))
        let small = family == .systemSmall
        let large = family == .systemLarge || family == .systemExtraLarge
        VStack(alignment: .leading, spacing: small ? 7 : 8) {
            HStack(spacing: 7) {
                C.Icon(name: "Page-habits", size: small ? 24 : 28)
                C.label(C.t(s, "Routinen", "Routines"))
                Spacer()
                if !all.isEmpty {
                    Text("\(done)/\(all.count)").font(.system(size: 13, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(C.ink)
                }
            }
            if !all.isEmpty { C.Tube(value: Double(done) / Double(all.count), height: 8) }
            if all.isEmpty {
                Spacer(minLength: 0)
                Text(s.day == "-" || !isToday ? C.t(s, "Öffne Fenn", "Open Fenn") : C.t(s, "Heute keine Routine.", "No routine today."))
                    .font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(C.soft)
            } else if done == all.count && !large {
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    C.Icon(name: "Set-sparkles", symbol: "sparkles", size: 28)
                    Text(C.t(s, "Alle erledigt. Stark.", "All done. Strong.")).font(.system(size: small ? 14 : 16, weight: .bold, design: .rounded)).foregroundStyle(C.ink)
                }
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: family == .systemMedium ? 2 : 1), alignment: .leading, spacing: small ? 6 : 7) {
                    ForEach(shown) { habit in row(habit, day: s.day, small: small, large: large) }
                }
            }
            Spacer(minLength: 0)
        }
        .widgetURL(URL(string: "fennfocus://habits"))
        .containerBackground(for: .widget) { C.Background() }
    }

    private func row(_ habit: FennWidgetHabit, day: String, small: Bool, large: Bool) -> some View {
        HStack(spacing: 7) {
            C.Icon(name: C.art(for: habit.symbol), symbol: habit.symbol, size: small ? 20 : 24)
            VStack(alignment: .leading, spacing: 0) {
                Text(habit.title).font(.system(size: small ? 11.5 : 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(habit.done ? C.soft : C.ink).lineLimit(1).minimumScaleFactor(0.85)
                if large, let detail = habit.detail {
                    Text(habit.done ? "✓" : detail).font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(C.soft).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if large, habit.streak >= 3 {
                HStack(spacing: 2) {
                    C.Icon(name: "Clay-campfire", symbol: "flame", size: 14)
                    Text("\(habit.streak)").font(.system(size: 11, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(C.soft)
                }
            }
            Button(intent: ToggleMacHabitIntent(habitId: habit.id, day: day)) { C.Tick(done: habit.done, size: small ? 20 : 22) }
                .buttonStyle(.plain)
        }
        .padding(large ? 8 : 0)
        .background { if large { Color.clear.desktopClayPad(radius: 14) } }
    }
}

struct ToggleMacHabitIntent: AppIntent {
    static var title: LocalizedStringResource = "Routine abhaken"
    static var isDiscoverable = false

    @Parameter(title: "Routine") var habitId: String
    @Parameter(title: "Tag") var day: String

    init() {}
    init(habitId: String, day: String) { self.habitId = habitId; self.day = day }

    func perform() async throws -> some IntentResult {
        if var snapshot = FennWidgetSnapshot.load(), let index = snapshot.habits?.firstIndex(where: { $0.id == habitId }) {
            snapshot.habits?[index].done.toggle()
            snapshot.save()
        }
        FennWidgetActions.enqueue("habit:\(habitId)|\(day)")
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Agent

struct PebbleDesktopEntry: TimelineEntry {
    let date: Date
    /// 0…5 – the pose; macOS springs from one entry to the next.
    let frame: Int
    /// Fenn used recently or every routine ticked – it hops; long untouched – it dozes.
    let happy: Bool
    let dozing: Bool
    let german: Bool
}

/// Three hours of poses, one every 5 minutes.
struct PebbleDesktopProvider: TimelineProvider {
    func placeholder(in context: Context) -> PebbleDesktopEntry {
        PebbleDesktopEntry(date: Date(), frame: 0, happy: true, dozing: false, german: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (PebbleDesktopEntry) -> Void) {
        if context.isPreview { return completion(placeholder(in: context)) }
        completion(entry(FennWidgetSnapshot.load(), at: Date(), frame: 0))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PebbleDesktopEntry>) -> Void) {
        let now = Date(), s = FennWidgetSnapshot.load()
        let entries = (0..<36).map { i in entry(s, at: now.addingTimeInterval(Double(i) * 300), frame: i % 6) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(_ s: FennWidgetSnapshot?, at date: Date, frame: Int) -> PebbleDesktopEntry {
        let hours = s.map { date.timeIntervalSince($0.updated) / 3600 } ?? 0
        let allDone = s.map { $0.day == DesktopClay.dayKey(date) && !($0.habits ?? []).isEmpty && ($0.habits ?? []).allSatisfy(\.done) } ?? false
        return PebbleDesktopEntry(date: date, frame: frame, happy: allDone || hours < 2, dozing: !allDone && hours >= 8,
                                  german: s?.german ?? true)
    }
}

/// Just Fenn – the pebble in a clay dish. A click opens the agent.
struct FennAgentDesktopView: View {
    let entry: PebbleDesktopEntry
    private typealias C = DesktopClay

    private var offsetY: CGFloat {
        let hop: [CGFloat] = [0, -4, -7, -4, 0, 2], sway: [CGFloat] = [0, -1, -2, -1, 0, 1]
        return entry.happy ? hop[entry.frame] : sway[entry.frame] + (entry.dozing ? 2 : 0)
    }

    private var tilt: Angle {
        let sway: [Double] = [0, 2, 3, 2, 0, -2]
        return .degrees(entry.dozing ? -6 + sway[entry.frame] * 0.5 : sway[entry.frame] * (entry.happy ? 1.5 : 0.6))
    }

    var body: some View {
        ZStack {
            Circle().fill(C.track).padding(14)
                .overlay(Circle().stroke(LinearGradient(colors: [.black.opacity(0.2), C.lightEdge.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2).padding(14))
            Image("FennAvatarStone").resizable().scaledToFit()
                .rotationEffect(tilt, anchor: .bottom)
                .offset(y: offsetY)
                .shadow(color: .black.opacity(0.22), radius: 4, x: 2, y: 5)
                .animation(.spring(duration: 1.4, bounce: entry.happy ? 0.55 : 0.25), value: entry.frame)
                .padding(28)
            if entry.happy {
                C.Icon(name: "Set-sparkles", symbol: "sparkles", size: 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(12)
            } else if entry.dozing {
                Text("z z z").font(.system(size: 13, weight: .heavy, design: .rounded)).tracking(1).foregroundStyle(C.soft)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(14)
            }
        }
        .widgetURL(URL(string: "fennfocus://coach"))
        .containerBackground(for: .widget) { C.Background(glow: C.sageLight.opacity(entry.happy ? 0.45 : 0.25)) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.german ? "Fenn fragen" : "Ask Fenn")
    }
}

// MARK: - Pomodoro

struct FennFocusDesktopView: View {
    @Environment(\.widgetFamily) private var envFamily
    let entry: FennDesktopEntry
    var familyOverride: WidgetFamily? = nil
    private var family: WidgetFamily { familyOverride ?? envFamily }
    private typealias C = DesktopClay

    var body: some View {
        let s = entry.snapshot
        let clock = s.pomodoro
        let phase = clock?.phase ?? "idle"
        let running = phase == "work" || phase == "break"
        let paused = phase == "paused"
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                C.Icon(name: "Page-focus", size: 26)
                C.label(phaseLabel(s, phase: phase))
                Spacer()
                if let settings = clock?.settings {
                    Text("\(settings.workMinutes)/\(settings.breakMinutes)").font(.system(size: 11, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(C.sage)
                }
            }
            Spacer(minLength: 0)
            countdown(clock, phase: phase)
                .font(.system(size: family == .systemSmall ? 30 : 38, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(C.ink)
            if let title = s.focusTitle, running || paused {
                Text(title).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(C.soft).lineLimit(1)
            } else if let settings = clock?.settings, !running && !paused {
                Text(C.t(s, "\(lengthLabel(settings.totalMinutes)) gesamt", "\(lengthLabel(settings.totalMinutes)) total"))
                    .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(C.soft)
            }
            if family != .systemSmall, let end = clock?.sessionEndsAt, running {
                Text(C.t(s, "Session bis ", "Session until ") + end.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(C.soft)
            }
            Spacer(minLength: 0)
            if !running && !paused {
                Link(destination: URL(string: "fennfocus://focus?start=1")!) { C.button(C.t(s, "Jetzt starten", "Start now"), symbol: "play.fill") }
            }
        }
        .widgetURL(URL(string: "fennfocus://focus"))
        .containerBackground(for: .widget) { C.Background() }
    }

    @ViewBuilder
    private func countdown(_ clock: PomodoroSnapshot?, phase: String) -> some View {
        if phase == "work" || phase == "break", let end = clock?.phaseEndsAt, let start = clock?.phaseStartedAt, start <= end, end > Date() {
            Text(timerInterval: start...end, countsDown: true)
        } else if phase == "paused" {
            Text(PomodoroClock.clock(clock?.pausedRemaining ?? 0))
        } else if phase == "done" {
            Text(DesktopClay.t(entry.snapshot, "Fertig", "Done"))
        } else if let settings = clock?.settings {
            Text(PomodoroClock.clock(TimeInterval(settings.workMinutes * 60)))
        } else {
            Text("50:00")
        }
    }

    private func lengthLabel(_ minutes: Int) -> String {
        if minutes % 60 == 0 { return "\(minutes / 60) h" }
        if minutes > 60 { return String(format: "%d:%02d h", minutes / 60, minutes % 60) }
        return "\(minutes) min"
    }

    private func phaseLabel(_ s: FennWidgetSnapshot, phase: String) -> String {
        switch phase {
        case "work": return DesktopClay.t(s, "Arbeit", "Work")
        case "break": return DesktopClay.t(s, "Pause", "Break")
        case "paused": return DesktopClay.t(s, "Pausiert", "Paused")
        case "done": return DesktopClay.t(s, "Fertig", "Done")
        default: return "Pomodoro"
        }
    }
}
