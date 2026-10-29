import SwiftUI
import FennFocusCore

struct IslandActions {
    var toggle: () -> Void
    var collapse: () -> Void
    var setPlacement: (IslandPlacement) -> Void
    /// Drag the collapsed pill around (false while moving, true on release).
    var movePill: (Bool) -> Void = { _ in }
    var chooseAudio: () -> Void
    var chooseCloudFolder: (SyncProvider) -> Void
    var openWindow: () -> Void
    var finishOnboarding: () -> Void
    var quit: () -> Void
}

struct IslandRootView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var focus: FocusTimer
    @ObservedObject var coach: CoachViewModel
    @ObservedObject var knowledge: KnowledgeStore
    let services: IslandServices
    let actions: IslandActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let geometry = model.geometry
        Group {
            switch geometry.placement {
            case .top:
                VStack(spacing: IslandGeometry.gap) {
                    bar
                    if model.isExpanded { panel(anchor: .top) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            case .left:
                HStack(spacing: IslandGeometry.gap) {
                    bar
                    if model.isExpanded { panel(anchor: .leading) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            case .right:
                HStack(spacing: IslandGeometry.gap) {
                    if model.isExpanded { panel(anchor: .trailing) }
                    bar
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.84), value: model.isExpanded)
        .fennScheme()
    }

    private var bar: some View {
        IslandBar(
            geometry: model.geometry,
            focus: focus,
            dictation: services.dictation,
            noteDictation: services.noteDictation,
            isExpanded: model.isExpanded,
            action: actions.toggle,
            move: actions.movePill,
            pillScale: $model.pillScale,
            toEdge: { actions.setPlacement(model.geometry.placement) }
        )
    }

    private func panel(anchor: UnitPoint) -> some View {
        PanelCard(
            model: model,
            focus: focus,
            coach: coach,
            knowledge: knowledge,
            dictation: services.dictation,
            ai: services.ai,
            services: services,
            actions: actions
        )
            .transition(reduceMotion ? .opacity : .scale(scale: 0.94, anchor: anchor).combined(with: .opacity))
    }
}

/// Black where it hugs the camera notch, a glass pill everywhere else (under the menu bar or on a screen edge).
struct IslandBar: View {
    let geometry: IslandGeometry
    @ObservedObject var focus: FocusTimer
    @ObservedObject var dictation: DictationController
    @ObservedObject var noteDictation: DictationController
    let isExpanded: Bool

    private var listening: DictationController? {
        dictation.isListening ? dictation : (noteDictation.isListening ? noteDictation : nil)
    }
    let action: () -> Void
    var move: (Bool) -> Void = { _ in }
    @Binding var pillScale: CGFloat
    var toEdge: () -> Void = {}
    /// A drag ends with a mouse-up on the pill – that must not also open it.
    @State private var lastDrag = Date.distantPast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var statusKey: String {
        if listening != nil { return "listening" }
        if focus.isActive { return "focus" }
        return "idle"
    }

    var body: some View {
        let size = geometry.collapsedSize
        let s = geometry.isVertical ? geometry.pillScale : 1
        Button {
            if Date().timeIntervalSince(lastDrag) > 0.3 { action() }
        } label: {
            Group {
                if geometry.usesNotch {
                    HStack(spacing: 0) {
                        leading
                            .padding(.leading, 14)
                            .frame(width: IslandGeometry.sideWidth, alignment: .leading)
                        Color.clear.frame(width: geometry.notchWidth)
                        timer
                            .padding(.trailing, 14)
                            .frame(width: IslandGeometry.sideWidth, alignment: .trailing)
                    }
                    .frame(width: size.width, height: size.height)
                    .background(
                        UnevenRoundedRectangle(
                            bottomLeadingRadius: size.height / 2,
                            bottomTrailingRadius: size.height / 2,
                            style: .continuous
                        )
                        .fill(Color.black)
                    )
                } else if geometry.isVertical {
                    VStack(spacing: 10 * s) {
                        PebbleMac(size: 22 * s)
                        if let listening {
                            Waveform(level: listening.level, bars: 5)
                        } else if focus.isActive {
                            Text(focus.label)
                                .font(Fenn.display(10 * max(s, 0.8)))
                                .monospacedDigit()
                                .foregroundStyle(Fenn.accent)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .frame(width: size.width - 4)
                                .contentTransition(reduceMotion ? .identity : .numericText())
                            ring(size: 12 * s)
                        } else {
                            Image(systemName: geometry.placement == .left ? "chevron.right" : "chevron.left")
                                .font(.fenn(size: 10 * s, weight: .bold))
                                .foregroundStyle(Fenn.fg.opacity(0.5))
                        }
                    }
                    .frame(width: size.width, height: size.height)
                    .fennGlass(cornerRadius: size.width / 2, shadow: false)
                } else {
                    HStack(spacing: 8) {
                        leading
                        Spacer(minLength: 0)
                        timer
                    }
                    .padding(.horizontal, 12)
                    .frame(width: size.width, height: size.height)
                    .fennGlass(cornerRadius: size.height / 2, shadow: false)
                }
            }
            .contentShape(Rectangle())
            .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.86), value: statusKey)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { _ in
                    guard !isExpanded else { return }
                    lastDrag = Date()
                    move(false)
                }
                .onEnded { _ in
                    guard !isExpanded else { return }
                    lastDrag = Date()
                    move(true)
                }
        )
        .contextMenu {
            Picker(tr("Größe am Rand", "Size on the edge"), selection: $pillScale) {
                ForEach(IslandModel.pillSizes, id: \.scale) { option in Text(option.title).tag(option.scale) }
            }
            .pickerStyle(.inline)
            if geometry.isVertical {
                Button(tr("Zurück an den Rand", "Back to the edge"), action: toEdge)
            }
        }
        .help(isExpanded ? "" : tr("Drüberfahren oder klicken zum Öffnen, Ziehen zum Verschieben, Rechtsklick für die Größe",
                                   "Hover or click to open, drag to move, right-click for the size"))
        .accessibilityLabel(isExpanded ? tr("Fenn einklappen", "Collapse Fenn") : tr("Fenn öffnen", "Open Fenn"))
    }

    private var leading: some View {
        HStack(spacing: 7) {
            PebbleMac(size: 19)
            if focus.isActive {
                Text(focus.phaseTitle)
                    .font(.fenn(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
                    .contentTransition(reduceMotion ? .identity : .interpolate)
            } else if !geometry.usesNotch {
                Text("Fenn")
                    .font(Fenn.display(12))
                    .foregroundStyle(Fenn.fg)
                    .contentTransition(reduceMotion ? .identity : .interpolate)
            }
        }
    }

    @ViewBuilder
    private var timer: some View {
        if let listening {
            Waveform(level: listening.level, bars: 7)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
        } else if focus.isActive {
            HStack(spacing: 6) {
                Text(focus.label)
                    .font(Fenn.display(12))
                    .monospacedDigit()
                    .foregroundStyle(Fenn.accent)
                    .contentTransition(reduceMotion ? .identity : .numericText())
                ring(size: 13)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.92)))
        }
    }

    private func ring(size: CGFloat) -> some View {
        ZStack {
            Circle().stroke(Fenn.fillStrong, lineWidth: 2.4)
            Circle()
                .trim(from: 0, to: 1 - focus.progress)
                .stroke(Fenn.accent, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

struct PanelCard: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var focus: FocusTimer
    @ObservedObject var coach: CoachViewModel
    @ObservedObject var knowledge: KnowledgeStore
    @ObservedObject var dictation: DictationController
    @ObservedObject var ai: AISettings
    let services: IslandServices
    let actions: IslandActions
    /// Shown in the big window instead of the island: fills it, no collapse button, no resize grip.
    var inWindow = false
    @AppStorage("fenn.mac.moduleOrder") private var moduleOrderRaw = "today,tasks,focus,habits,ideas,notes,connectors"
    @AppStorage("fenn.mac.mainModuleCount") private var mainCount = 6
    @AppStorage(FennScheme.key) private var themeRaw = FennScheme.green.rawValue
    @AppStorage(FennFontChoice.key) private var fontRaw = FennFontChoice.standard.rawValue
    @AppStorage(FennAppearance.key) private var appearanceRaw = FennAppearance.system.rawValue
    @ObservedObject private var agent = FennAgent.shared
    @ObservedObject private var intro = MacIntro.shared
    @FocusState private var composerFocused: Bool
    @State private var draft = ""
    @State private var dragStart: CGSize?
    @State private var showDesign = FennDemo.isOn && UserDefaults.standard.bool(forKey: "FennQADesign")

    var body: some View {
        VStack(spacing: 16) {
            if showDesign {
                MacDesignSheet { showDesign = false }
            } else if model.needsOnboarding {
                MacOnboardingView(ai: ai, cloud: FennCloudFolder.shared, connectCloud: actions.chooseCloudFolder,
                                  openWindow: actions.openWindow, finish: actions.finishOnboarding)
            } else if model.launcher && !inWindow {
                launcher
                    .transition(.opacity)
            } else {
                header
                    .zIndex(1) // hover labels of the icons lie over the page, not under it
                    .transition(.opacity.combined(with: .offset(y: -8)))
                modules
                    .transition(.opacity.combined(with: .offset(y: 16)))
            }
        }
        .padding(inWindow ? 28 : 18)
        .frame(width: inWindow ? nil : model.geometry.panelSize.width,
               height: inWindow ? nil : (model.launcher ? IslandModel.launcherHeight : model.geometry.panelSize.height),
               alignment: .top)
        .animation(.spring(response: 0.46, dampingFraction: 0.8), value: model.launcher)
        .frame(maxWidth: inWindow ? .infinity : nil, maxHeight: inWindow ? .infinity : nil)
        .modifier(PanelBackground(inWindow: inWindow))
        .overlay(alignment: model.geometry.placement == .right ? .bottomLeading : .bottomTrailing) {
            if !inWindow && !model.launcher { resizeGrip }
        }
        .overlay { ConfettiOverlay().clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous)) }
        .overlay {
            if !model.needsOnboarding, intro.isRunning {
                MacIntroOverlay(intro: intro)
            }
        }
        .onChange(of: intro.index) { _, _ in
            if let module = intro.current?.module { model.module = module }
        }
        .onAppear {
            composerFocused = model.module == .coach
            if intro.isRunning, let module = intro.current?.module { model.module = module }
        }
    }

    /// Drag the corner to make the island bigger; the size is remembered. No visible icon, only the resize cursor.
    private var resizeGrip: some View {
        Color.clear
            .frame(width: 26, height: 26)
            .contentShape(Rectangle())
            .padding(6)
            .modifier(ResizeCursor(leading: model.geometry.placement == .right))
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = dragStart ?? model.geometry.panelSize
                        if dragStart == nil { dragStart = start }
                        let placement = model.geometry.placement
                        // The panel is centred on the notch (top) or vertically (edges), so it grows both ways.
                        let dx = placement == .top ? value.translation.width * 2 : (placement == .right ? -value.translation.width : value.translation.width)
                        let dy = placement == .top ? value.translation.height : value.translation.height * 2
                        model.panelSize = CGSize(width: (start.width + dx).rounded(), height: (start.height + dy).rounded())
                    }
                    .onEnded { _ in
                        dragStart = nil
                        model.panelSize = model.geometry.panelSize
                    }
            )
            .help(tr("Ziehen, um Fenn größer zu machen", "Drag to make Fenn bigger"))
            .accessibilityLabel(tr("Größe ändern", "Resize"))
    }

    @ViewBuilder
    private var modules: some View {
            Group {
                switch model.module {
                case .today:
                    TodayModuleView(focus: focus) { model.module = $0 }
                case .tasks:
                    TasksModuleView(store: TaskStore.shared, focus: focus, metrics: services.metrics) { model.module = $0 }
                case .habits:
                    HabitsModuleView(store: HabitStore.shared)
                case .coach:
                    CoachModuleView(
                        agent: agent,
                        hasKey: ai.isConfigured,
                        openConnectors: { model.module = .connectors },
                        knowledge: knowledge,
                        send: ask,
                        listening: dictation.isListening,
                        listen: dictation.toggle
                    )
                case .notes:
                    NotesModuleView(notes: services.notes, dictation: services.noteDictation, chooseAudio: actions.chooseAudio)
                case .focus:
                    FocusModuleView(focus: focus, tasks: JournalMarkdown.priorities(in: FennVault.readText(FennStorage.url(.journal(FennVault.dayKey(Date())))) ?? ""))
                case .ideas:
                    IdeasModuleView(store: IdeaStore.shared, selected: $model.openIdea)
                case .journal:
                    JournalModuleView()
                case .connectors:
                    ConnectorsModuleView(cloud: FennCloudFolder.shared, ai: ai, connectCloud: actions.chooseCloudFolder)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            // Fenn is one sentence away everywhere – except where a module has its own input.
            if ![.ideas, .notes, .connectors].contains(model.module) {
                composer
            }
    }

    /// The person's order (drag and drop in the header): the first `mainCount` are always visible, the rest sit behind "…".
    private static let orderable: [IslandModule] = [.today, .tasks, .habits, .focus, .ideas, .notes, .journal, .connectors]

    /// Modules added in an update land at their default place, not at the end.
    private var moduleOrder: [IslandModule] {
        var order: [IslandModule] = []
        for module in moduleOrderRaw.split(separator: ",").compactMap({ IslandModule(rawValue: String($0)) }) where Self.orderable.contains(module) && !order.contains(module) {
            order.append(module)
        }
        for (index, module) in Self.orderable.enumerated() where !order.contains(module) {
            order.insert(module, at: min(index, order.count))
        }
        return order
    }

    private var mainModules: [IslandModule] { Array(moduleOrder.prefix(mainCount)) }
    private var moreModules: [IslandModule] { Array(moduleOrder.dropFirst(mainCount)) }

    private func saveOrder(_ order: [IslandModule], main: Int? = nil) {
        withAnimation(.snappy) {
            moduleOrderRaw = order.map(\.rawValue).joined(separator: ",")
            if let main { mainCount = min(max(main, 2), 7) }
        }
    }

    /// Dropping one icon onto another puts it in that place.
    private func move(_ module: IslandModule, to target: IslandModule) {
        guard module != target else { return }
        var order = moduleOrder
        let wasMain = mainModules.contains(module)
        let targetMain = mainModules.contains(target)
        order.removeAll { $0 == module }
        let index = order.firstIndex(of: target) ?? order.count
        order.insert(module, at: index)
        saveOrder(order, main: mainCount + (targetMain && !wasMain ? 1 : 0) - (!targetMain && wasMain ? 1 : 0))
    }

    private func moveToMore(_ module: IslandModule) {
        var order = moduleOrder
        order.removeAll { $0 == module }
        order.insert(module, at: mainCount - 1)
        saveOrder(order, main: mainCount - 1)
    }

    private func moveToMain(_ module: IslandModule) {
        var order = moduleOrder
        order.removeAll { $0 == module }
        order.insert(module, at: mainCount)
        saveOrder(order, main: mainCount + 1)
    }

    private func shift(_ module: IslandModule, by step: Int) {
        var order = moduleOrder
        guard let index = order.firstIndex(of: module) else { return }
        let target = min(max(index + step, 0), mainCount - 1)
        order.remove(at: index)
        order.insert(module, at: target)
        saveOrder(order)
    }

    private var header: some View {
        HStack(spacing: 8) {
            // Fenn himself: the agent. Everything else is a small icon.
            Button { model.module = .coach } label: {
                FennAvatar(size: 26)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(model.module == .coach ? Fenn.accent.opacity(0.22) : Fenn.fill))
                    .overlay(Circle().strokeBorder(model.module == .coach ? Fenn.accent.opacity(0.8) : Color.clear, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("1", modifiers: .command)
            .hoverLabel("Fenn  ⌘1")
            .accessibilityLabel("Fenn")

            HStack(spacing: 4) {
                ForEach(Array(mainModules.enumerated()), id: \.element) { index, module in
                    // ⌘1 is Fenn, then ⌘2 … ⌘9 along the bar.
                    let key: KeyboardShortcut? = index < 8 ? KeyboardShortcut(KeyEquivalent(Character(String(index + 2))), modifiers: .command) : nil
                    Button {
                        model.module = module
                    } label: {
                        ModuleIcon(module: module, size: model.module == module ? 26 : 24)
                    }
                    .buttonStyle(FennModuleButtonStyle(isActive: model.module == module))
                    .keyboardShortcut(key)
                    .hoverLabel(key == nil ? module.title : "\(module.title)  ⌘\(index + 2)")
                    .accessibilityLabel(module.title)
                    .draggable(module.rawValue) {
                        ModuleIcon(module: module, size: 26)
                            .frame(width: 36, height: 36).background(Circle().fill(Fenn.fillStrong))
                    }
                    .dropDestination(for: String.self) { dropped, _ in
                        guard let moved = dropped.first.flatMap(IslandModule.init(rawValue:)) else { return false }
                        move(moved, to: module)
                        return true
                    }
                    .contextMenu {
                        Button(tr("Nach links", "Move left")) { shift(module, by: -1) }
                        Button(tr("Nach rechts", "Move right")) { shift(module, by: 1) }
                        if mainModules.count > 2 {
                            Button(tr("In „…“ verschieben", "Move into “…”")) { moveToMore(module) }
                        }
                    }
                }
                Menu {
                    ForEach(moreModules) { module in
                        Button { model.module = module } label: { Label(module.title, systemImage: module.symbol) }
                    }
                    if !moreModules.isEmpty && mainModules.count < 7 {
                        Divider()
                        Menu(tr("In die Leiste holen", "Pin to the bar")) {
                            ForEach(moreModules) { module in
                                Button { moveToMain(module) } label: { Label(module.title, systemImage: module.symbol) }
                            }
                        }
                    }
                    Button(tr("Reihenfolge zurücksetzen", "Reset order")) {
                        saveOrder(Self.orderable, main: 6)
                    }
                } label: {
                    let current = moreModules.first { $0 == model.module }
                    Group {
                        if let art = current?.art {
                            Image(art).resizable().interpolation(.high).scaledToFit().frame(width: 24, height: 24)
                        } else {
                            Image(systemName: current?.symbol ?? "ellipsis")
                        }
                    }
                        .font(.fenn(size: 14, weight: current == nil ? .regular : .semibold))
                        .foregroundStyle(current == nil ? Fenn.fg.opacity(0.7) : Fenn.onAccent)
                        .frame(width: current == nil ? 34 : 50, height: 34)
                        .background(Capsule().fill(current == nil ? Fenn.fill : Fenn.accent))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .hoverLabel(tr("Mehr", "More"))
                .accessibilityLabel(tr("Mehr", "More"))
                .dropDestination(for: String.self) { dropped, _ in
                    guard let moved = dropped.first.flatMap(IslandModule.init(rawValue:)), mainModules.contains(moved), mainModules.count > 2 else { return false }
                    moveToMore(moved)
                    return true
                }
            }
            .padding(3)
            .background(Capsule().fill(Fenn.fill))

            Spacer()

            Menu {
                Picker(tr("Platzierung", "Placement"), selection: Binding(
                    get: { model.geometry.placement },
                    set: { actions.setPlacement($0) }
                )) {
                    ForEach(IslandPlacement.allCases) { placement in
                        Text(placement.title).tag(placement)
                    }
                }
                .pickerStyle(.inline)
                Picker(tr("Symbol am Rand", "Edge pill"), selection: $model.pillScale) {
                    ForEach(IslandModel.pillSizes, id: \.scale) { option in Text(option.title).tag(option.scale) }
                }
                Divider()
                if !inWindow {
                    Button(tr("Im Fenster öffnen (Vollbild möglich)", "Open in a window (full screen possible)"), action: actions.openWindow)
                    Button(tr("Standardgröße", "Default size")) { model.panelSize = IslandGeometry.defaultPanelSize }
                }
                Button(tr("Einführung ansehen", "Show introduction")) { intro.start() }
                // Colour scheme, light/dark, typeface and modes as previews on their own page.
                Button(tr("Design und Modus …", "Design and mode …")) { showDesign = true }
                Picker(tr("Modus", "Mode"), selection: Binding(
                    get: { MacMode.current.id },
                    set: { id in if let mode = MacMode.all.first(where: { $0.id == id }) { withAnimation(.snappy) { mode.activate() } } }
                )) {
                    ForEach(MacMode.all) { Text($0.title).tag($0.id) }
                }
                Button(tr("Mitteilungen erlauben", "Allow notifications")) { FennNotificationBrand.authorizeIfNeeded() }
                Toggle(tr("Fenn zuerst (Eingabe statt Startseite)", "Fenn first (input instead of home)"), isOn: Binding(
                    get: { IslandModel.fennFirst },
                    set: { UserDefaults.standard.set($0, forKey: IslandModel.fennFirstKey) }))
                Toggle(tr("Öffnen beim Drüberfahren", "Open on hover"), isOn: Binding(
                    get: { IslandController.hoverOpens },
                    set: { UserDefaults.standard.set($0, forKey: IslandController.hoverOpensKey) }))
                Toggle(tr("Meldungen aus der Notch", "Notices from the notch"), isOn: Binding(
                    get: { NotchNotices.isEnabled },
                    set: { UserDefaults.standard.set($0, forKey: NotchNotices.enabledKey) }))
                Divider()
                Button(tr("Fenn beenden", "Quit Fenn"), action: actions.quit)
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.fenn(size: 14, weight: .regular))
                    .foregroundStyle(Fenn.fg.opacity(0.7))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Fenn.fill))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .hoverLabel(tr("Einstellungen", "Settings"))
            .accessibilityLabel(tr("Einstellungen", "Settings"))

            if !inWindow {
                Button(action: actions.openWindow) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(FennIconButtonStyle())
                .background(Circle().fill(Fenn.fill))
                .help(tr("Im Fenster öffnen – mit Vollbild", "Open in a window – with full screen"))
                .accessibilityLabel(tr("Im Fenster öffnen", "Open in a window"))

                Button(action: actions.collapse) {
                    Image(systemName: collapseSymbol)
                }
                .buttonStyle(FennIconButtonStyle())
                .background(Circle().fill(Fenn.fill))
                .help(tr("Einklappen (Esc)", "Collapse (Esc)"))
                .accessibilityLabel(tr("Einklappen", "Collapse"))
            }
        }
    }

    private var collapseSymbol: String {
        switch model.geometry.placement {
        case .top: return "chevron.up"
        case .left: return "chevron.left"
        case .right: return "chevron.right"
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            // Fenn's orb: calm ring when idle, orbits while answering, a wave while listening.
            ThinkingOrb(state: dictation.isListening ? .listening : (agent.isWorking ? .working : .breathing), size: 30,
                        fps: dictation.isListening || agent.isWorking ? 30 : 10)
                .frame(width: 32, height: 32)
                .animation(.easeInOut(duration: 0.25), value: agent.isWorking)
            if dictation.isListening {
                Waveform(level: dictation.level, bars: 5)
                Text(dictation.transcript.isEmpty ? tr("Ich höre zu …", "Listening …") : dictation.transcript)
                    .font(.fenn(size: 14))
                    .foregroundStyle(Fenn.fg.opacity(dictation.transcript.isEmpty ? 0.5 : 0.9))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField(tr("Frag Fenn", "Ask Fenn"), text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.fenn(size: 14))
                    .foregroundStyle(Fenn.fg)
                    .lineLimit(1...3)
                    .focused($composerFocused)
                    .onSubmit(send)
            }
            Button(action: dictation.toggle) {
                Image(systemName: dictation.isListening ? "stop.fill" : "mic.fill")
                    .font(.fenn(size: 13, weight: .medium))
                    .foregroundStyle(dictation.isListening ? Fenn.onAccent : Fenn.fg.opacity(0.8))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(dictation.isListening ? Fenn.accent : Fenn.fill))
            }
            .buttonStyle(.plain)
            .help(tr("Diktieren (⌃⌥ V)", "Dictate (⌃⌥ V)"))
            .accessibilityLabel(dictation.isListening ? tr("Diktat beenden", "Stop dictation") : tr("Diktieren", "Dictate"))
            // While Fenn works the send button becomes stop – a request never locks the chat.
            Button(action: agent.isWorking ? agent.stop : send) {
                Image(systemName: agent.isWorking ? "stop.fill" : "arrow.up")
                    .font(.fenn(size: agent.isWorking ? 12 : 14, weight: .medium))
                    .foregroundStyle(canSend || agent.isWorking ? Fenn.canvas : Fenn.fg.opacity(0.5))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(canSend || agent.isWorking ? Fenn.fg : Fenn.fill))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .disabled(!canSend && !agent.isWorking)
            .help(agent.isWorking ? tr("Anfrage stoppen", "Stop the request") : tr("Senden", "Send"))
            .accessibilityLabel(agent.isWorking ? tr("Stopp", "Stop") : tr("Senden", "Send"))
        }
        .padding(8)
        .background(Capsule().fill(Fenn.fill))
        .overlay(Capsule().strokeBorder(dictation.isListening ? Fenn.accent.opacity(0.5) : Fenn.hairline))
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !agent.isWorking
    }

    private func send() {
        guard canSend else { return }
        let text = draft
        draft = ""
        ask(text)
    }

    /// Everything goes to Fenn; the chat opens so you see what happens.
    private func ask(_ text: String) {
        model.module = .coach
        model.launcher = false
        agent.start(text)
    }

    // MARK: Fenn first

    private static let launcherChips = [
        tr("Plan meinen Tag", "Plan my day"),
        tr("25 min Fokus auf die wichtigste Aufgabe", "25 min focus on the top task"),
        tr("Was steht diese Woche noch an?", "What's still due this week?"),
    ]

    /// Like a language model first: Fenn, one input, three ideas. The home page is one click (or one question) away.
    private var launcher: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                LauncherPebble(thinking: agent.isWorking, listening: dictation.isListening,
                               hidden: model.popInFlight)
                VStack(alignment: .leading, spacing: 2) {
                    Text(TodayModuleView.greeting).font(Fenn.display(20)).foregroundStyle(Fenn.fg).lineLimit(1)
                    Text(tr("Schreib oder sag, was du tun willst.", "Type or say what you want to do."))
                        .font(.fenn(size: 12)).foregroundStyle(Fenn.fg.opacity(0.55))
                }
                .modifier(LauncherRise(delay: 0.05))
                Spacer(minLength: 8)
            }
            composer.modifier(LauncherRise(delay: 0.14))
            ChipFlow(spacing: 6) {
                ForEach(Array(Self.launcherChips.enumerated()), id: \.offset) { index, chip in
                    Button { ask(chip) } label: {
                        Text(chip)
                            .font(.fenn(size: 12.5, weight: .medium))
                            .foregroundStyle(Fenn.fg.opacity(0.85))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(Fenn.fill))
                            .overlay(Capsule().strokeBorder(Fenn.hairline))
                    }
                    .buttonStyle(.plain)
                    .modifier(LauncherRise(delay: 0.2 + Double(index) * 0.05))
                }
            }
            Spacer(minLength: 0)
            // At the very bottom: unfolds the home page (click, ⌘↓ or pull it down).
            LauncherHandle { openHome() }
                .modifier(LauncherRise(delay: 0.3))
        }
        .onAppear { composerFocused = true }
    }

    private func openHome() {
        model.module = .today
        model.launcher = false
    }
}

