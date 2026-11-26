import SwiftUI
import AppKit
import Carbon.HIToolbox
import FennFocusCore

/// The whole panel for one task: its goal, the title big, the running Pomodoro. "Abschließen" (⌘⏎) ticks it off and the
/// next one follows straight away in the same Pomodoro – the goal's next step, else what's next overall.
struct TaskFocusView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var focus: FocusTimer
    @ObservedObject var nav: TasksNav
    private var finished: [String] { nav.focusFinished }

    var body: some View {
        let task = nav.focusTaskId.flatMap { id in store.tasks.first { $0.id == id && !$0.done } }
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Button { nav.closeFocus() } label: {
                    Label(tr("Aufgaben", "Tasks"), systemImage: "chevron.left").font(.fenn(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Fenn.fg.opacity(0.65))
                .help(tr("Zurück zu den Aufgaben (Esc)", "Back to the tasks (Esc)"))
                Spacer()
            }

            if let task {
                taskBody(task)
                Spacer(minLength: 0)
            } else {
                allDone.frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Task

    @ViewBuilder
    private func taskBody(_ task: FennTask) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let goal = store.goal(task.goalId) {
                Label(goal.title, systemImage: goal.symbol ?? "flag.checkered")
                    .font(.fenn(size: 12.5)).foregroundStyle(Fenn.fg.opacity(0.6))
            }
            Text(task.title)
                .font(Fenn.display(30))
                .foregroundStyle(Fenn.fg)
                .lineLimit(4)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
                .id(task.id)
                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
            HStack(spacing: 10) {
                if let estimate = task.estimateMinutes {
                    Label(task.spentMinutes > 0 ? "\(TaskFormat.duration(task.spentMinutes)) / \(TaskFormat.duration(estimate))" : "~\(TaskFormat.duration(estimate))",
                          systemImage: "hourglass")
                } else if task.spentMinutes > 0 {
                    Label(TaskFormat.duration(task.spentMinutes), systemImage: "timer")
                }
                if let due = task.due { Label(TaskFormat.when(due), systemImage: "calendar") }
            }
            .font(.fenn(size: 12))
            .foregroundStyle(Fenn.fg.opacity(0.55))
        }

        clock

        HStack(spacing: 10) {
            Button { FocusFlow.startPause(task, focus: focus) } label: {
                Label(focus.isRunning ? tr("Pause", "Pause") : (focus.isActive ? tr("Weiter", "Resume") : tr("Start", "Start")),
                      systemImage: focus.isRunning ? "pause.fill" : "play.fill")
                    .font(.fenn(size: 13, weight: .semibold))
                    .frame(minWidth: 96, minHeight: 30)
            }
            .buttonStyle(FennPillButtonStyle(prominent: true))
            .help(tr("Leertaste", "Space"))
            .padding(.trailing, 6)
            Button { FocusFlow.complete(task, store: store, focus: focus, nav: nav) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                    Text(tr("Abschließen", "Complete"))
                    Text("⌘⏎").foregroundStyle(Fenn.fg.opacity(0.45))
                }
                .font(.fenn(size: 13, weight: .medium))
                .frame(minHeight: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Fenn.fg.opacity(0.8))
            .help(tr("Abhaken – die nächste Aufgabe kommt sofort", "Tick off – the next task follows right away"))
            Spacer()
        }

        if let after = FocusFlow.next(after: task, store: store) {
            (Text(tr("Danach: ", "Up next: ")).foregroundColor(Fenn.fg.opacity(0.5)) + Text(after.title).foregroundColor(Fenn.fg.opacity(0.75)))
                .font(.fenn(size: 13)).lineLimit(1)
        }
        if !finished.isEmpty {
            Text(tr("Schon geschafft: ", "Done already: ") + finished.joined(separator: ", "))
                .font(.fenn(size: 11)).foregroundStyle(Fenn.fg.opacity(0.45)).lineLimit(2)
        }
    }

    /// The Pomodoro as it runs – on a soft aura capsule, like the other key numbers.
    private var clock: some View {
        let palette = MeshAura.Palette.level
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        return HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                DotMatrixText(text: focus.isActive ? focus.label : PomodoroClock.clock(TimeInterval(focus.focusMinutes * 60)), height: 46, color: palette.ink)
                Text(focus.isActive
                     ? tr("\(focus.phaseTitle) · Pomodoro \(focus.blocksInRound + 1) von \(FocusTimer.blocksPerRound) · Session noch \(focus.sessionLabel)",
                          "\(focus.phaseTitle) · Pomodoro \(focus.blocksInRound + 1) of \(FocusTimer.blocksPerRound) · session \(focus.sessionLabel) left")
                     : tr("Bereit · \(focus.focusMinutes) min Arbeit, \(focus.breakMinutes) min Pause", "Ready · \(focus.focusMinutes) min work, \(focus.breakMinutes) min break"))
                    .font(.fenn(size: 11.5)).foregroundStyle(palette.ink.opacity(0.75))
            }
            Spacer(minLength: 0)
            ZStack {
                Circle().stroke(palette.ink.opacity(0.2), lineWidth: 5)
                Circle().trim(from: 0, to: focus.isActive ? max(0.001, focus.progress) : 0)
                    .stroke(palette.ink.opacity(0.9), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: focus.isRunning ? "timer" : "pause")
                    .font(.fenn(size: 18, weight: .medium)).foregroundStyle(palette.ink.opacity(0.85))
            }
            .frame(width: 58, height: 58)
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .background {
            ZStack {
                MeshAura(palette: palette)
                LinearGradient(colors: [.white.opacity(0.2), .clear, .black.opacity(0.15)], startPoint: .top, endPoint: .bottom)
            }
            .clipShape(shape)
        }
        .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.05), .white.opacity(0.2)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
        .shadow(color: palette.colors[1].opacity(0.25), radius: 14, y: 6)
        .accessibilityElement(children: .combine)
    }

    // MARK: All done

    private var allDone: some View {
        VStack(spacing: 14) {
            ZStack {
                PebbleMac(size: 96)
                PebbleFace(mood: .happy, blush: true).frame(width: 96, height: 96)
            }
            .accessibilityHidden(true)
            Text(tr("Alles erledigt", "All done")).font(Fenn.display(28)).foregroundStyle(Fenn.fg)
            Text(finished.isEmpty ? tr("Keine offene Aufgabe mehr. Atme durch.", "No open task left. Take a breath.")
                                  : tr("\(finished.count) geschafft in diesem Fokus. Atme durch.", "\(finished.count) finished in this focus. Take a breath."))
                .font(.fenn(size: 13)).foregroundStyle(Fenn.fg.opacity(0.6))
            if focus.isActive {
                DotMatrixText(text: focus.label, height: 22, color: Fenn.fg.opacity(0.6))
                Button(tr("Pomodoro beenden", "End the Pomodoro")) { focus.stop() }
                    .buttonStyle(.plain).font(.fenn(size: 13)).foregroundStyle(Fenn.fg.opacity(0.65))
            }
            Button(tr("Zurück zu den Aufgaben", "Back to the tasks")) { nav.closeFocus() }
                .buttonStyle(FennPillButtonStyle(prominent: true))
        }
        .frame(maxWidth: .infinity)
    }

}

