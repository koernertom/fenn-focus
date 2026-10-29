import AppKit
import SwiftUI

/// "Ideen" on the Mac: the pebble with today's line, one field (or the mic) for a new idea, and every idea with how far it has come.
struct IdeasModuleView: View {
    @ObservedObject var store: IdeaStore
    @Binding var selected: String?
    @StateObject private var dictation = DictationController(maxDuration: .seconds(120), silenceTimeout: 4)
    @State private var draft = ""
    @State private var showParked = false
    @State private var showArchived = false
    @State private var suggestion: NoteEntry?
    @AppStorage("fenn.ideas.dismissedSuggestions") private var dismissed = ""

    private var active: [IdeaProject] { store.projects.filter { $0.status != .parked }.sorted { $0.updated > $1.updated } }
    private var parked: [IdeaProject] { store.projects.filter { $0.status == .parked }.sorted { $0.updated > $1.updated } }

    var body: some View {
        if let id = selected, store.project(id) != nil {
            IdeaProjectView(store: store, projectId: id) { selected = nil }
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 10) {
                hero
                ForEach(active) { project in
                    Button { selected = project.id } label: { IdeaRowMac(project: project) }.buttonStyle(.plain)
                }
                if let suggestion { suggestionCard(suggestion) }
                if !parked.isEmpty {
                    Button {
                        withAnimation(.snappy) { showParked.toggle() }
                    } label: {
                        Text(showParked ? tr("Geparkte ausblenden", "Hide parked")
                             : parked.count == 1 ? tr("1 geparkte Idee", "1 parked idea") : tr("\(parked.count) geparkte Ideen", "\(parked.count) parked ideas"))
                            .font(.fenn(size: 12)).foregroundStyle(Fenn.fg.opacity(0.6))
                            .frame(minHeight: 30)
                    }
                    .buttonStyle(.plain)
                    if showParked {
                        ForEach(parked) { project in
                            Button { selected = project.id } label: { IdeaRowMac(project: project).opacity(0.6) }.buttonStyle(.plain)
                        }
                    }
                }
                if !store.archived.isEmpty {
                    Button {
                        withAnimation(.snappy) { showArchived.toggle() }
                    } label: {
                        Text(showArchived ? tr("Archiv ausblenden", "Hide archive")
                             : store.archived.count == 1 ? tr("1 archivierte Idee", "1 archived idea") : tr("\(store.archived.count) archivierte Ideen", "\(store.archived.count) archived ideas"))
                            .font(.fenn(size: 12)).foregroundStyle(Fenn.fg.opacity(0.6))
                            .frame(minHeight: 30)
                    }
                    .buttonStyle(.plain)
                    if showArchived {
                        ForEach(store.archived) { project in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(project.title).font(.fenn(size: 14, weight: .semibold)).foregroundStyle(Fenn.fg).lineLimit(2)
                                    Text(tr("Archiviert, \(IdeaRowMac.when(project.updated))", "Archived, \(IdeaRowMac.when(project.updated))"))
                                        .font(.fenn(size: 11.5)).foregroundStyle(Fenn.fg.opacity(0.6))
                                }
                                Spacer(minLength: 0)
                                Button {
                                    withAnimation(.snappy) { store.restore(project) }
                                } label: {
                                    Label(tr("Zurückholen", "Restore"), systemImage: "arrow.uturn.backward")
                                        .font(.fenn(size: 12, weight: .medium)).foregroundStyle(Fenn.fg)
                                        .padding(.horizontal, 10).frame(height: 28)
                                        .background(Capsule().fill(Fenn.fillStrong))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.leading, 14).padding(.trailing, 10).padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Fenn.fill))
                            .opacity(0.75)
                        }
                    }
                }
                Button(tr("Ordner zeigen", "Show folder")) {
                    let url = IdeaFiles.root(in: FennStorage.root)
                    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                .buttonStyle(.plain).font(.fenn(size: 11)).foregroundStyle(Fenn.fg.opacity(0.45))
                .padding(.top, 4)
            }
            .padding(.bottom, 8)
        }
        .scrollIndicators(.never)
        .onAppear {
            store.reload()
            findSuggestion()
            dictation.onFinish = { text in create(text) }
        }
        .onChange(of: dictation.transcript) { _, spoken in if dictation.isListening { draft = spoken } }
        .onDisappear { dictation.stop() }
    }

    // MARK: Pebble, line of the day, field + mic

    private var hero: some View {
        let quote = FennQuotes.today
        return VStack(spacing: 12) {
            FennAvatar(size: 64)
            VStack(spacing: 5) {
                Text("„\(quote.text)“")
                    .font(.fenn(size: 17, weight: .semibold)).foregroundStyle(Fenn.fg)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(quote.by).font(.fenn(size: 12)).foregroundStyle(Fenn.fg.opacity(0.6))
            }
            .padding(.horizontal, 16)
            HStack(spacing: 8) {
                if dictation.isListening {
                    Waveform(level: dictation.level, bars: 5)
                    Text(draft.isEmpty ? tr("Ich höre zu …", "Listening …") : draft)
                        .font(.fenn(size: 13)).foregroundStyle(Fenn.fg.opacity(draft.isEmpty ? 0.6 : 1))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField(tr("Deine Idee in einem Satz", "Your idea in one sentence"), text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.fenn(size: 13))
                        .lineLimit(1...3)
                        .onSubmit { create(draft) }
                }
                if !draft.trimmingCharacters(in: .whitespaces).isEmpty && !dictation.isListening {
                    Button { create(draft) } label: {
                        Image(systemName: "arrow.up").font(.fenn(size: 12, weight: .bold)).foregroundStyle(Fenn.onAccent)
                            .frame(width: 28, height: 28).background(Circle().fill(Fenn.accent))
                    }
                    .buttonStyle(.plain)
                    .help(tr("Idee anlegen", "Save idea"))
                } else {
                    Button {
                        if !dictation.isListening { draft = "" }
                        dictation.toggle()
                    } label: {
                        Image(systemName: dictation.isListening ? "stop.fill" : "mic.fill")
                            .font(.fenn(size: 12, weight: .semibold)).foregroundStyle(Fenn.onAccent)
                            .frame(width: 28, height: 28).background(Circle().fill(Fenn.accent))
                    }
                    .buttonStyle(.plain)
                    .help(dictation.isListening ? tr("Aufnahme beenden", "Stop recording") : tr("Idee sprechen", "Speak an idea"))
                }
            }
            .padding(.leading, 14).padding(.trailing, 5).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Fenn.fill))
            if let error = dictation.errorMessage {
                Text(error).font(.fenn(size: 11)).foregroundStyle(Fenn.danger).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 10)
    }

    // MARK: From the notes

    private func suggestionCard(_ note: NoteEntry) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title).font(.fenn(size: 14, weight: .semibold)).foregroundStyle(Fenn.fg).lineLimit(2)
                Text(tr("Aus deinen Notizen", "From your notes")).font(.fenn(size: 11)).foregroundStyle(Fenn.fg.opacity(0.6))
            }
            Spacer(minLength: 0)
            Button {
                withAnimation(.snappy) { dismissed += "\n" + note.url.lastPathComponent }
                suggestion = nil
            } label: {
                Image(systemName: "xmark").font(.fenn(size: 11, weight: .semibold)).foregroundStyle(Fenn.fg.opacity(0.5)).frame(width: 26, height: 30)
            }
            .buttonStyle(.plain)
            .help(tr("Vorschlag ausblenden", "Dismiss suggestion"))
            Button {
                dismissed += "\n" + note.url.lastPathComponent
                suggestion = nil
                create(note.summary.isEmpty ? note.title + ". " + note.firstSentence : note.summary, title: note.title)
            } label: {
                Image(systemName: "plus").font(.fenn(size: 13, weight: .bold)).foregroundStyle(Fenn.onAccent)
                    .frame(width: 30, height: 30).background(Circle().fill(Fenn.accent))
            }
            .buttonStyle(.plain)
            .help(tr("Als Idee anlegen", "Save as idea"))
        }
        .padding(.leading, 14).padding(.trailing, 10).padding(.vertical, 10)
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Fenn.fg.opacity(0.28), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])))
    }

    /// The newest idea-like note of the last month that isn't an idea yet.
    private func findSuggestion() {
        let skip = Set(dismissed.components(separatedBy: "\n"))
        let monthAgo = Date().addingTimeInterval(-30 * 86_400)
        suggestion = NoteEntry.load(from: FennStorage.url(.notesFolder), limit: 60).first { note in
            note.topic == .idea && (note.date ?? .distantPast) > monthAgo && !skip.contains(note.url.lastPathComponent) && store.find(note.title) == nil
        }
    }

    private func create(_ text: String, title: String? = nil) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = ""
        guard !clean.isEmpty else { return }
        let name = title ?? clean.split(separator: " ").prefix(5).joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: ".,!?:"))
        let project = store.create(title: name, pitch: clean)
        selected = project.id
        Task { await store.send(tr("Hier ist meine Idee: \(clean). Hilf mir, sie weiterzudenken.", "Here's my idea: \(clean). Help me think it through."), to: project.id) }
    }
}

