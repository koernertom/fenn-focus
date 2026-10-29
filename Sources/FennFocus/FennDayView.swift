import SwiftUI

// The day hour by hour: appointments grey, tasks as coloured blocks (drag to move, tap to edit),
// tasks without a time on top; above it the load of the day and Fenn's suggestions when it's too full.

/// How much of the day the calendar card on the home screen shows (stored per device).
enum DayCalendarSize: String, CaseIterable, Identifiable {
    case small, medium, large

    static let key = "fenn.home.calendarSize"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: return tr("Klein, nächste 3 Std.", "Small, next 3 hours")
        case .medium: return tr("Mittel, nächste 6 Std.", "Medium, next 6 hours")
        case .large: return tr("Groß, ganzer Tag", "Large, whole day")
        }
    }

    /// Hours shown from the current hour on; nil = the whole day as the task view shows it.
    var hours: Int? {
        switch self {
        case .small: return 3
        case .medium: return 6
        case .large: return nil
        }
    }

    var hourHeight: CGFloat {
        switch self {
        case .small: return 40
        case .medium: return 44
        case .large: return 54
        }
    }
}

/// The size switch for the calendar card: one menu, the three sizes with a check on the current one.
struct DayCalendarSizeMenu: View {
    @Binding var size: DayCalendarSize

