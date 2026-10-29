import SwiftUI

/// Routines after Atomic Habits: small, stacked onto something you already do, with a two-minute version
/// and streaks that forgive one gap. Stored as habits/habits.json in the Fenn folder.
struct HabitsModuleView: View {
    @ObservedObject var store: HabitStore
    @State private var draft = ""
    @State private var editing: UUID?
    @State private var showArchive = false
    @State private var showAll = false
    @State private var showIdeas = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(tr("Routinen", "Routines")).font(Fenn.display(22)).foregroundStyle(Fenn.fg)
                Spacer()
                let list = store.today()
                if !list.isEmpty {
                    Text(tr("\(store.doneToday()) von \(list.count) heute", "\(store.doneToday()) of \(list.count) today"))
                        .font(.fenn(size: 12, weight: .medium).monospacedDigit()).foregroundStyle(Fenn.fg.opacity(0.6))
                }
            }
            addField

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if store.active.isEmpty {
                        intro
                    } else {
                        consistency
                        today
                        all
                    }
                    ideas
                    if !store.archived.isEmpty { archive }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.never)
        }
        .onAppear {
            store.reload()
            store.archiveFinished()
            store.applyAuto()
        }
    }

    // MARK: Add

    private var addField: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus").font(.fenn(size: 13, weight: .semibold)).foregroundStyle(Fenn.accent)
            TextField(tr("Neue Routine", "New routine"), text: $draft)
                .textFieldStyle(.plain)
                .font(.fenn(size: 14))
                .focused($fieldFocused)
                .onSubmit(add)
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(Capsule().fill(Fenn.field))
        .overlay(Capsule().strokeBorder(fieldFocused ? Fenn.accent.opacity(0.5) : Fenn.hairline))
    }

    private func add() {
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let habit = Habit(title: title)
        withAnimation(.snappy) { store.add(habit) }
        draft = ""
        editing = habit.id
    }

    // MARK: Sections

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Werde, wer du sein willst – eine kleine Stimme nach der anderen.", "Become who you want to be – one small vote at a time."))
                .font(Fenn.display(18)).foregroundStyle(Fenn.fg)
            principle("eye", tr("Offensichtlich", "Obvious"), tr("An etwas hängen, das du eh tust: „Nach dem Kaffee …“", "Stack it: “After my coffee …”"))
            principle("sparkles", tr("Attraktiv", "Attractive"), tr("Jedes Abhaken ist eine Stimme für die Person, die du sein willst.", "Every tick is a vote for who you want to be."))
            principle("hare", tr("Einfach", "Easy"), tr("Eine 2-Minuten-Version, die an schlechten Tagen auch zählt.", "A two-minute version that counts on bad days."))
            principle("checkmark.seal", tr("Befriedigend", "Satisfying"), tr("Serien, die eine Lücke verzeihen – nur nie zweimal in Folge.", "Streaks that forgive one gap – just never miss twice."))
        }
        .padding(14)
        .fennGlass(cornerRadius: 22, shadow: false)
    }

    private func principle(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ClaySymbol(symbol: symbol, size: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.fenn(size: 13, weight: .semibold)).foregroundStyle(Fenn.fg)
                Text(text).font(.fenn(size: 12)).foregroundStyle(Fenn.fg.opacity(0.6))
            }
        }
    }

    private var consistency: some View {
        let values = store.consistency(weeks: 8)
        let week = values.last.flatMap { $0 }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                sectionLabel(tr("BESTÄNDIGKEIT, 8 WOCHEN", "CONSISTENCY, 8 WEEKS"))
                Spacer()
                if let week {
                    Text(tr("Diese Woche \(Int((week * 100).rounded())) %", "This week \(Int((week * 100).rounded()))%"))
                        .font(.fenn(size: 12, weight: .medium).monospacedDigit()).foregroundStyle(Fenn.fg.opacity(0.7))
                }
            }
            HabitConsistencyBars(values: values, height: 56)
        }
        .padding(16)
        .fennGlass(cornerRadius: 22, shadow: false)
        .help(tr("Eine Lücke bricht keine Serie – nur zweimal in Folge.", "One gap doesn't break a streak – only two in a row."))
    }

    private var today: some View {
        let list = store.today()
        return VStack(alignment: .leading, spacing: 4) {
            sectionLabel(tr("HEUTE", "TODAY"))
            if list.isEmpty {
                Text(tr("Heute ist keine Routine geplant.", "No routine planned today."))
                    .font(.fenn(size: 13)).foregroundStyle(Fenn.fg.opacity(0.55)).padding(.vertical, 6)
            }
            ForEach(HabitTime.allCases) { time in
                let items = list.filter { $0.time == time }
                if !items.isEmpty {
                    HStack(spacing: 6) {
                        ClaySymbol(symbol: time.symbol, size: 18, tint: Fenn.fg.opacity(0.5))
                        Text(time.title)
                    }
                    .font(.fenn(size: 11, weight: .medium)).foregroundStyle(Fenn.fg.opacity(0.5))
                    .padding(.top, 6)
                    ForEach(items) { habit in
                        HabitRow(habit: habit, store: store) { editing = habit.id }
                    }
                }
            }
        }
        .padding(14)
        .fennGlass(cornerRadius: 22, shadow: false)
    }

    private var all: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Today already lists every routine due – the full list with streaks and editing folds out.
            disclosure(tr("Alle Routinen, \(store.active.count)", "All routines, \(store.active.count)"), open: $showAll)
            if showAll || editing != nil {
            VStack(spacing: 0) {
                ForEach(store.active) { habit in
                    VStack(spacing: 0) {
                        Button { withAnimation(.snappy) { editing = editing == habit.id ? nil : habit.id } } label: { summary(habit) }
                            .buttonStyle(.plain)
                        if editing == habit.id {
                            HabitEditor(habit: habit, store: store) { withAnimation(.snappy) { editing = nil } }
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .padding(.bottom, 8)
                        }
                    }
                    if habit.id != store.active.last?.id { Rectangle().fill(Fenn.hairline).frame(height: 1) }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
            .fennGlass(cornerRadius: 20, shadow: false)
            }
        }
    }

    /// A small folding section header, like the archive's.
    private func disclosure(_ title: String, open: Binding<Bool>) -> some View {
        Button { withAnimation(.snappy) { open.wrappedValue.toggle() } } label: {
            Label(title, systemImage: open.wrappedValue ? "chevron.down" : "chevron.right")
                .font(.fenn(size: 11, weight: .medium)).tracking(1.1).foregroundStyle(Fenn.fg.opacity(0.55))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 4)
    }

    private func summary(_ habit: Habit) -> some View {
        var parts = [habit.time.title, habit.weekdaysText]
        if let challenge = store.challengeDay(habit) { parts.append(tr("Tag \(challenge.day)/\(challenge.of)", "Day \(challenge.day)/\(challenge.of)")) }
        parts.append(tr("Serie \(store.streak(habit)), beste \(store.best(habit))", "streak \(store.streak(habit)), best \(store.best(habit))"))
        return HStack(spacing: 10) {
            ClaySymbol(symbol: habit.displaySymbol, size: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.title).font(.fenn(size: 13, weight: .medium)).foregroundStyle(Fenn.fg).lineLimit(1)
                Text(parts.joined(separator: ", ")).font(.fenn(size: 11)).foregroundStyle(Fenn.fg.opacity(0.5)).lineLimit(1)
            }
            Spacer(minLength: 8)
            HabitConsistencyBars(values: store.consistency(habit, weeks: 8), height: 18).frame(width: 60)
        }
        .frame(minHeight: 46)
        .contentShape(Rectangle())
        .help(tr("Bearbeiten", "Edit"))
    }

    /// Starting points not in the list yet.
    @ViewBuilder
    private var ideas: some View {
        let taken = Set(store.habits.map { $0.title.lowercased() })
        let ideas = HabitTemplates.all.filter { !taken.contains($0.title.lowercased()) }
        if !ideas.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if store.active.isEmpty {
                    sectionLabel(tr("ZUM START", "TO START")).padding(.leading, 4)
                } else {
                    disclosure(tr("Ideen", "Ideas"), open: $showIdeas)
                }
                if store.active.isEmpty || showIdeas {
                VStack(spacing: 0) {
                    ForEach(ideas.prefix(store.active.isEmpty ? 10 : 4)) { idea in
                        HStack(spacing: 10) {
                            ClaySymbol(symbol: idea.displaySymbol, size: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(idea.title).font(.fenn(size: 13, weight: .medium)).foregroundStyle(Fenn.fg)
                                let line = [idea.anchorText(in: []), idea.auto.map { _ in tr("hakt sich selbst ab", "ticks itself off") }].compactMap { $0 }.joined(separator: ", ")
                                Text(line.isEmpty ? idea.time.title : line).font(.fenn(size: 11)).foregroundStyle(Fenn.fg.opacity(0.5)).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Button { withAnimation(.snappy) { store.add(idea) } } label: {
                                Image(systemName: "plus.circle.fill").font(.fenn(size: 18)).foregroundStyle(Fenn.accent)
                            }
                            .buttonStyle(.plain)
                            .help(tr("Hinzufügen", "Add"))
                        }
                        .frame(minHeight: 42)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
                .fennGlass(cornerRadius: 20, shadow: false)
                }
            }
        }
    }

    private var archive: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation(.snappy) { showArchive.toggle() } } label: {
                Label(tr("Archiv, \(store.archived.count)", "Archive, \(store.archived.count)"), systemImage: showArchive ? "chevron.down" : "chevron.right")
                    .font(.fenn(size: 11, weight: .medium)).tracking(1.1).foregroundStyle(Fenn.fg.opacity(0.55))
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
            if showArchive {
                VStack(spacing: 0) {
                    ForEach(store.archived) { habit in
                        HStack(spacing: 10) {
                            ClaySymbol(symbol: habit.lengthDays != nil ? "rosette" : "archivebox", size: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(habit.title).font(.fenn(size: 13, weight: .medium)).foregroundStyle(Fenn.fg)
                                Text(tr("Beste Serie \(store.best(habit)), \(store.votes(habit)) Mal gemacht", "Best streak \(store.best(habit)), done \(store.votes(habit)) times")
                                     + (habit.lengthDays.map { tr(", \($0)-Tage-Challenge", ", \($0)-day challenge") } ?? ""))
                                    .font(.fenn(size: 11)).foregroundStyle(Fenn.fg.opacity(0.5))
                            }
                            Spacer(minLength: 0)
                            Button(tr("Aufnehmen", "Bring back")) { withAnimation(.snappy) { store.archive(habit.id, false) } }
                                .buttonStyle(FennPillButtonStyle())
                            Button { withAnimation(.snappy) { store.delete(habit.id) } } label: { Image(systemName: "trash") }
                                .buttonStyle(.plain)
                                .foregroundStyle(Fenn.danger.opacity(0.8))
                                .help(tr("Löschen", "Delete"))
                        }
                        .frame(minHeight: 46)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
                .fennGlass(cornerRadius: 20, shadow: false)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.fenn(size: 11, weight: .medium)).tracking(1.2).foregroundStyle(Fenn.fg.opacity(0.55))
    }
}

// MARK: - Row

/// One routine to tick off: circle, title, the anchor / streak / gentle nudge below, flame from three days.
struct HabitRow: View {
    let habit: Habit
    @ObservedObject var store: HabitStore
    var edit: (() -> Void)?
    @State private var pulse = false

    var body: some View {
        let done = store.isDone(habit)
        let line = HabitLine.subtitle(habit, store: store)
        Button {
            withAnimation(.snappy) { store.toggle(habit) }
            if !done { pulse = true }
        } label: {
            HStack(spacing: 10) {
                ClaySymbol(symbol: habit.displaySymbol, size: 26)
                    .opacity(done ? 0.55 : 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(habit.title)
                        .font(.fenn(size: 13, weight: .medium))
                        .foregroundStyle(done ? Fenn.fg.opacity(0.5) : Fenn.fg)
                        .lineLimit(1)
                    if let line {
                        Text(line.text).font(.fenn(size: 11))
                            .foregroundStyle(line.warn ? Fenn.amber : Fenn.fg.opacity(0.5))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                let streak = store.streak(habit)
                if streak >= 3 {
                    HStack(spacing: 3) {
                        ClaySymbol(symbol: "flame.fill", size: 15)
                        Text("\(streak)").font(.fenn(size: 12, weight: .medium).monospacedDigit())
                    }
                    .foregroundStyle(done ? Fenn.accent : Fenn.fg.opacity(0.45))
                    .help(tr("Serie", "Streak"))
                }
                ZStack {
                    Circle().strokeBorder(done ? Fenn.accent : Fenn.fg.opacity(0.35), lineWidth: 1.5)
                    if done {
                        Circle().fill(Fenn.accent)
                        Image(systemName: "checkmark").font(.fenn(size: 10, weight: .bold)).foregroundStyle(Fenn.canvas)
                    }
                }
                .frame(width: 22, height: 22)
                .scaleEffect(pulse ? 1.15 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: pulse)
            }
            .frame(minHeight: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onChange(of: pulse) { _, on in
            if on { Task { try? await Task.sleep(nanoseconds: 250_000_000); pulse = false } }
        }
        .accessibilityLabel(habit.title)
        .accessibilityValue(done ? tr("erledigt", "done") : tr("offen", "open"))
        .contextMenu {
            if !done, let tiny = habit.tiny, !tiny.isEmpty {
                Button(tr("Nur 2 Minuten: \(tiny)", "Just two minutes: \(tiny)")) { store.toggle(habit, tiny: true) }
            }
            if let identity = habit.identity, !identity.isEmpty {
                Text(tr("Stimme für: Ich bin \(identity)", "A vote for: I am \(identity)"))
            }
            if let edit { Button(tr("Bearbeiten", "Edit"), action: edit) }
            Button(tr("Archivieren", "Archive")) { store.archive(habit.id) }
        }
    }
}

// MARK: - Editor

/// Inline editor: when, Atomic Habits (identity, anchor, two minutes), auto tick, length, reminder.
struct HabitEditor: View {
    @State var habit: Habit
    let store: HabitStore
    let close: () -> Void
    /// Archived or deleted from here: nothing to write back on close.
    @State private var dropped = false

    private static let lengths: [Int?] = [nil, 21, 30, 66]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(tr("Was willst du jeden Tag tun?", "What do you want to do every day?"), text: $habit.title)
                .textFieldStyle(.plain)
                .font(.fenn(size: 15, weight: .medium))
                .onSubmit(commit)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    label("clock", tr("Wann", "When"))
                    FennSegments(options: HabitTime.allCases, selection: $habit.time) { $0.title }
                }
                GridRow {
                    label("calendar", tr("Tage", "Days"))
                    HStack(spacing: 4) {
                        ForEach(HabitStore.weekdayOrder, id: \.self) { day in
                            let on = habit.weekdays.isEmpty || habit.weekdays.contains(day)
                            Button { toggle(day) } label: {
                                Text(HabitStore.weekdaySymbols[day - 1])
                                    .font(.fenn(size: 11, weight: .medium))
                                    .foregroundStyle(on ? Fenn.canvas : Fenn.fg)
                                    .frame(width: 26, height: 26)
                                    .background(Circle().fill(on ? Fenn.fg : Fenn.fill))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                GridRow {
                    label("person", tr("Ich bin …", "I am …"))
                    field(tr("jemand, der sich jeden Tag bewegt", "someone who moves every day"),
                          Binding(get: { habit.identity ?? "" }, set: { habit.identity = $0.isEmpty ? nil : $0 }))
                }
                GridRow {
                    label("link", tr("Nach …", "After …"))
                    HStack(spacing: 6) {
                        if let anchorId = habit.anchorId, let other = store.habits.first(where: { $0.id == anchorId }) {
                            Text(other.title).font(.fenn(size: 13)).foregroundStyle(Fenn.fg)
                            Spacer(minLength: 0)
                        } else {
                            field(tr("dem ersten Kaffee", "my first coffee"),
                                  Binding(get: { habit.anchor ?? "" }, set: { habit.anchor = $0.isEmpty ? nil : $0 }))
                        }
                        let others = store.active.filter { $0.id != habit.id }
                        if !others.isEmpty {
                            Menu {
                                ForEach(others) { other in Button(other.title) { habit.anchorId = other.id; habit.anchor = nil } }
                                Divider()
                                Button(tr("Kein Anker", "No anchor")) { habit.anchorId = nil; habit.anchor = nil }
                            } label: { Image(systemName: "chevron.up.chevron.down").font(.fenn(size: 10)) }
                                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                                .help(tr("Nach einer anderen Routine", "After another routine"))
                        }
                    }
                }
                GridRow {
                    label("hare", tr("2 Minuten", "2 minutes"))
                    field(tr("die kleinste Version, z. B. eine Seite", "the smallest version, e.g. one page"),
                          Binding(get: { habit.tiny ?? "" }, set: { habit.tiny = $0.isEmpty ? nil : $0 }))
                }
                GridRow {
                    label("wand.and.stars", tr("Automatisch", "Automatic"))
                    HStack(spacing: 8) {
                        Menu {
                            Button(tr("Nur von Hand", "By hand only")) { habit.auto = nil }
                            ForEach(HabitAuto.allCases) { auto in Button(auto.title) { habit.auto = auto } }
                        } label: {
                            Text(habit.auto?.title ?? tr("Nur von Hand", "By hand only")).font(.fenn(size: 13))
                        }
                        .menuStyle(.borderlessButton).fixedSize()
                    }
                }
                GridRow {
                    label("flag.checkered", tr("Dauer", "Length"))
                    FennSegments(options: Self.lengths, selection: $habit.lengthDays) { length in
                        length.map { tr("\($0) Tage", "\($0) days") } ?? tr("Fortlaufend", "Ongoing")
                    }
                }
            }

            HStack(spacing: 8) {
                Text(tr("\(store.votes(habit)) Mal, beste Serie \(store.best(habit))", "\(store.votes(habit)) times, best streak \(store.best(habit))"))
                    .font(.fenn(size: 11)).foregroundStyle(Fenn.fg.opacity(0.5))
                Spacer()
                Button(tr("Archivieren", "Archive")) { commit(); dropped = true; store.archive(habit.id); close() }
                    .buttonStyle(FennPillButtonStyle())
                Button { dropped = true; store.delete(habit.id); close() } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Fenn.danger.opacity(0.8))
                    .help(tr("Löschen", "Delete"))
                Button(tr("Fertig", "Done")) { commit(); close() }
                    .buttonStyle(FennPillButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .background(Fenn.fill)
        .onDisappear { if !dropped { commit() } }
    }

    private func commit() {
        var copy = habit
        copy.title = copy.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !copy.title.isEmpty, let stored = store.habits.first(where: { $0.id == copy.id }), stored != copy else { return }
        copy.archivedAt = stored.archivedAt
        store.update(copy)
    }

    private func toggle(_ day: Int) {
        var days = habit.weekdays.isEmpty ? Set(1...7) : Set(habit.weekdays)
        if days.contains(day) { days.remove(day) } else { days.insert(day) }
        if days.isEmpty { return }
        habit.weekdays = days.count == 7 ? [] : days.sorted()
    }

    private func label(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.fenn(size: 12)).foregroundStyle(Fenn.fg.opacity(0.55))
            .gridColumnAlignment(.leading)
    }

    private func field(_ prompt: String, _ text: Binding<String>) -> some View {
        TextField(prompt, text: text).textFieldStyle(.plain).font(.fenn(size: 13)).onSubmit(commit)
    }
}

// MARK: - Today

/// Routines on Today: x of y, a tick ruler, up to five to tick off – the header opens the module.
struct HabitsTodayCard: View {
    @ObservedObject var store: HabitStore
    let open: () -> Void

    var body: some View {
        let list = store.today()
        let done = list.filter { store.isDone($0) }.count
        VStack(alignment: .leading, spacing: 8) {
            Button(action: open) {
                HStack(spacing: 10) {
                    Text(tr("ROUTINEN", "ROUTINES"))
                        .font(.fenn(size: 11, weight: .medium)).tracking(1.2).foregroundStyle(Fenn.fg.opacity(0.55))
                    Spacer()
                    if !list.isEmpty {
                        Text(tr("\(done) von \(list.count)", "\(done) of \(list.count)"))
                            .font(.fenn(size: 13, weight: .medium).monospacedDigit()).foregroundStyle(Fenn.fg)
                    }
                    Image(systemName: "chevron.right").font(.fenn(size: 11)).foregroundStyle(Fenn.fg.opacity(0.4))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(tr("Alle Routinen", "All routines"))

            if list.isEmpty {
                Button(action: open) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tr("Kleine Routinen, jeden Tag", "Small routines, every day")).font(.fenn(size: 13, weight: .medium)).foregroundStyle(Fenn.fg)
                        Text(tr("An etwas anhängen, das du eh tust. Fenn hakt ab, was er misst.", "Stack it onto something you already do. Fenn ticks off what it measures."))
                            .font(.fenn(size: 12)).foregroundStyle(Fenn.fg.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Fenn.fill)
                        Capsule().fill(Fenn.accent).frame(width: max(4, proxy.size.width * CGFloat(done) / CGFloat(list.count)))
                    }
                }
                .frame(height: 4)
                .animation(.easeOut(duration: 0.4), value: done)
                VStack(spacing: 0) {
                    ForEach(list.prefix(5)) { habit in HabitRow(habit: habit, store: store, edit: open) }
                }
                if list.count > 5 {
                    Button(action: open) {
                        Text(tr("+ \(list.count - 5) weitere", "+ \(list.count - 5) more")).font(.fenn(size: 12, weight: .medium)).foregroundStyle(Fenn.fg.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fennGlass(cornerRadius: 22, shadow: false)
        .onAppear {
            store.reload()
            store.applyAuto()
        }
    }
}

/// Tasks nobody touched for two weeks: plan them, star them, finish or let them go.
struct SlippingCard: View {
    @ObservedObject var store: TaskStore

    var body: some View {
        let items = Array(store.slipping().prefix(3))
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(tr("BLEIBT LIEGEN", "SLIPPING")).font(.fenn(size: 11, weight: .medium)).tracking(1.2).foregroundStyle(Fenn.fg.opacity(0.55))
                    Spacer()
                    Text(tr("seit 2+ Wochen unberührt", "untouched for 2+ weeks")).font(.fenn(size: 11)).foregroundStyle(Fenn.fg.opacity(0.45))
                }
                ForEach(items) { task in
                    HStack(spacing: 10) {
                        ClaySymbol(symbol: "hourglass", size: 22, tint: Fenn.amber)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(task.title).font(.fenn(size: 13, weight: .medium)).foregroundStyle(Fenn.fg).lineLimit(1)
                            Text(age(task)).font(.fenn(size: 11)).foregroundStyle(Fenn.fg.opacity(0.5))
                        }
                        Spacer(minLength: 0)
                        Button(tr("Heute", "Today")) { plan(task, 0) }.buttonStyle(FennPillButtonStyle())
                        Menu {
                            Button(tr("Nächste Woche", "Next week")) { plan(task, 7) }
                            Button(tr("In die Top 3", "Into the top 3")) { store.toggleStar(task.id) }
                            Button(tr("Erledigt", "Done")) { withAnimation(.snappy) { store.toggle(task.id) } }
                            Divider()
                            Button(tr("Loslassen (löschen)", "Let go (delete)"), role: .destructive) { withAnimation(.snappy) { store.delete(task.id) } }
                        } label: { Image(systemName: "ellipsis.circle").font(.fenn(size: 14)) }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            .help(tr("Was tun damit?", "What to do with it?"))
                    }
                    .frame(minHeight: 36)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fennGlass(cornerRadius: 22, shadow: false)
        }
    }

    private func age(_ task: FennTask) -> String {
        let days = Calendar.current.dateComponents([.day], from: task.updated, to: Date()).day ?? 14
        let topic = task.topic.isEmpty ? "" : ", \(task.topic)"
        return (days >= 14 ? tr("\(days / 7) Wochen liegen geblieben", "sat for \(days / 7) weeks") : tr("\(days) Tage", "\(days) days")) + topic
    }

    private func plan(_ task: FennTask, _ days: Int) {
        var copy = task
        copy.due = Calendar.current.date(byAdding: .day, value: days, to: Calendar.current.startOfDay(for: Date()))
        withAnimation(.snappy) { store.update(copy) }
    }
}

/// One older journal day or note, brought back – "Heute vor einem Monat" first. Click to read it all.
struct ResurfaceCard: View {
    @State private var item: ResurfaceItem?
    @State private var expanded = false

    init(loadNow: Bool = false) {
        if loadNow { _item = State(initialValue: Self.pickToday()) }
    }

    var body: some View {
        // A ZStack is there even while empty, so onAppear fires.
        ZStack {
            if let item {
                Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.when().uppercased()).font(.fenn(size: 11, weight: .medium)).tracking(1.2).foregroundStyle(Fenn.fg.opacity(0.55))
                            Spacer()
                            Label(item.sourceTitle, systemImage: item.source == .journal ? "book.closed" : "doc.text")
                                .font(.fenn(size: 11)).foregroundStyle(Fenn.fg.opacity(0.45))
                        }
                        Text(item.title).font(.fenn(size: 12, weight: .medium)).foregroundStyle(Fenn.fg.opacity(0.6))
                        Text("„\(item.text)“")
                            .font(.fenn(size: 14)).italic()
                            .foregroundStyle(Fenn.fg)
                            .lineLimit(expanded ? nil : 3)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(14)
                .fennGlass(cornerRadius: 22, shadow: false)
                .contextMenu {
                    if let url = item.url { Button(tr("Im Finder zeigen", "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() { item = Self.pickToday() }

    private static func pickToday() -> ResurfaceItem? {
        let items = Resurface.items(from: files(FennStorage.url(.journalFolder)), source: .journal)
            + Resurface.items(from: files(FennStorage.url(.notesFolder)), source: .note)
        return Resurface.pick(items)
    }

    private static func files(_ folder: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return Array(urls.filter { $0.pathExtension == "md" }.sorted { $0.lastPathComponent > $1.lastPathComponent }.prefix(400))
    }
}
