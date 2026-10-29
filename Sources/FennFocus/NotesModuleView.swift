import SwiftUI

struct NotesModuleView: View {
    @ObservedObject var notes: NotesStore
    @ObservedObject var dictation: DictationController
    let chooseAudio: () -> Void
    @State private var reading: NoteEntry?
    @State private var todosOpen = false
    @AppStorage("fenn.notes.resurfaceSkipped") private var skipped = ""
    @AppStorage("fenn.notes.resurfaceHidden") private var hidden = ""

    var body: some View {
        if let note = reading {
            NoteReaderMac(notes: notes, note: note, open: { reading = $0 }) { reading = nil }
        } else {
            board
        }
    }

    private var board: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(tr("Notizen", "Notes"))
                    .font(Fenn.display(22))
                    .foregroundStyle(Fenn.fg)
                Spacer()
                Label(tr("Lokal", "Local"), systemImage: "lock.fill")
                    .font(.fenn(size: 11, weight: .medium))
                    .foregroundStyle(Fenn.fg.opacity(0.45))
                    .help(tr("Ausgewertet von einem Modell auf diesem Mac – nichts geht in die Cloud.", "Analysed by a model on this Mac – nothing goes to the cloud."))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let current = notes.current {
                        resultCard(current)
                    } else {
                        inputCard
                    }
                    if notes.trashed != nil {
                        HStack(spacing: 10) {
                            Image(systemName: "trash").foregroundStyle(Fenn.fg.opacity(0.5))
                            Text(tr("Notiz in den Papierkorb gelegt.", "Note moved to the Trash."))
                                .font(.fenn(size: 12)).foregroundStyle(Fenn.fg.opacity(0.7))
                            Spacer()
                            Button(tr("Rückgängig", "Undo")) { notes.undoDelete() }
                                .buttonStyle(FennPillButtonStyle(prominent: false))
                            Button { notes.clearTrashed() } label: { Image(systemName: "xmark").font(.fenn(size: 10, weight: .bold)) }
                                .buttonStyle(.plain).foregroundStyle(Fenn.fg.opacity(0.45))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .fennGlass(cornerRadius: 14, shadow: false)
                    }
                    if let message = notes.message {
                        Text(message).font(.fenn(size: 12)).foregroundStyle(Fenn.fg.opacity(0.7))
                    }
                    if notes.current == nil {
                        if !openTodos.isEmpty || todosOpen { todoButton }
                        if let note = resurfaced { resurfacedCard(note) }
                    }
                    if !notes.recent.isEmpty { tiles }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
        }
        .onAppear {
            notes.refreshRecent()
            dictation.onFinish = { text in Task { await notes.process(text, source: .voice) } }
        }
    }

    // MARK: Input

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                if dictation.isListening {
                    HStack(alignment: .top, spacing: 8) {
                        Waveform(level: dictation.level, bars: 5).padding(.top, 2)
                        Text(dictation.transcript.isEmpty ? tr("Ich höre zu …", "Listening …") : dictation.transcript)
                            .font(.fenn(size: 14))
                            .foregroundStyle(Fenn.fg.opacity(dictation.transcript.isEmpty ? 0.5 : 0.9))
                    }
                    .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
                } else {
                    if notes.draft.isEmpty {
                        Text(tr("Gedanken, Meeting-Notizen, To-dos …", "Thoughts, meeting notes, to-dos …"))
                            .font(.fenn(size: 14))
                            .foregroundStyle(Fenn.fg.opacity(0.4))
                            .padding(.top, 1)
                            .padding(.leading, 5)
                    }
                    TextEditor(text: $notes.draft)
                        .font(.fenn(size: 14))
                        .foregroundStyle(Fenn.fg)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 110, maxHeight: 180)
                }
            }

            if let status = notes.status {
                FennThinking(state: .working, text: status)
            } else {
                HStack(spacing: 10) {
                    Button(action: dictation.toggle) {
                        Image(systemName: dictation.isListening ? "stop.fill" : "mic.fill")
                            .font(.fenn(size: 16, weight: .semibold))
                            .foregroundStyle(dictation.isListening ? Fenn.canvas : Fenn.fg)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(dictation.isListening ? Fenn.accent : Fenn.fillStrong))
                    }
                    .buttonStyle(.plain)
                    .help(tr("Sprechen", "Speak"))
                    .accessibilityLabel(dictation.isListening ? tr("Stopp", "Stop") : tr("Sprechen", "Speak"))

                    Button(action: chooseAudio) {
                        Image(systemName: "waveform.badge.plus").font(.fenn(size: 14))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(FennIconButtonStyle())
                    .disabled(dictation.isListening)
                    .help(tr("Audiodatei transkribieren (m4a, mp3, wav)", "Transcribe an audio file (m4a, mp3, wav)"))

                    Spacer()

                    Button {
                        Task { await notes.process(notes.draft, source: .typed) }
                    } label: {
                        Label(tr("Ordnen", "Sort"), systemImage: "sparkles")
                    }
                    .buttonStyle(FennPillButtonStyle(prominent: true))
                    .disabled(notes.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || dictation.isListening)
                    .help(tr("Titel, Kurzfassung und To-dos daraus machen", "Turn it into title, summary and to-dos"))
                }
            }
        }
        .padding(14)
        .fennGlass(cornerRadius: 22, shadow: false)
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(dictation.isListening ? Fenn.accent.opacity(0.6) : .clear, lineWidth: 1.5))
    }

    // MARK: Result

    private func resultCard(_ note: ProcessedNote) -> some View {
        let open = note.digest.todos.filter { !note.addedTodoIDs.contains($0.id) }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                ClaySymbol(symbol: "doc.text", size: 22)
                Text(note.digest.title).font(Fenn.display(17)).foregroundStyle(Fenn.fg)
                Spacer()
                Button { openTextFile(note.fileURL) } label: { Image(systemName: "arrow.up.forward.square") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Fenn.fg.opacity(0.55))
                    .help(tr("Datei öffnen", "Open file"))
                Button { notes.delete(note.fileURL) } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Fenn.fg.opacity(0.55))
                    .help(tr("Notiz löschen", "Delete note"))
                    .accessibilityLabel(tr("Notiz löschen", "Delete note"))
                Button { notes.dismissCurrent() } label: {
                    Image(systemName: "xmark").font(.fenn(size: 11, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Fenn.fg.opacity(0.5))
                .help(tr("Neue Notiz", "New note"))
            }
            Text(note.digest.summary)
                .font(.fenn(size: 13))
                .foregroundStyle(Fenn.fg.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            if !note.digest.todos.isEmpty {
                VStack(spacing: 0) {
                    ForEach(note.digest.todos) { todo in
                        let added = note.addedTodoIDs.contains(todo.id)
                        HStack(spacing: 10) {
                            Image(systemName: added ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(added ? Fenn.accent : Fenn.fg.opacity(0.4))
                            Text(todo.title).font(.fenn(size: 13)).foregroundStyle(Fenn.fg)
                            Spacer()
                            if todo.dayOffset != nil {
                                Text(todo.dayLabel)
                                    .font(.fenn(size: 11, weight: .medium))
                                    .foregroundStyle(Fenn.fg.opacity(0.6))
                            }
                            if !added {
                                Button { notes.addToTasks([todo]) } label: { Image(systemName: "plus.circle") }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Fenn.accent)
                                    .help(tr("In Aufgaben", "To tasks"))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                }
                .fennGlass(cornerRadius: 16, shadow: false)
                HStack(spacing: 8) {
                    Button {
                        notes.addToTasks(open)
                    } label: {
                        Label(open.isEmpty ? tr("In Aufgaben", "In tasks") : tr("\(open.count) in Aufgaben", "\(open.count) to tasks"),
                              systemImage: open.isEmpty ? "checkmark" : "checklist")
                    }
                    .buttonStyle(FennPillButtonStyle(prominent: !open.isEmpty))
                    .disabled(open.isEmpty)
                    Menu {
                        Button(tr("In Erinnerungen", "To Reminders")) { notes.target = .reminders; Task { await notes.addToCalendar(open) } }
                        Button(tr("Als Kalender-Termine", "As calendar events")) { notes.target = .calendar; Task { await notes.addToCalendar(open) } }
                    } label: {
                        Image(systemName: "ellipsis.circle").foregroundStyle(Fenn.fg.opacity(0.6))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .disabled(open.isEmpty)
                    Spacer()
                    Text(TaskStore.destination)
                        .font(.fenn(size: 11, weight: .light))
                        .foregroundStyle(Fenn.fg.opacity(0.45))
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fennGlass(cornerRadius: 22, shadow: false)
    }

    // MARK: To-dos from all notes

    private struct OpenTodo: Identifiable {
        var id: String { note.url.lastPathComponent + "#\(todo.line)" }
        let note: NoteEntry
        let todo: NoteEntry.Todo
    }

    private var openTodos: [OpenTodo] {
        notes.recent.flatMap { note in note.openTodos.map { OpenTodo(note: note, todo: $0) } }
    }

    private var todoButton: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy) { todosOpen.toggle() }
            } label: {
                HStack(spacing: 8) {
                    FennAvatar(size: 24)
                    Text(openTodos.isEmpty ? tr("Alles erledigt", "All done")
                         : openTodos.count == 1 ? tr("1 offenes To-do", "1 open to-do")
                         : tr("\(openTodos.count) offene To-dos", "\(openTodos.count) open to-dos"))
                        .font(.fenn(size: 13, weight: .medium)).foregroundStyle(Fenn.fg)
                    Image(systemName: "chevron.down").font(.fenn(size: 10, weight: .semibold)).foregroundStyle(Fenn.fg.opacity(0.5))
                        .rotationEffect(.degrees(todosOpen ? 180 : 0))
                }
                .padding(.leading, 6).padding(.trailing, 14).frame(height: 36)
                .background(Capsule().fill(Fenn.fill))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            if todosOpen && !openTodos.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(openTodos) { item in
                        NoteTodoRowMac(todo: item.todo, detail: item.note.title) { _ = notes.toggle(item.todo, in: item.note) }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Fenn.fill))
            }
        }
    }

    // MARK: Wiederentdeckt

    private var resurfaced: NoteEntry? {
        let today = FennVault.dayKey(Date())
        let skippedToday = skipped.hasPrefix(today + "|") ? Set(skipped.dropFirst(today.count + 1).components(separatedBy: "|")) : []
        let hiddenNames = Set(hidden.components(separatedBy: "\n"))
        let pool = notes.recent.filter { !hiddenNames.contains($0.url.lastPathComponent) && !skippedToday.contains($0.url.lastPathComponent) }
        let items = pool.compactMap { note in
            note.date.map { ResurfaceItem(source: .note, date: $0, title: note.title, text: note.firstSentence, url: note.url) }
        }
        guard let pick = Resurface.pick(items) else { return nil }
        return pool.first { $0.url == pick.url }
    }

    private func resurfacedCard(_ note: NoteEntry) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { reading = note } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(note.date.map { ResurfaceItem(source: .note, date: $0, title: "", text: "").when() } ?? "")
                        .font(.fenn(size: 11, weight: .semibold)).opacity(0.75)
                    Text("„\(note.firstSentence)“")
                        .font(.fenn(size: 18, weight: .semibold))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            HStack(spacing: 6) {
                Button(tr("Behalten", "Keep")) {
                    let today = FennVault.dayKey(Date())
                    let earlier = skipped.hasPrefix(today + "|") ? String(skipped.dropFirst(today.count + 1)) : ""
                    withAnimation(.snappy) { skipped = today + "|" + [earlier, note.url.lastPathComponent].filter { !$0.isEmpty }.joined(separator: "|") }
                }
                .font(.fenn(size: 12, weight: .semibold)).foregroundStyle(Fenn.accent)
                .padding(.horizontal, 14).frame(height: 30)
                .background(Capsule().fill(Fenn.onAccent))
                Button(tr("Nicht mehr zeigen", "Don't show again")) {
                    withAnimation(.snappy) { hidden = [hidden, note.url.lastPathComponent].filter { !$0.isEmpty }.joined(separator: "\n") }
                }
                .font(.fenn(size: 12)).foregroundStyle(Fenn.onAccent.opacity(0.85))
                .padding(.horizontal, 8).frame(height: 30)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Fenn.onAccent)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Fenn.accent))
    }

    // MARK: Tiles

    private var tiles: some View {
        let list = notes.recent
        return HStack(alignment: .top, spacing: 10) {
            ForEach(0..<2, id: \.self) { column in
                LazyVStack(spacing: 10) {
                    ForEach(Array(list.enumerated()).filter { $0.offset % 2 == column }, id: \.element.id) { index, note in
                        NoteTileMac(note: note, tall: index % 3 == 0, open: { reading = note },
                                    delete: { withAnimation(.snappy) { notes.delete(note.url) } })
                    }
                }
            }
        }
    }
}

