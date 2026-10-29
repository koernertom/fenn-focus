import SwiftUI
import FennFocusCore

struct TodayModuleView: View {
    @ObservedObject var focus: FocusTimer
    let openModule: (IslandModule) -> Void
    @ObservedObject private var calendar = WorkCalendar.shared
    @AppStorage(HomeLayout.key) private var layoutRaw = HomeLayout.defaultModules
    @AppStorage(DayCalendarSize.key) private var calendarSizeRaw = DayCalendarSize.medium.rawValue
    @State private var customizing = false
    /// The mode being edited (a new one when its title is empty); nil = Today as usual.
    @State private var editingMode: MacMode?? = FennDemo.isOn && UserDefaults.standard.bool(forKey: "FennQAModeEditor") ? .some(MacMode.all[1]) : nil
    @AppStorage(HomeLayout.sizesKey) private var sizesRaw = ""
    // The active mode decides the home, too – watched so a switch redraws it right away.
    @AppStorage(MacMode.key) private var modeRaw = MacMode.own.id
    @AppStorage(MacMode.listKey) private var modesData = Data()
    @AppStorage(MacMode.orderKey) private var barOrderRaw = ""
    @State private var hovered: HomeModule?
    @State private var dropTarget: HomeModule?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if customizing {
                HomeLayoutEditor { customizing = false }
            } else if let editing = editingMode {
                MacModeEditor(mode: editing) { editingMode = nil }
            } else {
                home
            }
        }
    }

    /// Focus time and routines side by side, the numbers in Fenn Dots.
    @ViewBuilder
    private var dayTiles: some View {
        let habits = HabitStore.shared.active.filter { $0.isScheduled(on: Date()) }
        let done = habits.filter { HabitStore.shared.isDone($0) }.count
        let focusMinutes = TaskStore.shared.focusMinutes(in: .today)
        HStack(spacing: 10) {
            tile(value: String(format: "%d:%02d", focusMinutes / 60, focusMinutes % 60), label: tr("Fokus heute", "Focus today")) { openModule(.focus) }
            if !habits.isEmpty {
                tile(value: "\(done)/\(habits.count)", label: tr("Routinen", "Routines")) { openModule(.habits) }
            }
        }
    }

    private func tile(value: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                DotMatrixText(text: value, height: 24)
                Text(label).font(.fenn(size: 11)).foregroundStyle(Fenn.fg.opacity(0.55))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .modifier(TileSurface())
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Self.kicker)
                            .font(.fenn(size: 11, weight: .medium))
                            .tracking(1.2)
                            .foregroundStyle(Fenn.fg.opacity(0.55))
                        Text(Self.greeting)
                            .font(Fenn.display(24))
                            .foregroundStyle(Fenn.fg)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                }
                .modifier(CardRise(index: 0))

                // Modes swap the module bar.
                ScrollView(.horizontal, showsIndicators: false) { MacModeSwitcher { editingMode = .some($0) } }
                    .modifier(CardRise(index: 0))

                dayTiles.modifier(CardRise(index: 0))

                if focus.isActive {
                    Button { openModule(.focus) } label: {
                        HStack {
                            FennOrb(size: 12)
                            Text("\(focus.phaseTitle), \(focus.taskTitle)").font(.fenn(size: 13, weight: .medium))
                            Spacer()
                            DotMatrixText(text: focus.label, height: 14, color: Fenn.accent)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Fenn.accent.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .modifier(CardRise(index: 1))
                }

                let _ = (modeRaw, modesData, barOrderRaw)
                let mode = MacMode.current
                let modules = mode.home ?? HomeLayout.modules(layoutRaw)
                grid(modules)
                    .id(mode.home == nil ? "own" : mode.id)
                    .transition(.opacity.combined(with: .offset(y: 10)))
                    .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.8), value: modeRaw)

                // In a mode with its own home, "anpassen" edits that mode's few tiles.
                Button { if mode.home != nil { editingMode = .some(mode) } else { customizing = true } } label: {
                    Label(modules.isEmpty ? tr("Startseite einrichten", "Set up home")
                          : mode.home != nil ? tr("Startseite für \(mode.title) anpassen", "Customise home for \(mode.title)")
                          : tr("Startseite anpassen", "Customise home"),
                          systemImage: "square.grid.2x2")
                        .font(.fenn(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(FennPillButtonStyle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
        .onAppear { TaskStore.shared.reload() }
    }

    // MARK: Bento grid

    private func size(_ module: HomeModule) -> HomeTileSize { HomeLayout.size(of: module, in: sizesRaw) }

    /// Wide tiles fill a row, small ones sit two side by side. Drag a tile onto another to move it there,
    /// drag its corner sideways to make it small or wide.
    private func grid(_ modules: [HomeModule]) -> some View {
        let rows = HomeLayout.rows(modules, size: size)
        return VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(rows.enumerated()), id: \.element) { rowIndex, row in
                HStack(alignment: .top, spacing: 14) {
                    ForEach(row) { module in
                        tile(module, in: modules, index: (modules.firstIndex(of: module) ?? 0) + 1)
                    }
                    if row.count == 1, size(row[0]) == .s {
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                    }
                }
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.78), value: layoutRaw)
        .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.78), value: modesData)
        .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.78), value: sizesRaw)
    }

    private func tile(_ module: HomeModule, in modules: [HomeModule], index: Int) -> some View {
        self.module(module)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .overlay(alignment: .bottomTrailing) {
                if hovered == module {
                    ResizeGrip(size: size(module)) { new in resize(module, to: new) }
                        .padding(6)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .overlay {
                if dropTarget == module {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Fenn.accent, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                        .allowsHitTesting(false)
                }
            }
            .scaleEffect(dropTarget == module ? 1.015 : 1)
            .onHover { inside in
                withAnimation(.easeOut(duration: 0.15)) {
                    if inside { hovered = module } else if hovered == module { hovered = nil }
                }
            }
            .draggable(module.rawValue) {
                Label(module.title, systemImage: module.symbol)
                    .font(.fenn(size: 13, weight: .medium))
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Capsule().fill(Fenn.canvas))
            }
            .dropDestination(for: String.self) { items, _ in
                guard let raw = items.first, let moved = HomeModule(rawValue: raw), moved != module else { return false }
                var order = modules
                order.removeAll { $0 == moved }
                let target = order.firstIndex(of: module) ?? order.count
                // Dropped on a tile further down: it lands after it, otherwise before.
                let wasBelow = (modules.firstIndex(of: moved) ?? 0) < (modules.firstIndex(of: module) ?? 0)
                order.insert(moved, at: wasBelow ? min(target + 1, order.count) : target)
                storeHome(order)
                return true
            } isTargeted: { over in
                withAnimation(.easeOut(duration: 0.15)) {
                    if over { dropTarget = module } else if dropTarget == module { dropTarget = nil }
                }
            }
            .contextMenu { moduleMenu(module, in: modules) }
            .modifier(CardRise(index: min(index, 6)))
    }

    /// Moving or hiding a tile changes the active mode's home if it has one, else your own.
    private func storeHome(_ order: [HomeModule]) {
        var mode = MacMode.current
        if mode.home != nil {
            mode.homeTiles = order.map(\.rawValue)
            MacMode.store(mode)
        } else {
            layoutRaw = HomeLayout.store(order)
        }
    }

    private func resize(_ module: HomeModule, to new: HomeTileSize) {
        guard new != size(module) else { return }
        sizesRaw = HomeLayout.storing(new, for: module, in: sizesRaw)
    }

    /// Focus timer plus – if apps are chosen – the app block, then the focus view.
    private func startFocusBlock() {
        if !focus.isActive { focus.start() }
        let blocker = MacBlocker.shared
        if !blocker.apps.isEmpty, !blocker.isActive, !blocker.withFocus { blocker.start(minutes: 25, fromFocus: true) }
        openModule(.focus)
    }

    @ViewBuilder
    private func module(_ module: HomeModule) -> some View {
        switch module {
        case .calendar:
            VStack(alignment: .leading, spacing: 12) {
                AgendaCard(calendar: calendar,
                           startFocus: { until in
                               focus.focus(on: nil)
                               focus.taskTitle = tr("Fokuszeit bis \(AgendaCard.time(until))", "Focus until \(AgendaCard.time(until))")
                               startFocusBlock()
                           },
                           openConnections: { openModule(.connectors) })
                if calendar.enabled {
                    DayCalendarCardMac(openTasks: { openModule(.tasks) })
                }
            }
        case .habits:
            HabitsTodayCard(store: HabitStore.shared) { openModule(.habits) }
        case .tasks:
            WorkTodayCard(store: TaskStore.shared, focus: focus,
                          startTask: { task in
                              focus.focus(on: task)
                              startFocusBlock()
                          },
                          openTasks: { openModule(.tasks) })
        case .slipping:
            SlippingCard(store: TaskStore.shared)
        case .focus:
            HomeShortcutCardMac(title: tr("Fokus starten", "Start focus"),
                                subtitle: tr("Timer, Apps sperren, dranbleiben", "Timer, block apps, stay on it"),
                                symbol: "timer") { openModule(.focus) }
        case .journal:
            VStack(alignment: .leading, spacing: 12) {
                HomeShortcutCardMac(title: tr("Tag festhalten", "Capture the day"),
                                    subtitle: tr("Ein paar Zeilen ins Journal", "A few lines in the journal"),
                                    symbol: "book.closed") { openModule(.journal) }
                ResurfaceCard()
            }
        }
    }

    @ViewBuilder
    private func moduleMenu(_ module: HomeModule, in modules: [HomeModule]) -> some View {
        if let index = modules.firstIndex(of: module), index > 0 {
            Button(tr("Ganz nach oben", "Move to top"), systemImage: "arrow.up.to.line") {
                var order = modules
                order.remove(at: index)
                order.insert(module, at: 0)
                withAnimation(.snappy) { storeHome(order) }
            }
        }
        Picker(tr("Breite", "Width"), selection: Binding(get: { size(module) }, set: { resize(module, to: $0) })) {
            Text(tr("Halb", "Half")).tag(HomeTileSize.s)
            Text(tr("Ganz", "Full")).tag(HomeTileSize.l)
        }
        Button(tr("Ausblenden", "Hide"), systemImage: "eye.slash") {
            withAnimation(.snappy) { storeHome(modules.filter { $0 != module }) }
        }
        if module == .calendar {
            Picker(tr("Größe", "Size"), selection: Binding(
                get: { DayCalendarSize(rawValue: calendarSizeRaw) ?? .medium },
                set: { calendarSizeRaw = $0.rawValue }
            )) {
                ForEach(DayCalendarSize.allCases) { Text($0.title).tag($0) }
            }
        }
        Button(tr("Startseite anpassen …", "Customise home …"), systemImage: "square.grid.2x2") { customizing = true }
    }

    private static var kicker: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.usesEnglish ? "en" : "de")
        formatter.dateFormat = "EEEE, d. MMMM"
        return formatter.string(from: Date()).uppercased()
    }

    static var greeting: String {
        let hour = Calendar.current.component(.hour, from: FennDemo.now)
        let salutation = hour < 11 ? tr("Guten Morgen", "Good morning")
            : hour < 17 ? tr("Hallo", "Hello")
            : tr("Guten Abend", "Good evening")
        let name = FennDemo.isOn ? FennDemo.person : PersonProfileStore.shared.firstName
        return name.isEmpty ? "\(salutation)." : "\(salutation), \(name)."
    }
}