/// Live microphone level as a few ember bars.
struct Waveform: View {
    let level: Float
    let bars: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<bars, id: \.self) { index in
                let shape = [0.5, 0.8, 1.0, 0.7, 0.9, 0.6, 0.75][index % 7]
                Capsule()
                    .fill(Fenn.accent)
                    .frame(width: 2.5, height: max(3, CGFloat(level) * 16 * shape))
            }
        }
        .frame(height: 16)
        .animation(.easeOut(duration: 0.08), value: level)
        .accessibilityHidden(true)
    }
}

/// The data and intelligence services the panel's modules read from.
struct IslandServices {
    let metrics: MetricsStore
    let dictation: DictationController
    let notes: NotesStore
    let noteDictation: DictationController
    let ai: AISettings
}

/// The system's diagonal resize cursor over the invisible corner grip (macOS 15+).
private struct ResizeCursor: ViewModifier {
    let leading: Bool

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.pointerStyle(.frameResize(position: leading ? .bottomLeading : .bottomTrailing))
        } else {
            content
        }
    }
}

/// Glass in the island; a plain dark canvas in the window.
private struct PanelBackground: ViewModifier {
    let inWindow: Bool
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let light = scheme == .light
        if inWindow {
            content.background {
                ZStack {
                    Fenn.canvas
                    if let name = Fenn.scheme.backdrop {
                        // Fill, but never grow past the panel – scaledToFill alone makes the ZStack taller than the glass.
                        Color.clear.overlay { Image(name).resizable().scaledToFill().blur(radius: 6).opacity(light ? 0.55 : 0.7) }.clipped()
                    }
                    FennAurora(intensity: light ? 0.2 : 1)
                }
                .ignoresSafeArea()
            }
        } else {
            content
                .background {
                    ZStack {
                        if let name = Fenn.scheme.backdrop {
                            Color.clear.overlay { Image(name).resizable().scaledToFill().blur(radius: 8).opacity(light ? 0.4 : 0.55) }.clipped()
                        }
                        FennAurora(intensity: light ? 0.15 : 0.55)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                }
                .fennGlass(cornerRadius: 30)
        }
    }
}

