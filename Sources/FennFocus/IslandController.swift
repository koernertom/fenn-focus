import AppKit
import SwiftUI
import Carbon.HIToolbox
import Combine
import FennFocusCore

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Lets the first click on the (inactive) island act immediately, and reports the mouse coming and going –
/// even while another app is active, so hovering the notch can open Fenn.
final class IslandHostingView<Content: View>: NSHostingView<Content> {
    var onHover: (Bool) -> Void = { _ in }
    private var hoverArea: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHover(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHover(false)
    }
}

/// Owns the one borderless panel that is Fenn: at the notch, under the menu bar, or on a screen edge.
@MainActor
final class IslandController: NSObject, NSWindowDelegate {
    let model = IslandModel()
    let focus = FocusTimer()
    let coach = CoachViewModel()
    let knowledge: KnowledgeStore
    let metrics: MetricsStore
    let dictation = DictationController()
    let noteDictation = DictationController(maxDuration: .seconds(600), silenceTimeout: 10)
    let notes: NotesStore
    let ai = AISettings.shared

    private let panel = IslandPanel(
        contentRect: .zero,
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    private var hotKeys: [HotKey] = []
    private var placement: IslandPlacement
    /// Where the person dragged the pill to (centre, as a fraction of the visible screen); nil = centred on its edge.
    private var pillCenter: CGPoint? = IslandController.storedPillCenter
    private var pillDrag: (mouse: NSPoint, origin: NSPoint)?
    private static let pillCenterKey = "fenn.pill.center"
    private var observers: Set<AnyCancellable> = []
    /// The same modules in a normal, resizable window that can go full screen.
    private var window: NSWindow?
    private let windowModel = IslandModel()

    override init() {
        knowledge = KnowledgeStore()
        metrics = MetricsStore()
        notes = NotesStore(knowledge: knowledge)
        placement = UserDefaults.standard.string(forKey: IslandPlacement.defaultsKey)
            .flatMap(IslandPlacement.init(rawValue:)) ?? .top
        super.init()
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.appearance = Self.appearance
        // Follow the "Darstellung" setting live (island, window and the SwiftUI inside them).
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .map { _ in FennAppearance.current }
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.panel.appearance = Self.appearance
                self?.window?.appearance = Self.appearance
            }
            .store(in: &observers)
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        if FennDemo.isOn {
            let agent = FennAgent.shared
            agent.show(AgentItem(kind: .user, text: tr("Erinner mich morgen ans Angebot und starte 25 min Fokus aufs Pitch-Deck", "Remind me about the offer tomorrow and start 25 min focus on the pitch deck")))
            agent.show(AgentItem(kind: .action(symbol: "checklist"), text: tr("Aufgabe angelegt: Angebot schicken", "Task added: Send offer")))
            agent.show(AgentItem(kind: .action(symbol: "timer"), text: tr("Fokus 25 min, Q4-Pitch-Deck für Nordlicht", "Focus 25 min, Q4 pitch deck for Nordlicht")))
            agent.show(AgentItem(kind: .fenn, text: tr("Steht für morgen, und dein Fokusblock aufs **Pitch-Deck** läuft. Danach 5 min Pause – ich sag Bescheid.", "Set for tomorrow, and your focus block on the **pitch deck** is running. Then a 5 min break – I'll let you know.")))
            for exchange in FennDemo.coach.suffix(1) {
                agent.show(AgentItem(kind: .user, text: exchange.question))
                agent.show(AgentItem(kind: .fenn, text: exchange.answer))
            }
        }
        let actions = panelActions(inWindow: false)
        let host = IslandHostingView(rootView: IslandRootView(
            model: model,
            focus: focus,
            coach: coach,
            knowledge: knowledge,
            services: IslandServices(
                metrics: metrics,
                dictation: dictation,
                notes: notes,
                noteDictation: noteDictation,
                ai: ai
            ),
            actions: actions
        ))
        host.onHover = { [weak self] inside in self?.hoverChanged(inside) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { FennPeek.shared.warmUp() }
        panel.contentView = host
        coach.contextProvider = { [weak self] question in
            self?.coachContext(for: question) ?? CoachContext(persona: nil, text: "", sources: [])
        }
        coach.onExchange = { [weak self] question, answer in
            self?.knowledge.logExchange(question: question, answer: answer)
        }
        // Fenn the agent: the coach's context plus tools for tasks, focus, notes, routines and more.
        let agent = FennAgent.shared
        agent.platform = "Mac"
        IdeaStore.shared.withRoot = { body in body(FennStorage.root) }
        DayPlanner.events = { day in
            let work = WorkCalendar.shared.events(on: day).filter { $0.calendar != TaskCalendarSync.calendarTitle }
            let own = TaskCalendarSync.shared.events(on: day)
            let feeds = work.filter { event in !own.contains { $0.title == event.title && $0.start == event.start } }.map { event in
                DayEvent(id: event.id, title: event.title, start: event.start, end: event.end, isAllDay: event.isAllDay, calendar: event.calendar, movable: false)
            }
            return (own + feeds).sorted { $0.start < $1.start }
        }
        TaskCalendarSync.shared.start()
        TaskCalendarSync.shared.sync()
        IdeaStore.shared.reload()
        agent.tools = MacAgentTools.make(self) + SharedAgentTools.ideas { [weak self] id in
            self?.model.module = .ideas
            self?.model.openIdea = id
        }
        agent.context = { [weak self] question in self?.coachContext(for: question).text ?? "" }
        // Other agents (Claude Code, Cursor) reach the same tools through MCP – only when switched on in Connections.
        FennMCPServer.shared.startIfEnabled()
        agent.persona = { [weak self] in self?.coachContext(for: "").persona }
        agent.onReply = { [weak self] question, answer in
            guard let self else { return }
            self.knowledge.logExchange(question: question, answer: answer)
            // Asked from the hotkey or a shortcut while the island is closed: the answer is ready.
            if !self.model.isExpanded {
                let line = answer.split(whereSeparator: \.isNewline).first.map(String.init) ?? answer
                self.notify(IslandNotice(symbol: "bubble.left.fill", art: PebbleMac.image, title: tr("Fenn hat geantwortet", "Fenn replied"),
                                         detail: line, module: .coach, duration: 6))
            }
        }
        agent.localCommand = { [weak self] text in
            guard let self else { return nil }
            return LocalVoice.handle(text, focus: self.focus, blocker: MacBlocker.shared) { self.model.module = .focus }
        }
        FennNotificationBrand.authorizeIfNeeded()

        focus.onFocusBlockCompleted = { [weak self] in
            self?.metrics.logFocusBlock()
        }
        TaskStore.shared.onTaskCompleted = { [weak self] in
            self?.metrics.logTaskDone()
            Celebration.shared.fire()
        }
        TaskStore.shared.onTaskDone = { [weak self] task in
            self?.notify(IslandNotice(symbol: "checkmark", art: "Page-tasks", title: task.title, detail: tr("Aufgabe erledigt", "Task done"), module: .tasks),
                         peek: tr("Erledigt!", "Done!"))
        }
        // Tasks live in the Fenn Focus folder (tasks/).
        TaskStore.withFolder = { body in body(FennStorage.root) }
        TaskStore.shared.reload()
        // Routines: habits/ in the same folder; what Fenn already knows ticks them off.
        let habits = HabitStore.shared
        HabitStore.withFolder = { body in body(FennStorage.root) }
        habits.onHabitDone = { [weak self] habit in
            guard let self else { return }
            self.metrics.logHabitDone()
            Celebration.shared.fire()
            self.notify(IslandNotice(symbol: "checkmark.seal.fill", art: ClayArt.name(for: habit.symbol ?? "") ?? "Page-habits",
                                     title: habit.title, detail: tr("Routine geschafft", "Routine done"), module: .habits),
                        peek: tr("Stark!", "Nice!"))
        }
        habits.autoCheck = { [weak self] auto, date in
            guard let self else { return false }
            let key = FennVault.dayKey(date)
            let journal = FennVault.readText(FennStorage.url(.journal(key))) ?? ""
            switch auto {
            case .checkIn: return journal.contains("## Check-in")
            case .review: return journal.contains("## Rückblick")
            case .focus: return self.metrics.record(key).focusBlocks > 0
            }
        }
        habits.reload()
        habits.archiveFinished()
        habits.applyAuto()
        // Optional app block that runs with each focus block and lifts for the break.
        // The focus block is over: Fenn pops out and calls the break.
        focus.$phase
            .removeDuplicates()
            .scan((FocusTimer.Phase.idle, FocusTimer.Phase.idle)) { ($0.1, $1) }
            .sink { [weak self] change in
                guard let self else { return }
                let minutes = max(1, Int((self.focus.remaining / 60).rounded()))
                if change.0 == .focus, change.1 == .shortBreak || change.1 == .longBreak {
                    self.notify(IslandNotice(symbol: "cup.and.saucer.fill", art: "Page-focus", title: tr("Fokusblock geschafft", "Focus block done"),
                                             detail: tr("Steh kurz auf, trink was.", "Stand up, have a drink."), trailing: "\(minutes) min",
                                             module: .focus, duration: 5),
                                peek: tr("Pause!", "Break!"))
                } else if change.0 == .shortBreak || change.0 == .longBreak, change.1 == .focus {
                    self.notify(IslandNotice(symbol: "hourglass", art: "Page-focus", title: tr("Pause vorbei", "Break's over"),
                                             detail: tr("Nächster Fokusblock läuft.", "Next focus block is on."), trailing: "\(minutes) min",
                                             module: .focus))
                }
            }
            .store(in: &observers)
        focus.$phase
            .removeDuplicates()
            .sink { [weak self] phase in
                guard let self else { return }
                let blocker = MacBlocker.shared
                if phase == .focus, blocker.withFocus, !blocker.isActive {
                    blocker.start(minutes: max(1, Int(self.focus.remaining / 60)), fromFocus: true)
                } else if phase != .focus, blocker.fromFocus {
                    blocker.stop()
                }
            }
            .store(in: &observers)
        dictation.onFinish = { [weak self] text in
            guard let self else { return }
            self.expand(module: .coach)
            FennAgent.shared.start(text)
        }
        startWidgetSync()
        startNotices()

        // ⌃⌥ F opens Fenn Focus, ⌃⌥ V dictates – clear of ⌥ Space (Claude, ChatGPT) and of the Fenn app's ⌃⌥ Space / ⌃⌥ D.
        // Once a day Fenn says hello from under the notch (QA: -FennQAPeek YES every launch).
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            let today = FennVault.dayKey(Date())
            let qa = FennDemo.isOn && UserDefaults.standard.bool(forKey: "FennQAPeek")
            guard qa || UserDefaults.standard.string(forKey: "fenn.peek.day") != today else { return }
            UserDefaults.standard.set(today, forKey: "fenn.peek.day")
            let hour = Calendar.current.component(.hour, from: Date())
            self?.peek(hour < 11 ? tr("Guten Morgen!", "Good morning!") : hour < 18 ? tr("Hallo!", "Hi!") : tr("Guten Abend!", "Good evening!"))
        }
        hotKeys = [
            HotKey(id: 1, keyCode: kVK_ANSI_F, modifiers: controlKey | optionKey) { [weak self] in self?.toggle() },
            HotKey(id: 2, keyCode: kVK_ANSI_V, modifiers: controlKey | optionKey) { [weak self] in self?.toggleDictation() }
        ].compactMap { $0 }

        model.$pillScale
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.layout(expanded: self?.model.isExpanded ?? false) }
            }
            .store(in: &observers)

        // Out of the launcher: the window takes the full size at once, the card grows into it.
        model.$launcher
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] launcher in
                guard let self, !launcher, self.model.isExpanded else { return }
                DispatchQueue.main.async { self.layout(expanded: true) }
            }
            .store(in: &observers)

        model.$panelSize
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self, self.model.isExpanded else { return }
                self.layout(expanded: true)
            }
            .store(in: &observers)

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == UInt16(kVK_Escape), let self, self.model.isExpanded else { return event }
            self.collapse()
            return nil
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.layout(expanded: self.model.isExpanded)
            }
        }
    }

    func show() {
        layout(expanded: false)
        panel.orderFrontRegardless()

        let defaults = UserDefaults.standard
        #if DEBUG
        // QA only: -FennCycleModules YES switches through all modules and logs how long each switch blocks the main thread.
        if defaults.bool(forKey: "FennCycleModules") {
            expand(module: .today)
            var last = CFAbsoluteTimeGetCurrent()
            Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
                let now = CFAbsoluteTimeGetCurrent()
                if now - last > 0.05 { print("HANG \(Int((now - last) * 1000)) ms in \(self?.model.module.rawValue ?? "?")") }
                last = now
            }
            Task { @MainActor in
                for _ in 0..<3 {
                    for module in IslandModule.allCases {
                        try? await Task.sleep(nanoseconds: 800_000_000)
                        print("SWITCH \(module.rawValue)")
                        self.model.module = module
                    }
                }
                print("DONE"); fflush(stdout); exit(0)
            }
        }
        #endif
        #if DEBUG
        // QA only: -FennQAWriteProfile YES writes the profile block and the goal like finishing the setup does, then quits.
        if defaults.bool(forKey: "FennQAWriteProfile") {
            PersonProfileStore.shared.commitGoal()
            PersonProfileStore.shared.writeProfile()
            print(FennStorage.url(.profile).path)
            fflush(stdout)
            exit(0)
        }
        // QA only: -FennQAServer ollama|lmStudio -FennQAModel <name> asks that server once and runs one agent step, then quits.
        if let server = defaults.string(forKey: "FennQAServer").flatMap(AIProvider.init(rawValue:)) {
            Task { @MainActor in
                let config = AIConfig(provider: server, baseURL: "", model: defaults.string(forKey: "FennQAModel") ?? "")
                let start = Date()
                do {
                    let reply = try await FennAI.complete(system: "Antworte auf Deutsch, in einem Satz.", messages: [AIMessage(role: .user, text: "Warum helfen Fokusblöcke?")],
                                                          maxTokens: 200, config: config)
                    print("[\(server.title)] \(String(format: "%.1f", Date().timeIntervalSince(start))) s: \(reply)")
                    let step = try await FennAI.step(system: "Du bist Fenn auf dem Mac. Nutze Werkzeuge, wenn sinnvoll.", entries: [.user("Leg mir für morgen die Aufgabe Steuer erledigen an.")],
                                                     tools: FennAgent.focusTools(FennAgent.shared.tools, for: "Leg mir für morgen die Aufgabe Steuer erledigen an."), config: config)
                    print("[Agent] \(String(format: "%.1f", Date().timeIntervalSince(start))) s: calls=\(step.calls.map { "\($0.name) \($0.arguments)" }) text=\(step.text.prefix(200))")
                } catch {
                    print("[\(server.title)] Fehler: \(error.localizedDescription)")
                }
                fflush(stdout)
                exit(0)
            }
        }
        // QA only: -FennQABrain "…" asks the downloaded model (or -FennModelDir), then the agent with tools, prints timings, quits.
        if let question = defaults.string(forKey: "FennQABrain") {
            Task { @MainActor in
                do {
                    let start = Date()
                    let reply = try await LocalBrainBridge.complete(system: "Du bist Fenn, ein knapper, freundlicher Assistent. Antworte auf Deutsch.",
                                                                    messages: [AIMessage(role: .user, text: question)], maxTokens: 200, choice: "auto")
                    print("[\(LocalModels.resolve("auto")?.id ?? "?")] \(String(format: "%.1f", Date().timeIntervalSince(start))) s: \(reply)")
                } catch {
                    print("[Brain] Fehler: \(error)")
                }
                let start = Date()
                do {
                    let step = try await FennAI.step(system: "Du bist Fenn auf dem Mac. Nutze Werkzeuge, wenn sinnvoll.", entries: [.user("Was steht heute an? Zeig mir meine Aufgaben.")],
                                                     tools: FennAgent.shared.tools, config: AIConfig(provider: .fennBrain, baseURL: "", model: "auto"))
                    print("[Agent] \(String(format: "%.1f", Date().timeIntervalSince(start))) s: calls=\(step.calls.map(\.name)) text=\(step.text.prefix(200))")
                } catch {
                    print("[Agent] Fehler: \(error)")
                }
                fflush(stdout)
                exit(0)
            }
        }
        // QA only: -FennAgentPrompt "…" sends one message to Fenn right after launch.
        if let prompt = defaults.string(forKey: "FennAgentPrompt") {
            FennAgent.shared.reset()
            FennAgent.shared.start(prompt)
        }
        #endif
        if let module = defaults.string(forKey: "FennStartModule").flatMap(IslandModule.init(rawValue:)) {
            expand(module: module)
            #if DEBUG
            // QA: -FennQALauncher YES shows the Fenn-first launcher instead of the module.
            if defaults.bool(forKey: "FennQALauncher") { model.launcher = true; layout(expanded: true) }
            #endif
        } else if defaults.bool(forKey: "FennStartExpanded") || model.needsOnboarding {
            // The first run opens straight to the setup.
            expand(module: .today)
        }
        if !model.needsOnboarding, MacIntro.needsIntro {
            expand(module: .today)
            MacIntro.shared.start()
        }
    }

    /// nil follows the system; otherwise pinned to light (aqua) or dark (darkAqua).
    static var appearance: NSAppearance? {
        switch FennAppearance.current {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    func toggle() {
        model.isExpanded ? collapse() : expand()
    }

    /// A desktop widget tapped `fenn://…`. Opens the matching module; `fenn://focus?start=1` starts the Pomodoro.
    func open(_ url: URL) {
        guard url.scheme?.lowercased() == "fennfocus" else { return }
        let host = (url.host ?? "").lowercased()
        let module: IslandModule
        switch host {
        case "tasks", "task": module = .tasks
        case "habits": module = .habits
        case "focus": module = .focus
        case "coach", "agent": module = .coach
        case "notes": module = .notes
        case "journal": module = .journal
        default: module = .today
        }
        model.module = module
        let start = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.contains { $0.name == "start" && $0.value == "1" } == true
        if host == "focus", start, !focus.isActive { focus.start() }
        openWindow()
        windowModel.module = module
        refreshWidgets()
    }

    private var widgetWork: DispatchWorkItem?

    private func startWidgetSync() {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let controller = Unmanaged<IslandController>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async { MainActor.assumeIsolated { controller.refreshWidgets() } }
            },
            FennWidgetActions.pingName,
            nil,
            .deliverImmediately
        )
        Publishers.Merge6(
            focus.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            TaskStore.shared.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            HabitStore.shared.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            MacBlocker.shared.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            WorkCalendar.shared.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            metrics.objectWillChange.map { _ in () }.eraseToAnyPublisher()
        )
        .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
        .sink { [weak self] _ in self?.refreshWidgets() }
        .store(in: &observers)
        Timer.publish(every: 120, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.refreshWidgets() }
            .store(in: &observers)
        refreshWidgets()
    }

    private func refreshWidgets() {
        #if DEBUG
        // QA runs are unsigned: touching the shared widget container would raise macOS' "access data from other apps" prompt.
        if UserDefaults.standard.bool(forKey: "FennQANoFocus") { return }
        #endif
        widgetWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            FennWidgetBridge.publish(metrics: self.metrics, focus: self.focus)
        }
        widgetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    // MARK: Notch notices

    private var noticedEvents = Set<String>()

    /// Dynamic-Island-style line out of the notch; with notices switched off, Fenn's little peek as before.
    private func notify(_ notice: IslandNotice, peek line: String? = nil) {
        if NotchNotices.isEnabled { NotchNotices.shared.post(notice) } else if let line { peek(line) }
    }

    private func startNotices() {
        let notices = NotchNotices.shared
        notices.anchor = { [weak self] in
            guard let self, let screen = NSScreen.screens.first else { return nil }
            let geometry = self.model.geometry
            return (screen, geometry.hasNotch ? geometry.notchWidth : 0, geometry.hasNotch ? geometry.barHeight : 0)
        }
        notices.canShow = { [weak self] in !(self?.model.isExpanded ?? true) }
        notices.onOpen = { [weak self] module in self?.expand(module: module ?? .today) }
        // Meetings: a word five minutes before they start.
        Timer.publish(every: 30, on: .main, in: .common).autoconnect()
            .sink { [weak self] now in
                self?.noticeUpcomingEvent(now: now)
            }
            .store(in: &observers)
        #if DEBUG
        // QA: -FennQANoticeDemo YES posts a sample notice a few seconds after launch.
        if UserDefaults.standard.bool(forKey: "FennQANoticeDemo") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                notices.post(IslandNotice(symbol: "checkmark", art: "Page-tasks", title: "Angebotsentwurf schicken",
                                          detail: tr("Aufgabe erledigt", "Task done"), module: .tasks, duration: 8))
            }
        }
        #endif
    }

    private func noticeUpcomingEvent(now: Date) {
        let soon = WorkCalendar.shared.events(on: now).filter {
            !$0.isAllDay && $0.calendar != TaskCalendarSync.calendarTitle
                && $0.start.timeIntervalSince(now) > 0 && $0.start.timeIntervalSince(now) <= 5 * 60
                && !noticedEvents.contains($0.id)
        }
        guard let event = soon.min(by: { $0.start < $1.start }) else { return }
        noticedEvents.insert(event.id)
        let minutes = max(1, Int((event.start.timeIntervalSince(now) / 60).rounded()))
        notify(IslandNotice(symbol: event.joinURL == nil ? "calendar" : "video.fill", art: "Page-today",
                            title: event.title,
                            detail: event.joinURL == nil ? tr("Gleich geht's los", "Starting soon") : tr("Gleich geht's los – Link im Kalender", "Starting soon – link in the calendar"),
                            trailing: tr("in \(minutes) min", "in \(minutes) min"), module: .today, duration: 7))
    }

    // MARK: Hover

    /// Opened by the mouse alone: it closes again when the mouse leaves, unless you clicked into it.
    private var openedByHover = false
    private var hoverWork: DispatchWorkItem?
    static let hoverOpensKey = "fenn.mac.hoverOpens"
    static var hoverOpens: Bool { UserDefaults.standard.object(forKey: hoverOpensKey) as? Bool ?? true }

    private func hoverChanged(_ inside: Bool) {
        hoverWork?.cancel()
        hoverWork = nil
        if inside {
            guard !model.isExpanded, Self.hoverOpens, placement == .top, pillDrag == nil else { return }
            // A short dwell, so passing the menu bar on the way to something else doesn't open Fenn.
            let work = DispatchWorkItem { [weak self] in self?.openByHover() }
            hoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14, execute: work)
        } else if openedByHover, model.isExpanded {
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.openedByHover, !self.panel.isKeyWindow,
                      !self.dictation.isListening, !self.noteDictation.isListening else { return }
                self.collapse()
            }
            hoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        }
    }

    private func openByHover() {
        guard !model.isExpanded else { return }
        openedByHover = true
        let launcher = IslandModel.fennFirst && !model.needsOnboarding
        if launcher {
            // Fenn's place in the launcher: card edge + padding + half the 52 pt pebble, below the notch.
            let card = model.geometry.panelSize.width
            let target = NSPoint(x: panel.frame.midX - card / 2 + 18 + 26,
                                 y: panel.frame.minY - IslandGeometry.gap - 18 - 26)
            model.popInFlight = true
            FennPeek.shared.pop(under: panel.frame, target: target, width: card + 40)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.model.popInFlight = false }
        } else {
            FennPeek.shared.pop(under: panel.frame)
        }
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // Fenn is out of the notch and in the air before the island grows around it.
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduce ? 0.1 : 0.42)) { [weak self] in
            guard let self, self.openedByHover, !self.model.isExpanded else { return }
            self.expand(takeFocus: false)
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        // Clicked into it: from now on it stays open like a clicked one.
        openedByHover = false
    }

    /// Fenn pops out under the notch and waves – only while the panel is closed and sits at the top.
    func peek(_ line: String) {
        guard !model.isExpanded, placement == .top, panel.isVisible else { return }
        FennPeek.shared.show(line, under: panel.frame)
    }

    /// `takeFocus: false` (hover) shows the island without pulling the keyboard away from the app you're in.
    func expand(module: IslandModule? = nil, takeFocus: Bool = true) {
        if takeFocus { openedByHover = false }
        if let module { model.module = module }
        if !model.isExpanded {
            model.launcher = module == nil && placement == .top && IslandModel.fennFirst && !model.needsOnboarding
        }
        if !model.isExpanded {
            layout(expanded: true)
            model.isExpanded = true
        }
        #if DEBUG
        // QA screenshots: show the panel without taking the keyboard from whatever the person is typing in.
        if UserDefaults.standard.bool(forKey: "FennQANoFocus") {
            panel.orderFrontRegardless()
            // -FennQASnapshot <file.png>: the panel draws itself into a PNG a few seconds later.
            if let path = UserDefaults.standard.string(forKey: "FennQASnapshot") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                    // -FennQACards YES: the routine, slipping and resurface cards plus the routine editor, drawn off-screen.
                    if UserDefaults.standard.bool(forKey: "FennQACards") {
                        let habit = HabitStore.shared.active.first ?? Habit(title: "Demo")
                        let renderer = ImageRenderer(content: VStack(spacing: 14) {
                            HabitsTodayCard(store: HabitStore.shared) {}
                            SlippingCard(store: TaskStore.shared)
                            ResurfaceCard(loadNow: true)
                            HabitEditor(habit: habit, store: HabitStore.shared) {}
                        }
                        .frame(width: 440).padding(20).background(Color.black).environment(\.colorScheme, .dark))
                        renderer.scale = 2
                        if let image = renderer.cgImage {
                            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                        }
                        return
                    }
                    if UserDefaults.standard.bool(forKey: "FennQANotice") {
                        let renderer = ImageRenderer(content: NotchNotices.qaStrip(barHeight: 32))
                        renderer.scale = 2
                        if let image = renderer.cgImage {
                            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                        }
                        return
                    }
                    if UserDefaults.standard.bool(forKey: "FennQAPop") {
                        let renderer = ImageRenderer(content: PopView.strip)
                        renderer.scale = 2
                        if let image = renderer.cgImage {
                            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                        }
                        return
                    }
                    if let mode = UserDefaults.standard.string(forKey: "FennQAWidgetGallery") {
                        let renderer = ImageRenderer(content: DesktopWidgetGallery(scheme: mode == "dark" ? .dark : .light))
                        renderer.scale = 2
                        if let image = renderer.cgImage {
                            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                        }
                        return
                    }
                    if UserDefaults.standard.bool(forKey: "FennQATimeline") {
                        let renderer = ImageRenderer(content: DayTimelineView(day: Date()) { _ in }
                            .frame(width: 440).padding(20).background(Color.black).environment(\.colorScheme, .dark))
                        renderer.scale = 2
                        if let image = renderer.cgImage {
                            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                        }
                        return
                    }
                    // show() at launch can race the start module back to the pill – open it again before drawing.
                    if let self { self.model.isExpanded = true; self.layout(expanded: true) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        guard let view = self?.panel.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                        view.cacheDisplay(in: view.bounds, to: rep)
                        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                    }
                }
            }
            return
        }
        #endif
        if takeFocus { panel.makeKeyAndOrderFront(nil) } else { panel.orderFrontRegardless() }
    }

    func collapse() {
        guard model.isExpanded else { return }
        openedByHover = false
        model.launcher = false
        model.isExpanded = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            if !model.isExpanded { layout(expanded: false) }
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        // Dictation keeps the panel open even if focus moves elsewhere.
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "FennQANoFocus") { return }
        #endif
        if !dictation.isListening && !noteDictation.isListening { collapse() }
    }

    /// Opens Fenn as a regular window (Dock icon while open, full screen with ⌃⌘F or the green button).
    func openWindow() {
        collapse()
        if window == nil {
            windowModel.module = model.module
            windowModel.needsOnboarding = false
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Fenn"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.fullScreenPrimary]
            window.minSize = NSSize(width: 560, height: 560)
            window.backgroundColor = NSColor(Fenn.canvas)
            window.appearance = Self.appearance
            window.delegate = self
            window.contentView = NSHostingView(rootView: FennWindowView(
                model: windowModel,
                focus: focus,
                coach: coach,
                knowledge: knowledge,
                services: IslandServices(metrics: metrics, dictation: dictation, notes: notes, noteDictation: noteDictation, ai: ai),
                actions: panelActions(inWindow: true)
            ))
            window.setFrameAutosaveName("FennMainWindow")
            if !window.setFrameUsingName("FennMainWindow") { window.center() }
            self.window = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func panelActions(inWindow: Bool) -> IslandActions {
        IslandActions(
            toggle: { [weak self] in if !inWindow { self?.toggle() } },
            collapse: { [weak self] in inWindow ? self?.window?.performClose(nil) : self?.collapse() },
            setPlacement: { [weak self] in self?.setPlacement($0) },
            movePill: { [weak self] ended in if !inWindow { self?.movePill(ended: ended) } },
            chooseAudio: { [weak self] in self?.chooseAudio() },
            chooseCloudFolder: { [weak self] in self?.chooseCloudFolder($0) },
            openWindow: { [weak self] in self?.openWindow() },
            finishOnboarding: { [weak self] in self?.finishOnboarding() },
            quit: { NSApp.terminate(nil) }
        )
    }

    /// After a file dialog: back to the window if it is open, otherwise to the island.
    private func reveal(_ module: IslandModule? = nil) {
        if let window, window.isVisible {
            if let module { windowModel.module = module }
            window.makeKeyAndOrderFront(nil)
        } else {
            expand(module: module)
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        // Back to a pure menu-bar companion without a Dock icon.
        NSApp.setActivationPolicy(.accessory)
    }

    private func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: IslandModel.onboardingKey)
        model.needsOnboarding = false
        model.module = .today
        if MacIntro.needsIntro {
            expand(module: .today)
            MacIntro.shared.start()
        }
    }

    private func chooseAudio() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.audio]
        openPanel.allowsMultipleSelection = false
        openPanel.prompt = tr("Transkribieren", "Transcribe")
        NSApp.activate()
        let result = openPanel.runModal()
        reveal(.today)
        if result == .OK, let url = openPanel.url {
            Task { await notes.transcribe(url) }
        }
    }

    /// The sandbox can't see iCloud Drive by path: the person picks (or creates) the "Fenn" folder once.
    private func chooseCloudFolder(_ provider: SyncProvider) {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        openPanel.prompt = tr("Verbinden", "Connect")
        switch provider {
        case .iCloud:
            openPanel.directoryURL = FennCloudFolder.iCloudDrive
            openPanel.message = tr("Wähle in iCloud Drive den Ordner „Fenn“ – oder iCloud Drive selbst, dann legt Fenn ihn an.",
                                   "Pick the “Fenn” folder in iCloud Drive – or iCloud Drive itself and Fenn creates it.")
        case .other:
            openPanel.message = tr("Wähle einen Ordner „Fenn“ – oder einen anderen, dann legt Fenn ihn darin an.",
                                   "Pick a “Fenn” folder – or any other and Fenn creates it inside.")
        }
        NSApp.activate()
        let result = openPanel.runModal()
        reveal()
        guard result == .OK, let url = openPanel.url else { return }
        FennCloudFolder.shared.connect(url)
        storageChanged()
    }

    /// Everything reads from the new root after the sync folder changed.
    private func storageChanged() {
        IdeaStore.shared.reload()
        metrics.reload()
        knowledge.storageChanged()
        notes.refreshRecent()
        TaskStore.shared.reload()
        HabitStore.shared.reload()
        HabitStore.shared.applyAuto()
    }

    private func toggleDictation() {
        if !dictation.isListening { expand(module: .coach) }
        dictation.toggle()
    }

    private func setPlacement(_ newPlacement: IslandPlacement) {
        placement = newPlacement
        UserDefaults.standard.set(newPlacement.rawValue, forKey: IslandPlacement.defaultsKey)
        storePillCenter(nil)
        layout(expanded: model.isExpanded)
    }

    /// Dragging the collapsed pill: it follows the mouse anywhere on the screen. Dropped near the top centre it goes
    /// back to the notch; anywhere else it stays there and opens towards the middle of the screen.
    private func movePill(ended: Bool) {
        guard !model.isExpanded, let screen = NSScreen.screens.first else { return }
        let mouse = NSEvent.mouseLocation
        if !ended {
            if pillDrag == nil { pillDrag = (mouse, panel.frame.origin) }
            guard let drag = pillDrag else { return }
            panel.setFrameOrigin(NSPoint(x: (drag.origin.x + mouse.x - drag.mouse.x).rounded(), y: (drag.origin.y + mouse.y - drag.mouse.y).rounded()))
            return
        }
        guard pillDrag != nil else { return }
        pillDrag = nil
        let visible = screen.visibleFrame
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        if center.y > visible.maxY - 60, abs(center.x - screen.frame.midX) < 160 {
            return setPlacement(.top)
        }
        placement = center.x < visible.midX ? .left : .right
        UserDefaults.standard.set(placement.rawValue, forKey: IslandPlacement.defaultsKey)
        storePillCenter(CGPoint(x: (center.x - visible.minX) / visible.width, y: (center.y - visible.minY) / visible.height))
        layout(expanded: false)
    }

    private func storePillCenter(_ point: CGPoint?) {
        pillCenter = point.map { CGPoint(x: min(max($0.x, 0), 1), y: min(max($0.y, 0), 1)) }
        if let pillCenter {
            UserDefaults.standard.set([Double(pillCenter.x), Double(pillCenter.y)], forKey: Self.pillCenterKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.pillCenterKey)
        }
    }

    private static var storedPillCenter: CGPoint? {
        guard let values = UserDefaults.standard.array(forKey: pillCenterKey) as? [Double], values.count == 2 else { return nil }
        return CGPoint(x: values[0], y: values[1])
    }

    /// Primary display (the one with the menu bar).
    private func layout(expanded: Bool) {
        guard let screen = NSScreen.screens.first else { return }
        let geometry = IslandGeometry.forScreen(screen, placement: placement, panelSize: model.panelSize, pillScale: model.pillScale)
        if model.geometry != geometry { model.geometry = geometry }

        var size = expanded ? geometry.expandedWindowSize : geometry.collapsedSize
        if expanded, model.launcher, placement == .top {
            size.height = geometry.collapsedSize.height + IslandGeometry.gap + IslandModel.launcherHeight + IslandGeometry.shadowMargin
        }
        let visible = screen.visibleFrame
        let origin: NSPoint
        switch placement {
        case .top:
            let centerX: CGFloat
            if geometry.hasNotch, let left = screen.auxiliaryTopLeftArea {
                centerX = screen.frame.minX + left.width + geometry.notchWidth / 2
            } else {
                centerX = screen.frame.midX
            }
            let top = geometry.hasNotch ? screen.frame.maxY : visible.maxY - 8
            origin = NSPoint(x: centerX - size.width / 2, y: top - size.height)
        case .left, .right:
            // The pill's centre: where it was dragged to, or the middle of its edge.
            let pill = geometry.collapsedSize
            let center = pillCenter.map { NSPoint(x: visible.minX + $0.x * visible.width, y: visible.minY + $0.y * visible.height) }
                ?? NSPoint(x: placement == .left ? visible.minX + 6 + pill.width / 2 : visible.maxX - 6 - pill.width / 2, y: visible.midY)
            let x = placement == .left ? center.x - pill.width / 2 : center.x + pill.width / 2 - size.width
            origin = NSPoint(x: min(max(x, visible.minX), visible.maxX - size.width),
                             y: min(max(center.y - size.height / 2, visible.minY), visible.maxY - size.height))
        }
        panel.setFrame(
            NSRect(x: origin.x.rounded(), y: origin.y.rounded(), width: size.width, height: size.height),
            display: true
        )
    }

    func coachContext(for question: String) -> CoachContext {
        var parts = [tr("Jetzt: ", "Now: ") + Date().formatted(date: .complete, time: .shortened)]
        var sources: [String] = []
        if focus.isActive {
            parts.append(tr("Laufender Fokus-Timer: ", "Running focus timer: ") + "\(focus.taskTitle), \(focus.phaseTitle), \(focus.label)")
        }
        let profileText = String((FennVault.readText(FennStorage.url(.profile)) ?? "").prefix(8000))
        if !profileText.isEmpty {
            parts.append(tr("Profil des Nutzers (profile.md):", "User profile (profile.md):") + "\n" + profileText)
            sources.append("profile.md")
        }
        if let goals = FennVault.readText(FennStorage.url(.goals)), goals.contains("## ") {
            parts.append(tr("Ziele (goals.md):", "Goals (goals.md):") + "\n" + goals.prefix(2000))
            sources.append("goals.md")
        }
        let journal = knowledge.journalContext()
        if !journal.isEmpty {
            parts.append(tr("Journal der letzten Tage (Befinden, Tagespläne, Rückblicke):", "Journal of the last days (how they feel, day plans, reviews):") + "\n" + journal)
            sources.append("journal")
        }
        let habits = HabitStore.shared.facts
        if !habits.isEmpty {
            parts.append(habits)
            sources.append("habits")
        }
        let week = metrics.records(lastDays: 7)
        let focusBlocks = week.reduce(0) { $0 + $1.focusBlocks }
        let tasksDone = week.reduce(0) { $0 + ($1.tasksCompleted ?? 0) }
        let habitsDone = week.reduce(0) { $0 + ($1.habitsDone ?? 0) }
        parts.append(tr("Letzte 7 Tage: \(focusBlocks) Fokusblöcke, \(tasksDone) Aufgaben erledigt, \(habitsDone) Routinen abgehakt, \(metrics.streakDays) Tage in Serie aktiv.",
                        "Last 7 days: \(focusBlocks) focus blocks, \(tasksDone) tasks done, \(habitsDone) routines ticked, active \(metrics.streakDays) days in a row."))
        sources.append(tr("Verlauf", "History"))
        let profileURL = FennStorage.url(.profile)
        let hits = knowledge.search(question, limit: 4).filter { $0.chunk.file != profileURL }
        if !hits.isEmpty {
            let notes = hits.map { hit in
                let heading = hit.chunk.heading.isEmpty ? "" : " – \(hit.chunk.heading)"
                return "[\(hit.chunk.file.lastPathComponent)\(heading)]\n\(hit.chunk.text)"
            }
            parts.append(tr("Passende Notizen aus dem Second Brain des Nutzers:", "Matching notes from the user's second brain:")
                         + "\n\n" + notes.joined(separator: "\n\n"))
            for hit in hits where !sources.contains(hit.chunk.file.lastPathComponent) {
                sources.append(hit.chunk.file.lastPathComponent)
            }
        }
        return CoachContext(persona: knowledge.soul, text: parts.joined(separator: "\n\n"), sources: sources)
    }
}