/// An idea in the list: eight dots for the eight canvas fields, the title, status and when it last moved.
private struct IdeaRowMac: View {
    let project: IdeaProject
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            IdeaMaturityRing(filled: project.canvas.filledCount, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.title).font(.fenn(size: 14, weight: .semibold)).foregroundStyle(Fenn.fg)
                    .multilineTextAlignment(.leading).lineLimit(2)
                Text("\(project.status.title), \(Self.when(project.updated))").font(.fenn(size: 11.5)).foregroundStyle(Fenn.fg.opacity(0.6))
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 10).padding(.trailing, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(hovering ? Fenn.fillStrong : Fenn.fill))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onHover { hovering = $0 }
    }

    /// Whole days only: "heute", "gestern", "vor 5 Tagen", "vor 3 Wochen".
    static func when(_ date: Date) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: Date())).day ?? 0
        switch days {
        case ..<1: return tr("heute", "today")
        case 1: return tr("gestern", "yesterday")
        case 2..<14: return tr("vor \(days) Tagen", "\(days) days ago")
        case 14..<60: return tr("vor \(days / 7) Wochen", "\(days / 7) weeks ago")
        default: return tr("vor \(days / 30) Monaten", "\(days / 30) months ago")
        }
    }
}

/// Eight dots in a circle, as many filled as canvas fields are, the count in the middle.
struct IdeaMaturityRing: View {
    let filled: Int
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                let angle = Angle.degrees(-90 + Double(index) * 45).radians
                Circle()
                    .fill(index < filled ? Fenn.accent : Fenn.fg.opacity(0.16))
                    .frame(width: size * 0.145, height: size * 0.145)
                    .offset(x: cos(angle) * size * 0.39, y: sin(angle) * size * 0.39)
            }
            Text("\(filled)").font(.fenn(size: size * 0.29, weight: .semibold).monospacedDigit()).foregroundStyle(Fenn.fg)
        }
        .frame(width: size, height: size)
        .help(tr("\(filled) von 8 Feldern", "\(filled) of 8 fields"))
    }
}