/// Work on Today: focus time and tasks done so far, and the next three tasks – ▶ starts a focus block on one.
struct WorkTodayCard: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var focus: FocusTimer
    let startTask: (FennTask) -> Void
    let openTasks: () -> Void

    var body: some View {
        let next = store.next(3)
        let focusMinutes = store.focusMinutes(in: .today)
        let due = store.open.filter { $0.isOverdue || $0.isDueToday }.count
        VStack(alignment: .leading, spacing: 10) {
            Button(action: openTasks) {
                HStack(spacing: 14) {
                    Text(tr("ARBEIT HEUTE", "WORK TODAY"))
                        .font(.fenn(size: 11, weight: .medium)).tracking(1.2).foregroundStyle(Fenn.fg.opacity(0.55))
                    Spacer()
                    figure("timer", focusMinutes == 0 ? "0" : String(format: "%d:%02d", focusMinutes / 60, focusMinutes % 60), tr("Fokus", "Focus"))
                    figure("checkmark", "\(store.doneCount(in: .today))", tr("Erledigt", "Done"))
                    if due > 0 { figure("calendar", "\(due)", tr("Fällig", "Due")) }
                    Image(systemName: "chevron.right").font(.fenn(size: 11)).foregroundStyle(Fenn.fg.opacity(0.4))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(tr("Alle Aufgaben", "All tasks"))

            if next.isEmpty {
                Button(action: openTasks) {
                    Label(tr("Aufgabe anlegen", "Add a task"), systemImage: "plus")
                        .font(.fenn(size: 13)).foregroundStyle(Fenn.fg.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(next.enumerated()), id: \.element.id) { index, task in
                        TaskRow(task: task, isEditing: false, isFocused: focus.taskId == task.id && focus.isActive,
                                toggle: { withAnimation(.snappy) { store.toggle(task.id) } },
                                edit: openTasks,
                                startFocus: { startTask(task) })
                        if index < next.count - 1 { Rectangle().fill(Fenn.hairline).frame(height: 1).padding(.leading, 44) }
                    }
                }
                .padding(.horizontal, -12)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fennGlass(cornerRadius: 22, shadow: false)
    }

    private func figure(_ symbol: String, _ value: String, _ title: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.fenn(size: 10, weight: .semibold)).foregroundStyle(Fenn.accent)
            Text(value).font(.fenn(size: 13, weight: .medium).monospacedDigit()).foregroundStyle(Fenn.fg)
        }
        .help(title)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)")
    }
}