/// Fenn in a normal window: the same modules, as big as you like, full screen included.
struct FennWindowView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var focus: FocusTimer
    @ObservedObject var coach: CoachViewModel
    @ObservedObject var knowledge: KnowledgeStore
    let services: IslandServices
    let actions: IslandActions

    var body: some View {
        PanelCard(
            model: model,
            focus: focus,
            coach: coach,
            knowledge: knowledge,
            dictation: services.dictation,
            ai: services.ai,
            services: services,
            actions: actions,
            inWindow: true
        )
        .padding(.top, 12)
        .background(Fenn.canvas)
        .fennScheme()
        .frame(minWidth: 560, minHeight: 560)
    }
}

/// A small label under an icon while the pointer rests on it – quicker and calmer than the system tooltip.
private struct HoverLabel: ViewModifier {
    let text: String
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hovering = inside } }
            .overlay(alignment: .bottom) {
                if hovering {
                    Text(text)
                        .font(.fenn(size: 11, weight: .medium))
                        // Always light on the dark pill – the theme's ink is dark in the white design.
                        .foregroundStyle(.white)
                        .fixedSize()
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.82)))
                        .offset(y: 30)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .zIndex(hovering ? 10 : 0)
    }
}

extension View {
    func hoverLabel(_ text: String) -> some View { modifier(HoverLabel(text: text)) }
}

