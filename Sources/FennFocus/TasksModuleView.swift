import SwiftUI
import AppKit

/// Work first: tasks by topic with priority, time frame and estimate – as a list, goals, a week plan, a timeline,
/// and what the time went into. Keys (when no text field is being edited): N new task, F focus, W week, G goals,
/// ↑/↓ select, Space tick off, ⌘K the command palette.
struct TasksModuleView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var focus: FocusTimer
    @ObservedObject var metrics: MetricsStore
    let openModule: (IslandModule) -> Void

    enum Mode: String, CaseIterable, Identifiable {
        case list, goals, week, day, timeline, stats
        var id: String { rawValue }
        var title: String {
            switch self {
            case .list: return tr("Heute", "Today")
            case .goals: return tr("Ziele", "Goals")
            case .week: return tr("Woche", "Week")
            case .day: return tr("Tag nach Stunden", "Day by the hour")
            case .timeline: return "Timeline"
            case .stats: return tr("Auswertung", "Review")
            }
        }
        var symbol: String {
            switch self {
            case .list: return "checklist"
            case .goals: return "flag.checkered"
            case .week: return "calendar"
            case .day: return "clock"
            case .timeline: return "calendar.day.timeline.left"
            case .stats: return "chart.bar.xaxis"
            }
        }
        /// The key that jumps here, shown in the tooltip.
        var key: String? {
            switch self {
            case .list: return "L"
            case .goals: return "G"
            case .week: return "W"
            default: return nil
            }
        }
    }

    static let modeKey = "fenn.tasks.mode"
    @AppStorage(TasksModuleView.modeKey) private var mode = Mode.list
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
    @ObservedObject private var nav = TasksNav.shared
    @StateObject private var keys = TaskKeyMonitor()

    var body: some View {
        ZStack(alignment: .top) {
            if nav.focusOpen {
                TaskFocusView(store: store, focus: focus, nav: nav)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                content
                    .transition(.opacity)
            }
            if nav.paletteOpen {
                Color.black.opacity(0.18)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .onTapGesture { nav.closePalette() }
                    .transition(.opacity)
                CommandPalette(items: paletteItems, nav: nav)
                    .padding(.horizontal, 20)
                    .padding(.top, 48)
                    .transition(.opacity.combined(with: .offset(y: -8)))
            }
        }
        .background(WindowReader { window in
            keys.window = window
            keys.releaseEmptyField()
        })
        .onAppear {
            keys.handle = { event, editing in handleKey(event, editing: editing) }
            keys.install()
            #if DEBUG
            qaOpen()
            #endif
        }
        .onDisappear {
            keys.remove()
            nav.paletteOpen = false
        }
        .onChange(of: nav.focusAddRequest) { _, _ in
            DispatchQueue.main.async { fieldFocused = true }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if mode != .stats { addField }
            if calendarSync.isOn && !calendarSync.hasAccess && !FennDemo.isOn {
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

            ScrollViewReader { proxy in
                ScrollView {
                    Group {
                        switch mode {
                        case .list: list
                        case .goals: GoalsView(store: store, nav: nav, edit: openInList, startFocus: startFocus)
                        case .week: WeekPlanView(store: store, nav: nav, edit: openInList, startFocus: startFocus)
                        case .day: dayView
                        case .timeline: TaskTimeline(tasks: store.open) { task in beginEditing(task.id); mode = .list }
                        case .stats: WorkStats(store: store, metrics: metrics) {
                            GoalPlanner.closeWeek(store)
                            nav.weekOffset = 1
                            withAnimation(.snappy) { mode = .week }
                        }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.never)
                .onChange(of: nav.selected) { _, id in
                    if let id { withAnimation(.snappy) { proxy.scrollTo(id, anchor: .center) } }
                }
            }
        }
        .onAppear {
            store.reload()
        }
    }

    // MARK: Header

    private static let mainModes: [Mode?] = [.list, .week, .goals]

    /// Title, three views as text segments, everything else in one … menu.
    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(tr("Aufgaben", "Tasks")).font(Fenn.display(22)).foregroundStyle(Fenn.fg)
            Spacer(minLength: 6)
            FennSegments(options: Self.mainModes,
                         selection: Binding(get: { Self.mainModes.contains(mode) ? mode : nil },
                                            set: { if let new = $0 { mode = new } }),
                         title: { $0?.title ?? "" },
                         help: { item in item.flatMap { mode in mode.key.map { "\(mode.title) (\($0))" } } })
            moreMenu
        }
    }

    private var moreMenu: some View {
        Menu {
            Section {
                ForEach([Mode.day, .timeline, .stats]) { item in
                    Button { withAnimation(.snappy) { mode = item } } label: {
                        Label(item == .stats ? tr("Auswertung und Wochenrückblick", "Review and week check") : item.title, systemImage: item.symbol)
                    }
                }
            }
            Section {
                Picker(tr("Gruppieren", "Group"), selection: Binding(get: { grouping }, set: { grouping = $0; topic = nil })) {
                    Text(tr("Nach Thema", "By topic")).tag("topic")
                    Text(tr("Nach Datum", "By date")).tag("date")
                }
                if !store.topics.isEmpty {
                    Picker(tr("Thema", "Topic"), selection: $topic) {
                        Text(tr("Alle (\(store.open.count))", "All (\(store.open.count))")).tag(String?.none)
                        ForEach(store.topics, id: \.self) { name in
                            Text("\(name) (\(store.open.filter { $0.topic == name }.count))").tag(String?.some(name))
                        }
                    }
                }
            }
            Section {
                Toggle(tr("Im Kalender „Fenn Focus“ anzeigen", "Show in the “Fenn Focus” calendar"), isOn: Binding(
                    get: { calendarSync.isOn },
                    set: { on in if on { Task { await calendarSync.enable() } } else { calendarSync.disable() } }))
                Text(tr("Gespeichert: \(TaskStore.destination)", "Stored: \(TaskStore.destination)"))
            }
            Section {
                Button(tr("Befehle und Tastenkürzel …  ⌘K", "Commands and shortcuts …  ⌘K")) { nav.openPalette() }
            }
        } label: {
            Image(systemName: "ellipsis.circle").font(.fenn(size: 16)).foregroundStyle(Fenn.fg.opacity(0.7))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(tr("Weitere Ansichten, Gruppierung, Kalender", "More views, grouping, calendar"))
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
            Image(systemName: "plus").font(.fenn(size: 12, weight: .semibold)).foregroundStyle(Fenn.fg.opacity(0.5))
            TextField(tr("Neue Aufgabe – @Ziel, morgen, 45 min", "New task – @goal, tomorrow, 45 min"), text: $draft)
                .textFieldStyle(.plain)
                .font(.fenn(size: 13))
                .focused($fieldFocused)
                .onSubmit(add)
        }
        .help(tr("Neue Aufgabe (N). @Ziel hängt sie an ein Ziel, #Thema, morgen, bis Freitag, 45 min, wichtig", "New task (N). @goal attaches it to a goal, #topic, tomorrow, by Friday, 45 min, important"))
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Capsule().fill(Fenn.field))
        .overlay(Capsule().strokeBorder(fieldFocused ? Fenn.accent.opacity(0.5) : Fenn.hairline))
    }

    private func add() {
        var tasks = TaskCapture.rules(draft, topics: store.topics, goals: store.goals).tasks
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
        VStack(alignment: .leading, spacing: 16) {
            if let topic {
                HStack(spacing: 6) {
                    Text(tr("Nur „\(topic)“", "Only “\(topic)”")).font(.fenn(size: 12)).foregroundStyle(Fenn.fg.opacity(0.6))
                    Button(tr("Alle zeigen", "Show all")) { withAnimation(.snappy) { self.topic = nil } }
                        .buttonStyle(.plain).font(.fenn(size: 12, weight: .medium)).foregroundStyle(Fenn.accent)
                }
                .padding(.horizontal, 4)
            }
            if topic == nil, !store.open.isEmpty { MainTaskCard(store: store, startFocus: startFocus) }
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

    private func group(_ name: String?, _ tasks: [FennTask]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let name {
                let estimate = tasks.compactMap(\.estimateMinutes).reduce(0, +)
                FennSectionHeader(name, value: estimate > 0 ? "~\(TaskFormat.duration(estimate))" : nil)
            }
            VStack(spacing: 0) {
                ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                    TaskRow(task: task, isEditing: editing == task.id, isFocused: focus.taskId == task.id && focus.isActive,
                            isSelected: nav.selected == task.id, showTopic: grouping == "date" || name == tr("Top 3", "Top 3"),
                            toggle: { withAnimation(.snappy) { store.toggle(task.id) } },
                            edit: { nav.selected = task.id; withAnimation(.snappy) { toggleEditing(task.id) } },
                            startFocus: { startFocus(task) })
                        .id(task.id)
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
                            Image(systemName: "chevron.right").font(.fenn(size: 10, weight: .semibold)).rotationEffect(.degrees(showDone ? 90 : 0))
                            Text(tr("Erledigt, \(done.count)", "Done, \(done.count)")).font(.fenn(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(Fenn.fg.opacity(0.5))
                        .padding(.horizontal, 4)
                        .contentShape(Rectangle())
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

    /// ▶ opens the focus view on the task and starts the Pomodoro (or moves a running one over to it).
    private func startFocus(_ task: FennTask) {
        endEditing()
        FocusFlow.enter(task, focus: focus, nav: nav, start: true)
    }

    /// From the goals or week view: the task in the list with its editor open.
    private func openInList(_ task: FennTask) {
        topic = nil
        if task.done { showDone = true }
        withAnimation(.snappy) { mode = .list }
        nav.selected = task.id
        beginEditing(task.id)
    }

    // MARK: Keys

    /// The list as it is drawn, top to bottom – for ↑/↓.
    private var displayOrder: [FennTask] {
        let open = openTasks
        if topic != nil { return open }
        if grouping == "date" { return TaskGroups.make(open, by: "date").flatMap(\.tasks) }
        let top = open.filter(\.isStarred)
        let rest = open.filter { !$0.isStarred }
        let groups = Dictionary(grouping: rest) { $0.topicTitle }
        return top + groupOrder(rest, groups).flatMap { groups[$0] ?? [] }
    }

    private func handleKey(_ event: NSEvent, editing: Bool) -> Bool {
        let key = TaskKeyMonitor.key(event)
        let modifiers = TaskKeyMonitor.modifiers(event)
        let character = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if nav.paletteOpen {
            let items = paletteItems
            switch key {
            case .escape: nav.closePalette()
            case .up: nav.paletteIndex = max(0, nav.paletteIndex - 1)
            case .down: nav.paletteIndex = min(max(items.count - 1, 0), nav.paletteIndex + 1)
            case .enter:
                guard items.indices.contains(nav.paletteIndex) else { return true }
                let item = items[nav.paletteIndex]
                nav.closePalette()
                item.run()
            default: return false
            }
            return true
        }
        if modifiers == .command, character == "k" {
            endEditing()
            nav.openPalette()
            return true
        }
        if nav.focusOpen {
            let task = nav.focusTaskId.flatMap { id in store.open.first { $0.id == id } }
            if key == .escape { nav.closeFocus(); return true }
            if modifiers == .command, key == .enter, let task {
                FocusFlow.complete(task, store: store, focus: focus, nav: nav)
                return true
            }
            if !editing, modifiers.isEmpty, key == .space, let task {
                FocusFlow.startPause(task, focus: focus)
                return true
            }
            return false
        }
        guard !editing, modifiers.isEmpty || (modifiers == .shift && key == .other) else { return false }

        switch key {
        case .up, .down:
            guard mode == .list else { return false }
            let order = displayOrder
            guard !order.isEmpty else { return true }
            let index = nav.selected.flatMap { id in order.firstIndex { $0.id == id } }
            let next = index.map { key == .down ? min(order.count - 1, $0 + 1) : max(0, $0 - 1) } ?? (key == .down ? 0 : order.count - 1)
            if self.editing != nil { endEditing() }
            nav.selected = order[next].id
            return true
        case .space:
            guard mode == .list, let id = nav.selected, store.open.contains(where: { $0.id == id }) else { return false }
            let order = displayOrder
            let index = order.firstIndex { $0.id == id }
            withAnimation(.snappy) { store.toggle(id) }
            // The selection moves on to the row that takes its place.
            let rest = order.filter { $0.id != id }
            if let index, !rest.isEmpty { nav.selected = rest[min(index, rest.count - 1)].id } else { nav.selected = nil }
            return true
        case .escape, .enter, .other:
            break
        }
        switch character {
        case "n":
            if mode == .stats || mode == .day || mode == .timeline { withAnimation(.snappy) { mode = .list } }
            nav.focusAddRequest += 1
            return true
        case "f":
            let selected = nav.selected.flatMap { id in store.open.first { $0.id == id } }
            guard let task = selected ?? (mode == .list ? displayOrder.first : nil) ?? store.mainTask(on: FennVault.dayKey(Date())) ?? store.next(1).first else { return false }
            FocusFlow.enter(task, focus: focus, nav: nav, start: false)
            return true
        case "w":
            withAnimation(.snappy) { mode = .week }
            return true
        case "l":
            withAnimation(.snappy) { mode = .list }
            return true
        case "g":
            withAnimation(.snappy) { mode = .goals }
            return true
        default:
            return false
        }
    }

    // MARK: Palette

    /// Tasks, goals, the module's views, the other areas and a few actions – filtered by what's typed.
    private var paletteItems: [PaletteItem] {
        let query = nav.paletteQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let action = tr("Aktion", "Action")
        let commands = tr("Befehle", "Commands")
        var actions = [
            PaletteItem(id: "action.task", title: tr("Neue Aufgabe", "New task"), kind: action, symbol: "plus", group: commands) {
                if mode == .stats || mode == .day || mode == .timeline { mode = .list }
                nav.focusAddRequest += 1
            },
            PaletteItem(id: "action.goal", title: tr("Neues Ziel", "New goal"), kind: action, symbol: "flag", group: commands) {
                nav.pendingNewGoal = true
                withAnimation(.snappy) { mode = .goals }
            },
            PaletteItem(id: "action.week", title: tr("Woche planen", "Plan the week"), kind: action, symbol: "calendar", group: commands) {
                withAnimation(.snappy) { mode = .week }
            },
        ]
        let focusTarget = nav.selected.flatMap { id in store.open.first { $0.id == id } }
            ?? store.mainTask(on: FennVault.dayKey(Date())) ?? store.next(1).first
        if let focusTarget {
            actions.append(PaletteItem(id: "action.focus", title: tr("Fokus starten: \(focusTarget.title)", "Start focus: \(focusTarget.title)"),
                                       kind: action, symbol: "timer", group: commands) {
                FocusFlow.enter(focusTarget, focus: focus, nav: nav, start: true)
            })
        }
        actions.append(PaletteItem(id: "action.closeWeek", title: tr("Woche abschließen", "Close the week"), kind: action, symbol: "checkmark.seal", group: commands) {
            withAnimation(.snappy) { mode = .stats }
        })
        let views = Mode.allCases.filter { $0 != mode }.map { item in
            PaletteItem(id: "view.\(item.rawValue)", title: item.title, kind: tr("Ansicht", "View"), symbol: item.symbol, group: commands) {
                withAnimation(.snappy) { mode = item }
            }
        }
        let goals = store.activeGoals.map { goal in
            PaletteItem(id: "goal.\(goal.id)", title: goal.title, kind: GoalPlanner.weekLine(store.goalMinutes(goal.id, in: .thisWeek), target: goal.weeklyMinutes),
                        symbol: goal.symbol ?? "flag.checkered", group: tr("Ziele", "Goals")) {
                withAnimation(.snappy) { mode = .goals }
            }
        }
        let tasks = store.open.map { task in
            PaletteItem(id: "task.\(task.id)", title: task.title,
                        kind: store.goal(task.goalId)?.title ?? (task.topic.isEmpty ? tr("Aufgabe", "Task") : task.topic), symbol: "circle", group: tr("Aufgaben", "Tasks")) {
                openInList(task)
            }
        }
        let modules = IslandModule.allCases.filter { $0 != .tasks }.map { module in
            PaletteItem(id: "module.\(module.rawValue)", title: module.title, kind: tr("Bereich", "Area"), symbol: module.symbol, group: tr("Bereiche", "Areas")) {
                openModule(module)
            }
        }
        if query.isEmpty { return actions + views + goals + Array(tasks.prefix(5)) + modules }
        let matches: ([PaletteItem]) -> [PaletteItem] = { $0.filter { $0.title.lowercased().contains(query) || $0.kind.lowercased().contains(query) } }
        return Array((matches(actions + views) + matches(goals) + matches(tasks) + matches(modules)).prefix(40))
    }

    #if DEBUG
    /// QA only (demo): -FennQATasksMode focus|alldone|palette|select|edit opens that state; the mode itself comes from -fenn.tasks.mode.
    private func qaOpen() {
        guard FennDemo.isOn else { return }
        // -FennQAStopTimer YES: ends the demo Pomodoro a QA run left behind (and its pending notification).
        if UserDefaults.standard.bool(forKey: "FennQAStopTimer") { focus.stop() }
        // -FennQAKeys "down,space,g": the keys arrive through the event queue, like typed ones.
        if let script = UserDefaults.standard.string(forKey: "FennQAKeys") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { TaskKeyMonitor.qaType(script, into: keys.window) }
        }
        guard let state = UserDefaults.standard.string(forKey: "FennQATasksMode") else { return }
        switch state {
        case "focus":
            if let task = store.mainTask(on: FennVault.dayKey(Date())) ?? store.next(1).first {
                FocusFlow.enter(task, focus: focus, nav: nav, start: UserDefaults.standard.bool(forKey: "FennQAFocusRun"))
                if UserDefaults.standard.bool(forKey: "FennQAFocusComplete") { FocusFlow.complete(task, store: store, focus: focus, nav: nav) }
            }
        case "alldone":
            nav.focusFinished = []
            nav.focusTaskId = nil
            nav.focusOpen = true
        case "palette":
            nav.openPalette()
            nav.paletteQuery = UserDefaults.standard.string(forKey: "FennQAPaletteQuery") ?? ""
        case "select":
            nav.selected = displayOrder.dropFirst().first?.id
        case "edit":
            if let task = displayOrder.first { nav.selected = task.id; beginEditing(task.id) }
        default: break
        }
    }
    #endif
}

// MARK: - Row

/// Title and one quiet line under it: goal (or topic), date, estimate, repeat. ▶ shows on hover.
struct TaskRow: View {
    let task: FennTask
    let isEditing: Bool
    let isFocused: Bool
    /// Picked with ↑/↓.
    var isSelected = false
    /// The goal in the second line – off inside the goal's own list.
    var showGoal = true
    /// The topic in the second line when there is no goal (off when the list is grouped by topic).
    var showTopic = false
    let toggle: () -> Void
    let edit: () -> Void
    let startFocus: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: toggle) {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(.fenn(size: 18, weight: .light))
                    .foregroundStyle(task.done ? Fenn.accent : task.priority.color)
            }
            .buttonStyle(.plain)
            .frame(width: 22)
            .help(task.done ? tr("Wieder öffnen", "Reopen") : tr("Erledigt", "Done"))

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.fenn(size: 13.5))
                    .foregroundStyle(task.done ? Fenn.fg.opacity(0.45) : Fenn.fg)
                    .strikethrough(task.done, color: Fenn.fg.opacity(0.3))
                    .lineLimit(2)
                if !task.done, let line = secondary {
                    line.font(.fenn(size: 11.5)).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if task.isStarred && !task.done {
                Image(systemName: "star.fill").font(.fenn(size: 10)).foregroundStyle(Fenn.amber).help(tr("Top 3", "Top 3"))
            }
            if isFocused {
                Image(systemName: "timer").font(.fenn(size: 13, weight: .medium)).foregroundStyle(Fenn.accent).help(tr("Läuft im Fokus", "In focus"))
            } else if !task.done, hovering || isEditing {
                Button(action: startFocus) { Image(systemName: "play.fill").font(.fenn(size: 11)) }
                    .buttonStyle(FennIconButtonStyle())
                    .help(tr("Fokus auf diese Aufgabe (F)", "Focus on this task (F)"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(isEditing ? Fenn.fill : (isSelected ? Fenn.accent.opacity(0.1) : .clear))
        .onTapGesture(perform: edit)
        .onHover { hovering = $0 }
        .contextMenu {
            let store = TaskStore.shared
            if !task.done {
                Button(task.isStarred ? tr("Aus den Top 3", "Remove from top 3") : tr("In die Top 3", "Into the top 3")) { withAnimation(.snappy) { store.toggleStar(task.id) } }
                let today = FennVault.dayKey(Date())
                Button(task.mainDay == today ? tr("Nicht mehr „Heute zuerst“", "No longer “First today”") : tr("Heute zuerst", "First today")) {
                    withAnimation(.snappy) { store.setMain(task.mainDay == today ? nil : task.id, on: today) }
                }
                if !store.activeGoals.isEmpty {
                    Menu(tr("Ziel", "Goal")) {
                        ForEach(store.activeGoals) { goal in
                            Button(goal.title) { var copy = task; copy.goalId = goal.id; store.update(copy) }
                        }
                        if task.goalId != nil {
                            Divider()
                            Button(tr("Kein Ziel", "No goal")) { var copy = task; copy.goalId = nil; store.update(copy) }
                        }
                    }
                }
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

    /// "Nordlicht-Pitch gewinnen · morgen · 2:30 h / 4 h · ↻" – colour only for the date's state and an overrun.
    private var secondary: Text? {
        let muted = Fenn.fg.opacity(0.55)
        var parts: [Text] = []
        if showGoal, let goal = TaskStore.shared.goal(task.goalId) {
            parts.append(Text(goal.title))
        } else if showTopic, !task.topic.isEmpty {
            parts.append(Text(task.topic))
        }
        if let due = task.due {
            let color = task.isOverdue ? Fenn.danger : (task.isDueToday ? Fenn.amber : muted)
            parts.append(Text(dateText(due)).foregroundColor(color))
        }
        if let estimate = task.estimateMinutes {
            parts.append(task.spentMinutes > 0
                         ? Text("\(TaskFormat.duration(task.spentMinutes)) / \(TaskFormat.duration(estimate))").foregroundColor(task.spentMinutes > estimate ? Fenn.danger : muted)
                         : Text("~\(TaskFormat.duration(estimate))"))
        } else if task.spentMinutes > 0 {
            parts.append(Text(TaskFormat.duration(task.spentMinutes)))
        }
        if task.repeatRule != nil { parts.append(Text(Image(systemName: "repeat"))) }
        guard let first = parts.first else { return nil }
        return parts.dropFirst().reduce(first) { $0 + Text(" · ") + $1 }.foregroundColor(muted)
    }

    private func dateText(_ due: Date) -> String {
        if let start = task.start, start < due, !Calendar.current.isDate(start, inSameDayAs: due) {
            return "\(TaskFormat.day(start)) – \(TaskFormat.when(due))"
        }
        return TaskFormat.when(due)
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
    private static let logChoices = [15, 25, 30, 45, 50, 60, 90, 120, 180]
    @State private var logMinutes = 25
    /// When the logged minutes ended.
    @State private var logEnd = Date()
    @State private var logged: String?

    /// "Mehr": priority, topic, start and time, repeat, appointment, log time.
    @State private var more = TaskEditor.qaMore

    /// QA only (demo): -FennQAEditorMore YES opens "Mehr".
    private static var qaMore: Bool {
        #if DEBUG
        return FennDemo.isOn && UserDefaults.standard.bool(forKey: "FennQAEditorMore")
        #else
        return false
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(tr("Titel", "Title"), text: $task.title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.fenn(size: 15, weight: .medium))
                .onSubmit(commit)

            HStack(spacing: 6) {
                goalMenu
                dateMenu
                estimateMenu
                Spacer(minLength: 0)
            }

            Button { withAnimation(.snappy) { more.toggle() } } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right").font(.fenn(size: 9, weight: .semibold)).rotationEffect(.degrees(more ? 90 : 0))
                    Text(more ? tr("Weniger", "Less") : tr("Mehr: Priorität, Uhrzeit, Wiederholen, Zeit nachtragen …", "More: priority, time, repeat, log time …"))
                        .font(.fenn(size: 12))
                }
                .foregroundStyle(Fenn.fg.opacity(0.55))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if more { grid.transition(.opacity) }

            HStack(spacing: 10) {
                Button(action: { commit(); startFocus() }) { Label(tr("Fokus", "Focus"), systemImage: "play.fill").font(.fenn(size: 12, weight: .medium)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Fenn.fg.opacity(0.75))
                    .help(tr("Fokusansicht mit Pomodoro", "Focus view with Pomodoro"))
                Spacer()
                Button { store.delete(task.id); close() } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Fenn.fg.opacity(0.45))
                    .help(tr("Löschen", "Delete"))
                    .accessibilityLabel(tr("Löschen", "Delete"))
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

    /// A small pull-down: symbol, value, chevron.
    private func pullLabel(_ symbol: String, _ text: String, set: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.fenn(size: 10, weight: .medium))
            Text(text).lineLimit(1)
            Image(systemName: "chevron.down").font(.fenn(size: 8, weight: .semibold)).opacity(0.5)
        }
        .font(.fenn(size: 12, weight: .medium))
        .foregroundStyle(set ? Fenn.fg.opacity(0.85) : Fenn.fg.opacity(0.55))
    }

    private var goalMenu: some View {
        Menu {
            ForEach(store.activeGoals) { goal in Button(goal.title) { task.goalId = goal.id } }
            if !store.activeGoals.isEmpty { Divider() }
            Button(tr("Kein Ziel", "No goal")) { task.goalId = nil }
        } label: {
            pullLabel("flag", store.goal(task.goalId)?.title ?? tr("Ziel", "Goal"), set: task.goalId != nil)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help(tr("Zu welchem Ziel diese Aufgabe gehört (auch mit @Ziel beim Anlegen)", "Which goal this task belongs to (also @goal when adding)"))
    }

    private var dateMenu: some View {
        Menu {
            Button(tr("Heute", "Today")) { setDay(0) }
            Button(tr("Morgen", "Tomorrow")) { setDay(1) }
            Button(tr("Nächste Woche", "Next week")) {
                let calendar = Calendar.current
                let monday = calendar.nextDate(after: Date(), matching: DateComponents(weekday: 2), matchingPolicy: .nextTime) ?? Date()
                setDay(calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: monday)).day ?? 7)
            }
            Button(tr("Datum wählen …", "Pick a date …")) {
                if task.due == nil { task.due = Calendar.current.startOfDay(for: Date()) }
                withAnimation(.snappy) { more = true }
            }
            if task.due != nil {
                Divider()
                Button(tr("Kein Datum", "No date")) { task.due = nil }
            }
        } label: {
            pullLabel("calendar", task.due.map(TaskFormat.when) ?? tr("Datum", "Date"), set: task.due != nil)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }

    private var estimateMenu: some View {
        Menu {
            ForEach(Self.estimates, id: \.self) { minutes in Button(TaskFormat.duration(minutes)) { task.estimateMinutes = minutes } }
            Divider()
            Button(tr("Keine Schätzung", "No estimate")) { task.estimateMinutes = nil }
        } label: {
            pullLabel("hourglass", task.estimateMinutes.map { "~\(TaskFormat.duration($0))" } ?? tr("Dauer", "Estimate"), set: task.estimateMinutes != nil)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }

    /// A new day keeps the time the task had.
    private func setDay(_ offset: Int) {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: Date())) ?? Date()
        if let due = task.due, DayPlanner.hasTime(due) {
            let parts = calendar.dateComponents([.hour, .minute], from: due)
            task.due = calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: day)
        } else {
            task.due = day
        }
        if let start = task.start, let due = task.due, start > due { task.start = nil }
    }

    private var grid: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                label("number", tr("Thema", "Topic"))
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
            if task.spentMinutes > 0 {
                GridRow {
                    label("timer", tr("Im Fokus", "In focus"))
                    Text(TaskFormat.duration(task.spentMinutes)).font(.fenn(size: 13)).foregroundStyle(Fenn.fg.opacity(0.7))
                }
            }
            GridRow {
                label("clock.arrow.circlepath", tr("Nachtragen", "Log time"))
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Menu {
                            ForEach(Self.logChoices, id: \.self) { minutes in Button(TaskFormat.duration(minutes)) { logMinutes = minutes } }
                        } label: {
                            Text(TaskFormat.duration(logMinutes)).font(.fenn(size: 13))
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        Text(tr("bis", "until")).font(.fenn(size: 12)).foregroundStyle(Fenn.fg.opacity(0.5))
                        DatePicker("", selection: $logEnd, in: ...Date().addingTimeInterval(60), displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden().datePickerStyle(.field).fixedSize()
                    }
                    HStack(spacing: 8) {
                        Button(tr("Eintragen", "Log")) { logTime() }
                            .buttonStyle(.plain).font(.fenn(size: 12, weight: .medium)).foregroundStyle(Fenn.accent)
                            .help(tr("Zeit, die ohne Timer an der Aufgabe gearbeitet wurde – zählt für Fokus und Ziel", "Time worked on the task without the timer – counts for focus and the goal"))
                        Text(logged ?? tr("ohne Timer gearbeitet? Zählt für Fokus und Ziel", "worked without the timer? Counts for focus and goal"))
                            .font(.fenn(size: 11)).foregroundStyle(logged == nil ? Fenn.fg.opacity(0.45) : Fenn.accent).lineLimit(1)
                    }
                }
            }
        }
    }

    /// Minutes worked without the timer: a focus session ending at `logEnd`, so the hours count for the day and the goal.
    private func logTime() {
        commit()
        let end = min(logEnd, Date())
        store.logFocus(minutes: logMinutes, taskId: task.id, title: task.title, start: end.addingTimeInterval(Double(-logMinutes * 60)))
        // The store added the minutes – the editor's copy follows, or closing would write the old number back.
        if let saved = store.tasks.first(where: { $0.id == task.id }) { task.spentMinutes = saved.spentMinutes }
        logged = tr("+\(TaskFormat.duration(logMinutes)) eingetragen", "+\(TaskFormat.duration(logMinutes)) logged")
        logEnd = Date()
    }

    private func label(_ symbol: String, _ title: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.fenn(size: 12))
            .foregroundStyle(Fenn.fg.opacity(0.55))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: 100, alignment: .leading)
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
struct WrapLayout: Layout {
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
    /// "Woche abschließen": the week check goes into today's journal, then next week opens.
    var closeWeek: () -> Void = {}
    @State private var period = Period.week
    @State private var weekClosed = false

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

            thisWeek
            topics(range)
            if period != .today { daily(range) }
            accuracy(range)
        }
    }

    /// Per goal: hours against the weekly target, steps done, what slipped – and the button that closes the week.
    private var thisWeek: some View {
        let goals = GoalPlanner.week(store)
        let today = Calendar.current.startOfDay(for: Date())
        let looseSlipped = store.open.filter { $0.goalId == nil && ($0.due.map { DateInterval.thisWeek.contains($0) && $0 < today } ?? false) }
        return card(tr("Diese Woche", "This week")) {
            if goals.isEmpty {
                Text(tr("Noch keine Ziele. In „Ziele“ (G) legst du eins an – dann siehst du hier, wie viele Stunden hineingeflossen sind.",
                        "No goals yet. Add one under “Goals” (G) – then you see here how many hours went in."))
                    .font(.fenn(size: 12)).foregroundStyle(Fenn.fg.opacity(0.55))
            }
            ForEach(goals) { item in
                HStack(spacing: 10) {
                    GoalRing(minutes: item.minutes, target: item.goal.weeklyMinutes, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.goal.title).font(.fenn(size: 13, weight: .medium)).foregroundStyle(Fenn.fg).lineLimit(1)
                        Text(weekLine(item)).font(.fenn(size: 11.5))
                            .foregroundStyle(item.slipped.isEmpty ? Fenn.fg.opacity(0.55) : Fenn.amber)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if !looseSlipped.isEmpty {
                Text(tr("Ohne Ziel verrutscht: ", "Slipped without a goal: ") + looseSlipped.prefix(4).map(\.title).joined(separator: ", "))
                    .font(.fenn(size: 11)).foregroundStyle(Fenn.fg.opacity(0.55))
            }
            HStack(spacing: 10) {
                Button {
                    closeWeek()
                    weekClosed = true
                } label: {
                    Label(tr("Woche abschließen", "Close the week"), systemImage: "checkmark.seal").font(.fenn(size: 12, weight: .medium))
                }
                .buttonStyle(FennPillButtonStyle(prominent: weekIsEnding))
                .help(tr("Schreibt einen kurzen Wochen-Check ins heutige Journal und öffnet die nächste Woche zum Planen",
                         "Writes a short week check into today's journal and opens next week for planning"))
                Text(weekClosed ? tr("Im Journal von heute.", "In today's journal.") : tr("Kurzer Check ins Journal, dann nächste Woche planen.", "A short check into the journal, then plan next week."))
                    .font(.fenn(size: 11)).foregroundStyle(Fenn.fg.opacity(0.5))
            }
            .padding(.top, 2)
        }
    }

    /// Friday afternoon to Sunday: closing the week is the thing to do.
    private var weekIsEnding: Bool {
        let now = Date()
        let weekday = Calendar.current.component(.weekday, from: now)
        return weekday == 1 || weekday == 7 || (weekday == 6 && Calendar.current.component(.hour, from: now) >= 12)
    }

    /// "3,7 von 8 h · 1 Schritt erledigt · verrutscht: …"
    private func weekLine(_ item: GoalPlanner.GoalWeek) -> String {
        let hours = item.goal.weeklyMinutes.map { tr("\(GoalPlanner.hours(item.minutes)) von \(GoalPlanner.hours($0)) h", "\(GoalPlanner.hours(item.minutes)) of \(GoalPlanner.hours($0)) h") }
            ?? "\(GoalPlanner.hours(item.minutes)) h"
        var parts = [hours, GoalPlanner.stepsDone(item.done.count)]
        if !item.slipped.isEmpty { parts.append(tr("verrutscht: ", "slipped: ") + item.slipped.prefix(3).map(\.title).joined(separator: ", ")) }
        return parts.joined(separator: " · ")
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
            Text(title).font(.fenn(size: 13, weight: .semibold)).foregroundStyle(Fenn.fg.opacity(0.6))
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
    /// A tooltip per segment (macOS: say the shortcut there).
    var help: ((Value) -> String?)? = nil

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
                .help(help?(option) ?? "")
            }
        }
        .padding(3)
        .background(Capsule().fill(Fenn.fill))
        .fixedSize()
    }
}
