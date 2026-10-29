import Foundation
import FennFocusCore

/// Fills the desktop widgets from the stores the Mac already has, and applies ticks made in a widget.
@MainActor
enum FennWidgetBridge {
    static func publish(metrics: MetricsStore, focus: FocusTimer) {
        applyQueued()
        let snapshot = make(metrics: metrics, focus: focus)
        if let existing = FennWidgetSnapshot.load(), existing.sameContent(as: snapshot) { return }
        snapshot.save()
        WidgetReload.reloadAllTimelines()
    }

    private static func applyQueued() {
        for id in FennWidgetActions.drain() {
            if id.hasPrefix("habit:") {
                let parts = id.dropFirst(6).split(separator: "|").map(String.init)
                let store = HabitStore.shared
                guard let uuid = parts.first.flatMap(UUID.init(uuidString:)),
                      let habit = store.habits.first(where: { $0.id == uuid }) else { continue }
                let day = parts.count > 1 ? (HabitStore.date(parts[1]) ?? Date()) : Date()
                store.toggle(habit, on: day)
                continue
            }
            guard let uuid = UUID(uuidString: id) else { continue }
            TaskStore.shared.toggle(uuid)
        }
    }

    private static func make(metrics: MetricsStore, focus: FocusTimer) -> FennWidgetSnapshot {
        let day = FennVault.dayKey(Date())
        let record = metrics.record(for: Date())
        let blocker = MacBlocker.shared
        let blocked = [blocker.isActive ? blocker.endsAt : nil, blocker.scheduleEnds].compactMap { $0 }.filter { $0 > Date() }.max()
        let now = Date()
        let events = WorkCalendar.shared.events(on: now)
            .filter { !$0.isAllDay && $0.end > now && $0.calendar != TaskCalendarSync.calendarTitle }
            .prefix(4)
            .map { FennWidgetEvent(title: $0.title, start: $0.start, end: $0.end, canJoin: $0.joinURL != nil) }

        let clock = focus.publishedClock ?? PomodoroSnapshot(
            settings: PomodoroSettings(totalMinutes: focus.totalMinutes, workMinutes: focus.focusMinutes, breakMinutes: focus.breakMinutes),
            phase: "idle"
        )

        return FennWidgetSnapshot(
            day: day,
            german: Locale.current.language.languageCode?.identifier != "en",
            focusMinutes: TaskStore.shared.focusMinutes(in: .today),
            focusBlocks: record.focusBlocks,
            tasksDone: TaskStore.shared.doneCount(in: .today),
            streak: metrics.streakDays,
            blockedUntil: blocked,
            updated: Date(),
            events: Array(events),
            tasks: widgetTasks(),
            goals: goals(),
            habits: widgetHabits(),
            pomodoro: clock,
            focusTitle: focus.taskTitle
        )
    }

    /// The headings of profile/goals.md, newest first – what the journal's goal entries add.
    private static func goals() -> [String] {
        let text = FennVault.readText(FennStorage.url(.goals)) ?? ""
        let headings = text.components(separatedBy: "\n").filter { $0.hasPrefix("## ") }.map { String($0.dropFirst(3)) }
        return Array(headings.reversed().prefix(3))
    }

    private static func widgetTasks() -> [FennWidgetTask] {
        let store = TaskStore.shared
        let today = store.open.filter { $0.isDueToday || $0.isOverdue || $0.isActiveToday || $0.isStarred }
        let doneToday = store.tasks.filter { $0.done && ($0.doneAt.map(Calendar.current.isDateInToday) ?? false) }
        let pick = (today.isEmpty ? Array(store.open.prefix(6)) : Array(today.prefix(6))) + doneToday.prefix(2)
        return pick.prefix(6).map { task in
            var detail: [String] = []
            if let due = task.due { detail.append(TaskFormat.day(due)) }
            if let minutes = task.estimateMinutes { detail.append(TaskFormat.duration(minutes)) }
            return FennWidgetTask(
                id: task.id.uuidString, title: task.title, done: task.done,
                detail: detail.isEmpty ? nil : detail.joined(separator: ", "),
                high: task.priority == .high
            )
        }
    }

    private static func widgetHabits() -> [FennWidgetHabit] {
        let store = HabitStore.shared
        return store.today().prefix(8).map { habit in
            FennWidgetHabit(
                id: habit.id.uuidString, title: habit.title, done: store.isDone(habit),
                detail: HabitLine.subtitle(habit, store: store)?.text ?? habit.time.title,
                streak: store.streak(habit), symbol: habit.displaySymbol
            )
        }
    }
}
