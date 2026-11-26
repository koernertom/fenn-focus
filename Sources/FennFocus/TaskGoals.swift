import SwiftUI
import FennFocusCore

// Goals in the Tasks module: one card per goal (hours this week against the weekly target, steps done, the next step),
// the goal chip on task rows, "Heute zuerst" (the one task that matters most today) and the planner bits behind them.

/// Where the Tasks module is: shared by the views, the key monitor and the command palette.
@MainActor
final class TasksNav: ObservableObject {
    static let shared = TasksNav()

    /// The focus view is open – on `focusTaskId`, or on "Alles erledigt" when that is nil.
    @Published var focusOpen = false
    @Published var focusTaskId: UUID?
    /// Titles ticked off since the focus view opened.
    @Published var focusFinished: [String] = []
    /// The row picked with ↑/↓ in the list.
    @Published var selected: UUID?
    @Published var paletteOpen = false
    @Published var paletteQuery = ""
    @Published var paletteIndex = 0
    /// 0 = this week in the week view, 1 = next week …
    @Published var weekOffset = 0
    /// The goals view opens the editor for a new goal (from the palette or a shortcut).
    @Published var pendingNewGoal = false
    /// Bumped to put the cursor into the "Neue Aufgabe" field.
    @Published var focusAddRequest = 0

    /// Esc belongs to the focus view or the palette while one is open – the island doesn't fold then.
    var takesEscape: Bool { focusOpen || paletteOpen }

    private init() {}

    func openFocus(on task: FennTask?) {
        focusTaskId = task?.id
        withAnimation(.snappy) { focusOpen = true }
    }

    func closeFocus() {
        withAnimation(.snappy) { focusOpen = false }
    }

    func openPalette() {
        paletteQuery = ""
        paletteIndex = 0
        withAnimation(.snappy(duration: 0.2)) { paletteOpen = true }
    }

    func closePalette() {
        withAnimation(.snappy(duration: 0.2)) { paletteOpen = false }
    }
}

@MainActor
enum GoalPlanner {
    /// The suggestion for "Heute zuerst": the next step of the goal that is furthest behind its weekly hours,
    /// otherwise simply the next task.
    static func suggestedMain(_ store: TaskStore) -> FennTask? {
        let week = DateInterval.thisWeek
        let behind = store.activeGoals.compactMap { goal -> (missing: Int, step: FennTask)? in
            guard let step = store.nextStep(of: goal.id) else { return nil }
            return ((goal.weeklyMinutes ?? 0) - store.goalMinutes(goal.id, in: week), step)
        }
        .sorted { $0.missing > $1.missing }
        if let first = behind.first, first.missing > 0 { return first.step }
        return store.next(1).first ?? behind.first?.step
    }

    /// "Zeit reservieren": the task gets the first free stretch of today's working hours that is long enough for its estimate.
    /// Nil when nothing fits any more.
    @discardableResult
    static func reserveTime(for task: FennTask, store: TaskStore) -> Date? {
        let load = DayPlanner.load(on: Date(), tasks: store.tasks.filter { $0.id != task.id })
        let need = Double(DayPlanner.minutes(of: task)) * 60
        guard let gap = DayPlanner.gaps(in: load).first(where: { $0.duration >= need }) else { return nil }
        var copy = task
        copy.due = gap.start
        if let start = copy.start, start > gap.start { copy.start = nil }
        store.update(copy)
        return gap.start
    }

    /// A symbol that fits the goal's name – the person can change it.
    static func symbol(for title: String) -> String {
        let lower = title.lowercased()
        let hints: [(String, [String])] = [
            ("figure.run", ["lauf", "marathon", "run", "triathlon", "rennen"]),
            ("dumbbell", ["gym", "kraft", "fit", "training", "workout"]),
            ("graduationcap", ["thesis", "arbeit schreiben", "studium", "prüfung", "exam", "promotion", "phd", "master", "bachelor"]),
            ("book.closed", ["buch", "book", "lesen", "read", "schreiben", "write"]),
            ("briefcase", ["kunde", "client", "pitch", "job", "projekt", "project", "angebot"]),
            ("house", ["wohnung", "haus", "home", "umzug", "move"]),
            ("heart", ["gesund", "health", "familie", "family"]),
            ("leaf", ["ruhe", "meditation", "calm", "garten"]),
            ("lightbulb", ["idee", "idea", "startup", "gründ"]),
            ("paintpalette", ["design", "kunst", "art", "malen", "musik"]),
            ("chart.line.uptrend.xyaxis", ["umsatz", "revenue", "wachst", "growth", "spar", "save"]),
        ]
        return hints.first { $0.1.contains(where: lower.contains) }?.0 ?? "flag.checkered"
    }

