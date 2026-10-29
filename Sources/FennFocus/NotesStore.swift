import Foundation

enum NoteSource {
    case typed
    case voice
    case file(String)

    var label: String {
        switch self {
        case .typed: return tr("Notiz", "Note")
        case .voice: return tr("Sprachnotiz", "Voice note")
        case .file(let name): return tr("Transkript von \(name)", "Transcript of \(name)")
        }
    }
}

struct ProcessedNote: Equatable {
    var digest: NoteDigest
    var fileURL: URL
    var addedTodoIDs: Set<UUID> = []
}

/// Notes typed, spoken or transcribed → digested by the local model → saved as Markdown in the second brain.
@MainActor
final class NotesStore: ObservableObject {
    @Published var draft = ""
    @Published private(set) var status: String?
    @Published private(set) var current: ProcessedNote?
    @Published private(set) var recent: [NoteEntry] = []
    @Published private(set) var message: String?
    /// The last note moved to the Trash – for "Rückgängig".
    @Published private(set) var trashed: (original: URL, inTrash: URL)?
    @Published var target: CalendarTarget {
        didSet { UserDefaults.standard.set(target.rawValue, forKey: CalendarTarget.defaultsKey) }
    }

    var isBusy: Bool { status != nil }

    var folder: URL { FennStorage.url(.notesFolder) }
    private let knowledge: KnowledgeStore
    private let calendar = CalendarBridge()

    init(knowledge: KnowledgeStore) {
        self.knowledge = knowledge
        target = UserDefaults.standard.string(forKey: CalendarTarget.defaultsKey).flatMap(CalendarTarget.init(rawValue:)) ?? .reminders
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        refreshRecent()
    }

    func process(_ text: String, source: NoteSource) async {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy else { return }
        message = nil
        status = tr("Lokales Modell wertet aus …", "Local model is analysing …")
        let digest = await LocalIntelligence.digest(text)
        let url = save(digest: digest, body: text, source: source)
        current = ProcessedNote(digest: digest, fileURL: url)
        draft = ""
        status = nil
        refreshRecent()
        await knowledge.reindex()
    }

    func transcribe(_ audio: URL) async {
        guard !isBusy else { return }
        message = nil
        status = tr("Transkribiere \(audio.lastPathComponent) …", "Transcribing \(audio.lastPathComponent) …")
        do {
            let text = try await Transcriber.transcribe(audio)
            status = nil
            await process(text, source: .file(audio.lastPathComponent))
        } catch {
            status = nil
            message = error.localizedDescription
        }
    }

    func addToCalendar(_ todos: [NoteTodo]) async {
        guard !todos.isEmpty else { return }
        do {
            try await calendar.add(todos, to: target)
            current?.addedTodoIDs.formUnion(todos.map(\.id))
            message = target == .reminders
                ? tr("\(todos.count) To-do(s) in Erinnerungen übernommen.", "\(todos.count) to-do(s) added to Reminders.")
                : tr("\(todos.count) To-do(s) als Termine eingeplant.", "\(todos.count) to-do(s) scheduled as events.")
        } catch {
            message = error.localizedDescription
        }
    }

    /// To-dos from the note into the task list.
    func addToTasks(_ todos: [NoteTodo]) {
        guard !todos.isEmpty else { return }
        TaskStore.shared.add(todos.map { TaskCapture.task(from: $0, topics: TaskStore.shared.topics) })
        current?.addedTodoIDs.formUnion(todos.map(\.id))
        message = nil
    }

    /// Moves the note file to the Trash (restorable there or via "Rückgängig").
    func delete(_ url: URL) {
        var result: NSURL?
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        } catch {
            message = error.localizedDescription
            return
        }
        if current?.fileURL == url { current = nil }
        trashed = (result as URL?).map { (original: url, inTrash: $0) }
        message = nil
        refreshRecent()
        Task { await knowledge.reindex() }
    }

    func undoDelete() {
        guard let trashed else { return }
        try? FileManager.default.moveItem(at: trashed.inTrash, to: trashed.original)
        self.trashed = nil
        refreshRecent()
        Task { await knowledge.reindex() }
    }

    func clearTrashed() { trashed = nil }

    func dismissCurrent() {
        current = nil
        message = nil
    }

    private func save(digest: NoteDigest, body: String, source: NoteSource) -> URL {
        let now = Date()
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd HHmm"
        let safeTitle = digest.title
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|"))
            .joined()
            .prefix(60)
        let url = folder.appendingPathComponent("\(stamp.string(from: now)) \(safeTitle).md")
        let todos = digest.todos.map { "- [ ] \($0.title) (\($0.dayLabel))" }.joined(separator: "\n")
        let markdown = """
        # \(digest.title)
        _\(now.formatted(date: .abbreviated, time: .shortened)), \(source.label), \(tr("lokal ausgewertet", "analysed locally")): \(digest.engine)_

        ## \(tr("Zusammenfassung", "Summary"))
        \(digest.summary)

        ## To-dos
        \(todos.isEmpty ? tr("– keine –", "– none –") : todos)

        ## \(tr("Notiz", "Note"))
        \(body)

        """
        try? markdown.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func refreshRecent() {
        recent = NoteEntry.load(from: folder)
    }

    /// Ticks or unticks a "- [ ]" line in the note's Markdown.
    func toggle(_ todo: NoteEntry.Todo, in note: NoteEntry) -> NoteEntry {
        let updated = note.toggling(todo)
        try? updated.raw.write(to: note.url, atomically: true, encoding: .utf8)
        if let index = recent.firstIndex(where: { $0.url == note.url }) { recent[index] = updated }
        return updated
    }
}

