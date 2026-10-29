import SwiftUI

/// Work first: tasks by topic with priority, time frame and estimate – as a list, a timeline, and what the time went into.
struct TasksModuleView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var focus: FocusTimer
    @ObservedObject var metrics: MetricsStore
    let openModule: (IslandModule) -> Void

    enum Mode: String, CaseIterable, Identifiable {
        case list, day, timeline, stats
        var id: String { rawValue }
        var title: String {
            switch self {
            case .list: return tr("Liste", "List")
            case .day: return tr("Tag nach Stunden", "Day by the hour")
            case .timeline: return "Timeline"
            case .stats: return tr("Auswertung", "Review")
            }
        }
        var symbol: String {
            switch self {
            case .list: return "checklist"
            case .day: return "clock"
            case .timeline: return "calendar.day.timeline.left"
            case .stats: return "chart.bar.xaxis"
            }
        }
    }

    @AppStorage("fenn.tasks.mode") private var mode = Mode.list
    @State private var draft = ""
    @State private var editing: UUID?
    /// Keeps rows from resorting/regrouping while the inline editor is open (avoids focus loss and jumping).
    @State private var frozenOrder: [UUID]?
    @State private var topic: String?
    @State private var showDone = false
    @AppStorage("fenn.tasks.grouping") private var grouping = "topic"
    @FocusState private var fieldFocused: Bool
    @ObservedObject private var calendarSync = TaskCalendarSync.shared
    @State private var day = Calendar.current.startOfDay(for: Date())

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Text(tr("Aufgaben", "Tasks")).font(Fenn.display(22)).foregroundStyle(Fenn.fg)
                Spacer()
                Button {
                    if calendarSync.isOn { calendarSync.disable() } else { Task { await calendarSync.enable() } }
                } label: {
                    Image(systemName: calendarSync.isOn ? "calendar.badge.checkmark" : "calendar.badge.plus")
                }
                .buttonStyle(FennIconButtonStyle(isActive: calendarSync.isOn))
                .help(calendarSync.isOn
                      ? tr("Aufgaben mit Datum stehen im Kalender „Fenn Focus“ – klicken zum Ausschalten", "Dated tasks are in the calendar “Fenn Focus” – click to turn off")
                      : tr("Aufgaben mit Datum im Apple Kalender anzeigen", "Show dated tasks in Apple Calendar"))
                .accessibilityLabel(tr("Im Kalender anzeigen", "Show in Calendar"))
                HStack(spacing: 2) {
                    ForEach(Mode.allCases) { item in
                        Button { withAnimation(.snappy) { mode = item } } label: { Image(systemName: item.symbol) }
                            .buttonStyle(FennIconButtonStyle(isActive: mode == item))
                            .help(item.title)
                            .accessibilityLabel(item.title)
                    }
                }
                .padding(3)
                .background(Capsule().fill(Fenn.fill))
            }

            if mode != .stats { addField }
            if calendarSync.isOn && !calendarSync.hasAccess {
                Button { Task { await calendarSync.enable() } } label: {
                    Label(tr("Kalenderzugriff fehlt – klicken, um ihn wieder zu erlauben", "Calendar access missing – click to allow it again"),
                          systemImage: "calendar.badge.exclamationmark")
                        .font(.fenn(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Fenn.accent)
            }
            if let error = calendarSync.errorMessage {
                Text(error).font(.fenn(size: 11)).foregroundStyle(Fenn.danger)
            }

            ScrollView {
                Group {
                    switch mode {
                    case .list: list
                    case .day: dayView
                    case .timeline: TaskTimeline(tasks: store.open) { task in beginEditing(task.id); mode = .list }
                    case .stats: WorkStats(store: store, metrics: metrics)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.never)

            storageLine
        }
        .onAppear {
            store.reload()
        }
    }

    // MARK: Day

    private var dayView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: tr("de_DE", "en_GB")))))
                    .font(.fenn(size: 14, weight: .semibold)).foregroundStyle(Fenn.fg)
                Spacer()
                Button { day = Calendar.current.date(byAdding: .day, value: -1, to: day) ?? day } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(FennIconButtonStyle())
                Button(tr("Heute", "Today")) { day = Calendar.current.startOfDay(for: Date()) }
                    .buttonStyle(.plain).font(.fenn(size: 12, weight: .medium)).foregroundStyle(Fenn.accent)
                Button { day = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(FennIconButtonStyle())
            }
            DayTimelineView(day: day) { task in beginEditing(task.id); mode = .list }
        }
    }

    // MARK: Add

    private var addField: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus").font(.fenn(size: 13, weight: .semibold)).foregroundStyle(Fenn.accent)
            TextField(tr("Neue Aufgabe", "New task"), text: $draft)
                .textFieldStyle(.plain)
                .font(.fenn(size: 14))
                .focused($fieldFocused)
                .onSubmit(add)
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(Capsule().fill(Fenn.field))
        .overlay(Capsule().strokeBorder(fieldFocused ? Fenn.accent.opacity(0.5) : Fenn.hairline))
    }

    private func add() {
        var tasks = TaskCapture.rules(draft, topics: store.topics).tasks
        guard !tasks.isEmpty else { return }
        // Typed into a filtered list: the topic comes with it.
        if let topic { for index in tasks.indices where tasks[index].topic.isEmpty { tasks[index].topic = topic } }
        store.add(tasks)
        draft = ""
        if tasks.count == 1 { beginEditing(tasks[0].id) }
        fieldFocused = true
    }

    private func beginEditing(_ id: UUID) {
        if frozenOrder == nil {
            frozenOrder = store.open.filter { topic == nil || $0.topic == topic }.map(\.id)
        }
        editing = id
    }

    private func endEditing() {
        editing = nil
        frozenOrder = nil
    }

    private func toggleEditing(_ id: UUID) {
        if editing == id { endEditing() } else { beginEditing(id) }
    }

    /// Open tasks in display order; frozen while an editor is open so edits don't reshuffle the list.
    private var openTasks: [FennTask] {
        let open = store.open.filter { topic == nil || $0.topic == topic }
        guard let frozen = frozenOrder, editing != nil else { return open }
        let byId = Dictionary(uniqueKeysWithValues: open.map { ($0.id, $0) })
        var ordered = frozen.compactMap { byId[$0] }
        let seen = Set(ordered.map(\.id))
        ordered.append(contentsOf: open.filter { !seen.contains($0.id) })
        return ordered
    }

    // MARK: List

    @ViewBuilder
    private var list: some View {
        let open = openTasks
        VStack(alignment: .leading, spacing: 14) {
            if store.topics.count > 0 { topicChips }
            if topic == nil { TaskKindCard() }
            if store.tasks.isEmpty {
                empty
            } else if topic != nil {
                group(nil, open)
            } else if grouping == "date" {
                ForEach(TaskGroups.make(open, by: "date"), id: \.title) { section in group(section.title, section.tasks) }
            } else {
                let top = open.filter(\.isStarred)
                if !top.isEmpty { group(tr("Top 3", "Top 3"), top) }
                let rest = open.filter { !$0.isStarred }
                let groups = Dictionary(grouping: rest) { $0.topicTitle }
                let order = groupOrder(rest, groups)
                ForEach(order, id: \.self) { name in group(name, groups[name] ?? []) }
            }
            doneSection
        }
    }

    private func groupOrder(_ tasks: [FennTask], _ groups: [String: [FennTask]]) -> [String] {
        if frozenOrder != nil, editing != nil {
            var seen = Set<String>()
            var order: [String] = []
            for task in tasks {
                let name = task.topicTitle
                if seen.insert(name).inserted { order.append(name) }
            }
            for name in groups.keys where !seen.contains(name) { order.append(name) }
            return order
        }
        return groups.keys.sorted { (groups[$0]?.first?.rank ?? 99) < (groups[$1]?.first?.rank ?? 99) }
    }

    private var topicChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                chip(tr("Alle", "All"), count: store.open.count, selected: topic == nil) { topic = nil }
                ForEach(store.topics, id: \.self) { name in
                    chip(name, count: store.open.filter { $0.topic == name }.count, selected: topic == name) { topic = topic == name ? nil : name }
                }
                Button { withAnimation(.snappy) { grouping = grouping == "date" ? "topic" : "date"; topic = nil } } label: {
                    Label(grouping == "date" ? tr("Nach Datum", "By date") : tr("Nach Thema", "By topic"),
                          systemImage: grouping == "date" ? "calendar" : "number")
                        .font(.fenn(size: 12, weight: .medium))
                        .foregroundStyle(Fenn.fg.opacity(0.75))
                        .padding(.horizontal, 11)
                        .frame(height: 28)
                        .overlay(Capsule().strokeBorder(Fenn.hairline))
                }
                .buttonStyle(.plain)
                .help(tr("Gruppierung wechseln: nach Thema oder nach Datum", "Switch grouping: by topic or by date"))
            }
        }
        .scrollIndicators(.never)
    }

    private func chip(_ title: String, count: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title).lineLimit(1)
                Text("\(count)").foregroundStyle(selected ? Fenn.canvas.opacity(0.6) : Fenn.fg.opacity(0.45))
            }
            .font(.fenn(size: 12, weight: .medium))
            .foregroundStyle(selected ? Fenn.canvas : Fenn.fg)
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(Capsule().fill(selected ? Fenn.fg : Fenn.fill))
        }
        .buttonStyle(.plain)
    }

    private func group(_ name: String?, _ tasks: [FennTask]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let name {
                let estimate = tasks.compactMap(\.estimateMinutes).reduce(0, +)
                HStack {
                    Text(name.uppercased()).font(.fenn(size: 11, weight: .medium)).tracking(1.2).foregroundStyle(Fenn.fg.opacity(0.55))
                    Spacer()
                    if estimate > 0 {
                        Text("~\(TaskFormat.duration(estimate))").font(.fenn(size: 11, weight: .light)).foregroundStyle(Fenn.fg.opacity(0.5))
                    }
                }
                .padding(.horizontal, 4)
            }
            VStack(spacing: 0) {
                ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                    TaskRow(task: task, isEditing: editing == task.id, isFocused: focus.taskId == task.id && focus.isActive,
                            toggle: { withAnimation(.snappy) { store.toggle(task.id) } },
                            edit: { withAnimation(.snappy) { toggleEditing(task.id) } },
                            startFocus: { startFocus(task) })
                    if editing == task.id {
                        TaskEditor(task: task, topics: store.topics, store: store,
                                   close: { withAnimation(.snappy) { endEditing() } },
                                   startFocus: { startFocus(task) })
                            .transition(.opacity)
                    }
                    if index < tasks.count - 1 { Rectangle().fill(Fenn.hairline).frame(height: 1).padding(.leading, 44) }
                }
            }
            .fennGlass(cornerRadius: 18, shadow: false)
        }
    }

    private var doneSection: some View {
        let done = store.tasks.filter { $0.done && (topic == nil || $0.topic == topic) }
            .sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }
        return Group {
            if !done.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Button { withAnimation(.snappy) { showDone.toggle() } } label: {
                        HStack(spacing: 6) {
                            Image(systemName: showDone ? "chevron.down" : "chevron.right").font(.fenn(size: 10, weight: .semibold))
                            Text(tr("ERLEDIGT, \(done.count)", "DONE, \(done.count)")).font(.fenn(size: 11, weight: .medium)).tracking(1.2)
                        }
                        .foregroundStyle(Fenn.fg.opacity(0.5))
                        .padding(.horizontal, 4)
                    }
                    .buttonStyle(.plain)
                    if showDone {
                        VStack(spacing: 0) {
                            ForEach(done.prefix(30)) { task in
                                TaskRow(task: task, isEditing: false, isFocused: false,
                                        toggle: { store.toggle(task.id) }, edit: {}, startFocus: {})
                            }
                        }
                        .fennGlass(cornerRadius: 18, shadow: false)
                    }
                }
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            ClaySymbol(symbol: "checklist", size: 48)
            Text(tr("Schreib oben deine erste Aufgabe.", "Type your first task above."))
                .font(.fenn(size: 13)).foregroundStyle(Fenn.fg.opacity(0.6))
            Text(tr("#Thema, morgen, bis Freitag, 45 min, wichtig", "#topic, tomorrow, by Friday, 45 min, important"))
                .font(.fenn(size: 12, design: .monospaced)).foregroundStyle(Fenn.fg.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func startFocus(_ task: FennTask) {
        focus.focus(on: task)
        if !focus.isRunning { focus.start() }
        openModule(.focus)
    }

    // MARK: Storage

    /// Where the tasks are stored – the Fenn Focus folder, or inside the app until one is picked.
    private var storageLine: some View {
        HStack(spacing: 8) {
            ClaySymbol(symbol: "folder", size: 17, tint: Fenn.fg.opacity(0.55))
            Text(TaskStore.destination).lineLimit(1)
            Spacer()
        }
        .font(.fenn(size: 11))
        .foregroundStyle(Fenn.fg.opacity(0.55))
    }
}

