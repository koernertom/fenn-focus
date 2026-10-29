import AppKit
import FennFocusCore

/// Pomodoro session: a window (starter 8 h) made of work and break cycles (starter 50/10).
/// All three lengths are independent. The running clock is an end date, so it survives sleep and relaunch.
@MainActor
final class FocusTimer: ObservableObject {
    enum Phase {
        case idle
        case focus
        case shortBreak
        case longBreak
    }

    static let blocksPerRound = 4

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var remaining: TimeInterval
    @Published private(set) var isRunning = false
    @Published private(set) var completedBlocks = 0
    @Published var taskTitle = tr("Fokus", "Focus")
    @Published var taskId: UUID?
    var onFocusBlockCompleted: () -> Void = {}

    private var settings: PomodoroSettings
    private var snapshot: PomodoroSnapshot?
    private var timer: Timer?
    private var loggedFocus: TimeInterval = 0

    init() {
        settings = Self.loadSettings()
        remaining = TimeInterval(settings.workMinutes * 60)
        restore()
    }

    var focusMinutes: Int { settings.workMinutes }
    var breakMinutes: Int { settings.breakMinutes }
    var totalMinutes: Int { settings.totalMinutes }
    var usesStarter: Bool { settings == .starter }
    var isActive: Bool { phase != .idle }

    /// The clock the desktop widget draws. Nil before the first start, after a finished session is cleared.
    var publishedClock: PomodoroSnapshot? { snapshot }

    var sessionRemaining: TimeInterval {
        if let snapshot, snapshot.phase == "paused" { return snapshot.sessionRemaining ?? 0 }
        return max(0, snapshot?.sessionEndsAt?.timeIntervalSinceNow ?? TimeInterval(totalMinutes * 60))
    }

    var sessionLabel: String { PomodoroClock.clock(sessionRemaining) }

    var progress: Double {
        guard let snapshot, let end = snapshot.phaseEndsAt, let start = snapshot.phaseStartedAt else { return 0 }
        let total = end.timeIntervalSince(start)
        return total > 0 ? 1 - remaining / total : 0
    }

    var label: String { PomodoroClock.clock(remaining) }
    var totalLabel: String {
        guard let snapshot, let end = snapshot.phaseEndsAt, let start = snapshot.phaseStartedAt else {
            return PomodoroClock.clock(TimeInterval(focusMinutes * 60))
        }
        return PomodoroClock.clock(end.timeIntervalSince(start))
    }

    var phaseTitle: String {
        switch phase {
        case .idle, .focus: return tr("Arbeit", "Work")
        case .shortBreak: return tr("Pause", "Break")
        case .longBreak: return tr("Lange Pause", "Long break")
        }
    }

    var summary: String {
        tr("\(FocusDial.label(totalMinutes)) gesamt, \(focusMinutes) min Arbeit, \(breakMinutes) min Pause",
           "\(FocusDial.label(totalMinutes)) total, \(focusMinutes) min work, \(breakMinutes) min break")
    }

    var blocksInRound: Int { completedBlocks % Self.blocksPerRound }

    func setMinutes(_ minutes: Int) { setWorkMinutes(FocusDial.minutes(at: FocusDial.index(of: minutes))) }
    func setWorkMinutes(_ minutes: Int) { update(work: minutes) }
    func setBreakMinutes(_ minutes: Int) { update(brk: minutes) }
    func setTotalMinutes(_ minutes: Int) { update(total: minutes) }

    func applyStarter() {
        settings = .starter
        saveSettings()
        if !isActive { remaining = TimeInterval(settings.workMinutes * 60) }
    }

    func applyVoice(_ change: PomodoroVoiceChange) {
        if let total = change.totalMinutes { setTotalMinutes(total) }
        if let work = change.workMinutes { setWorkMinutes(work) }
        if let brk = change.breakMinutes { setBreakMinutes(brk) }
        if change.start {
            if isActive, !isRunning { start() }
            else if !isActive { start() }
        }
    }

    func focus(on task: FennTask?) {
        taskId = task?.id
        taskTitle = task?.title ?? tr("Fokus", "Focus")
    }

    func start() {
        if isActive, !isRunning, let snapshot {
            adopt(PomodoroClock.resume(snapshot, at: Date()))
            arm()
            return
        }
        guard !isActive else { return }
        loggedFocus = 0
        adopt(PomodoroClock.begin(settings, at: Date()))
        FocusMusic.shared.sessionBegan()
        arm()
    }

    func pause() {
        guard let snapshot, isRunning else { return }
        adopt(PomodoroClock.pause(snapshot, at: Date()))
        timer?.invalidate()
        FocusMusic.shared.sessionPaused()
    }

    func addFiveMinutes() {
        guard var snapshot else { return }
        snapshot.phaseEndsAt = snapshot.phaseEndsAt?.addingTimeInterval(5 * 60)
        snapshot.sessionEndsAt = snapshot.sessionEndsAt?.addingTimeInterval(5 * 60)
        if snapshot.phase == "paused" {
            snapshot.pausedRemaining = (snapshot.pausedRemaining ?? 0) + 5 * 60
            snapshot.sessionRemaining = (snapshot.sessionRemaining ?? 0) + 5 * 60
        }
        adopt(snapshot)
    }

    func stop() {
        if let snapshot {
            var final = snapshot
            if final.phase == "work" || final.phase == "break" { final = PomodoroClock.pause(final, at: Date()) }
            logPartial(from: loggedFocus, to: final.focusedSeconds)
        }
        timer?.invalidate()
        self.snapshot = nil
        UserDefaults.standard.removeObject(forKey: Self.snapshotKey)
        FennNotificationBrand.clearPhase()
        isRunning = false
        phase = .idle
        remaining = TimeInterval(settings.workMinutes * 60)
        FocusMusic.shared.sessionEnded()
    }