/// Cards settle in one after another. Soft ease, no bounce.
/// Tiles pop in one after another: up from a little below, out of a soft blur, with a small overshoot.
private struct CardRise: ViewModifier {
    var index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown || reduceMotion ? 1 : 0.94, anchor: .bottom)
            .offset(y: shown || reduceMotion ? 0 : 18)
            .blur(radius: shown || reduceMotion ? 0 : 6)
            .onAppear {
                let animation: Animation = reduceMotion ? .easeOut(duration: 0.25) : .spring(response: 0.5, dampingFraction: 0.68)
                withAnimation(animation.delay(0.05 + Double(index) * 0.06)) { shown = true }
            }
    }
}

/// The small handle in a tile's corner: drag sideways (or click) to switch between half and full width.
private struct ResizeGrip: View {
    let size: HomeTileSize
    let change: (HomeTileSize) -> Void
    @State private var pull: CGFloat = 0

    var body: some View {
        Image(systemName: size == .l ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
            .font(.fenn(size: 10, weight: .bold))
            .foregroundStyle(Fenn.fg.opacity(0.7))
            .frame(width: 24, height: 24)
            .background(Circle().fill(Fenn.canvas))
            .overlay(Circle().strokeBorder(Fenn.hairline))
            .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
            .offset(x: pull)
            .contentShape(Circle())
            .onTapGesture { change(size == .l ? .s : .l) }
            .gesture(DragGesture(minimumDistance: 4)
                .onChanged { pull = max(-40, min(40, $0.translation.width / 3)) }
                .onEnded { value in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { pull = 0 }
                    if value.translation.width < -30 { change(.s) } else if value.translation.width > 30 { change(.l) }
                })
            .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
            .help(tr("Ziehen oder klicken: halbe oder ganze Breite", "Drag or click: half or full width"))
            .accessibilityLabel(tr("Breite ändern", "Change width"))
    }
}

/// The small number tiles: a white card in Fenn Weiß, a soft tint everywhere else.
struct TileSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        if Fenn.scheme.solidWhite && scheme == .light {
            content.fennGlass(cornerRadius: 16, shadow: false)
        } else {
            content.background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Fenn.fg.opacity(0.07)))
        }
    }
}

