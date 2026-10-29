import Foundation

/// Layout of the Fenn folder (iCloud Drive or any folder the person picks),
/// plain Markdown and JSON so people and models can read it:
///
///     Fenn/
///       README.md
///       profile/    profile.md · goals.md · SOUL.md · MEMORY.md · HABITS.md
///       journal/    2026-09-23.md          check-in, day plan, review, goals
///       notes/      notes and transcripts
///       coach/      2026-09-23.md (questions & answers) · insights.json
///       stats/      days.json (focus blocks, tasks and routines done per day)
///       tasks/      tasks.json (to-dos, focus log) · Aufgaben.md (readable overview by topic)
///       habits/     habits.json (routines and ticks) · Routinen.md (readable overview)
///       ideas/      <project>/README.md (idea canvas) · brainstorm.md · idea.json – one folder per business idea
enum FennVault {
    enum Place {
        case readme
        case profile, goals, soul, memory, habits
        case journalFolder, journal(String)
        case notesFolder
        case coachFolder, coachLog(String), insights
        case dayStats
        case tasks, tasksOverview
    }

    static func url(_ place: Place, in root: URL) -> URL {
        switch place {
        case .readme: return root.appendingPathComponent("README.md")
        case .profile: return root.appendingPathComponent("profile/profile.md")
        case .goals: return root.appendingPathComponent("profile/goals.md")
        case .soul: return root.appendingPathComponent("profile/SOUL.md")
        case .memory: return root.appendingPathComponent("profile/MEMORY.md")
        case .habits: return root.appendingPathComponent("profile/HABITS.md")
        case .journalFolder: return root.appendingPathComponent("journal", isDirectory: true)
        case .journal(let day): return root.appendingPathComponent("journal/\(day).md")
        case .notesFolder: return root.appendingPathComponent("notes", isDirectory: true)
        case .coachFolder: return root.appendingPathComponent("coach", isDirectory: true)
        case .coachLog(let day): return root.appendingPathComponent("coach/\(day).md")
        case .insights: return root.appendingPathComponent("coach/insights.json")
        case .dayStats: return root.appendingPathComponent("stats/days.json")
        case .tasks: return root.appendingPathComponent("tasks/tasks.json")
        case .tasksOverview: return root.appendingPathComponent("tasks/Aufgaben.md")
        }
    }

    static func dayKey(_ date: Date) -> String { dayFormatter.string(from: date) }

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // MARK: Setup

    /// Creates the folders and README, and moves files from the earlier flat layout into place.
    static func prepare(_ root: URL) {
        let manager = FileManager.default
        for folder in ["profile", "journal", "notes", "coach", "stats", "tasks", "habits", "ideas"] {
            try? manager.createDirectory(at: root.appendingPathComponent(folder, isDirectory: true), withIntermediateDirectories: true)
        }
        let legacy: [(String, Place)] = [
            ("profile.md", .profile), ("SOUL.md", .soul), ("MEMORY.md", .memory), ("HABITS.md", .habits),
            ("insights.json", .insights)
        ]
        for (name, place) in legacy {
            moveIfMissing(root.appendingPathComponent(name), to: url(place, in: root))
        }
        for (old, new) in [("daily", Place.coachFolder)] {
            let folder = root.appendingPathComponent(old, isDirectory: true)
            guard let files = try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { continue }
            for file in files { moveIfMissing(file, to: url(new, in: root).appendingPathComponent(file.lastPathComponent)) }
            if (try? manager.contentsOfDirectory(atPath: folder.path))?.isEmpty == true { try? manager.removeItem(at: folder) }
        }
        if !manager.fileExists(atPath: url(.readme, in: root).path) {
            _ = write(Data(readme.utf8), to: url(.readme, in: root))
        }
    }

    /// Copies everything from `local` into `shared` that isn't there yet — used when a sync folder gets connected.
    static func adopt(from local: URL, into shared: URL) {
        let manager = FileManager.default
        guard local.standardizedFileURL != shared.standardizedFileURL,
              let enumerator = manager.enumerator(at: local, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        prepare(local)
        for case let file as URL in enumerator {
            guard (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true else { continue }
            let relative = String(file.standardizedFileURL.path.dropFirst(local.standardizedFileURL.path.count + 1))
            // Device-local things (imported music, caches) stay where they are.
            guard !relative.hasPrefix("Music") && !relative.hasPrefix(".") else { continue }
            let target = shared.appendingPathComponent(relative)
            guard !manager.fileExists(atPath: target.path) else { continue }
            try? manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? manager.copyItem(at: file, to: target)
        }
    }

    private static func moveIfMissing(_ source: URL, to target: URL) {
        let manager = FileManager.default
        guard manager.fileExists(atPath: source.path), !manager.fileExists(atPath: target.path) else { return }
        try? manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? manager.moveItem(at: source, to: target)
    }

    // MARK: Coordinated I/O (iCloud syncs files underneath us)

    static func read(_ url: URL) -> Data? {
        var result: Data?
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { result = try? Data(contentsOf: $0) }
        return result
    }

    static func readText(_ url: URL) -> String? {
        read(url).flatMap { String(data: $0, encoding: .utf8) }
    }

    @discardableResult
    static func write(_ data: Data, to url: URL) -> Bool {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var ok = false
        var error: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &error) {
            ok = (try? data.write(to: $0, options: .atomic)) != nil
        }
        return ok
    }

    @discardableResult
    static func writeText(_ text: String, to url: URL) -> Bool {
        write(Data(text.utf8), to: url)
    }

    /// Appends a Markdown block, creating the file with `header` first.
    @discardableResult
    static func append(_ text: String, to url: URL, header: String) -> Bool {
        let existing = readText(url) ?? header
        return writeText(existing + text, to: url)
    }

    /// Newest files first.
    static func files(in folder: URL, extension ext: String) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == ext }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    static let readme = """
    # Fenn

    Dieser Ordner gehört dir: Fenn Focus legt hier alles als Markdown oder JSON ab – du kannst es lesen, \
    in Obsidian öffnen oder einem anderen Modell geben. Fenn liest ihn als Kontext für Antworten.

    | Ordner | Inhalt |
    |---|---|
    | `profile/` | `profile.md` (wer du bist), `goals.md` (Ziele), `SOUL.md` (Fenns Ton), `MEMORY.md`, `HABITS.md` |
    | `journal/` | Ein Eintrag pro Tag: Check-in, Tagesplan, Tagesrückblick, Ziele |
    | `notes/` | Notizen, Sprachnotizen und Transkripte |
    | `coach/` | Fragen und Antworten an Fenn pro Tag, `insights.json` |
    | `stats/` | `days.json` – Fokusblöcke, erledigte Aufgaben und Routinen pro Tag |
    | `tasks/` | `tasks.json` (Aufgaben), `Aufgaben.md` (lesbare Übersicht nach Thema) |
    | `habits/` | `habits.json` (Routinen und abgehakte Tage), `Routinen.md` (lesbare Übersicht mit Serien) |
    | `ideas/` | Ein Ordner pro Idee: `README.md` (Ideen-Canvas), `brainstorm.md` (Gespräch mit Fenn), eigene Notizen als `.md` |
    """
}