/// A note on the board: topic symbol, title, when, open to-dos. Click opens it; the context menu deletes it.
private struct NoteTileMac: View {
    let note: NoteEntry
    let tall: Bool
    let open: () -> Void
    let delete: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 8) {
                ClaySymbol(symbol: note.topic.symbol, size: 26)
                Text(note.title)
                    .font(.fenn(size: 14, weight: .semibold)).foregroundStyle(Fenn.fg)
                    .multilineTextAlignment(.leading).lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Text(note.when).font(.fenn(size: 11)).foregroundStyle(Fenn.fg.opacity(0.6)).lineLimit(1)
                    Spacer(minLength: 0)
                    if !note.openTodos.isEmpty {
                        Text("\(note.openTodos.count)").font(.fenn(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(Fenn.onAccent)
                            .padding(.horizontal, 6).frame(minWidth: 20, minHeight: 20)
                            .background(Capsule().fill(Fenn.accent))
                            .help(tr("\(note.openTodos.count) offene To-dos", "\(note.openTodos.count) open to-dos"))
                    } else if note.topic == .idea {
                        Text(tr("Idee?", "Idea?")).font(.fenn(size: 11, weight: .semibold)).foregroundStyle(Fenn.accent)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: tall ? 130 : 108, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(hovering ? Fenn.fillStrong : Fenn.fill))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            Button(tr("Öffnen", "Open"), action: open)
            Button(tr("Im Editor öffnen", "Open in editor")) { openTextFile(note.url) }
            Divider()
            Button(tr("Löschen", "Delete"), role: .destructive, action: delete)
        }
    }
}