    // MARK: Week

    struct GoalWeek: Identifiable {
        let goal: FennGoal
        let minutes: Int
        let done: [FennTask]
        let slipped: [FennTask]
        var id: UUID { goal.id }
    }

    /// Per goal: hours this week, steps done this week, and what was due this week but is still open.
    static func week(_ store: TaskStore, now: Date = Date()) -> [GoalWeek] {
        let week = DateInterval.thisWeek
        let today = Calendar.current.startOfDay(for: now)
        return store.activeGoals.map { goal in
            let steps = store.tasks(of: goal.id)
            return GoalWeek(goal: goal, minutes: store.goalMinutes(goal.id, in: week),
                            done: steps.filter { $0.done && ($0.doneAt.map(week.contains) ?? false) },
                            slipped: steps.filter { !$0.done && ($0.due.map { week.contains($0) && $0 < today } ?? false) })
        }
    }

    /// "## Wochen-Check" for today's journal: per goal hours against target, steps done, what slipped.
    static func weekCheck(_ store: TaskStore, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let weekNumber = calendar.component(.weekOfYear, from: now)
        let goals = week(store, now: now)
        var lines = ["", "## Wochen-Check, \(tr("KW", "week")) \(weekNumber), \(now.formatted(date: .omitted, time: .shortened))"]
        for item in goals {
            var line = "- **\(item.goal.title)**: \(TaskFormat.duration(item.minutes))"
            if let target = item.goal.weeklyMinutes { line += " \(tr("von", "of")) \(TaskFormat.duration(target))" }
            line += ", " + stepsDone(item.done.count)
            if !item.slipped.isEmpty { line += tr(", verrutscht: ", ", slipped: ") + item.slipped.map(\.title).joined(separator: ", ") }
            lines.append(line)
        }
        let range = DateInterval.thisWeek
        let loose = store.tasks.filter { $0.goalId == nil && $0.done && ($0.doneAt.map(range.contains) ?? false) }.count
        let total = store.focusMinutes(in: range)
        lines.append(tr("- Ohne Ziel: \(loose) erledigt. Fokus gesamt: \(TaskFormat.duration(total)).",
                        "- No goal: \(loose) done. Total focus: \(TaskFormat.duration(total))."))
        if goals.isEmpty { lines.append(tr("- Noch keine Ziele – vielleicht eins für nächste Woche?", "- No goals yet – maybe one for next week?")) }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// Appends the week check to today's journal file.
    static func closeWeek(_ store: TaskStore) {
        let url = FennStorage.url(.journal(FennVault.dayKey(Date())))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: tr("de_DE", "en_US"))
        formatter.dateFormat = "EEEE, d. MMMM yyyy"
        FennVault.append(weekCheck(store), to: url, header: "# Journal, \(formatter.string(from: Date()))\n")
    }

    /// "1 Schritt erledigt", "3 Schritte erledigt".
    static func stepsDone(_ count: Int) -> String {
        count == 1 ? tr("1 Schritt erledigt", "1 step done") : tr("\(count) Schritte erledigt", "\(count) steps done")
    }

    /// "noch 12 Tage", "heute", "3 Tage drüber".
    static func deadlineText(_ goal: FennGoal) -> String? {
        guard let days = goal.daysLeft() else { return nil }
        switch days {
        case 0: return tr("Deadline heute", "Due today")
        case 1: return tr("noch 1 Tag", "1 day left")
        case 2...: return tr("noch \(days) Tage", "\(days) days left")
        case -1: return tr("1 Tag drüber", "1 day over")
        default: return tr("\(-days) Tage drüber", "\(-days) days over")
        }
    }