// MARK: - Row

struct TaskRow: View {
    let task: FennTask
    let isEditing: Bool
    let isFocused: Bool
    let toggle: () -> Void
    let edit: () -> Void
    let startFocus: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: toggle) {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(.fenn(size: 17, weight: .light))
                    .foregroundStyle(task.done ? Fenn.accent : task.priority.color)
            }
            .buttonStyle(.plain)
            .frame(width: 24)
            .help(task.done ? tr("Wieder öffnen", "Reopen") : tr("Erledigt", "Done"))

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.fenn(size: 14))
                    .foregroundStyle(task.done ? Fenn.fg.opacity(0.45) : Fenn.fg)
                    .strikethrough(task.done, color: Fenn.fg.opacity(0.3))
                    .lineLimit(2)
                if !task.done { meta }
            }
            Spacer(minLength: 4)
            if task.isStarred && !task.done {
                ClaySymbol(symbol: "star.fill", size: 16, tint: Fenn.amber).help(tr("Top 3", "Top 3"))
            }
            if isFocused {
                ClaySymbol(symbol: "timer", size: 20).help(tr("Läuft im Fokus", "In focus"))
            } else if !task.done, hovering || isEditing {
                Button(action: startFocus) { Image(systemName: "play.fill").font(.fenn(size: 11)) }
                    .buttonStyle(FennIconButtonStyle())
                    .help(tr("Fokus auf diese Aufgabe", "Focus on this task"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .background(isEditing ? Fenn.fill : .clear)
        .onTapGesture(perform: edit)
        .onHover { hovering = $0 }
        .contextMenu {
            let store = TaskStore.shared
            if !task.done {
                Button(task.isStarred ? tr("Aus den Top 3", "Remove from top 3") : tr("In die Top 3", "Into the top 3")) { withAnimation(.snappy) { store.toggleStar(task.id) } }
                Button(tr("Heute", "Today")) { move(0) }
                Button(tr("Morgen", "Tomorrow")) { move(1) }
                Button(tr("Ist ein Termin – blockt nur Zeit", "It's an appointment – just blocks time")) { store.setBlocker(task.id, true) }
                Menu(tr("Wiederholen", "Repeat")) {
                    Button(tr("Nie", "Never")) { var copy = task; copy.repeatRule = nil; store.update(copy) }
                    ForEach(TaskRepeat.allCases) { rule in
                        Button(rule.title) { var copy = task; copy.repeatRule = rule; store.update(copy) }
                    }
                }
                Divider()
            }
            Button(task.done ? tr("Wieder öffnen", "Reopen") : tr("Abhaken", "Tick off"), action: toggle)
            Button(tr("Löschen", "Delete"), role: .destructive) { withAnimation(.snappy) { store.delete(task.id) } }
        }
    }

    private func move(_ offset: Int) {
        var copy = task
        let day = Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        if let due = task.due, DayPlanner.hasTime(due) {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: due)
            copy.due = Calendar.current.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: day)
        } else {
            copy.due = day
        }
        TaskStore.shared.update(copy)
    }

    private var meta: some View {
        HStack(spacing: 8) {
            if task.priority == .high {
                Label(tr("Hoch", "High"), systemImage: "exclamationmark").labelStyle(.titleAndIcon).foregroundStyle(Fenn.accent)
            }
            if let due = task.due {
                Label(dateText(due), systemImage: "calendar")
                    .foregroundStyle(task.isOverdue ? Fenn.danger : (task.isDueToday ? Fenn.amber : Fenn.fg.opacity(0.55)))
            }
            if let rule = task.repeatRule {
                Label(rule.title, systemImage: "repeat").foregroundStyle(Fenn.fg.opacity(0.55))
            }
            if let estimate = task.estimateMinutes {
                Label(task.spentMinutes > 0 ? "\(TaskFormat.duration(task.spentMinutes)) / \(TaskFormat.duration(estimate))" : "~\(TaskFormat.duration(estimate))",
                      systemImage: "hourglass")
                    .foregroundStyle(task.spentMinutes > estimate ? Fenn.danger.opacity(0.8) : Fenn.fg.opacity(0.55))
            } else if task.spentMinutes > 0 {
                Label(TaskFormat.duration(task.spentMinutes), systemImage: "timer").foregroundStyle(Fenn.fg.opacity(0.55))
            }
        }
        .font(.fenn(size: 11))
        .labelStyle(CompactLabel())
    }

    private func dateText(_ due: Date) -> String {
        if let start = task.start, start < due, !Calendar.current.isDate(start, inSameDayAs: due) {
            return "\(TaskFormat.day(start)) – \(TaskFormat.when(due))"
        }
        return TaskFormat.when(due)
    }
}