struct NoteTodoRowMac: View {
    let todo: NoteEntry.Todo
    var detail: String?
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().strokeBorder(todo.done ? Fenn.accent : Fenn.fg.opacity(0.45), lineWidth: 1.5)
                    if todo.done {
                        Circle().fill(Fenn.accent)
                        Image(systemName: "checkmark").font(.fenn(size: 9, weight: .bold)).foregroundStyle(Fenn.onAccent)
                    }
                }
                .frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(todo.text).font(.fenn(size: 13)).foregroundStyle(Fenn.fg.opacity(todo.done ? 0.45 : 1))
                        .strikethrough(todo.done, color: Fenn.fg.opacity(0.45))
                    if let detail {
                        Text(detail).font(.fenn(size: 10.5)).foregroundStyle(Fenn.fg.opacity(0.5)).lineLimit(1)
                    }
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One note inside the island: the text, Fenn's to-dos, a related note – and the file one click away.
private struct NoteReaderMac: View {
    @ObservedObject var notes: NotesStore
    @State var note: NoteEntry
    let open: (NoteEntry) -> Void
    let back: () -> Void
    @State private var addedTasks = false
    @State private var createdIdea = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button(action: back) { Image(systemName: "chevron.left").font(.fenn(size: 13, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(Fenn.fg.opacity(0.7))
                    .keyboardShortcut(.cancelAction)
                    .help(tr("Alle Notizen", "All notes"))
                Spacer()
                Button { openTextFile(note.url) } label: { Image(systemName: "arrow.up.forward.square") }
                    .buttonStyle(.plain).foregroundStyle(Fenn.fg.opacity(0.55))
                    .help(tr("Im Editor öffnen", "Open in editor"))
                Button { notes.delete(note.url); back() } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain).foregroundStyle(Fenn.fg.opacity(0.55))
                    .help(tr("Notiz löschen (Papierkorb)", "Delete note (Trash)"))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        if !note.longWhen.isEmpty {
                            Text(note.longWhen).font(.fenn(size: 12)).foregroundStyle(Fenn.fg.opacity(0.6))
                        }
                        Text(note.title).font(.fenn(size: 22, weight: .bold)).foregroundStyle(Fenn.fg)
                    }
                    Text(LocalizedStringKey(Self.inline(note.body)))
                        .font(.fenn(size: 14)).lineSpacing(4).foregroundStyle(Fenn.fg)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !note.todos.isEmpty { todoCard }
                    if note.topic == .idea { ideaButton }
                    if let related = note.related(in: notes.recent) {
                        Button { open(related) } label: {
                            HStack(spacing: 10) {
                                Text(tr("Passt dazu", "Related")).font(.fenn(size: 12)).foregroundStyle(Fenn.fg.opacity(0.6))
                                Text(related.title).font(.fenn(size: 13, weight: .medium)).foregroundStyle(Fenn.fg).lineLimit(1)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.fenn(size: 11, weight: .semibold)).foregroundStyle(Fenn.fg.opacity(0.4))
                            }
                            .padding(.horizontal, 14).frame(minHeight: 40)
                            .overlay(Capsule().strokeBorder(Fenn.fg.opacity(0.14)))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollIndicators(.never)
        }
    }