/// What the focus view's buttons (and keys) do.
@MainActor
enum FocusFlow {
    static func startPause(_ task: FennTask, focus: FocusTimer) {
        if !focus.isActive {
            focus.focus(on: task)
            focus.start()
        } else if focus.isRunning {
            focus.pause()
        } else {
            if focus.taskId != task.id { focus.handOver(to: task) }
            focus.start()
        }
    }

    /// The goal's next step, else the next task overall – never the one in focus.
    static func next(after task: FennTask, store: TaskStore) -> FennTask? {
        if let goal = task.goalId, let step = store.open.first(where: { $0.goalId == goal && $0.id != task.id }) { return step }
        return store.next(3).first { $0.id != task.id }
    }

    /// Tick off; the next task takes over the running Pomodoro (its minutes so far stay with the finished one).
    static func complete(_ task: FennTask, store: TaskStore, focus: FocusTimer, nav: TasksNav) {
        let following = next(after: task, store: store)
        if focus.isActive { focus.handOver(to: following) } else { focus.focus(on: following) }
        store.toggle(task.id)
        nav.focusFinished.append(task.title)
        withAnimation(.snappy) { nav.focusTaskId = following?.id }
    }

    /// Opens the focus view on a task; a Pomodoro running on another one moves over to it.
    static func enter(_ task: FennTask, focus: FocusTimer, nav: TasksNav, start: Bool) {
        if focus.isActive { focus.handOver(to: task) } else { focus.focus(on: task) }
        if start, !focus.isRunning { focus.start() }
        nav.focusFinished = []
        nav.openFocus(on: task)
    }
}