    /// 200 → "3:20"
    static func clock(_ minutes: Int) -> String { String(format: "%d:%02d", minutes / 60, minutes % 60) }

    /// 222 → "3,7" (hours with one decimal, in the app language; whole hours without).
    static func hours(_ minutes: Int) -> String {
        let value = Double(minutes) / 60
        let text = abs(value - value.rounded()) < 0.05 ? String(Int(value.rounded())) : String(format: "%.1f", value)
        return L10n.usesEnglish ? text : text.replacingOccurrences(of: ".", with: ",")
    }

    /// "3,7 von 8 h diese Woche" or "3,7 h diese Woche".
    static func weekLine(_ minutes: Int, target: Int?) -> String {
        if let target { return tr("\(hours(minutes)) von \(hours(target)) h diese Woche", "\(hours(minutes)) of \(hours(target)) h this week") }
        return tr("\(hours(minutes)) h diese Woche", "\(hours(minutes)) h this week")
    }

    /// Names for the goal symbols in the picker.
    static func symbolName(_ symbol: String) -> String {
        switch symbol {
        case "flag.checkered": return tr("Ziel", "Finish")
        case "figure.run": return tr("Laufen", "Running")
        case "book.closed": return tr("Buch", "Book")
        case "briefcase": return tr("Arbeit", "Work")
        case "graduationcap": return tr("Studium", "Study")
        case "heart": return tr("Herz", "Heart")
        case "lightbulb": return tr("Idee", "Idea")
        case "dumbbell": return tr("Kraft", "Strength")
        case "leaf": return tr("Ruhe", "Calm")
        case "house": return tr("Zuhause", "Home")
        case "paintpalette": return tr("Kreativ", "Creative")
        default: return tr("Wachstum", "Growth")
        }
    }
}

// MARK: - Small pieces

/// A sentence-case section title with an optional quiet value on the right.
struct FennSectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.fenn(size: 13, weight: .semibold)).foregroundStyle(Fenn.fg.opacity(0.6))
            Spacer(minLength: 6)
            trailing()
        }
        .padding(.horizontal, 4)
    }
}

extension FennSectionHeader where Trailing == Text {
    init(_ title: String, value: String? = nil) {
        self.title = title
        self.trailing = { Text(value ?? "").font(.fenn(size: 11.5)).foregroundStyle(Fenn.fg.opacity(0.5)) }
    }
}

/// Hours this week against the weekly target as a ring; just the hours when there is no target.
struct GoalRing: View {
    let minutes: Int
    let target: Int?
    var size: CGFloat = 40