private struct CompactLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.font(.fenn(size: 9, weight: .semibold))
            configuration.title
        }
    }
}

// MARK: - Editor

struct TaskEditor: View {
    @State var task: FennTask
    let topics: [String]
    let store: TaskStore
    let close: () -> Void
    let startFocus: () -> Void

    private static let estimates = [15, 30, 45, 60, 90, 120, 180, 240, 360, 480]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(tr("Titel", "Title"), text: $task.title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.fenn(size: 15, weight: .medium))
                .onSubmit(commit)

            grid

            HStack(spacing: 8) {
                Button(action: { commit(); startFocus() }) { Label(tr("Fokus", "Focus"), systemImage: "play.fill") }
                    .buttonStyle(FennPillButtonStyle())
                Spacer()
                Button(task.done ? tr("Wieder öffnen", "Reopen") : tr("Abhaken", "Tick off")) { commit(); store.toggle(task.id); close() }
                    .buttonStyle(FennPillButtonStyle())
                Button { store.delete(task.id); close() } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Fenn.danger.opacity(0.8))
                    .help(tr("Löschen", "Delete"))
                Button(tr("Fertig", "Done")) { commit(); close() }
                    .buttonStyle(FennPillButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .background(Fenn.fill)
        // Commit once on close — live onChange re-sorted/re-grouped the list and stole TextField focus.
        .onDisappear(perform: commit)
    }