// MARK: - Command palette

struct PaletteItem: Identifiable {
    let id: String
    let title: String
    let kind: String
    let symbol: String
    /// "Befehle", "Ziele", "Aufgaben", "Bereiche" – the palette draws a small header where it changes.
    var group: String = ""
    let run: () -> Void
}

/// ⌘K: search tasks, goals, modules and actions; ↑↓ to move, ⏎ to run, Esc to close.
struct CommandPalette: View {
    let items: [PaletteItem]
    @ObservedObject var nav: TasksNav
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.fenn(size: 14, weight: .medium)).foregroundStyle(Fenn.fg.opacity(0.5))
                TextField(tr("Aufgaben, Ziele, Bereiche, Aktionen …", "Tasks, goals, areas, actions …"), text: $nav.paletteQuery)
                    .textFieldStyle(.plain)
                    .font(.fenn(size: 15))
                    .focused($focused)
                    .onChange(of: nav.paletteQuery) { _, _ in nav.paletteIndex = 0 }
                Text("esc").font(.fenn(size: 11)).foregroundStyle(Fenn.fg.opacity(0.4))
            }
            .padding(.horizontal, 14).frame(height: 46)
            Rectangle().fill(Fenn.hairline).frame(height: 1)
            if items.isEmpty {
                Text(tr("Nichts gefunden.", "Nothing found.")).font(.fenn(size: 12)).foregroundStyle(Fenn.fg.opacity(0.5))
                    .frame(maxWidth: .infinity, minHeight: 50)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                if index == 0 || items[index - 1].group != item.group, !item.group.isEmpty {
                                    Text(item.group).font(.fenn(size: 11.5, weight: .semibold)).foregroundStyle(Fenn.fg.opacity(0.5))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 10).padding(.top, index == 0 ? 2 : 8).padding(.bottom, 2)
                                }
                                row(item, selected: index == nav.paletteIndex)
                                    .id(item.id)
                                    .onTapGesture { nav.closePalette(); item.run() }
                            }
                        }
                        .padding(6)
                    }
                    .scrollIndicators(.never)
                    .frame(height: min(340, CGFloat(items.count) * 36 + CGFloat(Set(items.map(\.group)).count) * 26 + 12))
                    .onChange(of: nav.paletteIndex) { _, index in
                        if items.indices.contains(index) { proxy.scrollTo(items[index].id) }
                    }
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Fenn.canvas))
        .fennGlass(cornerRadius: 18)
        .onAppear { DispatchQueue.main.async { focused = true } }
    }

    private func row(_ item: PaletteItem, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.symbol).font(.fenn(size: 13)).foregroundStyle(Fenn.fg.opacity(0.6)).frame(width: 20)
            Text(item.title).font(.fenn(size: 13)).foregroundStyle(Fenn.fg).lineLimit(1)
            Spacer(minLength: 6)
            Text(item.kind).font(.fenn(size: 11.5)).foregroundStyle(Fenn.fg.opacity(0.45)).lineLimit(1)
            if selected { Image(systemName: "return").font(.fenn(size: 10, weight: .semibold)).foregroundStyle(Fenn.fg.opacity(0.45)) }
        }
        .padding(.horizontal, 10).frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? Fenn.accent.opacity(0.14) : Color.clear))
        .contentShape(Rectangle())
    }
}