    var body: some View {
        let progress = target.map { Double(minutes) / Double(max($0, 1)) } ?? 0
        let line = max(3, size / 11)
        ZStack {
            Circle().stroke(Fenn.fill, lineWidth: line)
            Circle()
                .trim(from: 0, to: min(1, progress))
                .stroke(Fenn.accent, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(GoalPlanner.hours(minutes))
                .font(.fenn(size: size >= 40 ? 11 : 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(Fenn.fg.opacity(0.8))
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GoalPlanner.weekLine(minutes, target: target))
    }
}

// MARK: - Goals view

/// "Ziele": all active goals in one grouped list, the editor inline, finished and archived goals folded away below.
struct GoalsView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var nav: TasksNav
    let edit: (FennTask) -> Void
    let startFocus: (FennTask) -> Void
    /// The goal being edited; a new one while its id isn't in the store yet.
    @State private var editing: FennGoal?
    @State private var expanded: Set<UUID> = []
    @State private var showClosed = false

    var body: some View {
        let active = store.activeGoals
        let week = active.reduce(0) { $0 + store.goalMinutes($1.id, in: .thisWeek) }
        VStack(alignment: .leading, spacing: 10) {
            FennSectionHeader(title: tr("Ziele", "Goals")) {
                if !active.isEmpty {
                    Text(tr("\(GoalPlanner.hours(week)) h diese Woche", "\(GoalPlanner.hours(week)) h this week"))
                        .font(.fenn(size: 11.5)).foregroundStyle(Fenn.fg.opacity(0.5))
                }
                Button { openNewGoal() } label: { Image(systemName: "plus") }
                    .buttonStyle(FennIconButtonStyle())
                    .help(tr("Neues Ziel", "New goal"))
                    .accessibilityLabel(tr("Neues Ziel", "New goal"))
            }

            if let goal = editing, store.goal(goal.id) == nil {
                GoalEditor(goal: goal, isNew: true, store: store) { withAnimation(.snappy) { editing = nil } }
                    .padding(14)
                    .fennGlass(cornerRadius: 18, shadow: false)
            }
            if active.isEmpty && editing == nil { empty }
            if !active.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(active.enumerated()), id: \.element.id) { index, goal in
                        if editing?.id == goal.id {
                            GoalEditor(goal: goal, isNew: false, store: store) { withAnimation(.snappy) { editing = nil } }
                                .padding(14)
                                .background(Fenn.fill)
                        } else {
                            GoalCard(goal: goal, store: store, expanded: expanded.contains(goal.id),
                                     toggleExpanded: { withAnimation(.snappy) { if expanded.contains(goal.id) { expanded.remove(goal.id) } else { expanded.insert(goal.id) } } },
                                     edit: { withAnimation(.snappy) { editing = goal } },
                                     editTask: edit, startFocus: startFocus)
                        }
                        if index < active.count - 1 { Rectangle().fill(Fenn.hairline).frame(height: 1).padding(.leading, 52) }
                    }
                }
                .fennGlass(cornerRadius: 18, shadow: false)
            }
            closed
        }
        .onChange(of: nav.pendingNewGoal) { _, pending in if pending { openNewGoal() } }
        .onAppear {
            if nav.pendingNewGoal { openNewGoal() }
            #if DEBUG
            if FennDemo.isOn, let first = active.first, UserDefaults.standard.bool(forKey: "FennQAGoalExpanded") { expanded.insert(first.id) }
            if FennDemo.isOn, UserDefaults.standard.bool(forKey: "FennQAGoalEditor") { editing = FennGoal(title: "", symbol: "flag.checkered") }
            #endif
        }
    }

    private func openNewGoal() {
        nav.pendingNewGoal = false
        withAnimation(.snappy) { editing = FennGoal(title: "", symbol: "flag.checkered") }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            ClaySymbol(symbol: "flag.checkered", size: 52)
            Text(tr("Ziele geben deinen Aufgaben eine Richtung.", "Goals give your tasks a direction."))
                .font(.fenn(size: 13, weight: .medium)).foregroundStyle(Fenn.fg.opacity(0.75))
            Text(tr("Leg eins an und häng Aufgaben mit @Ziel dran – Fenn zählt die Stunden, die hineingehen.",
                    "Add one and attach tasks with @goal – Fenn counts the hours that go in."))
                .font(.fenn(size: 12)).foregroundStyle(Fenn.fg.opacity(0.55))
                .multilineTextAlignment(.center)
            Button(tr("Ziel anlegen", "Add a goal")) { openNewGoal() }
                .buttonStyle(FennPillButtonStyle(prominent: true))
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    @ViewBuilder
    private var closed: some View {
        let closed = store.goals.filter { !$0.isActive }.sorted { $0.updated > $1.updated }
        if !closed.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Button { withAnimation(.snappy) { showClosed.toggle() } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right").font(.fenn(size: 10, weight: .semibold))
                            .rotationEffect(.degrees(showClosed ? 90 : 0))
                        Text(tr("Erreicht und archiviert, \(closed.count)", "Reached and archived, \(closed.count)"))
                            .font(.fenn(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Fenn.fg.opacity(0.5))
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if showClosed {
                    VStack(spacing: 0) {
                        ForEach(closed) { goal in
                            HStack(spacing: 10) {
                                Image(systemName: goal.done == true ? "checkmark.seal" : "archivebox")
                                    .font(.fenn(size: 13)).foregroundStyle(Fenn.fg.opacity(0.5)).frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(goal.title).font(.fenn(size: 13)).foregroundStyle(Fenn.fg.opacity(0.8))
                                    Text((goal.done == true ? tr("Erreicht", "Reached") : tr("Archiviert", "Archived"))
                                         + " · " + tr("\(GoalPlanner.hours(store.goalMinutes(goal.id))) h insgesamt", "\(GoalPlanner.hours(store.goalMinutes(goal.id))) h in total"))
                                        .font(.fenn(size: 11.5)).foregroundStyle(Fenn.fg.opacity(0.5))
                                }
                                Spacer()
                                Button(tr("Wieder aktiv", "Reactivate")) {
                                    var copy = goal
                                    copy.done = nil
                                    copy.archivedAt = nil
                                    withAnimation(.snappy) { store.updateGoal(copy) }
                                }
                                .buttonStyle(.plain).font(.fenn(size: 12, weight: .medium)).foregroundStyle(Fenn.accent)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .contextMenu {
                                Button(tr("Löschen", "Delete"), role: .destructive) { withAnimation(.snappy) { store.deleteGoal(goal.id) } }
                            }
                        }
                    }
                    .fennGlass(cornerRadius: 18, shadow: false)
                }
            }
        }
    }
}

