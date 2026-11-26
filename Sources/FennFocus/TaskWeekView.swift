import SwiftUI

/// "Woche": the days of the week (from today on; the past ones fold away) with each day's tasks by due day and how much
/// free working time is left after them, plus "Ohne Datum". Tasks move between days by drag and drop; "+" adds one for a day.
struct WeekPlanView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var nav: TasksNav
    let edit: (FennTask) -> Void
    let startFocus: (FennTask) -> Void
    @State private var addingDay: Date?
    @State private var draft = ""
    @State private var target: String?
    @State private var showPast = false
    @FocusState private var fieldFocused: Bool

    /// Weeks run Monday to Sunday here, whatever the region says.
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        calendar.timeZone = .current
        return calendar
    }

    private var days: [Date] {
        let calendar = Self.calendar
        let today = calendar.startOfDay(for: Date())
        let monday = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let start = calendar.date(byAdding: .day, value: 7 * nav.weekOffset, to: monday) ?? monday
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        let days = days
        let today = Self.calendar.startOfDay(for: Date())
        // In this week the days already gone fold away; other weeks show all seven.
        let past = nav.weekOffset == 0 ? days.filter { $0 < today } : []
        let shown = days.filter { !past.contains($0) || showPast }
        let open = store.open
        let unplanned = open.filter { $0.due == nil }
        VStack(alignment: .leading, spacing: 12) {
            header(days)
            if !past.isEmpty {
                Button { withAnimation(.snappy) { showPast.toggle() } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right").font(.fenn(size: 10, weight: .semibold)).rotationEffect(.degrees(showPast ? 90 : 0))
                        let done = past.reduce(0) { $0 + doneCount(on: $1) }
                        Text(tr("Vergangene Tage", "Past days") + (done > 0 ? tr(" · \(done) erledigt", " · \(done) done") : ""))
                            .font(.fenn(size: 12))
                    }
                    .foregroundStyle(Fenn.fg.opacity(0.5))
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element) { index, day in
                    dayBlock(day, tasks: open.filter { $0.due.map { Self.calendar.isDate($0, inSameDayAs: day) } ?? false }
                        .sorted { ($0.due ?? .distantFuture, $0.rank) < ($1.due ?? .distantFuture, $1.rank) })
                    if index < shown.count - 1 { Rectangle().fill(Fenn.hairline).frame(height: 1).padding(.horizontal, 12) }
                }
            }
            .fennGlass(cornerRadius: 18, shadow: false)
            if !unplanned.isEmpty { tray(unplanned) }
        }
    }

    // MARK: Header

    private func header(_ days: [Date]) -> some View {
        let calendar = Self.calendar
        let week = calendar.component(.weekOfYear, from: days[0])
        let range = "\(days[0].formatted(.dateTime.day().month(.abbreviated).locale(fennLocale))) – \(days[6].formatted(.dateTime.day().month(.abbreviated).locale(fennLocale)))"
        let end = days[6].addingTimeInterval(86_400)
        let planned = store.open.filter { task in task.due.map { $0 >= days[0] && $0 < end } ?? false }
            .reduce(0) { $0 + DayPlanner.minutes(of: $1) }
        return HStack(alignment: .center, spacing: 4) {
            VStack(alignment: .leading, spacing: 1) {
                Text(range).font(.fenn(size: 14, weight: .semibold)).foregroundStyle(Fenn.fg)
                Text(tr("KW \(week)", "Week \(week)") + (planned > 0 ? tr(" · ~\(TaskFormat.duration(planned)) geplant", " · ~\(TaskFormat.duration(planned)) planned") : ""))
                    .font(.fenn(size: 11.5)).foregroundStyle(Fenn.fg.opacity(0.55))
            }
            Spacer()
            Button { withAnimation(.snappy) { nav.weekOffset -= 1 } } label: {
                Image(systemName: "chevron.left").font(.fenn(size: 12, weight: .semibold)).frame(width: 26, height: 26).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(Fenn.fg.opacity(0.6))
            .help(tr("Woche davor", "Previous week"))
            Button(tr("Heute", "Today")) { withAnimation(.snappy) { nav.weekOffset = 0 } }
                .buttonStyle(.plain).font(.fenn(size: 12, weight: .medium))
                .foregroundStyle(nav.weekOffset == 0 ? Fenn.fg.opacity(0.35) : Fenn.accent)
                .disabled(nav.weekOffset == 0)
            Button { withAnimation(.snappy) { nav.weekOffset += 1 } } label: {
                Image(systemName: "chevron.right").font(.fenn(size: 12, weight: .semibold)).frame(width: 26, height: 26).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(Fenn.fg.opacity(0.6))
            .help(tr("Nächste Woche", "Next week"))
        }
        .padding(.horizontal, 4)
    }

    // MARK: Day

    private func dayBlock(_ day: Date, tasks: [FennTask]) -> some View {
        let calendar = Self.calendar
        let key = FennVault.dayKey(day)
        let isToday = calendar.isDateInToday(day)
        let isPast = day < calendar.startOfDay(for: Date())
        let weekend = calendar.isDateInWeekend(day)
        let planned = tasks.reduce(0) { $0 + DayPlanner.minutes(of: $1) }
        let free = isPast || weekend ? nil : DayPlanner.load(on: day).freeMinutes
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(day.formatted(.dateTime.weekday(.wide).locale(fennLocale)))
                    .font(.fenn(size: 13, weight: .semibold))
                    .foregroundStyle(isToday ? Fenn.accent : Fenn.fg.opacity(isPast ? 0.45 : 0.85))
                Text(day.formatted(.dateTime.day().month(.abbreviated).locale(fennLocale)))
                    .font(.fenn(size: 11.5)).foregroundStyle(Fenn.fg.opacity(isPast ? 0.35 : 0.5))
                Spacer(minLength: 4)
                capacity(planned: planned, free: free, doneCount: isPast ? doneCount(on: day) : nil)
                Button {
                    withAnimation(.snappy) { addingDay = addingDay == day ? nil : day }
                    draft = ""
                    fieldFocused = true
                } label: {
                    Image(systemName: "plus").font(.fenn(size: 11, weight: .semibold)).frame(width: 22, height: 22).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(Fenn.fg.opacity(0.45))
                .help(tr("Aufgabe für diesen Tag", "Task for this day"))
                .accessibilityLabel(tr("Aufgabe für diesen Tag", "Task for this day"))
            }
            ForEach(tasks) { task in line(task) }
            if addingDay == day {
                HStack(spacing: 8) {
                    Image(systemName: "plus").font(.fenn(size: 11, weight: .semibold)).foregroundStyle(Fenn.fg.opacity(0.45)).frame(width: 16)
                    TextField(tr("Neue Aufgabe für \(day.formatted(.dateTime.weekday(.wide).locale(fennLocale)))", "New task for \(day.formatted(.dateTime.weekday(.wide).locale(fennLocale)))"), text: $draft)
                        .textFieldStyle(.plain)
                        .font(.fenn(size: 13))
                        .focused($fieldFocused)
                        .onSubmit { add(on: day) }
                }
                .frame(height: 26)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(target == key ? Fenn.accent.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, _ in move(items, to: day) } isTargeted: { over in
            withAnimation(.easeOut(duration: 0.12)) { if over { target = key } else if target == key { target = nil } }
        }
    }

    /// "2 h frei", "1:30 h zu viel" (danger) – or what got done on a past day.
    @ViewBuilder
    private func capacity(planned: Int, free: Int?, doneCount: Int?) -> some View {
        if let doneCount {
            if doneCount > 0 { Text(tr("\(doneCount) erledigt", "\(doneCount) done")).font(.fenn(size: 11.5)).foregroundStyle(Fenn.fg.opacity(0.45)) }
        } else if let free {
            let left = free - planned
            Text(left >= 0 ? tr("\(TaskFormat.duration(left)) frei", "\(TaskFormat.duration(left)) free")
                           : tr("\(TaskFormat.duration(-left)) zu viel", "\(TaskFormat.duration(-left)) too much"))
                .font(.fenn(size: 11.5).monospacedDigit())
                .foregroundStyle(left < 0 ? Fenn.danger : Fenn.fg.opacity(0.5))
                .help(tr("~\(TaskFormat.duration(planned)) geplant, \(TaskFormat.duration(free)) freie Arbeitszeit nach Terminen",
                         "~\(TaskFormat.duration(planned)) planned, \(TaskFormat.duration(free)) free working time after appointments"))
        } else if planned > 0 {
            Text("~\(TaskFormat.duration(planned))").font(.fenn(size: 11.5)).foregroundStyle(Fenn.fg.opacity(0.5))
        }
    }

    private func doneCount(on day: Date) -> Int {
        store.tasks.filter { $0.done && ($0.doneAt.map { Self.calendar.isDate($0, inSameDayAs: day) } ?? false) }.count
    }

    /// One task: tick, title, time or estimate – drag it to another day.
    private func line(_ task: FennTask) -> some View {
        HStack(spacing: 8) {
            Button { withAnimation(.snappy) { store.toggle(task.id) } } label: {
                Image(systemName: "circle").font(.fenn(size: 14, weight: .light)).foregroundStyle(task.priority.color)
            }
            .buttonStyle(.plain)
            .frame(width: 16)
            .help(tr("Erledigt", "Done"))
            Text(task.title).font(.fenn(size: 13)).foregroundStyle(Fenn.fg).lineLimit(1)
            if task.mainDay == FennVault.dayKey(Date()) {
                Image(systemName: "star.fill").font(.fenn(size: 9)).foregroundStyle(Fenn.amber).help(tr("Heute zuerst", "First today"))
            }
            Spacer(minLength: 4)
            Group {
                if let due = task.due, DayPlanner.hasTime(due) {
                    Text(due.formatted(date: .omitted, time: .shortened))
                } else if let estimate = task.estimateMinutes {
                    Text("~\(TaskFormat.duration(estimate))")
                }
            }
            .font(.fenn(size: 11.5).monospacedDigit()).foregroundStyle(Fenn.fg.opacity(0.5))
        }
        .frame(height: 26)
        .contentShape(Rectangle())
        .onTapGesture { edit(task) }
        .help(store.goal(task.goalId).map { tr("Ziel: \($0.title)", "Goal: \($0.title)") } ?? "")
        .draggable(task.id.uuidString) {
            Text(task.title)
                .font(.fenn(size: 12, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(Fenn.canvas))
        }
        .contextMenu {
            Button(tr("Fokus", "Focus")) { startFocus(task) }
            Button(tr("Bearbeiten", "Edit")) { edit(task) }
            if task.due != nil { Button(tr("Ohne Datum", "No date")) { _ = move([task.id.uuidString], to: nil) } }
        }
    }

    // MARK: Without a date

    private func tray(_ tasks: [FennTask]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            FennSectionHeader(tr("Ohne Datum", "No date"), value: "\(tasks.count)")
                .help(tr("Auf einen Tag ziehen gibt das Datum; hierher ziehen nimmt es weg.", "Drag onto a day to give it a date; drop here to remove it."))
            VStack(spacing: 0) { ForEach(tasks) { task in line(task) } }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(target == "tray" ? Fenn.accent.opacity(0.1) : Color.clear)
                .fennGlass(cornerRadius: 18, shadow: false)
                .contentShape(Rectangle())
                .dropDestination(for: String.self) { items, _ in move(items, to: nil) } isTargeted: { over in
                    withAnimation(.easeOut(duration: 0.12)) { if over { target = "tray" } else if target == "tray" { target = nil } }
                }
        }
    }

    // MARK: Changes

    /// A task dropped on a day gets that day (keeping its time if it had one); dropped on "Ohne Datum" it loses its date.
    private func move(_ items: [String], to day: Date?) -> Bool {
        target = nil
        guard let id = items.first.flatMap(UUID.init(uuidString:)), var task = store.tasks.first(where: { $0.id == id }) else { return false }
        if let day {
            if let due = task.due, DayPlanner.hasTime(due) {
                let parts = Calendar.current.dateComponents([.hour, .minute], from: due)
                task.due = Calendar.current.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: day)
            } else {
                task.due = Calendar.current.startOfDay(for: day)
            }
            if let start = task.start, let due = task.due, start > due { task.start = nil }
        } else {
            task.due = nil
        }
        withAnimation(.snappy) { store.update(task) }
        return true
    }

    private func add(on day: Date) {
        var tasks = TaskCapture.rules(draft, topics: store.topics, goals: store.goals).tasks
        guard !tasks.isEmpty else { return }
        for index in tasks.indices where tasks[index].due == nil { tasks[index].due = Calendar.current.startOfDay(for: day) }
        store.add(tasks)
        draft = ""
        fieldFocused = true
    }
}
