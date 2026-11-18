import SwiftUI
import Charts
import FennFocusCore

/// Fortschritt: the hours that went into focus, the tasks that got done, the Pomodoros and the streak –
/// all from the person's own files (focus sessions in tasks.json, days in stats/days.json).
struct ProgressModuleView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var metrics: MetricsStore
    let openModule: (IslandModule) -> Void
    @State private var period = Period.week
    @State private var selectedDay: Date?

    enum Period: String, CaseIterable, Identifiable {
        case week, month, year
        var id: String { rawValue }
        var title: String {
            switch self {
            case .week: return tr("Woche", "Week")
            case .month: return tr("Monat", "Month")
            case .year: return tr("Jahr", "Year")
            }
        }
    }

    /// Hours that are worth a little party.
    static let milestones = [1, 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(tr("Fortschritt", "Progress")).font(Fenn.display(22)).foregroundStyle(Fenn.fg)
                Spacer()
                if metrics.streakDays > 1 {
                    Label(tr("\(metrics.streakDays) Tage in Serie", "\(metrics.streakDays) days in a row"), systemImage: "flame.fill")
                        .font(.fenn(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(Fenn.fg.opacity(0.6))
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    hero
                    tiles
                    FennSegments(options: Period.allCases, selection: $period) { $0.title }
                        .frame(maxWidth: .infinity)
                    focusChart
                    heatmap
                    tasksChart
                    topics
                    bestTime
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.never)
        }
    }

    // MARK: Numbers

    private var calendar: Calendar { Calendar.current }
    private var totalMinutes: Int { store.sessions.reduce(0) { $0 + $1.minutes } }
    private var firstSession: Date? { store.sessions.map(\.start).min() }
    private var tasksDoneEver: Int { store.tasks.filter(\.done).count }

    private func interval(weeksAgo: Int) -> DateInterval {
        let week = DateInterval.thisWeek
        let shift = TimeInterval(-weeksAgo * 7 * 86_400)
        return DateInterval(start: week.start.addingTimeInterval(shift), end: week.end.addingTimeInterval(shift))
    }

    private func blocks(in range: DateInterval) -> Int {
        days(from: range.start, to: min(range.end, Date())).reduce(0) { $0 + metrics.record(for: $1).focusBlocks }
    }

    private func days(from start: Date, to end: Date) -> [Date] {
        var result: [Date] = []
        var day = calendar.startOfDay(for: start)
        while day < end {
            result.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    /// "12,5" or "12.5" – hours with one decimal, in the app language.
    private static func hours(_ minutes: Int) -> String {
        let value = Double(minutes) / 60
        let text = value >= 100 ? String(Int(value.rounded())) : String(format: "%.1f", value)
        return L10n.usesEnglish ? text : text.replacingOccurrences(of: ".", with: ",")
    }

    private static func clock(_ minutes: Int) -> String { String(format: "%d:%02d", minutes / 60, minutes % 60) }

    private static func delta(_ now: Int, _ before: Int) -> (text: String, up: Bool)? {
        guard before > 0 else { return nil }
        let change = Int((Double(now - before) / Double(before) * 100).rounded())
        guard change != 0 else { return nil }
        return ("\(abs(change)) %", change > 0)
    }

    // MARK: Hero

    private var hero: some View {
        let total = totalMinutes
        let next = Self.milestones.first { $0 * 60 > total }
        let previous = Self.milestones.last { $0 * 60 <= total } ?? 0
        let progress = next.map { Double(total - previous * 60) / Double(($0 - previous) * 60) } ?? 1
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("FOKUS INSGESAMT", "TOTAL FOCUS"))
                        .font(.fenn(size: 11, weight: .medium)).tracking(1.2)
                        .foregroundStyle(MeshAura.Palette.level.ink.opacity(0.75))
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        DotMatrixText(text: Self.hours(total), height: 44, color: MeshAura.Palette.level.ink)
                        Text(tr("Stunden", "hours"))
                            .font(.fenn(size: 15, weight: .medium))
                            .foregroundStyle(MeshAura.Palette.level.ink.opacity(0.8))
                    }
                    Text(heroLine)
                        .font(.fenn(size: 12))
                        .foregroundStyle(MeshAura.Palette.level.ink.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                ZStack {
                    PebbleMac(size: 74)
                    PebbleFace(mood: total > 0 ? .happy : .content, blush: total > 0)
                        .frame(width: 74, height: 74)
                }
                .accessibilityHidden(true)
            }
            if let next {
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { proxy in
                        Capsule().fill(MeshAura.Palette.level.ink.opacity(0.18))
                            .overlay(alignment: .leading) {
                                Capsule().fill(MeshAura.Palette.level.ink.opacity(0.9))
                                    .frame(width: max(8, proxy.size.width * min(max(progress, 0), 1)))
                            }
                    }
                    .frame(height: 7)
                    HStack {
                        Text(tr("Noch \(TaskFormat.duration(next * 60 - total)) bis \(next) h",
                                "\(TaskFormat.duration(next * 60 - total)) to go until \(next) h"))
                        Spacer()
                        milestoneBadges(reached: Self.milestones.filter { $0 * 60 <= total })
                    }
                    .font(.fenn(size: 11, weight: .medium))
                    .foregroundStyle(MeshAura.Palette.level.ink.opacity(0.8))
                }
            }
        }
        .padding(18)
        .background {
            ZStack {
                MeshAura(palette: .level)
                LinearGradient(colors: [.white.opacity(0.22), .clear, .black.opacity(0.16)], startPoint: .top, endPoint: .bottom)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0.05), .white.opacity(0.2)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var heroLine: String {
        guard let first = firstSession else {
            return tr("Starte deinen ersten Fokusblock – hier wächst dann deine Zeit.", "Start your first focus block – your time grows here.")
        }
        let since = first.formatted(.dateTime.day().month(.wide).locale(fennLocale))
        return tr("seit \(since), \(tasksDoneEver) Aufgaben erledigt", "since \(since), \(tasksDoneEver) tasks done")
    }

    private func milestoneBadges(reached: [Int]) -> some View {
        HStack(spacing: 4) {
            ForEach(reached.suffix(3), id: \.self) { hours in
                Text("\(hours) h")
                    .font(.fenn(size: 10, weight: .semibold).monospacedDigit())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().strokeBorder(MeshAura.Palette.level.ink.opacity(0.45), lineWidth: 1))
            }
        }
    }

    // MARK: Tiles

    private var tiles: some View {
        let week = interval(weeksAgo: 0), last = interval(weeksAgo: 1)
        let focusNow = store.focusMinutes(in: week), focusBefore = store.focusMinutes(in: last)
        let doneNow = store.doneCount(in: week), doneBefore = store.doneCount(in: last)
        let blocksNow = blocks(in: week), blocksBefore = blocks(in: last)
        let focusDelta = Self.delta(focusNow, focusBefore)
        let doneDelta = Self.delta(doneNow, doneBefore)
        let blocksDelta = Self.delta(blocksNow, blocksBefore)
        return Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                AuraPill(title: tr("Fokus diese Woche", "Focus this week"), value: Self.clock(focusNow), unit: "h", palette: .steady,
                         symbol: "timer", delta: focusDelta?.text, up: focusDelta?.up)
                AuraPill(title: tr("Erledigt diese Woche", "Done this week"), value: "\(doneNow)", palette: .fresh,
                         symbol: "checkmark", delta: doneDelta?.text, up: doneDelta?.up)
            }
            GridRow {
                AuraPill(title: "Pomodoros", value: "\(blocksNow)", palette: .ember, symbol: "hourglass",
                         delta: blocksDelta?.text, up: blocksDelta?.up)
                AuraPill(title: tr("Serie", "Streak"), value: "\(metrics.streakDays)", unit: tr("Tage", "days"), palette: .stone,
                         symbol: "flame.fill")
            }
        }
    }

    // MARK: Focus per day

    private struct Bucket: Identifiable {
        let start: Date
        let minutes: Int
        let done: Int
        var id: Date { start }
    }

    /// Days of this week or month, or the weeks of the last year.
    private var buckets: [Bucket] {
        switch period {
        case .week, .month:
            let range = period == .week ? DateInterval.thisWeek : DateInterval.thisMonth
            return days(from: range.start, to: range.end).map { day in
                let span = calendar.dateInterval(of: .day, for: day) ?? DateInterval(start: day, duration: 86_400)
                return Bucket(start: day, minutes: day > Date() ? 0 : store.focusMinutes(in: span), done: store.doneCount(in: span))
            }
        case .year:
            return (0..<52).reversed().map { weeksAgo in
                let span = interval(weeksAgo: weeksAgo)
                return Bucket(start: span.start, minutes: store.focusMinutes(in: span), done: store.doneCount(in: span))
            }
        }
    }

    private var unit: Calendar.Component { period == .year ? .weekOfYear : .day }

    private var focusChart: some View {
        let data = buckets
        let active = data.filter { $0.minutes > 0 }
        let average = active.isEmpty ? 0 : Double(active.reduce(0) { $0 + $1.minutes }) / Double(active.count)
        let best = data.max { $0.minutes < $1.minutes }
        let shown = selectedDay.flatMap { day in data.first { calendar.isDate($0.start, equalTo: day, toGranularity: unit) } }
        return card(tr("Fokus pro \(period == .year ? "Woche" : "Tag")", "Focus per \(period == .year ? "week" : "day")"),
                    trailing: shown.map { "\(label(for: $0.start)): \(TaskFormat.duration($0.minutes))" }
                        ?? (best.map { $0.minutes > 0 ? tr("Bester: \(label(for: $0.start))", "Best: \(label(for: $0.start))") : "" } ?? "")) {
            Chart {
                ForEach(data) { bucket in
                    BarMark(x: .value("Tag", bucket.start, unit: unit), y: .value("Minuten", bucket.minutes))
                        .foregroundStyle(LinearGradient(colors: [Fenn.accent.opacity(0.55), Fenn.accent], startPoint: .bottom, endPoint: .top))
                        .cornerRadius(period == .year ? 2 : 5)
                        .opacity(shown == nil || shown?.start == bucket.start ? 1 : 0.35)
                }
                if average > 0 {
                    RuleMark(y: .value("Schnitt", average))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        .foregroundStyle(Fenn.fg.opacity(0.35))
                        .annotation(position: .top, alignment: .trailing) {
                            Text(tr("Ø \(TaskFormat.duration(Int(average)))", "avg \(TaskFormat.duration(Int(average)))"))
                                .font(.fenn(size: 10, weight: .medium)).foregroundStyle(Fenn.fg.opacity(0.5))
                        }
                }
            }
            .chartXSelection(value: $selectedDay)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Fenn.fg.opacity(0.08))
                    AxisValueLabel {
                        if let minutes = value.as(Int.self) { Text(minutes >= 60 ? "\(minutes / 60) h" : "\(minutes)") }
                    }
                    .font(.fenn(size: 9)).foregroundStyle(Fenn.fg.opacity(0.45))
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: period == .year ? .month : (period == .month ? .weekOfYear : .day))) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) { Text(axisLabel(date)) }
                    }
                    .font(.fenn(size: 9)).foregroundStyle(Fenn.fg.opacity(0.45))
                }
            }
            .environment(\.locale, fennLocale)
            .frame(height: 150)
            .animation(.snappy, value: period)
        }
    }

    /// Charts ignores the app language for its own date labels, so they are written here.
    private func axisLabel(_ date: Date) -> String {
        switch period {
        case .week: return date.formatted(.dateTime.weekday(.abbreviated).locale(fennLocale))
        case .month: return date.formatted(.dateTime.day().locale(fennLocale))
        case .year: return date.formatted(.dateTime.month(.narrow).locale(fennLocale))
        }
    }

    private func label(for date: Date) -> String {
        period == .year
            ? tr("KW \(calendar.component(.weekOfYear, from: date))", "Week \(calendar.component(.weekOfYear, from: date))")
            : date.formatted(.dateTime.weekday(.abbreviated).day().locale(fennLocale))
    }

    // MARK: Heatmap

    /// The last 20 weeks, one square per day – darker means more focus.
    private var heatmap: some View {
        let weeks = 20
        let today = calendar.startOfDay(for: Date())
        let thisWeek = DateInterval.thisWeek.start
        let start = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeek) ?? thisWeek
        var minutesByDay: [Date: Int] = [:]
        for session in store.sessions where session.start >= start {
            minutesByDay[calendar.startOfDay(for: session.start), default: 0] += session.minutes
        }
        let top = max(60, minutesByDay.values.max() ?? 60)
        let activeDays = minutesByDay.values.filter { $0 > 0 }.count
        return card(tr("Letzte \(weeks) Wochen", "Last \(weeks) weeks"), trailing: tr("\(activeDays) Tage mit Fokus", "\(activeDays) days with focus")) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 3) {
                    ForEach(0..<weeks, id: \.self) { column in
                        VStack(spacing: 3) {
                            ForEach(0..<7, id: \.self) { row in
                                let day = calendar.date(byAdding: .day, value: column * 7 + row, to: start) ?? start
                                let minutes = minutesByDay[day] ?? 0
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(day > today ? Color.clear : (minutes == 0 ? Fenn.fill : Fenn.accent.opacity(0.25 + 0.75 * min(1, Double(minutes) / Double(top)))))
                                    .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .strokeBorder(calendar.isDate(day, inSameDayAs: today) ? Fenn.fg.opacity(0.6) : .clear, lineWidth: 1))
                                    .aspectRatio(1, contentMode: .fit)
                                    .help(day > today ? "" : "\(day.formatted(.dateTime.weekday().day().month().locale(fennLocale))): \(TaskFormat.duration(minutes))")
                            }
                        }
                    }
                }
                HStack(spacing: 4) {
                    Spacer()
                    Text(tr("weniger", "less"))
                    ForEach([0.0, 0.3, 0.6, 1.0], id: \.self) { level in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(level == 0 ? Fenn.fill : Fenn.accent.opacity(0.25 + 0.75 * level))
                            .frame(width: 9, height: 9)
                    }
                    Text(tr("mehr", "more"))
                }
                .font(.fenn(size: 9)).foregroundStyle(Fenn.fg.opacity(0.45))
            }
        }
    }

    // MARK: Tasks

    private var tasksChart: some View {
        let data = buckets
        var running = 0
        // Up to today only – the line shouldn't run on into days that haven't happened.
        let cumulative = data.filter { $0.start <= Date() }.map { bucket -> (Date, Int) in
            running += bucket.done
            return (bucket.start, running)
        }
        let total = running
        return card(tr("Erledigte Aufgaben", "Tasks done"), trailing: "\(total)") {
            if total == 0 {
                Text(tr("Noch nichts abgehakt in diesem Zeitraum. Fenn freut sich schon auf das erste Häkchen.",
                        "Nothing ticked off in this period yet. Fenn is looking forward to the first one."))
                    .font(.fenn(size: 12)).foregroundStyle(Fenn.fg.opacity(0.55))
            } else {
                Chart {
                    ForEach(cumulative, id: \.0) { point in
                        AreaMark(x: .value("Tag", point.0, unit: unit), y: .value("Erledigt", point.1))
                            .foregroundStyle(LinearGradient(colors: [Fenn.accent.opacity(0.35), Fenn.accent.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Tag", point.0, unit: unit), y: .value("Erledigt", point.1))
                            .foregroundStyle(Fenn.accent)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                            .interpolationMethod(.monotone)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine().foregroundStyle(Fenn.fg.opacity(0.08))
                        AxisValueLabel().font(.fenn(size: 9)).foregroundStyle(Fenn.fg.opacity(0.45))
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: 90)
            }
        }
    }

    // MARK: Topics

    private var topics: some View {
        let range = period == .week ? DateInterval.thisWeek : (period == .month ? DateInterval.thisMonth : interval52)
        let items = store.minutesByTopic(in: range)
        let top = Array(items.prefix(4))
        let rest = items.dropFirst(4).reduce(0) { $0 + $1.minutes }
        let slices = top + (rest > 0 ? [(topic: tr("Andere", "Other"), minutes: rest)] : [])
        let total = slices.reduce(0) { $0 + $1.minutes }
        let shades: [Double] = [1, 0.75, 0.55, 0.38, 0.22]
        return card(tr("Wofür", "Where it went")) {
            if slices.isEmpty {
                Button { openModule(.focus) } label: {
                    Label(tr("Ersten Fokusblock starten", "Start your first focus block"), systemImage: "play.fill")
                        .font(.fenn(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Fenn.accent)
            } else {
                HStack(spacing: 16) {
                    Chart {
                        ForEach(Array(slices.enumerated()), id: \.offset) { index, slice in
                            SectorMark(angle: .value("Minuten", slice.minutes), innerRadius: .ratio(0.62), angularInset: 1.5)
                                .cornerRadius(4)
                                .foregroundStyle(Fenn.accent.opacity(shades[min(index, shades.count - 1)]))
                        }
                    }
                    .chartBackground { _ in
                        VStack(spacing: 0) {
                            Text(Self.clock(total)).font(.fenn(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(Fenn.fg)
                            Text("h").font(.fenn(size: 10)).foregroundStyle(Fenn.fg.opacity(0.5))
                        }
                    }
                    .frame(width: 112, height: 112)
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(slices.enumerated()), id: \.offset) { index, slice in
                            HStack(spacing: 8) {
                                Circle().fill(Fenn.accent.opacity(shades[min(index, shades.count - 1)])).frame(width: 8, height: 8)
                                Text(slice.topic).font(.fenn(size: 12)).foregroundStyle(Fenn.fg).lineLimit(1)
                                Spacer(minLength: 4)
                                Text("\(Int((Double(slice.minutes) / Double(max(total, 1)) * 100).rounded())) %")
                                    .font(.fenn(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(Fenn.fg.opacity(0.55))
                            }
                        }
                    }
                }
            }
        }
    }

    private var interval52: DateInterval {
        DateInterval(start: interval(weeksAgo: 51).start, end: DateInterval.thisWeek.end)
    }

    // MARK: Best time

    /// When focus happens: minutes per hour of the day over the last 90 days.
    private var bestTime: some View {
        let since = Date().addingTimeInterval(-90 * 86_400)
        var byHour = Array(repeating: 0, count: 24)
        for session in store.sessions where session.start >= since {
            byHour[calendar.component(.hour, from: session.start)] += session.minutes
        }
        let peak = byHour.indices.max { byHour[$0] < byHour[$1] } ?? 9
        let hasData = byHour.contains { $0 > 0 }
        return Group {
            if hasData {
                card(tr("Deine beste Zeit", "Your best time"),
                     trailing: tr("um \(peak)–\(peak + 1) Uhr", "\(peak):00–\(peak + 1):00")) {
                    Chart {
                        ForEach(6..<23, id: \.self) { hour in
                            BarMark(x: .value("Stunde", hour), y: .value("Minuten", byHour[hour]), width: .ratio(0.7))
                                .foregroundStyle(hour == peak ? Fenn.accent : Fenn.accent.opacity(0.3))
                                .cornerRadius(3)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: [6, 9, 12, 15, 18, 21]) { value in
                            AxisValueLabel { if let hour = value.as(Int.self) { Text("\(hour)") } }
                                .font(.fenn(size: 9)).foregroundStyle(Fenn.fg.opacity(0.45))
                        }
                    }
                    .chartYAxis(.hidden)
                    .frame(height: 70)
                }
            }
        }
    }

    // MARK: Card

    private func card<Content: View>(_ title: String, trailing: String = "", @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.uppercased()).font(.fenn(size: 11, weight: .medium)).tracking(1.2).foregroundStyle(Fenn.fg.opacity(0.55))
                Spacer()
                Text(trailing).font(.fenn(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(Fenn.fg.opacity(0.6))
                    .contentTransition(.numericText())
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(TileSurface())
    }
}