/// One goal as a row: symbol, title, one line with the week's hours and the deadline, the ring; the next step under it.
/// A click unfolds all steps with "+ Schritt".
struct GoalCard: View {
    let goal: FennGoal
    @ObservedObject var store: TaskStore
    let expanded: Bool
    let toggleExpanded: () -> Void
    let edit: () -> Void
    let editTask: (FennTask) -> Void
    let startFocus: (FennTask) -> Void
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        let steps = store.tasks(of: goal.id)
        let next = store.nextStep(of: goal.id)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ClaySymbol(symbol: goal.symbol ?? "flag.checkered", size: 26)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(goal.title).font(.fenn(size: 15, weight: .semibold)).foregroundStyle(Fenn.fg).lineLimit(2)
                        Image(systemName: "chevron.right").font(.fenn(size: 10, weight: .semibold)).foregroundStyle(Fenn.fg.opacity(0.3))
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                    secondary.font(.fenn(size: 11.5)).lineLimit(1)
                }
                Spacer(minLength: 8)
                GoalRing(minutes: store.goalMinutes(goal.id, in: .thisWeek), target: goal.weeklyMinutes, size: 40)
                    .help(GoalPlanner.weekLine(store.goalMinutes(goal.id, in: .thisWeek), target: goal.weeklyMinutes))
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: toggleExpanded)
            .help(goal.why ?? "")

            if let next {
                HStack(spacing: 8) {
                    (Text(tr("Nächster Schritt: ", "Next step: ")).foregroundColor(Fenn.fg.opacity(0.55))
                     + Text(next.title).foregroundColor(Fenn.fg))
                        .font(.fenn(size: 13)).lineLimit(1)
                        .onTapGesture { editTask(next) }
                    Spacer(minLength: 6)
                    Button { startFocus(next) } label: { Image(systemName: "play.fill").font(.fenn(size: 11)) }
                        .buttonStyle(FennIconButtonStyle())
                        .help(tr("Fokus auf diesen Schritt", "Focus on this step"))
                }
                .padding(.leading, 38)
            } else {
                Text(steps.isEmpty ? tr("Noch kein Schritt. Was wäre der erste?", "No step yet. What would be the first?")
                                   : tr("Alle Schritte erledigt – Ziel erreicht oder fehlt noch einer?", "All steps done – goal reached, or is one missing?"))
                    .font(.fenn(size: 12)).foregroundStyle(Fenn.fg.opacity(0.55))
                    .padding(.leading, 38)
            }

            if expanded { stepList(steps).padding(.leading, 26) }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            Button(tr("Bearbeiten", "Edit"), action: edit)
            Button(tr("Als erreicht markieren", "Mark as reached")) {
                var copy = goal
                copy.done = true
                withAnimation(.snappy) { store.updateGoal(copy) }
            }
            Button(tr("Archivieren", "Archive")) {
                var copy = goal
                copy.archivedAt = Date()
                withAnimation(.snappy) { store.updateGoal(copy) }
            }
            Divider()
            Button(tr("Löschen (Aufgaben bleiben)", "Delete (tasks stay)"), role: .destructive) { withAnimation(.snappy) { store.deleteGoal(goal.id) } }
        }
    }

    /// "3,7 von 8 h diese Woche · noch 9 Tage" – only the deadline takes a colour, and only when it is close.
    private var secondary: Text {
        let muted = Fenn.fg.opacity(0.55)
        var text = Text(GoalPlanner.weekLine(store.goalMinutes(goal.id, in: .thisWeek), target: goal.weeklyMinutes)).foregroundColor(muted)
        if let deadline = GoalPlanner.deadlineText(goal), let days = goal.daysLeft() {
            text = text + Text(" · ").foregroundColor(muted)
                + Text(deadline).foregroundColor(days < 0 ? Fenn.danger : (days <= 7 ? Fenn.amber : muted))
        }
        return text
    }

    private func stepList(_ steps: [FennTask]) -> some View {
        let ordered = steps.filter { !$0.done }.sorted { $0.rank < $1.rank } + steps.filter(\.done).sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }
        return VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Fenn.hairline).frame(height: 1)
            ForEach(ordered) { task in
                TaskRow(task: task, isEditing: false, isFocused: false, showGoal: false,
                        toggle: { withAnimation(.snappy) { store.toggle(task.id) } },
                        edit: { editTask(task) },
                        startFocus: { startFocus(task) })
                Rectangle().fill(Fenn.hairline).frame(height: 1).padding(.leading, 44)
            }
            HStack(spacing: 10) {
                Image(systemName: "plus").font(.fenn(size: 12, weight: .semibold)).foregroundStyle(Fenn.fg.opacity(0.45)).frame(width: 22)
                TextField(tr("Schritt hinzufügen", "Add a step"), text: $draft)
                    .textFieldStyle(.plain)
                    .font(.fenn(size: 13))
                    .focused($fieldFocused)
                    .onSubmit(addStep)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Text(tr("\(steps.filter(\.done).count) von \(steps.count) Schritten erledigt", "\(steps.filter(\.done).count) of \(steps.count) steps done"))
                .font(.fenn(size: 11.5)).foregroundStyle(Fenn.fg.opacity(0.5))
                .padding(.horizontal, 12).padding(.bottom, 2)
        }
    }

    private func addStep() {
        var tasks = TaskCapture.rules(draft, topics: store.topics, goals: store.goals).tasks
        guard !tasks.isEmpty else { return }
        for index in tasks.indices { tasks[index].goalId = goal.id }
        store.add(tasks)
        draft = ""
        fieldFocused = true
    }
}