    private func update(total: Int? = nil, work: Int? = nil, brk: Int? = nil) {
        settings = PomodoroSettings(
            totalMinutes: total ?? settings.totalMinutes,
            workMinutes: work ?? settings.workMinutes,
            breakMinutes: brk ?? settings.breakMinutes
        ).clamped()
        saveSettings()
        if var snapshot, snapshot.phase == "work" || snapshot.phase == "break" || snapshot.phase == "paused" {
            snapshot.settings = settings
            if total != nil { snapshot = PomodoroClock.retarget(snapshot, totalMinutes: settings.totalMinutes, at: Date()) }
            adopt(snapshot)
        } else if !isActive {
            remaining = TimeInterval(settings.workMinutes * 60)
        }
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: Self.snapshotKey),
              let stored = try? JSONDecoder().decode(PomodoroSnapshot.self, from: data) else { return }
        let snap = stored.phase == "paused" ? stored : PomodoroClock.catchUp(stored, now: Date())
        guard snap.phase == "work" || snap.phase == "break" || snap.phase == "paused" else {
            UserDefaults.standard.removeObject(forKey: Self.snapshotKey)
            return
        }
        loggedFocus = snap.focusedSeconds
        completedBlocks = snap.completedWorkBlocks
        adopt(snap)
        if snap.phase == "work" || snap.phase == "break" { arm() }
    }

    private func adopt(_ snap: PomodoroSnapshot) {
        let previousBlocks = completedBlocks
        let previousFocus = loggedFocus
        if snap.completedWorkBlocks > previousBlocks {
            let blocks = snap.completedWorkBlocks - previousBlocks
            let added = max(0, snap.focusedSeconds - previousFocus)
            let minutes = max(1, Int((added / Double(blocks) / 60).rounded()))
            for _ in 0..<blocks {
                TaskStore.shared.logFocus(minutes: minutes, taskId: taskId, title: taskTitle, start: Date().addingTimeInterval(Double(-minutes * 60)))
                onFocusBlockCompleted()
            }
            loggedFocus = snap.focusedSeconds
        }
        snapshot = snap
        settings = snap.settings
        completedBlocks = snap.completedWorkBlocks
        switch snap.phase {
        case "work":
            phase = .focus
            isRunning = true
            remaining = max(0, snap.phaseEndsAt?.timeIntervalSinceNow ?? 0)
        case "break":
            phase = .shortBreak
            isRunning = true
            remaining = max(0, snap.phaseEndsAt?.timeIntervalSinceNow ?? 0)
        case "paused":
            isRunning = false
            phase = snap.pausedKind == "break" ? .shortBreak : .focus
            remaining = snap.pausedRemaining ?? 0
        default:
            phase = .idle
            isRunning = false
            remaining = TimeInterval(settings.workMinutes * 60)
            FocusMusic.shared.sessionEnded()
        }
        if let data = try? JSONEncoder().encode(snap), snap.phase != "done" {
            UserDefaults.standard.set(data, forKey: Self.snapshotKey)
        }
        armNotification(snap)
        if snap.phase == "break" || snap.phase == "work", previousBlocks != snap.completedWorkBlocks, snap.phase == "break" {
            // Music keeps playing through the break. A new work block after a break does not reopen Spotify.
        }
    }

    private func logPartial(from before: TimeInterval, to after: TimeInterval) {
        let minutes = Int(((after - before) / 60).rounded())
        guard minutes >= 1 else { return }
        TaskStore.shared.logFocus(minutes: minutes, taskId: taskId, title: taskTitle, start: Date().addingTimeInterval(Double(-minutes * 60)))
    }

    private func arm() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private func refresh() {
        guard let snapshot else { return }
        let updated = PomodoroClock.catchUp(snapshot, now: Date())
        if updated != snapshot {
            adopt(updated)
            if updated.phase != "work", updated.phase != "break" { timer?.invalidate() }
        } else {
            remaining = max(0, snapshot.phaseEndsAt?.timeIntervalSinceNow ?? 0)
        }
    }

    private func armNotification(_ snap: PomodoroSnapshot) {
        guard snap.phase == "work" || snap.phase == "break", let end = snap.phaseEndsAt else {
            FennNotificationBrand.clearPhase()
            return
        }
        let finishes = (snap.sessionEndsAt?.timeIntervalSince(end) ?? 1) < 2
        let title: String
        let body: String
        if finishes {
            title = tr("Pomodoro fertig", "Pomodoro done")
            body = tr("Die Session ist vorbei.", "The session is over.")
        } else if snap.phase == "work" {
            title = tr("Pause", "Break")
            body = tr("Arbeitsblock vorbei. \(breakMinutes) Minuten Pause.", "Work block done. \(breakMinutes) minute break.")
        } else {
            title = tr("Weiterarbeiten", "Back to work")
            body = tr("Pause vorbei. Nächster Arbeitsblock.", "Break's over. Next work block.")
        }
        FennNotificationBrand.schedulePhase(after: end.timeIntervalSinceNow, title: title, body: body, url: "fennfocus://focus")
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: Self.settingsKey) }
    }

    private static let settingsKey = "fenn.pomodoro.settings"
    private static let snapshotKey = "fenn.pomodoro.snapshot"

    private static func loadSettings() -> PomodoroSettings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(PomodoroSettings.self, from: data) else { return .starter }
        return settings.clamped()
    }
}
