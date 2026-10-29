import Foundation

/// Standalone check for the pomodoro clock and voice parsers. Not part of an app target.
@main
enum RhythmCoreCheck {
    static func main() {
        var failed = 0
        func expect(_ condition: Bool, _ label: String) {
            if condition { print("ok  \(label)") } else { failed += 1; print("FAIL \(label)") }
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let fridayMorning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 7, minute: 0))!
        let rule = DistractionRule.socialMorning
        expect(DistractionSchedule.isActive(rule, at: fridayMorning, calendar: calendar), "6–8 active at 07:00")
        let before = calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 5, minute: 59))!
        let after = calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 8, minute: 0))!
        expect(!DistractionSchedule.isActive(rule, at: before, calendar: calendar), "inactive at 05:59")
        expect(!DistractionSchedule.isActive(rule, at: after, calendar: calendar), "inactive at 08:00")
        var weekdays = rule
        weekdays.weekdays = [2, 3, 4, 5, 6]
        expect(DistractionSchedule.isActive(weekdays, at: fridayMorning, calendar: calendar), "weekday rule on Friday")
        let saturday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 7))!
        expect(!DistractionSchedule.isActive(weekdays, at: saturday, calendar: calendar), "weekday rule off on Saturday")
        expect(DistractionSchedule.deviceIntervals(for: rule).count == 1, "2h window is one Screen Time interval")

        let social = DistractionVoice.parse("06:00–08:00: no social media")
        expect(social?.startMinutes == 6 * 60 && social?.endMinutes == 8 * 60 && social?.social == true, "parse 6–8 social")
        expect(DistractionVoice.parse("von 6 bis 8 kein Social Media")?.social == true, "parse German 6 bis 8")
        expect(DistractionVoice.parse("Wie spät ist es") == nil, "unrelated text is not a rule")

        let start = PomodoroVoice.parse("Pomodoro starten")
        expect(start?.start == true && start?.totalMinutes == nil && start?.workMinutes == nil, "start keeps current values")
        expect(PomodoroVoice.parse("Gesamtdauer 6 Stunden")?.totalMinutes == 360, "total 6 hours")
        expect(PomodoroVoice.parse("Arbeitsminuten 45")?.workMinutes == 45, "work 45")
        expect(PomodoroVoice.parse("Pausenminuten 5")?.breakMinutes == 5, "break 5")
        let all = PomodoroVoice.parse("Setze den Pomodoro auf 4 Stunden, 40 Minuten Arbeit und 8 Minuten Pause und starte")
        expect(all?.totalMinutes == 240 && all?.workMinutes == 40 && all?.breakMinutes == 8 && all?.start == true, "set all three and start")
        expect(PomodoroVoice.parse("Starte 25 Minuten Fokus")?.workMinutes == 25, "25 minute focus sets work")
        expect(PomodoroVoice.parse("Starte 25 Minuten Fokus")?.totalMinutes == nil, "25 minute focus leaves the window")
        expect(PomodoroVoice.parse("Wie starte ich den Fokus?") == nil, "a question does not start")

        let begin = calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 10))!
        let settings = PomodoroSettings(totalMinutes: 120, workMinutes: 50, breakMinutes: 10)
        let started = PomodoroClock.begin(settings, at: begin)
        let at1050 = calendar.date(byAdding: .minute, value: 50, to: begin)!
        let firstBreak = PomodoroClock.catchUp(started, now: at1050)
        expect(firstBreak.phase == "break" && firstBreak.completedWorkBlocks == 1, "50 min lands on the break")
        let at1130 = calendar.date(byAdding: .minute, value: 90, to: begin)!
        let secondWork = PomodoroClock.catchUp(started, now: at1130)
        expect(secondWork.phase == "work" && secondWork.completedWorkBlocks == 1, "90 min is the second work block")
        expect(abs(secondWork.focusedSeconds - 50 * 60) < 2, "focused time counts finished work blocks")
        let at1200 = calendar.date(byAdding: .minute, value: 120, to: begin)!
        let done = PomodoroClock.catchUp(started, now: at1200)
        expect(done.phase == "done" && done.completedWorkBlocks == 2, "120 min window finishes after two work blocks")

        let paused = PomodoroClock.pause(started, at: calendar.date(byAdding: .minute, value: 10, to: begin)!)
        expect(paused.phase == "paused" && abs(paused.focusedSeconds - 600) < 2, "pause keeps the focused minutes")
        let resumed = PomodoroClock.resume(paused, at: calendar.date(byAdding: .minute, value: 40, to: begin)!)
        expect(resumed.phase == "work" && (resumed.phaseEndsAt?.timeIntervalSince(resumed.phaseStartedAt ?? begin) ?? 0) > 39 * 60, "resume continues the block")

        if failed > 0 {
            print("\(failed) failed")
            exit(1)
        }
        print("all passed")
    }
}