// MARK: - Notes as the board shows them

/// What a note is mostly about – guessed on the device from a few words, only for the symbol on its tile.
enum NoteTopic {
    case meeting, work, idea, thought

    var symbol: String {
        switch self {
        case .meeting: return "person.2"
        case .work: return "briefcase"
        case .idea: return "lightbulb"
        case .thought: return "quote.bubble"
        }
    }

    private static let words: [(NoteTopic, [String])] = [
        (.idea, ["idee", "idea", "könnte man", "geschäft", "business", "startup", "produkt"]),
        (.meeting, ["meeting", "call", "protokoll", "agenda", "teilnehmer", "besprechung", "weekly", "1:1", "standup", "workshop"]),
        (.work, ["pitch", "folien", "kunde", "projekt", "arbeit", "büro", "mail", "präsentation", "slides", "termin", "chef", "deadline"])
    ]

    static func guess(title: String, text: String) -> NoteTopic {
        let head = title.lowercased()
        if words[0].1.contains(where: head.contains) { return .idea }
        let all = " " + (title + " " + text).lowercased() + " "
        let scored = words.map { topic, list in (topic, list.reduce(0) { $0 + all.components(separatedBy: $1).count - 1 }) }
        guard let best = scored.max(by: { $0.1 < $1.1 }), best.1 > 0 else { return .thought }
        return best.0
    }
}

/// One Markdown note as the board shows it: title, date, the text, and its "- [ ]" to-dos.
struct NoteEntry: Identifiable, Equatable {
    struct Todo: Identifiable, Equatable {
        var id: Int { line }
        let line: Int
        let text: String
        var done: Bool
    }

    var id: URL { url }
    let url: URL
    var raw: String
    let title: String
    let date: Date?
    let summary: String
    let body: String
    var todos: [Todo]
    let topic: NoteTopic

    var openTodos: [Todo] { todos.filter { !$0.done } }

    init(url: URL, raw: String) {
        self.url = url
        self.raw = raw
        let lines = raw.components(separatedBy: "\n")
        var title: String?
        var section = ""
        var summary: [String] = []
        var body: [String] = []
        var todos: [Todo] = []
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let todo = Self.todo(trimmed, line: index) {
                todos.append(todo)
                continue
            }
            if trimmed.hasPrefix("# "), title == nil {
                title = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if trimmed.hasPrefix("## ") {
                section = trimmed.dropFirst(3).lowercased()
                continue
            }
            // The italic stamp under the title ("_5. Okt. 2026, 08:12, Mac, Apple Intelligence_").
            if trimmed.hasPrefix("_"), trimmed.hasSuffix("_"), body.isEmpty, summary.isEmpty { continue }
            if section.hasPrefix("zusammenfassung") || section.hasPrefix("summary") {
                summary.append(line)
            } else if section.hasPrefix("to-do") {
                continue
            } else {
                body.append(line)
            }
        }
        self.title = title ?? NoteEntry.fileTitle(url)
        self.date = NoteEntry.fileDate(url)
        self.summary = summary.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let text = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        self.body = text.isEmpty ? self.summary : text
        self.todos = todos
        self.topic = NoteTopic.guess(title: self.title, text: self.body)
    }

    private static func todo(_ line: String, line index: Int) -> Todo? {
        guard line.count > 6, line.hasPrefix("- [") || line.hasPrefix("* [") else { return nil }
        let mark = line[line.index(line.startIndex, offsetBy: 3)]
        guard [" ", "x", "X"].contains(mark), line[line.index(line.startIndex, offsetBy: 4)] == "]" else { return nil }
        let text = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : Todo(line: index, text: text, done: mark != " ")
    }