// MARK: - Keys

/// Keys for the Tasks module. The island is a nonactivating panel where SwiftUI focus is unreliable, so a local key monitor
/// listens – only for the window the module sits in, only while it is on screen, and never while a text field is being edited
/// (except Esc, ↑↓ and ⏎ for the palette's own field).
@MainActor
final class TaskKeyMonitor: ObservableObject {
    weak var window: NSWindow?
    var handle: (NSEvent, Bool) -> Bool = { _, _ in false }
    private var monitor: Any?

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, event.window === window else { return event }
            // A text field or a date field (↑/↓ change its value) keeps its keys.
            let responder = window.firstResponder
            let editing = (responder as? NSTextView)?.isEditable == true || responder is NSDatePicker
            return self.handle(event, editing) ? nil : event
        }
    }

    func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// When the Tasks module opens, an empty text field (Fenn's input below) gives the keys back to the list.
    func releaseEmptyField() {
        guard let window, let field = window.firstResponder as? NSTextView, field.isEditable, field.string.isEmpty else { return }
        window.makeFirstResponder(nil)
    }

    enum Key { case escape, up, down, enter, space, other }

    static func key(_ event: NSEvent) -> Key {
        switch Int(event.keyCode) {
        case kVK_Escape: return .escape
        case kVK_UpArrow: return .up
        case kVK_DownArrow: return .down
        case kVK_Return, kVK_ANSI_KeypadEnter: return .enter
        case kVK_Space: return .space
        default: return .other
        }
    }

    #if DEBUG
    /// QA only: types a few keys into the window ("down,space,cmd+k,g,esc"), one every 0.4 s, through the normal event queue.
    static func qaType(_ script: String, into window: NSWindow?) {
        guard let window else { return }
        let codes: [String: (Int, String)] = [
            "down": (kVK_DownArrow, "\u{F701}"), "up": (kVK_UpArrow, "\u{F700}"), "space": (kVK_Space, " "),
            "return": (kVK_Return, "\r"), "esc": (kVK_Escape, "\u{1B}"), "k": (kVK_ANSI_K, "k"), "n": (kVK_ANSI_N, "n"),
            "f": (kVK_ANSI_F, "f"), "w": (kVK_ANSI_W, "w"), "g": (kVK_ANSI_G, "g"),
        ]
        for (index, token) in script.split(separator: ",").enumerated() {
            let command = token.hasPrefix("cmd+")
            guard let (code, characters) = codes[String(token.dropFirst(command ? 4 : 0))] else { continue }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4 * Double(index)) {
                guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: command ? .command : [],
                                                   timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                                   context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                                   isARepeat: false, keyCode: UInt16(code)) else { return }
                NSApp.postEvent(event, atStart: false)
            }
        }
    }
    #endif

    /// Command, option, control or shift held – arrows and the keypad set their own flags, which don't count.
    static func modifiers(_ event: NSEvent) -> NSEvent.ModifierFlags {
        event.modifierFlags.intersection([.command, .option, .control, .shift])
    }
}

/// Hands the hosting window to the key monitor.
struct WindowReader: NSViewRepresentable {
    let found: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ReaderView()
        view.found = found
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ReaderView: NSView {
        var found: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let window = self.window
            DispatchQueue.main.async { [weak self] in self?.found?(window) }
        }
    }
}