/// The pebble beside the launcher input – smiling and alive: a hop when it appears, then every few seconds a wave,
/// a turn around itself (the real turnaround frames) or a little hop; a wave when the mouse comes by. Eyes busy while
/// Fenn works. Plain task loops with explicit animations – no repeating keyframe animators (they pile up).
private struct LauncherPebble: View {
    var thinking = false
    var listening = false
    /// Fenn is still jumping here out of the notch.
    var hidden = false
    @State private var lift: CGFloat = 0
    @State private var tilt: Double = 0
    @State private var spinFrame: Int?
    @State private var busy = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let spinFrame {
                PopView.spinImage(spinFrame).resizable().interpolation(.high).scaledToFit()
            } else {
                Image(PebbleMac.image)
                    .resizable().interpolation(.high).scaledToFit()
                    .overlay { PebbleFace(mood: listening ? .listening : thinking ? .thinking : .content, blush: true) }
                    .compositingGroup()
            }
        }
        .frame(width: 52, height: 52)
        .scaleEffect(x: 1 + lift * 0.004, y: 1 - lift * 0.004, anchor: .bottom)
        .rotationEffect(.degrees(tilt), anchor: .bottom)
        .offset(y: -lift)
        .opacity(hidden ? 0 : 1)
        .contentShape(Rectangle())
        .onHover { inside in if inside { play(wave) } }
        .task(id: "\(hidden)-\(thinking)-\(listening)") { await idle() }
        .accessibilityHidden(true)
    }

    private func idle() async {
        guard !reduceMotion, !hidden else { return }
        await run(hop)
        guard !thinking, !listening else { return }
        var turn = 0
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 5...8)))
            guard !Task.isCancelled else { return }
            turn += 1
            await run(turn % 3 == 1 ? wave : turn % 3 == 2 ? spin : hop)
        }
    }

    private func play(_ move: @escaping @MainActor () async -> Void) {
        guard !reduceMotion, !hidden else { return }
        Task { await run(move) }
    }

    /// One move at a time.
    private func run(_ move: @MainActor () async -> Void) async {
        guard !busy else { return }
        busy = true
        await move()
        busy = false
    }

    private func pause(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }

    private func hop() async {
        withAnimation(.easeOut(duration: 0.18)) { lift = 10 }
        await pause(0.18)
        withAnimation(.spring(response: 0.34, dampingFraction: 0.45)) { lift = 0 }
        await pause(0.4)
    }

    /// Side to side, like waving with the whole stone.
    private func wave() async {
        for angle in [-12.0, 11, -9, 7, -4, 0] {
            withAnimation(.easeInOut(duration: 0.15)) { tilt = angle }
            await pause(0.15)
        }
    }

    /// Up, once around itself in the air, down with a bounce.
    private func spin() async {
        withAnimation(.easeOut(duration: 0.2)) { lift = 9 }
        await pause(0.12)
        for frame in 0..<PopView.frames {
            spinFrame = frame
            await pause(0.028)
        }
        spinFrame = nil
        withAnimation(.spring(response: 0.34, dampingFraction: 0.45)) { lift = 0 }
        await pause(0.4)
    }
}