/// Round ▶ in the accent colour – for the one primary action on screen.
struct PlayButton: View {
    var size: CGFloat = 30
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "play.fill")
                .font(.fenn(size: size * 0.36, weight: .semibold))
                .foregroundStyle(Fenn.onAccent)
                .frame(width: size, height: size)
                .background(Circle().fill(Fenn.accent))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("Fokus starten", "Start focus"))
    }
}

/// New goal or edit: title, why, deadline and hours per week on one row, symbol from a menu.
struct GoalEditor: View {
    @State var goal: FennGoal
    let isNew: Bool
    let store: TaskStore
    let close: () -> Void
    @FocusState private var titleFocused: Bool

    private static let hours = [1, 2, 3, 4, 5, 6, 8, 10, 12, 15, 20]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Menu {
                    ForEach(FennGoal.symbols, id: \.self) { symbol in
                        Button { goal.symbol = symbol } label: { Label(GoalPlanner.symbolName(symbol), systemImage: symbol) }
                    }
                } label: {
                    Image(systemName: goal.symbol ?? "flag.checkered").font(.fenn(size: 15)).foregroundStyle(Fenn.accent)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 26, height: 26)
                .help(tr("Symbol wählen", "Pick a symbol"))
                TextField(tr("Was willst du erreichen?", "What do you want to reach?"), text: $goal.title)
                    .textFieldStyle(.plain)
                    .font(.fenn(size: 15, weight: .medium))
                    .focused($titleFocused)
                    .onSubmit(save)
            }
            TextField(tr("Warum ist es dir wichtig?", "Why does it matter to you?"),
                      text: Binding(get: { goal.why ?? "" }, set: { goal.why = $0.isEmpty ? nil : $0 }), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.fenn(size: 13))
                .lineLimit(1...3)
                .padding(.leading, 36)

            HStack(spacing: 14) {
                if let deadline = goal.deadline {
                    HStack(spacing: 4) {
                        Text(tr("Frist", "Deadline")).font(.fenn(size: 12)).foregroundStyle(Fenn.fg.opacity(0.55))
                        DatePicker("", selection: Binding(get: { deadline }, set: { goal.deadline = Calendar.current.startOfDay(for: $0) }), displayedComponents: .date)
                            .labelsHidden().datePickerStyle(.field).fixedSize()
                        Button { goal.deadline = nil } label: { Image(systemName: "xmark.circle.fill").font(.fenn(size: 10)) }
                            .buttonStyle(.plain).foregroundStyle(Fenn.fg.opacity(0.35))
                            .accessibilityLabel(tr("Frist entfernen", "Remove deadline"))
                    }
                } else {
                    Button(tr("+ Frist", "+ Deadline")) {
                        goal.deadline = Calendar.current.date(byAdding: .day, value: 30, to: Calendar.current.startOfDay(for: Date()))
                    }
                    .buttonStyle(.plain).font(.fenn(size: 12, weight: .medium)).foregroundStyle(Fenn.fg.opacity(0.65))
                }
                Menu {
                    ForEach(Self.hours, id: \.self) { hours in Button("\(hours) h") { goal.weeklyMinutes = hours * 60 } }
                    Divider()
                    Button(tr("Kein Wochenziel", "No weekly target")) { goal.weeklyMinutes = nil }
                } label: {
                    Text(goal.weeklyMinutes.map { tr("\(GoalPlanner.hours($0)) h pro Woche", "\(GoalPlanner.hours($0)) h per week") } ?? tr("Stunden pro Woche …", "Hours per week …"))
                        .font(.fenn(size: 12, weight: .medium))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Spacer(minLength: 0)
            }
            .padding(.leading, 36)

            HStack(spacing: 8) {
                if !isNew {
                    Button { store.deleteGoal(goal.id); close() } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain)
                        .foregroundStyle(Fenn.danger.opacity(0.8))
                        .help(tr("Ziel löschen – die Aufgaben bleiben", "Delete goal – the tasks stay"))
                }
                Spacer()
                Button(tr("Abbrechen", "Cancel"), action: close)
                    .buttonStyle(.plain).font(.fenn(size: 13)).foregroundStyle(Fenn.fg.opacity(0.7))
                Button(isNew ? tr("Anlegen", "Add") : tr("Sichern", "Save"), action: save)
                    .buttonStyle(FennPillButtonStyle(prominent: true))
                    .disabled(goal.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear { if isNew { titleFocused = true } }
    }

    private func save() {
        guard !goal.title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if isNew {
            if goal.symbol == nil || goal.symbol == "flag.checkered" { goal.symbol = GoalPlanner.symbol(for: goal.title) }
            store.addGoal(goal)
        } else {
            store.updateGoal(goal)
        }
        close()
    }
}