    private var todoCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                FennAvatar(size: 22)
                Text(note.todos.count == 1 ? tr("Fenn hat 1 To-do gefunden", "Fenn found 1 to-do")
                     : tr("Fenn hat \(note.todos.count) To-dos gefunden", "Fenn found \(note.todos.count) to-dos"))
                    .font(.fenn(size: 13, weight: .semibold)).foregroundStyle(Fenn.fg)
            }
            .frame(height: 38)
            ForEach(note.todos) { todo in
                NoteTodoRowMac(todo: todo) { note = notes.toggle(todo, in: note) }
            }
            if !note.openTodos.isEmpty {
                Button(addedTasks ? tr("In Aufgaben übernommen", "Added to tasks") : tr("In Aufgaben übernehmen", "Add to tasks")) {
                    let existing = Set(TaskStore.shared.open.map { $0.title.lowercased() })
                    TaskStore.shared.add(note.openTodos.filter { !existing.contains($0.text.lowercased()) }.map { FennTask(title: $0.text) })
                    addedTasks = true
                }
                .buttonStyle(FennPillButtonStyle())
                .disabled(addedTasks)
                .padding(.top, 6)
            }
        }
        .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Fenn.fill))
    }

    private var ideaButton: some View {
        Button(createdIdea ? tr("Liegt jetzt bei den Ideen", "Now in Ideas") : tr("Als Idee weiterdenken", "Develop as an idea")) {
            IdeaStore.shared.reload()
            if IdeaStore.shared.find(note.title) == nil {
                IdeaStore.shared.create(title: note.title, pitch: note.summary.isEmpty ? note.firstSentence : note.summary)
            }
            createdIdea = true
        }
        .buttonStyle(FennPillButtonStyle(prominent: true))
        .disabled(createdIdea)
    }

    /// Headings as bold lines – SwiftUI's inline Markdown doesn't render "#".
    private static func inline(_ text: String) -> String {
        text.components(separatedBy: "\n").map { line in
            line.hasPrefix("#") ? "**" + line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces) + "**" : line
        }.joined(separator: "\n")
    }
}