/// "Startseite" at the bottom of the launcher: a full-width bar with a chevron that nudges down now and then.
/// Click it, press ⌘↓ or pull it down to unfold the home page.
private struct LauncherHandle: View {
    let open: () -> Void
    @State private var nudge = false
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: open) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.down").font(.fenn(size: 10, weight: .bold))
                    .offset(y: nudge ? 2.5 : 0)
                Text(tr("Startseite", "Home")).font(.fenn(size: 12, weight: .semibold))
            }
            .foregroundStyle(Fenn.fg.opacity(hovering ? 0.85 : 0.55))
            .frame(maxWidth: .infinity, minHeight: 26)
            .background(Capsule().fill(Fenn.fill.opacity(hovering ? 1 : 0)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.downArrow, modifiers: .command)
        .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hovering = inside } }
        .simultaneousGesture(DragGesture(minimumDistance: 6).onEnded { value in
            if value.translation.height > 14 { open() }
        })
        .help(tr("Startseite aufklappen – ⌘↓ oder nach unten ziehen", "Unfold the home page – ⌘↓ or pull down"))
        .accessibilityLabel(tr("Startseite aufklappen", "Unfold home page"))
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.6))
                if hovering { continue }
                withAnimation(.easeInOut(duration: 0.22)) { nudge = true }
                try? await Task.sleep(for: .seconds(0.22))
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { nudge = false }
            }
        }
    }
}

/// The launcher's pieces arrive one after another (no blur – it made the opening stutter while Fenn jumps in).
private struct LauncherRise: ViewModifier {
    let delay: Double
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 8)
            .onAppear { withAnimation(.spring(response: 0.45, dampingFraction: 0.75).delay(delay)) { shown = true } }
    }
}