    /// The same note with one to-do ticked or unticked, rewritten in the Markdown.
    func toggling(_ todo: Todo) -> NoteEntry {
        var lines = raw.components(separatedBy: "\n")
        guard lines.indices.contains(todo.line) else { return self }
        let line = lines[todo.line]
        lines[todo.line] = todo.done
            ? line.replacingOccurrences(of: "[x]", with: "[ ]").replacingOccurrences(of: "[X]", with: "[ ]")
            : line.replacingOccurrences(of: "[ ]", with: "[x]")
        return NoteEntry(url: url, raw: lines.joined(separator: "\n"))
    }

    /// The first real sentence – what "Wiederentdeckt" quotes.
    var firstSentence: String {
        let source = body.isEmpty ? summary : body
        let flat = source.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "*", with: "")
        let end = flat.firstIndex { ".!?".contains($0) }.map { flat.index(after: $0) } ?? flat.endIndex
        let sentence = String(flat[..<end]).trimmingCharacters(in: .whitespaces)
        return sentence.count > 140 ? String(sentence.prefix(137)) + " …" : sentence
    }

    /// "Heute, 08:12", "Gestern", "Freitag", "12. Sep."
    var when: String {
        guard let date else { return "" }
        let calendar = Calendar.current
        let locale = Locale(identifier: tr("de_DE", "en_GB"))
        if calendar.isDateInToday(date) {
            return tr("Heute", "Today") + (Self.hasTime(url) ? ", " + date.formatted(.dateTime.hour().minute().locale(locale)) : "")
        }
        if calendar.isDateInYesterday(date) { return tr("Gestern", "Yesterday") }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: Date())).day ?? 99
        if days < 7 { return date.formatted(.dateTime.weekday(.wide).locale(locale)) }
        return date.formatted(.dateTime.day().month(.abbreviated).locale(locale))
    }

    var longWhen: String {
        guard let date else { return "" }
        let locale = Locale(identifier: tr("de_DE", "en_GB"))
        let day = date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))
        return Self.hasTime(url) ? day + ", " + date.formatted(.dateTime.hour().minute().locale(locale)) : day
    }

    /// "2026-09-24 0915 Idee Q4-Pitch.md" → "Idee Q4-Pitch", "2026-09-24-wall-ball-technik.md" → "Wall ball technik"
    static func fileTitle(_ url: URL) -> String {
        var name = url.deletingPathExtension().lastPathComponent
        if let range = name.range(of: #"^\d{4}-\d{2}-\d{2}[ -](\d{4} )?"#, options: .regularExpression) { name.removeSubrange(range) }
        if !name.contains(" ") { name = name.replacingOccurrences(of: "-", with: " ") }
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    static func fileDate(_ url: URL) -> Date? {
        let name = url.lastPathComponent
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        if hasTime(url), let date = formatter.date(from: String(name.prefix(15))) { return date }
        formatter.dateFormat = "yyyy-MM-dd"
        return name.count >= 10 ? formatter.date(from: String(name.prefix(10))) : nil
    }

    private static func hasTime(_ url: URL) -> Bool {
        url.lastPathComponent.range(of: #"^\d{4}-\d{2}-\d{2} \d{4}"#, options: .regularExpression) != nil
    }

    /// The note that shares the most telling words with this one, if any shares enough.
    func related(in notes: [NoteEntry]) -> NoteEntry? {
        let mine = Self.keywords(title + " " + body)
        guard !mine.isEmpty else { return nil }
        let scored = notes.filter { $0.url != url }.map { ($0, Self.keywords($0.title + " " + $0.body).intersection(mine).count) }
        guard let best = scored.max(by: { $0.1 < $1.1 }), best.1 >= 2 else { return nil }
        return best.0
    }

    private static let stopwords: Set<String> = ["nicht", "heute", "morgen", "wieder", "immer", "schon", "einen", "einem", "einer", "eine", "dann",
                                                 "diese", "dieser", "wenn", "aber", "noch", "nach", "über", "unter", "habe", "haben", "sind",
                                                 "about", "after", "there", "their", "which", "would", "could", "should", "today"]

    private static func keywords(_ text: String) -> Set<String> {
        Set(text.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { $0.count >= 5 && !stopwords.contains($0) })
    }
}

extension NoteEntry {
    /// Newest first, from the notes folder.
    static func load(from folder: URL, limit: Int = 120) -> [NoteEntry] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .prefix(limit)
            .compactMap { url in (try? String(contentsOf: url, encoding: .utf8)).map { NoteEntry(url: url, raw: $0) } }
    }
}