    private var grid: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                label("tag", tr("Tag / Thema", "Tag / topic"))
                HStack(spacing: 6) {
                    TextField(tr("z. B. Arbeit, Privat", "e.g. Work, private"), text: $task.topic)
                        .textFieldStyle(.plain)
                        .font(.fenn(size: 13))
                        .onSubmit(commit)
                    if !topics.isEmpty {
                        Menu {
                            ForEach(topics, id: \.self) { name in Button(name) { task.topic = name } }
                            Divider()
                            Button(tr("Ohne Thema", "No topic")) { task.topic = "" }
                        } label: { Image(systemName: "chevron.up.chevron.down").font(.fenn(size: 10)) }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()
                    }
                }
            }
            GridRow {
                label("flag", tr("Priorität", "Priority"))
                HStack(spacing: 10) {
                    FennSegments(options: TaskPriority.allCases, selection: $task.priority) { $0.title }
                    Button { task.starred = task.isStarred ? nil : true } label: {
                        Label(tr("Top 3", "Top 3"), systemImage: task.isStarred ? "star.fill" : "star")
                            .font(.fenn(size: 12, weight: .medium))
                            .foregroundStyle(task.isStarred ? Fenn.amber : Fenn.fg.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help(tr("Eine der drei wichtigsten Aufgaben heute", "One of today's three most important tasks"))
                }
            }
            GridRow {
                label("repeat", tr("Wiederholen", "Repeat"))
                HStack(spacing: 10) {
                    Menu {
                        Button(tr("Nie", "Never")) { task.repeatRule = nil }
                        ForEach(TaskRepeat.allCases) { rule in Button(rule.title) { task.repeatRule = rule } }
                    } label: {
                        Text(task.repeatRule?.title ?? tr("nie", "never")).font(.fenn(size: 13))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
            GridRow {
                label("calendar.badge.clock", tr("Termin", "Appointment"))
                Toggle(tr("Blockt nur Zeit, keine offene Aufgabe", "Just blocks time, not an open task"),
                       isOn: Binding(get: { task.isBlocker }, set: { task.blocker = $0 ? true : nil }))
                    .toggleStyle(.checkbox).font(.fenn(size: 12))
            }
            GridRow {
                label("calendar", tr("Start → Fällig", "Start → due"))
                HStack(spacing: 6) {
                    dateField(tr("Start", "Start"), $task.start, fallback: Date())
                    Image(systemName: "arrow.right").font(.fenn(size: 9)).foregroundStyle(Fenn.fg.opacity(0.4))
                    dateField(tr("Fällig", "Due"), $task.due, fallback: task.start ?? Date())
                }
            }
            if let due = task.due {
                GridRow {
                    label("clock", tr("Uhrzeit", "Time"))
                    HStack(spacing: 8) {
                        Toggle("", isOn: Binding(get: { DayPlanner.hasTime(due) }, set: { on in
                            task.due = on ? Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: due) : Calendar.current.startOfDay(for: due)
                        }))
                        .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                        if DayPlanner.hasTime(due) {
                            DatePicker("", selection: Binding(get: { due }, set: { task.due = $0 }), displayedComponents: .hourAndMinute)
                                .labelsHidden().datePickerStyle(.field).fixedSize()
                        } else {
                            Text(tr("ganztägig", "all day")).font(.fenn(size: 12)).foregroundStyle(Fenn.fg.opacity(0.5))
                        }
                    }
                }
            }
            GridRow {
                label("hourglass", tr("Dauer", "Estimate"))
                HStack(spacing: 8) {
                    Menu {
                        ForEach(Self.estimates, id: \.self) { minutes in Button(TaskFormat.duration(minutes)) { task.estimateMinutes = minutes } }
                        Divider()
                        Button(tr("Keine Schätzung", "No estimate")) { task.estimateMinutes = nil }
                    } label: {
                        Text(task.estimateMinutes.map { "~\(TaskFormat.duration($0))" } ?? tr("schätzen …", "estimate …"))
                            .font(.fenn(size: 13))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    if task.spentMinutes > 0 {
                        Text(tr("\(TaskFormat.duration(task.spentMinutes)) im Fokus", "\(TaskFormat.duration(task.spentMinutes)) in focus"))
                            .font(.fenn(size: 12, weight: .light)).foregroundStyle(Fenn.fg.opacity(0.55))
                    }
                }
            }
        }
    }

    private func label(_ symbol: String, _ title: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.fenn(size: 12))
            .foregroundStyle(Fenn.fg.opacity(0.55))
            .frame(width: 92, alignment: .leading)
    }

    /// An optional date: a small "+ Start" button until set, then a compact picker with a clear button.
    @ViewBuilder
    private func dateField(_ title: String, _ date: Binding<Date?>, fallback: Date) -> some View {
        if let value = date.wrappedValue {
            HStack(spacing: 2) {
                DatePicker("", selection: Binding(get: { value }, set: { new in
                    // A new day keeps the time that was set.
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: value)
                    date.wrappedValue = Calendar.current.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: new) ?? new
                }), displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .fixedSize()
                Button { date.wrappedValue = nil } label: { Image(systemName: "xmark.circle.fill").font(.fenn(size: 10)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Fenn.fg.opacity(0.35))
            }
        } else {
            Button { date.wrappedValue = Calendar.current.startOfDay(for: fallback) } label: {
                Text("+ \(title)").font(.fenn(size: 12)).foregroundStyle(Fenn.fg.opacity(0.6))
                    .padding(.horizontal, 9).frame(height: 24)
                    .background(Capsule().fill(Fenn.fill))
            }
            .buttonStyle(.plain)
        }
    }

    private func commit() {
        guard !task.title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if let start = task.start, let due = task.due, due < start { task.due = start }
        // The top-3 limit lives in the store: a new star goes through toggleStar.
        let wasStarred = store.tasks.first { $0.id == task.id }?.isStarred ?? false
        var saved = task
        if task.isStarred && !wasStarred { saved.starred = nil }
        store.update(saved)
        if task.isStarred && !wasStarred { store.toggleStar(task.id) }
    }
}

// MARK: - Timeline

/// Two weeks from yesterday: bars from start to due, a diamond where there's only a due date,
/// and the planned hours per day on top (open estimate spread over the remaining days).
struct TaskTimeline: View {
    let tasks: [FennTask]
    let open: (FennTask) -> Void

    private let labelWidth: CGFloat = 132
    private let rowHeight: CGFloat = 26

    var body: some View {
        let dated = tasks.filter { $0.due != nil || $0.start != nil }
            .sorted { ($0.start ?? $0.due ?? .distantFuture) < ($1.start ?? $1.due ?? .distantFuture) }
        let undated = tasks.filter { $0.due == nil && $0.start == nil }
        VStack(alignment: .leading, spacing: 14) {
            GeometryReader { geometry in
                let count = geometry.size.width > 640 ? 21 : 14
                let columns = days(count)
                let width = (geometry.size.width - labelWidth) / CGFloat(count)
                VStack(alignment: .leading, spacing: 0) {
                    header(columns, width: width)
                    ForEach(dated) { task in row(task, columns: columns, width: width) }
                }
                .overlay(alignment: .topLeading) { todayLine(columns, width: width, height: CGFloat(dated.count) * rowHeight + 52) }
            }
            .frame(height: CGFloat(dated.count) * rowHeight + 52)
            .padding(12)
            .fennGlass(cornerRadius: 18, shadow: false)

            if dated.isEmpty {
                Text(tr("Gib Aufgaben einen Start oder ein Fälligkeitsdatum – dann erscheinen sie hier.",
                        "Give tasks a start or due date and they appear here."))
                    .font(.fenn(size: 12)).foregroundStyle(Fenn.fg.opacity(0.55))
            }
            if !undated.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("OHNE TERMIN, \(undated.count)", "NO DATE, \(undated.count)"))
                        .font(.fenn(size: 11, weight: .medium)).tracking(1.2).foregroundStyle(Fenn.fg.opacity(0.5))
                    WrapLayout(spacing: 6) {
                        ForEach(undated) { task in
                            Button { open(task) } label: {
                                HStack(spacing: 5) {
                                    Circle().fill(task.priority.color).frame(width: 6, height: 6)
                                    Text(task.title).lineLimit(1)
                                }
                                .font(.fenn(size: 12))
                                .foregroundStyle(Fenn.fg.opacity(0.85))
                                .padding(.horizontal, 10).frame(height: 26)
                                .background(Capsule().fill(Fenn.fill))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func days(_ count: Int) -> [Date] {
        let start = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date()))!
        return (0..<count).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }
    }

    private func header(_ columns: [Date], width: CGFloat) -> some View {
        let load = plannedMinutes(columns)
        let letter = DateFormatter()
        letter.locale = fennLocale
        letter.dateFormat = "EEEEE"
        return HStack(spacing: 0) {
            Text(Date().formatted(.dateTime.month(.wide).locale(fennLocale)))
                .font(.fenn(size: 12, weight: .medium)).foregroundStyle(Fenn.fg.opacity(0.7))
                .frame(width: labelWidth, alignment: .leading)
            ForEach(Array(columns.enumerated()), id: \.offset) { index, day in
                let today = Calendar.current.isDateInToday(day)
                let weekend = Calendar.current.isDateInWeekend(day)
                VStack(spacing: 2) {
                    Text(letter.string(from: day)).font(.fenn(size: 9)).foregroundStyle(Fenn.fg.opacity(weekend ? 0.3 : 0.5))
                    Text("\(Calendar.current.component(.day, from: day))")
                        .font(.fenn(size: 11, weight: today ? .bold : .regular))
                        .foregroundStyle(today ? Fenn.accent : Fenn.fg.opacity(weekend ? 0.4 : 0.8))
                    // Planned hours: a small bar, full at 6 h.
                    Capsule()
                        .fill(load[index] > 360 ? Fenn.danger : Fenn.amber.opacity(0.8))
                        .frame(width: max(2, min(width - 6, 16)), height: max(1.5, min(14, CGFloat(load[index]) / 360 * 14)))
                        .opacity(load[index] > 0 ? 1 : 0.15)
                        .frame(height: 14, alignment: .bottom)
                        .help(load[index] > 0 ? tr("~\(TaskFormat.duration(load[index])) geplant", "~\(TaskFormat.duration(load[index])) planned") : "")
                }
                .frame(width: width)
            }
        }
        .frame(height: 52, alignment: .top)
    }

    private func row(_ task: FennTask, columns: [Date], width: CGFloat) -> some View {
        let calendar = Calendar.current
        let first = columns.first!, last = columns.last!
        let start = calendar.startOfDay(for: task.start ?? task.due!)
        let end = calendar.startOfDay(for: task.due ?? task.start!)
        let from = max(start, first), to = min(end, last)
        let startIndex = calendar.dateComponents([.day], from: first, to: from).day ?? 0
        let span = (calendar.dateComponents([.day], from: from, to: to).day ?? 0) + 1
        let visible = to >= from
        return Button { open(task) } label: {
            HStack(spacing: 0) {
                HStack(spacing: 5) {
                    Circle().fill(task.priority.color).frame(width: 5, height: 5)
                    Text(task.title).font(.fenn(size: 12)).foregroundStyle(Fenn.fg.opacity(0.9)).lineLimit(1)
                }
                .frame(width: labelWidth, alignment: .leading)
                ZStack(alignment: .leading) {
                    Color.clear
                    if visible {
                        if task.start == nil || start == end {
                            Image(systemName: "diamond.fill")
                                .font(.fenn(size: 9))
                                .foregroundStyle(task.isOverdue ? Fenn.danger : task.priority.color)
                                .frame(width: width)
                                .offset(x: CGFloat(startIndex) * width)
                        } else {
                            Capsule()
                                .fill(LinearGradient(colors: [task.priority.color.opacity(0.55), task.priority.color], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(width * CGFloat(span) - 4, 6), height: 12)
                                .offset(x: CGFloat(startIndex) * width + 2)
                        }
                    } else if end < first {
                        Image(systemName: "exclamationmark.circle.fill").font(.fenn(size: 10)).foregroundStyle(Fenn.danger)
                            .help(tr("Überfällig", "Overdue"))
                    }
                }
            }
            .frame(height: rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(task.title)
    }

    private func todayLine(_ columns: [Date], width: CGFloat, height: CGFloat) -> some View {
        Rectangle()
            .fill(Fenn.accent.opacity(0.35))
            .frame(width: 1, height: height - 40)
            .offset(x: labelWidth + width * 1.5, y: 40)
            .allowsHitTesting(false)
    }

    /// Open estimate (minus focus already spent) spread evenly over the weekdays left until due.
    private func plannedMinutes(_ columns: [Date]) -> [Int] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var load = Array(repeating: 0, count: columns.count)
        for task in tasks {
            guard let estimate = task.estimateMinutes, let due = task.due else { continue }
            let left = max(0, estimate - task.spentMinutes)
            guard left > 0 else { continue }
            let from = max(today, calendar.startOfDay(for: task.start ?? today))
            let to = max(from, calendar.startOfDay(for: due))
            var days: [Date] = []
            var day = from
            while day <= to {
                if !calendar.isDateInWeekend(day) || from == to { days.append(day) }
                day = calendar.date(byAdding: .day, value: 1, to: day)!
            }
            if days.isEmpty { days = [to] }
            for day in days {
                if let index = columns.firstIndex(where: { calendar.isDate($0, inSameDayAs: day) }) { load[index] += left / days.count }
            }
        }
        return load
    }
}

/// Chips that wrap onto the next line.
private struct WrapLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += line + spacing; line = 0 }
            x += size.width + spacing
            line = max(line, size.height)
        }
        return CGSize(width: width, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += line + spacing; line = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}

// MARK: - Review

/// What the time went into: focus per topic and per day, tasks and routines done, estimate vs. actual.
struct WorkStats: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var metrics: MetricsStore
    @State private var period = Period.week

    enum Period: String, CaseIterable, Identifiable {
        case today, week, month
        var id: String { rawValue }
        var title: String {
            switch self {
            case .today: return tr("Heute", "Today")
            case .week: return tr("Woche", "Week")
            case .month: return tr("Monat", "Month")
            }
        }
        var interval: DateInterval {
            switch self {
            case .today: return .today
            case .week: return .thisWeek
            case .month: return .thisMonth
            }
        }
    }

    var body: some View {
        let range = period.interval
        let focusMinutes = store.focusMinutes(in: range)
        let done = store.doneCount(in: range)
        let routines = routinesDone(in: range)
        VStack(alignment: .leading, spacing: 16) {
            FennSegments(options: Period.allCases, selection: $period) { $0.title }

            HStack(spacing: 10) {
                AuraPill(title: tr("Fokus", "Focus"), value: hours(focusMinutes), unit: "h", palette: .steady, symbol: "timer")
                AuraPill(title: tr("Erledigt", "Done"), value: "\(done)", palette: .fresh, symbol: "checkmark")
                AuraPill(title: tr("Routinen", "Routines"), value: "\(routines)", palette: .ember, symbol: "repeat")
            }

            topics(range)
            if period != .today { daily(range) }
            accuracy(range)
        }
    }

    private func hours(_ minutes: Int) -> String {
        minutes == 0 ? "0" : String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    private func routinesDone(in range: DateInterval) -> Int {
        days(in: range).reduce(0) { $0 + (metrics.record(for: $1).habitsDone ?? 0) }
    }

    private func days(in range: DateInterval) -> [Date] {
        var result: [Date] = []
        var day = range.start
        let end = min(range.end, Date())
        while day < end {
            result.append(day)
            day = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        }
        return result
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.fenn(size: 11, weight: .medium)).tracking(1.2).foregroundStyle(Fenn.fg.opacity(0.55))
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fennGlass(cornerRadius: 18, shadow: false)
    }

    @ViewBuilder
    private func topics(_ range: DateInterval) -> some View {
        let items = store.minutesByTopic(in: range)
        let top = items.first?.minutes ?? 1
        card(tr("Wofür", "Where it went")) {
            if items.isEmpty {
                Text(tr("Noch keine Fokuszeit. Starte eine Aufgabe mit ▶.", "No focus time yet. Start a task with ▶."))
                    .font(.fenn(size: 12)).foregroundStyle(Fenn.fg.opacity(0.55))
            } else {
                ForEach(items, id: \.topic) { item in
                    HStack(spacing: 10) {
                        Text(item.topic).font(.fenn(size: 12)).foregroundStyle(Fenn.fg).lineLimit(1).frame(width: 110, alignment: .leading)
                        GeometryReader { geometry in
                            Capsule().fill(Fenn.fill)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(LinearGradient(colors: [Fenn.accent.opacity(0.6), Fenn.accent], startPoint: .leading, endPoint: .trailing))
                                        .frame(width: max(6, geometry.size.width * CGFloat(item.minutes) / CGFloat(max(top, 1))))
                                }
                        }
                        .frame(height: 8)
                        Text(TaskFormat.duration(item.minutes)).font(.fenn(size: 11, weight: .light)).foregroundStyle(Fenn.fg.opacity(0.65))
                            .frame(width: 58, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func daily(_ range: DateInterval) -> some View {
        let days = days(in: range)
        let values = days.map { day in store.focusMinutes(in: Calendar.current.dateInterval(of: .day, for: day)!) }
        let top = max(60, values.max() ?? 60)
        let letter = DateFormatter()
        letter.locale = fennLocale
        letter.dateFormat = days.count > 7 ? "d" : "EE"
        return card(tr("Fokus pro Tag", "Focus per day")) {
            HStack(alignment: .bottom, spacing: days.count > 7 ? 3 : 10) {
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    VStack(spacing: 4) {
                        bar(values[index], top: top, color: Fenn.accent)
                            .frame(height: 80, alignment: .bottom)
                        if days.count <= 7 || index % 3 == 0 {
                            Text(letter.string(from: day)).font(.fenn(size: 9)).foregroundStyle(Fenn.fg.opacity(0.5))
                        } else {
                            Text(" ").font(.fenn(size: 9))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .help("\(day.formatted(.dateTime.weekday().day().month().locale(fennLocale))): \(tr("Fokus", "Focus")) \(TaskFormat.duration(values[index]))")
                }
            }
        }
    }

    private func bar(_ minutes: Int, top: Int, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color.opacity(minutes > 0 ? 0.9 : 0.15))
            .frame(maxWidth: 10)
            .frame(height: max(2, 80 * CGFloat(minutes) / CGFloat(top)))
    }

    @ViewBuilder
    private func accuracy(_ range: DateInterval) -> some View {
        let finished = store.tasks.filter { $0.done && ($0.doneAt.map(range.contains) ?? false) && $0.estimateMinutes != nil && $0.spentMinutes > 0 }
        let open = store.open
        let left = open.compactMap { task in task.estimateMinutes.map { max(0, $0 - task.spentMinutes) } }.reduce(0, +)
        card(tr("Planung", "Planning")) {
            HStack(spacing: 0) {
                figure("\(open.count)", tr("offen", "open"))
                figure("\(open.filter(\.isOverdue).count)", tr("überfällig", "overdue"), warn: open.contains(where: \.isOverdue))
                figure(left > 0 ? TaskFormat.duration(left) : "–", tr("noch geschätzt", "estimated left"))
            }
            if !finished.isEmpty {
                let estimate = finished.compactMap(\.estimateMinutes).reduce(0, +)
                let spent = finished.reduce(0) { $0 + $1.spentMinutes }
                let ratio = Double(spent) / Double(max(estimate, 1))
                Text(ratio > 1.1
                     ? tr("Du brauchst im Schnitt \(Int(((ratio - 1) * 100).rounded())) % länger als geschätzt.", "You take \(Int(((ratio - 1) * 100).rounded()))% longer than estimated on average.")
                     : ratio < 0.9
                        ? tr("Du bist im Schnitt \(Int(((1 - ratio) * 100).rounded())) % schneller als geschätzt.", "You're \(Int(((1 - ratio) * 100).rounded()))% faster than estimated on average.")
                        : tr("Deine Schätzungen passen gut.", "Your estimates are on point."))
                    .font(.fenn(size: 12)).foregroundStyle(Fenn.fg.opacity(0.7))
            }
        }
    }

    private func figure(_ value: String, _ title: String, warn: Bool = false) -> some View {
        VStack(spacing: 3) {
            Text(value).font(Fenn.display(18)).foregroundStyle(warn ? Fenn.danger : Fenn.fg)
            Text(title).font(.fenn(size: 11, weight: .light)).foregroundStyle(Fenn.fg.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
    }
}

/// Small capsule switch in Fenn's colours (instead of the blue system segmented control).
struct FennSegments<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button { withAnimation(.snappy) { selection = option } } label: {
                    Text(title(option))
                        .font(.fenn(size: 12, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Fenn.canvas : Fenn.fg.opacity(0.75))
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background(Capsule().fill(selected ? Fenn.fg : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Fenn.fill))
        .fixedSize()
    }
}
