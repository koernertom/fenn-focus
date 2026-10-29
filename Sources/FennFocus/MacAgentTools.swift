import Foundation
import FennFocusCore

/// What Fenn can do on the Mac – on top of the shared task tools.
@MainActor
enum MacAgentTools {
    static func make(_ c: IslandController) -> [AgentTool] {
        let sections: [String: IslandModule] = [
            "heute": .today, "aufgaben": .tasks, "fokus": .focus, "fenn": .coach, "notizen": .notes, "journal": .journal,
            "ideen": .ideas, "verbindungen": .connectors, "routinen": .habits,
        ]
        return SharedAgentTools.tasks + SharedAgentTools.habits + [
            AgentTool("today_overview", "Holt den Überblick über heute: Termine, Fokuszeit, fällige Aufgaben, Routinen.") { _ in
                var lines: [String] = []
                let events = WorkCalendar.shared.events(on: Date()).filter { !$0.isAllDay && $0.end > Date() }
                if !events.isEmpty {
                    lines.append("Termine: " + events.prefix(6).map { "\(AgendaCard.time($0.start)) \($0.title)" }.joined(separator: "; "))
                }
                let habits = HabitStore.shared.today()
                if !habits.isEmpty {
                    lines.append("Routinen: \(habits.filter { HabitStore.shared.isDone($0) }.count) von \(habits.count) erledigt")
                }
                let store = TaskStore.shared
                lines.append("Fokus heute \(store.focusMinutes(in: .today)) min, erledigt \(store.doneCount(in: .today)) Aufgaben")
                let due = store.open.filter { $0.isDueToday || $0.isOverdue }
                if !due.isEmpty { lines.append("Heute fällig: " + due.prefix(8).map(\.title).joined(separator: "; ")) }
                if c.focus.isActive { lines.append("Fokus läuft: \(c.focus.taskTitle), noch \(c.focus.label)") }
                return .info(lines.joined(separator: "\n"))
            },
            AgentTool("open_section", "Öffnet einen Bereich der App, wenn die Person etwas sehen will.",
                      properties: ["section": AgentTool.string("Bereich", options: Array(sections.keys).sorted())], required: ["section"]) { args in
                guard let module = (args["section"] as? String).flatMap({ sections[$0.lowercased()] }) else { return .info("Unbekannter Bereich.") }
                c.model.module = module
                return .done(tr("\(module.title) geöffnet", "Opened \(module.title)"), symbol: module.symbol)
            },
            AgentTool("start_focus", "Startet die Pomodoro-Session mit den aktuellen Werten (Standard 8 Stunden, 50 Minuten Arbeit, 10 Minuten Pause). minutes ändert nur die Arbeitslänge.",
                      properties: ["minutes": AgentTool.number("Arbeitsminuten, optional"),
                                   "total_hours": AgentTool.number("Gesamtfenster in Stunden, optional"),
                                   "break_minutes": AgentTool.number("Pausenminuten, optional"),
                                   "task": AgentTool.string("Titel der Aufgabe")],
                      needsIntent: AgentTool.startWords + ["fokus", "focus", "pomodoro", "konzentr"]) { args in
                if let hours = (args["total_hours"] as? NSNumber)?.intValue { c.focus.setTotalMinutes(hours * 60) }
                if let minutes = (args["minutes"] as? NSNumber)?.intValue { c.focus.setWorkMinutes(minutes) }
                if let brk = (args["break_minutes"] as? NSNumber)?.intValue { c.focus.setBreakMinutes(brk) }
                let query = ((args["task"] as? String) ?? "").lowercased()
                let task = query.isEmpty ? nil : TaskStore.shared.open.first { $0.title.lowercased().contains(query) || query.contains($0.title.lowercased()) }
                c.focus.focus(on: task)
                if task == nil, !query.isEmpty { c.focus.taskTitle = args["task"] as? String ?? c.focus.taskTitle }
                if !c.focus.isRunning { c.focus.start() }
                c.model.module = .focus
                return .done(tr("Pomodoro gestartet. \(c.focus.summary)", "Pomodoro started. \(c.focus.summary)"), symbol: "timer")
            },
            AgentTool("set_pomodoro", "Setzt Gesamtdauer, Arbeitsminuten und Pausenminuten unabhängig voneinander. Standard 8 Stunden, 50/10. start=true startet sofort.",
                      properties: ["total_minutes": AgentTool.number("Gesamtminuten"),
                                   "total_hours": AgentTool.number("Gesamtstunden"),
                                   "work_minutes": AgentTool.number("Arbeitsminuten"),
                                   "break_minutes": AgentTool.number("Pausenminuten"),
                                   "start": ["type": "boolean", "description": "Sofort starten"]]) { args in
                var change = PomodoroVoiceChange(start: (args["start"] as? Bool) ?? false)
                if let hours = (args["total_hours"] as? NSNumber)?.intValue { change.totalMinutes = hours * 60 }
                if let minutes = (args["total_minutes"] as? NSNumber)?.intValue { change.totalMinutes = minutes }
                if let work = (args["work_minutes"] as? NSNumber)?.intValue { change.workMinutes = work }
                if let brk = (args["break_minutes"] as? NSNumber)?.intValue { change.breakMinutes = brk }
                c.focus.applyVoice(change)
                if change.start { c.model.module = .focus }
                return .done(tr("Pomodoro: \(c.focus.summary)", "Pomodoro: \(c.focus.summary)"), symbol: "timer")
            },
            AgentTool("add_block_rule", "Legt eine Zeitregel zum Sperren an, z. B. 6 bis 8 Uhr kein Social Media.",
                      properties: ["start_hour": AgentTool.number("0–23"), "end_hour": AgentTool.number("0–23"),
                                   "start_minute": AgentTool.number("Standard 0"), "end_minute": AgentTool.number("Standard 0"),
                                   "social": ["type": "boolean", "description": "true = Social Media"],
                                   "weekdays": AgentTool.string("all, weekdays oder weekend")],
                      required: ["start_hour", "end_hour"]) { args in
                let start = ((args["start_hour"] as? NSNumber)?.intValue ?? 6) * 60 + ((args["start_minute"] as? NSNumber)?.intValue ?? 0)
                let end = ((args["end_hour"] as? NSNumber)?.intValue ?? 8) * 60 + ((args["end_minute"] as? NSNumber)?.intValue ?? 0)
                let social = (args["social"] as? Bool) ?? true
                let days: [Int]
                switch (args["weekdays"] as? String)?.lowercased() {
                case "weekdays", "werktags": days = [2, 3, 4, 5, 6]
                case "weekend", "wochenende": days = [1, 7]
                default: days = Array(1...7)
                }
                let rule = MacBlocker.shared.upsert(DistractionVoiceDraft(startMinutes: start, endMinutes: end, social: social, weekdays: days,
                                                                          title: social ? "Kein Social Media" : "Sperre"))
                c.model.module = .focus
                return .done(tr("Regel \(rule.windowLabel)", "Rule \(rule.windowLabel)"), symbol: "lock.fill")
            },
            AgentTool("stop_focus", "Beendet oder pausiert den laufenden Fokusblock.",
                      properties: ["pause": ["type": "boolean", "description": "true = nur pausieren"]]) { args in
                guard c.focus.isActive else { return .info("Es läuft kein Fokus.") }
                if args["pause"] as? Bool == true { c.focus.pause(); return .done(tr("Fokus pausiert", "Focus paused"), symbol: "pause.circle") }
                c.focus.stop()
                return .done(tr("Fokus beendet", "Focus stopped"), symbol: "stop.circle")
            },
            AgentTool("block_distractions", "Sperrt ablenkende Apps und Websites für eine Zeit.",
                      properties: ["minutes": AgentTool.number("Minuten")], required: ["minutes"], needsIntent: AgentTool.startWords + ["sperr", "block", "ablenk"]) { args in
                let minutes = max(5, min(240, (args["minutes"] as? NSNumber)?.intValue ?? 30))
                MacBlocker.shared.start(minutes: minutes)
                return .done(tr("Ablenkungen \(minutes) min gesperrt", "Distractions blocked for \(minutes) min"), symbol: "lock.fill")
            },
            AgentTool("remember", "Merkt sich eine dauerhafte Info über die Person (Vorlieben, Umstände) in MEMORY.md.",
                      properties: ["fact": AgentTool.string("Die Info in einem Satz")], required: ["fact"]) { args in
                guard let fact = args["fact"] as? String, !fact.isEmpty else { return .info("Nichts zu merken.") }
                c.knowledge.remember(fact)
                return .done(tr("Gemerkt: \(fact)", "Remembered: \(fact)"), symbol: "brain.head.profile")
            },
            AgentTool("switch_mode", "Wechselt den Modus auf dem Mac (z. B. Fokus, Freizeit, Erholung oder eigene): andere Module in der Leiste, gesperrte und geöffnete Apps. „Meine Leiste“ hebt die Sperren wieder auf.",
                      properties: ["mode": AgentTool.string("Name des Modus", options: MacMode.all.map(\.title))], required: ["mode"],
                      needsIntent: ["modus", "mode", "fokus", "focus", "freizeit", "feierabend", "erholung", "leiste"]) { args in
                let wanted = (args["mode"] as? String ?? "").lowercased()
                guard let mode = MacMode.all.first(where: { $0.title.lowercased() == wanted })
                        ?? MacMode.all.first(where: { $0.title.lowercased().contains(wanted) || wanted.contains($0.title.lowercased()) }) else {
                    return .info("Diesen Modus gibt es nicht. Vorhanden: " + MacMode.all.map(\.title).joined(separator: ", "))
                }
                mode.activate()
                return .done(tr("Modus: \(mode.title)", "Mode: \(mode.title)"), symbol: "square.grid.2x2", detail: "Modus \(mode.title) ist an. \(mode.detail)")
            },
        ]
    }
}