// MARK: - Most important first

/// "Heute zuerst": the one task that matters most today, as one quiet row with ▶. Fenn suggests the next step of the goal
/// that is furthest behind its hours; "Zeit reservieren" and changing it sit in the … menu.
struct MainTaskCard: View {
    @ObservedObject var store: TaskStore
    let startFocus: (FennTask) -> Void
    @State private var note: String?

    var body: some View {
        let day = FennVault.dayKey(Date())
        let main = store.mainTask(on: day)
        let suggestion = GoalPlanner.suggestedMain(store)
        Group {
            if let main {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Button { withAnimation(.snappy) { store.toggle(main.id) } } label: {
                            Image(systemName: "circle").font(.fenn(size: 18, weight: .light)).foregroundStyle(main.priority.color)
                        }
                        .buttonStyle(.plain)
                        .frame(width: 22)
                        .help(tr("Erledigt", "Done"))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(main.title).font(.fenn(size: 15, weight: .medium)).foregroundStyle(Fenn.fg).lineLimit(2)
                            Text(secondary(main)).font(.fenn(size: 11.5)).foregroundStyle(Fenn.fg.opacity(0.55)).lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        menu(day: day, main: main, suggestion: suggestion)
                        PlayButton(size: 30) { startFocus(main) }
                            .help(tr("Fokus auf die wichtigste Aufgabe", "Focus on the most important task"))
                    }
                    if let note {
                        Text(note).font(.fenn(size: 11.5)).foregroundStyle(Fenn.fg.opacity(0.55)).padding(.leading, 32)
                    }
                }
                .contextMenu { menuItems(day: day, main: main, suggestion: suggestion) }
            } else if let suggestion {
                HStack(spacing: 10) {
                    Image(systemName: "star").font(.fenn(size: 13)).foregroundStyle(Fenn.amber).frame(width: 22)
                    (Text(tr("Vorschlag für heute zuerst: ", "Suggested first today: ")).foregroundColor(Fenn.fg.opacity(0.55)) + Text(suggestion.title).foregroundColor(Fenn.fg))
                        .font(.fenn(size: 13)).lineLimit(1)
                    Spacer(minLength: 6)
                    Button(tr("Festlegen", "Set")) { withAnimation(.snappy) { store.setMain(suggestion.id, on: day) } }
                        .buttonStyle(.plain).font(.fenn(size: 12, weight: .medium)).foregroundStyle(Fenn.accent)
                        .help(tr("Der nächste Schritt des Ziels, dem diese Woche die meisten Stunden fehlen", "The next step of the goal that is furthest behind its hours this week"))
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fennGlass(cornerRadius: 16, shadow: false)
        .onChange(of: main?.id) { _, _ in note = nil }
    }

    /// "Heute zuerst · Nordlicht-Pitch gewinnen · ab 9:30 · ~4 h"
    private func secondary(_ task: FennTask) -> String {
        var parts = [tr("Heute zuerst", "First today")]
        if let goal = store.goal(task.goalId) { parts.append(goal.title) }
        if let due = task.due, Calendar.current.isDateInToday(due), DayPlanner.hasTime(due) {
            parts.append(tr("ab \(due.formatted(date: .omitted, time: .shortened))", "from \(due.formatted(date: .omitted, time: .shortened))"))
        }
        if let estimate = task.estimateMinutes { parts.append("~\(TaskFormat.duration(estimate))") }
        return parts.joined(separator: " · ")
    }

    private func menu(day: String, main: FennTask, suggestion: FennTask?) -> some View {
        Menu { menuItems(day: day, main: main, suggestion: suggestion) } label: {
            Image(systemName: "ellipsis").font(.fenn(size: 13, weight: .medium)).foregroundStyle(Fenn.fg.opacity(0.55))
                .frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(tr("Zeit reservieren oder ändern", "Reserve time or change"))
    }

    @ViewBuilder
    private func menuItems(day: String, main: FennTask, suggestion: FennTask?) -> some View {
        if !(main.due.map { Calendar.current.isDateInToday($0) && DayPlanner.hasTime($0) } ?? false) {
            Button(tr("Zeit reservieren", "Reserve time"), systemImage: "calendar.badge.plus") {
                if let start = GoalPlanner.reserveTime(for: main, store: store) {
                    note = tr("Ab \(start.formatted(date: .omitted, time: .shortened)) geblockt.", "Blocked from \(start.formatted(date: .omitted, time: .shortened)).")
                } else {
                    note = tr("Heute ist keine Lücke mehr frei, die lang genug ist.", "No free slot left today that is long enough.")
                }
            }
        }
        Menu(tr("Andere Aufgabe", "Another task")) {
            if let suggestion, suggestion.id != main.id {
                Button(tr("Vorschlag: \(suggestion.title)", "Suggestion: \(suggestion.title)")) { store.setMain(suggestion.id, on: day) }
                Divider()
            }
            ForEach(store.next(10).filter { $0.id != main.id }) { task in
                Button(task.title) { store.setMain(task.id, on: day) }
            }
        }
        Divider()
        Button(tr("Keine Hauptaufgabe", "No main task")) { store.setMain(nil, on: day) }
    }
}

/// A thin capsule bar, filled to `value`.
struct GoalBar: View {
    let value: Double
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geometry in
            Capsule().fill(Fenn.fill)
                .overlay(alignment: .leading) {
                    Capsule().fill(Fenn.accent)
                        .frame(width: value > 0 ? max(height, geometry.size.width * min(1, value)) : 0)
                }
        }
        .frame(height: height)
    }
}