    var body: some View {
        Menu {
            Picker(tr("Größe", "Size"), selection: $size) {
                ForEach(DayCalendarSize.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "arrow.up.and.down")
                .font(.fenn(size: 12, weight: .semibold))
                .foregroundStyle(Fenn.fg.opacity(0.55))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(tr("Größe des Kalenders", "Calendar size"))
    }
}

struct DayTimelineView: View {
    let day: Date
    /// Set on the home screen: a window of the day from now on, without the load card. nil = the full day view.
    var size: DayCalendarSize? = nil
    let edit: (FennTask) -> Void
    @ObservedObject private var store = TaskStore.shared
    @State private var showSuggestions = false
    @State private var dragging: UUID?
    @State private var dragOffset: CGFloat = 0

    private var hourHeight: CGFloat { size?.hourHeight ?? 54 }
    private let labelWidth: CGFloat = 42

    private struct Block: Identifiable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let task: FennTask?
        let event: DayEvent?
        var lane = 0
        var lanes = 1
    }

    var body: some View {
        let load = DayPlanner.load(on: day, tasks: store.tasks)
        VStack(alignment: .leading, spacing: 12) {
            if size == nil { loadCard(load) }
            if size != .small { untimed(load) }
            timeline(load)
        }
        .sheet(isPresented: $showSuggestions) { DaySuggestionView(day: day) }
    }

    // MARK: Load

    /// The day against the working hours. After work it just says what's still open – no alarm, the evening is no extra item.
    private func loadCard(_ load: DayLoad) -> some View {
        let over = Calendar.current.isDateInToday(day) && FennDemo.now >= load.workEnd
        let tight = load.isOverloaded && !over
        let guesses = TaskKindGuess.candidates(in: load.tasks)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(tight ? tr("Der Tag ist zu voll", "The day is too full") : tr("Auslastung", "Load"))
                    .font(.fenn(size: 15, weight: .semibold)).foregroundStyle(tight ? Fenn.danger : Fenn.fg)
                Spacer()
                Text(over
                     ? tr("\(TaskFormat.duration(load.taskMinutes)) Aufgaben offen", "\(TaskFormat.duration(load.taskMinutes)) of tasks open")
                     : tr("\(TaskFormat.duration(load.taskMinutes)) Aufgaben, \(TaskFormat.duration(load.freeMinutes)) frei",
                          "\(TaskFormat.duration(load.taskMinutes)) tasks, \(TaskFormat.duration(load.freeMinutes)) free"))
                    .font(.fenn(size: 12)).foregroundStyle(Fenn.fg.opacity(0.6))
            }
            GeometryReader { proxy in
                let capacity = max(1, Double(load.capacityMinutes))
                let events = min(1, Double(load.eventMinutes) / capacity)
                let tasks = min(1 - events, Double(load.taskMinutes) / capacity)
                ZStack(alignment: .leading) {
                    Capsule().fill(Fenn.fill)
                    HStack(spacing: 0) {
                        Rectangle().fill(Fenn.fg.opacity(0.35)).frame(width: proxy.size.width * events)
                        Rectangle().fill(tight ? Fenn.danger : Fenn.accent).frame(width: proxy.size.width * tasks)
                    }
                    .clipShape(Capsule())
                }
            }
            .frame(height: 8)
            Text(over
                 ? tr("Termine \(TaskFormat.duration(load.eventMinutes)), Arbeitszeit bis \(DayPlanner.workHours.end) Uhr – was offen ist, kann auf die nächsten Tage.",
                      "Events \(TaskFormat.duration(load.eventMinutes)), work hours until \(DayPlanner.workHours.end) – what's open can move to the next days.")
                 : tight
                 ? tr("Etwa \(TaskFormat.duration(load.overloadMinutes)) mehr Aufgaben als freie Zeit – Fenn schlägt vor, was du verschieben kannst.",
                      "About \(TaskFormat.duration(load.overloadMinutes)) more tasks than free time – Fenn suggests what to move.")
                 : tr("Termine \(TaskFormat.duration(load.eventMinutes)), Arbeitszeit \(DayPlanner.workHours.start)–\(DayPlanner.workHours.end) Uhr",
                      "Events \(TaskFormat.duration(load.eventMinutes)), work hours \(DayPlanner.workHours.start)–\(DayPlanner.workHours.end)"))
                .font(.fenn(size: 12)).foregroundStyle(Fenn.fg.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            if !guesses.isEmpty {
                Text(tr("Sieht nach Termin aus: \(guesses.map(\.title).joined(separator: ", ")) – Fenn kann sie als Blocker statt Aufgabe führen.",
                        "Looks like an appointment: \(guesses.map(\.title).joined(separator: ", ")) – Fenn can keep them as blockers, not tasks."))
                    .font(.fenn(size: 12)).foregroundStyle(Fenn.fg.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if tight || !load.untimedTasks.isEmpty || !guesses.isEmpty || (over && !load.tasks.isEmpty) {
                Button { showSuggestions = true } label: {
                    Label(tight ? tr("Fenn: Tag entlasten", "Fenn: lighten the day")
                          : over ? tr("Fenn: Offenes verteilen", "Fenn: spread what's open")
                          : !guesses.isEmpty && load.untimedTasks.isEmpty ? tr("Fenn: Termine & Aufgaben sortieren", "Fenn: sort appointments & tasks")
                          : tr("Fenn: in freie Zeiten einplanen", "Fenn: fit into free time"),
                          systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FennPillButtonStyle(prominent: tight))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(tight ? Fenn.danger.opacity(0.1) : Fenn.fill))
    }

    // MARK: Untimed

    @ViewBuilder
    private func untimed(_ load: DayLoad) -> some View {
        let allDay = load.events.filter(\.isAllDay)
        if !load.untimedTasks.isEmpty || !allDay.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("OHNE UHRZEIT", "NO TIME SET")).font(.fenn(size: 10, weight: .semibold)).tracking(1).foregroundStyle(Fenn.fg.opacity(0.45))
                ForEach(allDay) { event in
                    Label(event.title, systemImage: "calendar").font(.fenn(size: 13)).foregroundStyle(Fenn.fg.opacity(0.7))
                        .contentShape(Rectangle())
                        .onTapGesture { if let task = DayPlanner.blockerTask(event) { edit(task) } }
                        .contextMenu { eventMenu(event) }
                }
                ForEach(load.untimedTasks) { task in
                    Button { edit(task) } label: {
                        HStack(spacing: 8) {
                            Circle().fill(task.priority.color).frame(width: 7, height: 7)
                            Text(task.title).font(.fenn(size: 13)).foregroundStyle(Fenn.fg).lineLimit(1)
                            Spacer()
                            Text("~\(TaskFormat.duration(DayPlanner.minutes(of: task)))").font(.fenn(size: 11)).foregroundStyle(Fenn.fg.opacity(0.5))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Fenn.fill))
        }
    }

    // MARK: Timeline

    private func hours(_ load: DayLoad) -> ClosedRange<Int> {
        let cal = Calendar.current
        if let span = size?.hours {
            // A window from the current hour (today) or from the start of work (another day), so "now" sits on top.
            let from = cal.isDateInToday(day) ? cal.component(.hour, from: FennDemo.now) : DayPlanner.workHours.start
            let first = max(0, min(from, 24 - span))
            return first...(first + span)
        }
        var first = DayPlanner.workHours.start - 1
        var last = DayPlanner.workHours.end + 1
        for block in blocks(load) {
            first = min(first, cal.component(.hour, from: block.start))
            last = max(last, cal.component(.hour, from: block.end) + 1)
        }
        return max(0, first)...min(24, max(first + 1, last))
    }

    private func blocks(_ load: DayLoad) -> [Block] {
        var items = load.events.filter { !$0.isAllDay }.map { Block(id: $0.id, title: $0.title, start: $0.start, end: max($0.end, $0.start.addingTimeInterval(900)), task: nil, event: $0) }
        items += load.timedTasks.compactMap { task in
            task.due.map { Block(id: task.id.uuidString, title: task.title, start: $0, end: $0.addingTimeInterval(Double(DayPlanner.minutes(of: task)) * 60), task: task, event: nil) }
        }
        items.sort { $0.start < $1.start }
        // Side by side where they overlap.
        var laneEnds: [Date] = []
        for index in items.indices {
            if let lane = laneEnds.firstIndex(where: { $0 <= items[index].start }) {
                items[index].lane = lane
                laneEnds[lane] = items[index].end
            } else {
                items[index].lane = laneEnds.count
                laneEnds.append(items[index].end)
            }
        }
        for index in items.indices {
            let overlapping = items.filter { $0.start < items[index].end && $0.end > items[index].start }
            items[index].lanes = (overlapping.map(\.lane).max() ?? 0) + 1
        }
        return items
    }

    private func timeline(_ load: DayLoad) -> some View {
        let range = hours(load)
        let items = blocks(load)
        let top = Calendar.current.date(bySettingHour: range.lowerBound, minute: 0, second: 0, of: day) ?? day
        let height = CGFloat(range.count - 1) * hourHeight
        return GeometryReader { proxy in
            let width = proxy.size.width - labelWidth - 4
            ZStack(alignment: .topLeading) {
                // Working hours lightly tinted (only the part inside the shown hours).
                let workFrom = max(DayPlanner.workHours.start, range.lowerBound), workTo = min(DayPlanner.workHours.end, range.upperBound)
                if workTo > workFrom {
                    Rectangle().fill(Fenn.fill.opacity(0.6))
                        .frame(width: width, height: CGFloat(workTo - workFrom) * hourHeight)
                        .offset(x: labelWidth + 4, y: CGFloat(workFrom - range.lowerBound) * hourHeight)
                }
                ForEach(Array(range), id: \.self) { hour in
                    HStack(spacing: 4) {
                        Text(String(format: "%02d:00", hour)).font(.fenn(size: 10, weight: .medium).monospacedDigit())
                            .foregroundStyle(Fenn.fg.opacity(0.45)).frame(width: labelWidth, alignment: .leading)
                        Rectangle().fill(Fenn.hairline).frame(height: 1)
                    }
                    .offset(y: CGFloat(hour - range.lowerBound) * hourHeight - 6)
                }
                // In a window, blocks outside it drop out and those crossing an edge are cut there.
                ForEach(size == nil ? items : items.filter { $0.end > top && $0.start < top.addingTimeInterval(Double(range.count - 1) * 3600) }) { item in
                    let rawY = CGFloat(item.start.timeIntervalSince(top) / 3600) * hourHeight
                    let y = size == nil ? rawY : max(0, rawY)
                    let bottom = CGFloat(item.end.timeIntervalSince(top) / 3600) * hourHeight - 1.5
                    // True to the minute: a 15-min slot is a quarter of an hour tall, not padded up to fit two lines.
                    let h = max(12, (size == nil ? bottom : min(bottom, height)) - y)
                    let laneWidth = width / CGFloat(item.lanes)
                    block(item, compact: h < 34)
                        .frame(width: laneWidth - 3, height: h)
                        .offset(x: labelWidth + 4 + CGFloat(item.lane) * laneWidth, y: y + (dragging.map { $0.uuidString == item.id } == true ? dragOffset : 0))
                        .zIndex(dragging.map { $0.uuidString == item.id } == true ? 2 : 1)
                }
                if Calendar.current.isDateInToday(day) {
                    let y = CGFloat(FennDemo.now.timeIntervalSince(top) / 3600) * hourHeight
                    if y >= 0 && y <= height {
                        HStack(spacing: 0) {
                            Circle().fill(Fenn.danger).frame(width: 7, height: 7)
                            Rectangle().fill(Fenn.danger).frame(height: 1.5)
                        }
                        .frame(width: width + 4)
                        .offset(x: labelWidth - 3, y: y - 3.5)
                        .allowsHitTesting(false)
                    }
                }
            }
        }
        .frame(height: height + 8)
    }

    @ViewBuilder
    private func block(_ item: Block, compact: Bool) -> some View {
        let clock = DateFormatter()
        let _ = clock.dateFormat = "HH:mm"
        if let task = item.task {
            let tint = task.priority == .low ? Fenn.fg.opacity(0.5) : task.priority.color
            Group {
                if compact {
                    HStack(spacing: 5) {
                        Text(task.title).font(.fenn(size: 11, weight: .semibold)).foregroundStyle(Fenn.fg).lineLimit(1)
                        Text(clock.string(from: item.start)).font(.fenn(size: 10)).foregroundStyle(Fenn.fg.opacity(0.6))
                    }
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(task.title).font(.fenn(size: 12, weight: .semibold)).foregroundStyle(Fenn.fg).lineLimit(2)
                        Text("\(clock.string(from: item.start)), ~\(TaskFormat.duration(DayPlanner.minutes(of: task)))")
                            .font(.fenn(size: 10)).foregroundStyle(Fenn.fg.opacity(0.6))
                    }
                }
            }
            .padding(.horizontal, 7).padding(.vertical, compact ? 0 : 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: compact ? .leading : .topLeading)
            .background(RoundedRectangle(cornerRadius: compact ? 5 : 8, style: .continuous).fill(tint.opacity(0.22)))
            .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 3).padding(.vertical, 3) }
            .contentShape(Rectangle())
            .onTapGesture { edit(task) }
            // Hold, then drag – so scrolling the day still works.
            .gesture(
                LongPressGesture(minimumDuration: 0.25)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .onChanged { value in
                        guard case .second(true, let drag) = value else { return }
                        dragging = task.id
                        dragOffset = drag?.translation.height ?? 0
                    }
                    .onEnded { value in
                        guard case .second(true, let drag) = value, let drag else { dragging = nil; dragOffset = 0; return }
                        let moved = Double(drag.translation.height / hourHeight) * 3600
                        dragging = nil
                        dragOffset = 0
                        if abs(moved) >= 450 { DayPlanner.reschedule(task, to: item.start.addingTimeInterval(moved)) }
                    }
            )
            .scaleEffect(dragging == task.id ? 1.03 : 1)
            .contextMenu {
                Button { TaskStore.shared.setBlocker(task.id, true) } label: {
                    Label(tr("Ist ein Termin – blockt nur Zeit", "It's an appointment – just blocks time"), systemImage: "calendar.badge.clock")
                }
            }
            .accessibilityLabel("\(task.title), \(clock.string(from: item.start))")
            .accessibilityHint(tr("Tippen zum Bearbeiten, halten und ziehen zum Verschieben", "Tap to edit, hold and drag to move"))
        } else if let event = item.event {
            Group {
                if compact {
                    HStack(spacing: 5) {
                        Text(event.title).font(.fenn(size: 11, weight: .medium)).foregroundStyle(Fenn.fg.opacity(0.85)).lineLimit(1)
                        Text("\(clock.string(from: event.start))–\(clock.string(from: event.end))")
                            .font(.fenn(size: 10)).foregroundStyle(Fenn.fg.opacity(0.5)).lineLimit(1).layoutPriority(-1)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(event.title).font(.fenn(size: 12, weight: .medium)).foregroundStyle(Fenn.fg.opacity(0.85)).lineLimit(2)
                        Text("\(clock.string(from: event.start))–\(clock.string(from: event.end)), \(event.calendar)")
                            .font(.fenn(size: 10)).foregroundStyle(Fenn.fg.opacity(0.5)).lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 7).padding(.vertical, compact ? 0 : 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: compact ? .leading : .topLeading)
            .background(RoundedRectangle(cornerRadius: compact ? 5 : 8, style: .continuous).fill(Fenn.fg.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: compact ? 5 : 8, style: .continuous).strokeBorder(Fenn.hairline))
            .contentShape(Rectangle())
            .onTapGesture { if let task = DayPlanner.blockerTask(event) { edit(task) } }
            .contextMenu { eventMenu(event) }
        }
    }

    /// Appointment or to-do – for a calendar event or a task kept as a blocker.
    @ViewBuilder
    private func eventMenu(_ event: DayEvent) -> some View {
        if let task = DayPlanner.blockerTask(event) {
            Button { TaskStore.shared.setBlocker(task.id, false) } label: {
                Label(tr("Ist doch eine Aufgabe", "It's a task after all"), systemImage: "checklist")
            }
        } else {
            Button { DayPlanner.takeAsTask(event) } label: {
                Label(tr("Ist eine Aufgabe – in die Liste", "It's a task – add to the list"), systemImage: "checklist")
            }
        }
    }
}

/// Fenn's proposals for a day: the rules' at once, the AI model's when it answers. Pick and apply.
struct DaySuggestionView: View {
    let day: Date
    @Environment(\.dismiss) private var dismiss
    @State private var summary = ""
    @State private var changes: [DayChange] = []
    @State private var chosen: Set<UUID> = []
    @State private var thinking = false
    @State private var error: String?
    @State private var result: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(tr("Vorschlag für \(TaskFormat.day(day))", "Suggestion for \(TaskFormat.day(day))")).font(Fenn.display(20)).foregroundStyle(Fenn.fg)
                Spacer()
                Button(tr("Schließen", "Close")) { dismiss() }.buttonStyle(.plain).foregroundStyle(Fenn.accent)
            }
            if !summary.isEmpty {
                Text(summary).font(.fenn(size: 14)).foregroundStyle(Fenn.fg.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
            }
            if thinking {
                HStack(spacing: 8) {
                    ThinkingOrb(state: .working, size: 20)
                    Text(tr("Fenn schaut sich den Tag an …", "Fenn is looking at the day …")).font(.fenn(size: 13)).foregroundStyle(Fenn.fg.opacity(0.6))
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if changes.isEmpty && !thinking {
                        Text(tr("Passt so – nichts zu verschieben.", "Looks fine – nothing to move.")).font(.fenn(size: 14)).foregroundStyle(Fenn.fg.opacity(0.6))
                    }
                    ForEach(changes) { change in
                        Button {
                            if chosen.contains(change.id) { chosen.remove(change.id) } else { chosen.insert(change.id) }
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: chosen.contains(change.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.fenn(size: 18)).foregroundStyle(chosen.contains(change.id) ? Fenn.accent : Fenn.fg.opacity(0.35))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(change.summary).font(.fenn(size: 14)).foregroundStyle(Fenn.fg).multilineTextAlignment(.leading)
                                    if !change.reason.isEmpty {
                                        Text(change.reason).font(.fenn(size: 12)).foregroundStyle(Fenn.fg.opacity(0.55)).multilineTextAlignment(.leading)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Fenn.fill))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if let error { Text(error).font(.fenn(size: 12)).foregroundStyle(Fenn.danger) }
            if let result { Text(result).font(.fenn(size: 13)).foregroundStyle(Fenn.accent) }
            Button {
                apply()
            } label: {
                Text(tr("Übernehmen (\(chosen.count))", "Apply (\(chosen.count))")).frame(maxWidth: .infinity)
            }
            .buttonStyle(FennPillButtonStyle(prominent: true))
            .disabled(chosen.isEmpty)
        }
        .padding(20)
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 460)
        #endif
        .background(Fenn.canvas.ignoresSafeArea())
        .task { await load() }
    }

    private func load() async {
        let full = DayPlanner.load(on: day)
        // Appointments that sit among the tasks first: they leave the task list and stop counting as work.
        let guesses = TaskKindGuess.candidates(in: full.tasks)
        let blocking = guesses.map { DayChange(target: .blocker($0.id), title: $0.title, to: $0.due ?? full.day, timed: false, reason: "") }
        let load = DayLoad(day: full.day, events: full.events, tasks: full.tasks.filter { task in !guesses.contains { $0.id == task.id } },
                           workStart: full.workStart, workEnd: full.workEnd)
        let relieved = DayPlanner.relieve(load)
        let movedAway = Set(relieved.compactMap { change -> UUID? in if case .task(let id) = change.target { return id } else { return nil } })
        let rest = DayLoad(day: load.day, events: load.events, tasks: load.tasks.filter { !movedAway.contains($0.id) },
                           workStart: load.workStart, workEnd: load.workEnd)
        changes = blocking + relieved + DayPlanner.fitIntoGaps(rest)
        chosen = Set(changes.map(\.id))
        let over = Calendar.current.isDateInToday(day) && FennDemo.now >= load.workEnd
        summary = !blocking.isEmpty && load.tasks.isEmpty
            ? tr("Das sind eher Termine als Aufgaben – sie blocken dann nur ihre Zeit.", "These are appointments rather than tasks – they then just block their time.")
            : over
            ? tr("Arbeitszeit vorbei – was offen ist, wandert auf die nächsten Tage.", "Work hours are over – what's open moves to the next days.")
            : load.isOverloaded
            ? tr("Zu viel für heute: \(TaskFormat.duration(load.taskMinutes)) Aufgaben, \(TaskFormat.duration(load.freeMinutes)) frei.",
                 "Too much: \(TaskFormat.duration(load.taskMinutes)) of tasks, \(TaskFormat.duration(load.freeMinutes)) free.")
            : tr("Aufgaben ohne Uhrzeit in die freien Lücken.", "Tasks without a time into the free slots.")
        guard FennAI.isConfigured, !FennAI.needsConsent(), !full.tasks.isEmpty else { return }
        thinking = true
        defer { thinking = false }
        do {
            let suggestion = try await DayPlanner.suggest(full)
            guard !suggestion.changes.isEmpty || !suggestion.summary.isEmpty else { return }
            if !suggestion.summary.isEmpty { summary = suggestion.summary }
            if !suggestion.changes.isEmpty {
                changes = suggestion.changes
                chosen = Set(changes.map(\.id))
            }
        } catch {
            self.error = tr("Fenn-Vorschlag nicht verfügbar – die Regeln oben gelten.", "Fenn's suggestion unavailable – the rules above apply.")
        }
    }

    private func apply() {
        // A "Termin?" the person left unticked is a task – Fenn stops asking.
        TaskKindGuess.dismiss(changes.compactMap { change in
            if case .blocker(let id) = change.target, !chosen.contains(change.id) { return id } else { return nil }
        })
        var failed: [String] = []
        for change in changes where chosen.contains(change.id) {
            if !DayPlanner.apply(change) { failed.append(change.title) }
        }
        if failed.isEmpty {
            dismiss()
        } else {
            result = tr("Nicht verschoben (Termin mit Teilnehmern oder kein Kalenderzugriff): \(failed.joined(separator: ", "))",
                        "Not moved (event with participants or no calendar access): \(failed.joined(separator: ", "))")
            changes.removeAll { chosen.contains($0.id) && !failed.contains($0.title) }
            chosen = []
        }
    }
}

/// Above the task list: entries that look like appointments (rules at once, the AI model once per launch) – one tap keeps
/// them as blockers – and the appointments kept that way, to turn back into tasks.
struct TaskKindCard: View {
    @ObservedObject private var store = TaskStore.shared
    @State private var aiGuesses: Set<UUID> = TaskKindCard.cache ?? []
    @State private var showsBlockers = false
    @State private var dismissedTick = 0
    @MainActor private static var cache: Set<UUID>?

    var body: some View {
        let _ = dismissedTick
        let open = store.open
        let rules = TaskKindGuess.candidates(in: open)
        let no = TaskKindGuess.dismissed
        let guesses = rules + open.filter { aiGuesses.contains($0.id) && !rules.contains($0) && !no.contains($0.id.uuidString) }
        VStack(alignment: .leading, spacing: 10) {
            if !guesses.isEmpty { suggestion(guesses) }
            if !store.blockers.isEmpty { blockerList }
        }
        .task {
            guard Self.cache == nil else { return }
            Self.cache = []
            let found = await TaskKindGuess.ai(store.open.filter { $0.due != nil }) ?? []
            Self.cache = Set(found.map(\.id))
            aiGuesses = Self.cache ?? []
        }
    }

    private func suggestion(_ guesses: [FennTask]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("Termine statt Aufgaben?", "Appointments, not tasks?")).font(.fenn(size: 14, weight: .semibold)).foregroundStyle(Fenn.fg)
            Text(tr("Als Termin blocken sie nur Zeit und stehen nicht mehr bei den offenen Aufgaben.",
                    "As appointments they just block time and leave the open tasks."))
                .font(.fenn(size: 12)).foregroundStyle(Fenn.fg.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            ForEach(guesses) { task in
                HStack(spacing: 8) {
                    Image(systemName: "calendar").font(.fenn(size: 12)).foregroundStyle(Fenn.accent)
                    Text(task.title).font(.fenn(size: 13)).foregroundStyle(Fenn.fg).lineLimit(1)
                    if let due = task.due { Text(TaskFormat.when(due)).font(.fenn(size: 11)).foregroundStyle(Fenn.fg.opacity(0.5)) }
                    Spacer(minLength: 0)
                    Button { store.setBlocker(task.id, true) } label: { Text(tr("Termin", "Appointment")).font(.fenn(size: 12, weight: .medium)) }
                        .buttonStyle(.plain).foregroundStyle(Fenn.accent)
                    Button { TaskKindGuess.dismiss([task.id]); dismissedTick += 1 } label: { Image(systemName: "xmark").font(.fenn(size: 11)) }
                        .buttonStyle(.plain).foregroundStyle(Fenn.fg.opacity(0.45))
                        .accessibilityLabel(tr("Bleibt Aufgabe", "Stays a task"))
                }
                .frame(minHeight: 32)
            }
            if guesses.count > 1 {
                Button(tr("Alle als Termine führen", "Keep all as appointments")) { guesses.forEach { store.setBlocker($0.id, true) } }
                    .buttonStyle(FennPillButtonStyle())
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Fenn.fill))
    }

    private var blockerList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation(.snappy) { showsBlockers.toggle() } } label: {
                HStack {
                    Label(tr("Termine (\(store.blockers.count))", "Appointments (\(store.blockers.count))"), systemImage: "calendar.badge.clock")
                        .font(.fenn(size: 13, weight: .medium)).foregroundStyle(Fenn.fg.opacity(0.75))
                    Spacer()
                    Image(systemName: showsBlockers ? "chevron.up" : "chevron.down").font(.fenn(size: 11)).foregroundStyle(Fenn.fg.opacity(0.4))
                }
                .frame(minHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showsBlockers {
                ForEach(store.blockers) { task in
                    HStack(spacing: 8) {
                        Text(task.title).font(.fenn(size: 13)).foregroundStyle(Fenn.fg).lineLimit(1)
                        if let due = task.due { Text(TaskFormat.when(due)).font(.fenn(size: 11)).foregroundStyle(Fenn.fg.opacity(0.5)) }
                        Spacer(minLength: 0)
                        Button(tr("Ist eine Aufgabe", "It's a task")) { store.setBlocker(task.id, false) }
                            .buttonStyle(.plain).font(.fenn(size: 12)).foregroundStyle(Fenn.accent)
                    }
                    .frame(minHeight: 32)
                }
                Text(tr("Blocken ihre Zeit im Tag, stehen nicht bei den Aufgaben. Vorbei = weg.",
                        "Block their time in the day, not listed as tasks. Once past, they're gone."))
                    .font(.fenn(size: 11)).foregroundStyle(Fenn.fg.opacity(0.45))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Fenn.fill.opacity(0.6)))
    }
}