/// Today hour by hour under "Dein Tag" – meetings grey, timed tasks in colour – in the size picked on the card
/// (next 3 hours, next 6, whole day; stored per Mac). Click a task → Tasks.
private struct DayCalendarCardMac: View {
    let openTasks: () -> Void
    @AppStorage(DayCalendarSize.key) private var sizeRaw = DayCalendarSize.medium.rawValue

    var body: some View {
        let size = Binding(get: { DayCalendarSize(rawValue: sizeRaw) ?? .medium },
                           set: { new in withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { sizeRaw = new.rawValue } })
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Text(tr("KALENDER HEUTE", "TODAY'S CALENDAR")).font(.fenn(size: 11, weight: .medium)).tracking(1.2).foregroundStyle(Fenn.fg.opacity(0.55))
                Spacer(minLength: 0)
                DayCalendarSizeMenu(size: size)
                    .help(tr("Größe: nächste 3 Std., 6 Std. oder ganzer Tag", "Size: next 3 hours, 6 hours or the whole day"))
                Button(action: openTasks) {
                    Image(systemName: "chevron.right").font(.fenn(size: 11, weight: .semibold)).foregroundStyle(Fenn.fg.opacity(0.35))
                        .frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tr("Aufgaben öffnen", "Open tasks"))
            }
            // Ticks every minute, so the window and the red now-line move along.
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                DayTimelineView(day: Date(), size: size.wrappedValue) { _ in openTasks() }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fennGlass(cornerRadius: 22, shadow: false)
    }
}