/// One idea: conversation with Fenn on the left of the switch, the canvas on the right.
private struct IdeaProjectView: View {
    @ObservedObject var store: IdeaStore
    let projectId: String
    let back: () -> Void
    @State private var showCanvas = false
    @State private var draft = ""
    @State private var addedTasks = false
    @State private var selectedSlot: String?
    @State private var tabChosen = false

    private var project: IdeaProject? { store.project(projectId) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let project {
                if showCanvas { overview(project) } else { conversation(project) }
            }
        }
        .onAppear {
            // A fresh idea opens on the conversation, one with some canvas on the overview.
            if !tabChosen { showCanvas = (project?.canvas.filledCount ?? 0) > 1; tabChosen = true }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: back) { Image(systemName: "chevron.left").font(.fenn(size: 13, weight: .semibold)) }
                .buttonStyle(.plain).foregroundStyle(Fenn.fg.opacity(0.7))
                .help(tr("Alle Ideen", "All ideas"))
            if !showCanvas {
                Text(project?.title ?? "").font(Fenn.display(16)).foregroundStyle(Fenn.fg).lineLimit(1)
            }
            Spacer()
            FennSegments(options: [true, false], selection: $showCanvas) { $0 ? tr("Überblick", "Overview") : "Brainstorm" }
            Menu {
                Picker(tr("Status", "Status"), selection: Binding(get: { project?.status ?? .idea }, set: { status in
                    if var updated = project { updated.status = status; store.save(updated) }
                })) {
                    ForEach(IdeaStatus.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Button(tr("Im Finder zeigen", "Show in Finder")) {
                    NSWorkspace.shared.activateFileViewerSelecting([IdeaFiles.folder(projectId, in: FennStorage.root)])
                }
                Divider()
                Button(tr("Archivieren (nach ideas/_archiv)", "Archive (to ideas/_archiv)")) {
                    if let project { store.archive(project) }
                    back()
                }
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
    }

    private func conversation(_ project: IdeaProject) -> some View {
        VStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if project.messages.isEmpty {
                            Text(tr("Erzähl Fenn von der Idee – oder wähl unten einen Denkanstoß.", "Tell Fenn about the idea – or pick a prompt below."))
                                .font(.fenn(size: 13)).foregroundStyle(Fenn.fg.opacity(0.6)).padding(.top, 12)
                        }
                        ForEach(project.messages) { message in
                            bubble(message).id(message.id)
                        }
                        if store.thinking == project.id {
                            FennThinking(state: .working, text: tr("Fenn denkt mit …", "Fenn is thinking …")).id("thinking")
                        }
                        if let error = store.errorMessage {
                            Text(error).font(.fenn(size: 12)).foregroundStyle(Fenn.danger)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)
                .onAppear { if let last = project.messages.last { proxy.scrollTo(last.id, anchor: .bottom) } }
                .onChange(of: project.messages.count) {
                    if let last = store.project(projectId)?.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
                .onChange(of: store.thinking) { if store.thinking != nil { withAnimation { proxy.scrollTo("thinking", anchor: .bottom) } } }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(IdeaMode.allCases) { mode in
                        Button { send(mode.prompt) } label: {
                            Label(mode.title, systemImage: mode.symbol).font(.fenn(size: 12, weight: .medium))
                                .padding(.horizontal, 10).frame(height: 26)
                                .background(Capsule().fill(Fenn.fillStrong))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Fenn.fg)
                        .disabled(store.thinking != nil)
                    }
                }
            }
            HStack(spacing: 8) {
                TextField(tr("Gedanke, Frage, Einwand …", "Thought, question, doubt …"), text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.fenn(size: 13))
                    .lineLimit(1...4)
                    .onSubmit { send(draft) }
                Button { send(draft) } label: {
                    Image(systemName: "arrow.up").font(.fenn(size: 12, weight: .bold)).foregroundStyle(Fenn.canvas)
                        .frame(width: 26, height: 26).background(Circle().fill(Fenn.fg))
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || store.thinking != nil)
            }
            .padding(.leading, 12).padding(.trailing, 5).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Fenn.fill))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Fenn.hairline))
        }
    }

    @ViewBuilder
    private func bubble(_ message: IdeaMessage) -> some View {
        if message.isUser {
            HStack {
                Spacer(minLength: 60)
                Text(message.text).font(.fenn(size: 13)).foregroundStyle(Fenn.fg)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Fenn.fillStrong))
                    .textSelection(.enabled)
            }
        } else {
            HStack(alignment: .top, spacing: 8) {
                FennAvatar(size: 22)
                FennMarkdown(text: message.text).textSelection(.enabled)
            }
        }
    }

    // MARK: Overview

    private struct Slot {
        let id: String
        let title: String
        let question: String
        let path: WritableKeyPath<IdeaCanvas, String>?
    }

    private var slots: [Slot] {
        let short = ["problem": tr("Problem", "Problem"), "audience": tr("Zielgruppe", "Audience"), "solution": tr("Lösung", "Solution"),
                     "business": tr("Geld", "Money"), "competition": tr("Wettbewerb", "Competition"), "risks": tr("Risiken", "Risks")]
        let questions = ["problem": tr("Welches Problem löst das – und für wen tut es weh?", "What problem does it solve – and who feels it?"),
                         "audience": tr("Wer genau hat das Problem? Beschreib eine Person.", "Who exactly has the problem? Describe one person."),
                         "solution": tr("Wie sieht die einfachste Lösung aus?", "What does the simplest solution look like?"),
                         "business": tr("Wer zahlt wie viel – und was bleibt übrig?", "Who pays how much – and what's left?"),
                         "competition": tr("Was machen Leute heute stattdessen?", "What do people do instead today?"),
                         "risks": tr("Was müsste stimmen, damit es klappt?", "What would have to be true for it to work?")]
        return [Slot(id: "pitch", title: "Pitch", question: tr("Wie sagst du die Idee in einem Satz?", "How do you say the idea in one sentence?"), path: \.pitch)]
            + IdeaCanvas.fields.map { Slot(id: $0.key, title: short[$0.key] ?? $0.title, question: questions[$0.key] ?? "", path: $0.path) }
            + [Slot(id: "steps", title: tr("Schritte", "Steps"), question: tr("Was ist der kleinste nächste Schritt?", "What's the smallest next step?"), path: nil)]
    }

    private func isFilled(_ slot: Slot, _ canvas: IdeaCanvas) -> Bool {
        if let path = slot.path { return !canvas[keyPath: path].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return !canvas.nextSteps.isEmpty
    }

    private func overview(_ project: IdeaProject) -> some View {
        let all = slots
        let current = all.first { $0.id == selectedSlot } ?? all.first { !isFilled($0, project.canvas) } ?? all[0]
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.status.title).font(.fenn(size: 12)).foregroundStyle(Fenn.fg.opacity(0.6))
                    TextField(tr("Titel", "Title"), text: Binding(
                        get: { store.project(projectId)?.title ?? "" },
                        set: { value in
                            guard var updated = store.project(projectId) else { return }
                            updated.title = value
                            store.save(updated)
                        }))
                        .textFieldStyle(.plain)
                        .font(.fenn(size: 22, weight: .bold)).foregroundStyle(Fenn.fg)
                        .help(tr("Klicken zum Umbenennen", "Click to rename"))
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 12) {
                    ForEach(Array(all.enumerated()), id: \.element.id) { index, slot in
                        let filled = isFilled(slot, project.canvas)
                        let chosen = slot.id == current.id
                        Button {
                            withAnimation(.snappy) { selectedSlot = slot.id }
                        } label: {
                            VStack(spacing: 5) {
                                Text(String(format: "%02d", index + 1))
                                    .font(.fenn(size: 13, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(filled ? Fenn.onAccent : Fenn.fg)
                                    .frame(width: 44, height: 44)
                                    .background(Circle().fill(filled ? Fenn.accent : Color.clear))
                                    .overlay {
                                        if !filled { Circle().strokeBorder(Fenn.fg.opacity(0.35), style: StrokeStyle(lineWidth: 1.2, dash: [3, 3])) }
                                    }
                                    .padding(3)
                                    .overlay(Circle().strokeBorder(chosen ? Fenn.fg : .clear, lineWidth: 1.5))
                                Text(slot.title).font(.fenn(size: 10.5, weight: chosen ? .semibold : .regular))
                                    .foregroundStyle(Fenn.fg.opacity(chosen ? 1 : 0.6)).lineLimit(1).minimumScaleFactor(0.8)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(slot.title + (filled ? tr(", ausgefüllt", ", filled") : tr(", offen", ", open")))
                    }
                }
                slotCard(current, project)
                if !project.canvas.questions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(tr("Offene Fragen", "Open questions")).font(.fenn(size: 12)).foregroundStyle(Fenn.fg.opacity(0.6))
                        ForEach(Array(project.canvas.questions.enumerated()), id: \.offset) { _, question in
                            Button { showCanvas = false; send(question) } label: {
                                Label(question, systemImage: "questionmark.bubble").font(.fenn(size: 12.5)).multilineTextAlignment(.leading)
                            }
                            .buttonStyle(.plain).foregroundStyle(Fenn.fg)
                        }
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .scrollIndicators(.never)
    }

    @ViewBuilder
    private func slotCard(_ slot: Slot, _ project: IdeaProject) -> some View {
        let filled = isFilled(slot, project.canvas)
        VStack(alignment: .leading, spacing: 10) {
            if !filled {
                HStack(spacing: 8) {
                    FennAvatar(size: 22)
                    Text(tr("\(slot.title) ist noch offen", "\(slot.title) is still open")).font(.fenn(size: 12)).foregroundStyle(Fenn.fg.opacity(0.6))
                }
                Text(slot.question).font(.fenn(size: 16, weight: .semibold)).foregroundStyle(Fenn.fg)
                    .fixedSize(horizontal: false, vertical: true)
                Button(tr("Mit Fenn klären", "Work it out with Fenn")) {
                    showCanvas = false
                    send(tr("Lass uns \(slot.title) klären: \(slot.question)", "Let's work out \(slot.title): \(slot.question)"))
                }
                .buttonStyle(FennPillButtonStyle(prominent: true))
                .disabled(store.thinking != nil)
            } else {
                HStack(spacing: 4) {
                    Text(slot.title).font(.fenn(size: 12)).foregroundStyle(Fenn.fg.opacity(0.6))
                    Image(systemName: "pencil").font(.fenn(size: 10)).foregroundStyle(Fenn.fg.opacity(0.4))
                }
                .help(tr("Text anklicken zum Bearbeiten", "Click the text to edit"))
            }
            if let path = slot.path {
                TextField(filled ? "" : tr("Oder selbst eintragen …", "Or write it yourself …"), text: Binding(
                    get: { store.project(projectId)?.canvas[keyPath: path] ?? "" },
                    set: { value in
                        guard var updated = store.project(projectId) else { return }
                        updated.canvas[keyPath: path] = value
                        store.save(updated)
                    }), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.fenn(size: filled ? 15 : 13)).foregroundStyle(Fenn.fg)
                    .lineLimit(1...10)
            } else if filled {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(project.canvas.nextSteps.enumerated()), id: \.offset) { _, step in
                        Label(step, systemImage: "circle").font(.fenn(size: 13.5)).foregroundStyle(Fenn.fg)
                    }
                }
                Button(addedTasks ? tr("In Aufgaben übernommen", "Added to tasks") : tr("Als Aufgaben übernehmen", "Add as tasks")) {
                    let existing = Set(TaskStore.shared.open.map { $0.title.lowercased() })
                    TaskStore.shared.add(project.canvas.nextSteps.filter { !existing.contains($0.lowercased()) }.map { step in
                        var task = FennTask(title: step)
                        task.topic = project.title
                        return task
                    })
                    addedTasks = true
                }
                .buttonStyle(FennPillButtonStyle())
                .disabled(addedTasks)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Fenn.fill))
    }

    private func send(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, store.thinking == nil else { return }
        draft = ""
        Task { await store.send(clean, to: projectId) }
    }
}
