import Foundation
import FennFocusCore

/// Commands that have to work without a model: pomodoro lengths and timed block rules.
@MainActor
enum LocalVoice {
    static func handle(_ text: String, focus: FocusTimer, blocker: MacBlocker, openFocus: () -> Void) -> String? {
        if let draft = DistractionVoice.parse(text) {
            let rule = blocker.upsert(draft)
            let when = rule.weekdays.count == 7 ? tr("jeden Tag", "every day") : tr("an ausgewählten Tagen", "on selected days")
            var reply = tr("Regel \(rule.windowLabel): \(rule.title), \(when).", "Rule \(rule.windowLabel): \(rule.title), \(when).")
            if rule.isSocial, blocker.socialApps.isEmpty {
                reply += " " + tr("Keine bekannte Social-App gefunden. Unter Fokus kannst du welche hinzufügen. Websites im Browser sperrt der Mac hier nicht.",
                                  "No known social app found. Add some under Focus. This Mac block doesn't cover websites in the browser.")
            }
            return reply
        }
        guard let change = PomodoroVoice.parse(text) else { return nil }
        let running = focus.isActive
        focus.applyVoice(change)
        if change.start {
            openFocus()
            if running {
                return tr("Läuft schon: \(focus.phaseTitle), noch \(focus.label). \(focus.summary).",
                          "Already running: \(focus.phaseTitle), \(focus.label) left. \(focus.summary).")
            }
            return tr("Pomodoro gestartet. \(focus.summary).", "Pomodoro started. \(focus.summary).")
        }
        return tr("Gespeichert. \(focus.summary).", "Saved. \(focus.summary).")
    }
}
