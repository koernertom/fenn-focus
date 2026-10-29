import AppKit
import NaturalLanguage

struct KnowledgeChunk: Sendable {
    let file: URL
    let heading: String
    let text: String
    let vector: [Double]?
    let terms: Set<String>
}

struct KnowledgeHit: Identifiable {
    let id = UUID()
    let chunk: KnowledgeChunk
    let score: Double
}

struct KnowledgeAnswer: Equatable {
    let question: String
    let text: String
    let sources: [URL]
}

private struct InsightsCache: Codable {
    let signature: String
    let items: [String]
}

/// On-device sentence vectors: Apple's contextual (transformer) embedding, mean-pooled over tokens.
/// Clearly better than `NLEmbedding.sentenceEmbedding` for German notes; if the system hasn't
/// downloaded the model yet, it is requested once and search falls back to keywords meanwhile.
final class SemanticModel {
    private let model: NLContextualEmbedding?

    init() {
        let candidate = NLContextualEmbedding(language: .german)
        if let candidate, candidate.hasAvailableAssets, (try? candidate.load()) != nil {
            model = candidate
        } else {
            candidate?.requestAssets { _, _ in }
            model = nil
        }
    }

    func vector(for text: String) -> [Double]? {
        guard let model, let result = try? model.embeddingResult(for: text, language: .german) else { return nil }
        var sum = [Double](repeating: 0, count: model.dimension)
        var count = 0.0
        result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { vector, _ in
            for index in vector.indices { sum[index] += vector[index] }
            count += 1
            return true
        }
        return count > 0 ? sum.map { $0 / count } : nil
    }
}

/// Hybrid retrieval as in second-brain-starter: 70 % semantic, 30 % keyword — all on this Mac.
enum KnowledgeIndex {
    private static let fileExtensions: Set<String> = ["md", "markdown", "txt"]
    private static let maxFiles = 2000
    private static let maxFileSize = 1_000_000
    private static let chunkLength = 700
    private static let minimumScore = 0.45

    static func build(roots: [URL]) -> (chunks: [KnowledgeChunk], files: Int) {
        let model = SemanticModel()
        var chunks: [KnowledgeChunk] = []
        var files = 0
        for url in markdownFiles(in: roots) {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            files += 1
            for (heading, body) in split(text) {
                chunks.append(KnowledgeChunk(
                    file: url,
                    heading: heading,
                    text: body,
                    vector: model.vector(for: body),
                    terms: terms(in: heading + " " + body)
                ))
            }
        }
        return (chunks, files)
    }

    /// Mean-pooled vectors crowd into a narrow cosine band, so similarity is min–max normalised per query.
    static func search(_ query: String, in chunks: [KnowledgeChunk], model: SemanticModel, limit: Int) -> [KnowledgeHit] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let queryVector = model.vector(for: query)
        let queryTerms = terms(in: query)
        let similarities: [Double?] = chunks.map { chunk in
            guard let queryVector, let vector = chunk.vector else { return nil }
            return cosine(queryVector, vector)
        }
        let known = similarities.compactMap { $0 }
        let low = known.min() ?? 0
        let high = known.max() ?? 0

        var hits: [KnowledgeHit] = []
        for (chunk, similarity) in zip(chunks, similarities) {
            let semantic = similarity.map { high > low ? ($0 - low) / (high - low) : 0 } ?? 0
            let keyword = queryTerms.isEmpty
                ? 0
                : Double(queryTerms.intersection(chunk.terms).count) / Double(queryTerms.count)
            let score = 0.7 * semantic + 0.3 * keyword
            if score >= minimumScore { hits.append(KnowledgeHit(chunk: chunk, score: score)) }
        }
        return Array(hits.sorted { $0.score > $1.score }.prefix(limit))
    }

    private static func markdownFiles(in roots: [URL]) -> [URL] {
        var result: [URL] = []
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator {
                guard fileExtensions.contains(url.pathExtension.lowercased()),
                      let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                      values.isRegularFile == true,
                      (values.fileSize ?? 0) <= maxFileSize else { continue }
                result.append(url)
                if result.count >= maxFiles { return result }
            }
        }
        return result
    }

    /// Paragraph chunks of ~700 characters, each tagged with the nearest heading.
    private static func split(_ text: String) -> [(String, String)] {
        var result: [(String, String)] = []
        var heading = ""
        var buffer = ""
        func flush() {
            let body = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            // Skips empty template bullets like "- ".
            if body.filter(\.isLetter).count >= 3 { result.append((heading, body)) }
            buffer = ""
        }
        for line in text.components(separatedBy: .newlines) {
            if line.hasPrefix("#") {
                flush()
                heading = line.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
                continue
            }
            if buffer.count + line.count > chunkLength { flush() }
            buffer += line + "\n"
        }
        flush()
        return result
    }

    private static func terms(in text: String) -> Set<String> {
        Set(text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 })
    }

    private static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, normA = 0.0, normB = 0.0
        for i in a.indices {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        return normA > 0 && normB > 0 ? dot / (normA.squareRoot() * normB.squareRoot()) : 0
    }
}

/// Fenn's second brain: core memory files in the Fenn folder plus an optional notes library (e.g. an Obsidian vault).
@MainActor
final class KnowledgeStore: ObservableObject {
    @Published private(set) var fileCount = 0
    @Published private(set) var chunkCount = 0
    @Published private(set) var isIndexing = false
    @Published private(set) var libraryURL: URL?
    @Published private(set) var insights: [String] = []
    @Published private(set) var isThinking = false
    @Published private(set) var answer: KnowledgeAnswer?
    @Published private(set) var errorMessage: String?
    /// What Fenn remembers: the dated lines in MEMORY.md, without the date.
    @Published private(set) var memories: [String] = []

    /// The whole Fenn folder is the second brain: profile, journal, notes, coach logs, tasks, ideas.
    var brainURL: URL { FennStorage.root }
    private let client = AIClient()
    private var chunks: [KnowledgeChunk] = []
    private lazy var model = SemanticModel()
    private static let libraryKey = "fenn.knowledgeLibraryBookmark"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.libraryKey) {
            var stale = false
            // Security-scoped, so the vault stays readable after a relaunch inside the sandbox.
            libraryURL = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale)
            _ = libraryURL?.startAccessingSecurityScopedResource()
        }
        ensureCoreFiles()
        loadMemories()
        Task { await reindex() }
    }

    var soulURL: URL { FennStorage.url(.soul) }
    var memoryURL: URL { FennStorage.url(.memory) }
    var habitsURL: URL { FennStorage.url(.habits) }
    var profileURL: URL { FennStorage.url(.profile) }
    var goalsURL: URL { FennStorage.url(.goals) }
    var dailyURL: URL { FennStorage.url(.coachLog(FennVault.dayKey(Date()))) }

    var coreFiles: [(title: String, detail: String, url: URL)] {
        [
            ("profile.md", tr("Wer du bist, Ziele, Rennen, PRs", "Who you are, goals, races, PRs"), profileURL),
            ("goals.md", tr("Deine Ziele aus dem Journal", "Your goals from the journal"), goalsURL),
            ("SOUL.md", tr("Fenns Persönlichkeit und Ton", "Fenn's personality and tone"), soulURL),
            ("MEMORY.md", tr("Entscheidungen und Erkenntnisse", "Decisions and lessons"), memoryURL),
            ("HABITS.md", tr("Gewohnheiten, die Fenn im Blick hat", "Habits Fenn keeps an eye on"), habitsURL),
            (tr("Tageslog heute", "Today's log"), tr("Fragen und Antworten von heute", "Today's questions and answers"), dailyURL)
        ]
    }

    /// SOUL.md replaces Fenn's default personality when it has content.
    var soul: String? {
        guard let text = try? String(contentsOf: soulURL, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(4000))
    }

    func reindex() async {
        guard !isIndexing else { return }
        isIndexing = true
        let roots = [brainURL] + (libraryURL.map { [$0] } ?? [])
        let result = await Task.detached(priority: .utility) { KnowledgeIndex.build(roots: roots) }.value
        chunks = result.chunks
        fileCount = result.files
        chunkCount = result.chunks.count
        isIndexing = false
    }

    func search(_ query: String, limit: Int = 8) -> [KnowledgeHit] {
        KnowledgeIndex.search(query, in: chunks, model: model, limit: limit)
    }

    /// Answers only from the retrieved notes (RAG), with the notes it used as sources.
    func ask(_ question: String) async {
        let hits = search(question, limit: 6)
        guard !hits.isEmpty else {
            answer = KnowledgeAnswer(question: question, text: tr("Dazu steht noch nichts in deinen Notizen.", "Your notes don't cover that yet."), sources: [])
            return
        }
        isThinking = true
        errorMessage = nil
        let notes = hits.map { "[\($0.chunk.file.lastPathComponent)]\n\($0.chunk.text)" }.joined(separator: "\n\n")
        do {
            let reply = try await client.send(
                history: [CoachMessage(role: .user, text: "Notizen:\n\n\(notes)\n\nFrage: \(question)")],
                system: """
                Du bist Fenn. Beantworte die Frage ausschließlich anhand der Notizen des Nutzers. \
                Steht dort nichts dazu, sag das ehrlich. Höchstens vier kurze Sätze, Deutsch außer bei englischer Frage.
                """
            )
            var sources: [URL] = []
            for hit in hits where !sources.contains(hit.chunk.file) { sources.append(hit.chunk.file) }
            answer = KnowledgeAnswer(question: question, text: reply, sources: sources)
        } catch {
            errorMessage = error.localizedDescription
        }
        isThinking = false
    }

    func clearAnswer() {
        answer = nil
    }

    /// "What Fenn knows about you": 3–5 facts distilled from profile, memory, habits and recent logs.
    /// Regenerated only when those files change.
    func refreshInsights(force: Bool = false) async {
        if FennDemo.isOn {
            insights = FennDemo.insights
            return
        }
        let files = [profileURL, goalsURL, memoryURL, habitsURL] + recentJournal(3) + recentDailyLogs(3)
        let signature = files.map { url in
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return "\(url.lastPathComponent)@\(date.timeIntervalSince1970)"
        }.joined(separator: "|")
        let cacheURL = FennStorage.url(.insights)
        if !force, let data = try? Data(contentsOf: cacheURL),
           let cache = try? JSONDecoder().decode(InsightsCache.self, from: data), cache.signature == signature {
            insights = cache.items
            return
        }
        guard FennAI.isConfigured, !isThinking else { return }
        let text = files.compactMap { url in
            (try? String(contentsOf: url, encoding: .utf8)).map { "[\(url.lastPathComponent)]\n\($0.prefix(3000))" }
        }.joined(separator: "\n\n")
        isThinking = true
        defer { isThinking = false }
        guard let reply = try? await client.send(
            history: [CoachMessage(role: .user, text: text)],
            system: """
            Fasse in 3 bis 5 kurzen Stichpunkten zusammen, was aus diesen Notizen über die Person hervorgeht: \
            Ziele, Rennen, Stärken, Schwächen, Gewohnheiten, Einschränkungen. Nur belegte Fakten, nichts erfinden. \
            Leere Vorlagen ignorieren. Antworte nur mit einem JSON-Array aus Strings, jeder unter 90 Zeichen. Gibt es nichts, antworte [].
            """
        ), let start = reply.firstIndex(of: "["), let end = reply.lastIndex(of: "]"),
           let items = try? JSONDecoder().decode([String].self, from: Data(reply[start...end].utf8)) else { return }
        insights = Array(items.prefix(5))
        if let data = try? JSONEncoder().encode(InsightsCache(signature: signature, items: insights)) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    private func recentDailyLogs(_ count: Int) -> [URL] {
        Array(FennVault.files(in: FennStorage.url(.coachFolder), extension: "md").prefix(count))
    }

    /// Latest journal entries (check-ins, day plans, reviews).
    func recentJournal(_ count: Int) -> [URL] {
        Array(FennVault.files(in: FennStorage.url(.journalFolder), extension: "md").prefix(count))
    }

    /// Compact text of the latest journal entries for prompts.
    func journalContext(days: Int = 3, limit: Int = 3000) -> String {
        let text = recentJournal(days).compactMap { url in FennVault.readText(url).map { "[journal/\(url.lastPathComponent)]\n\($0)" } }
            .joined(separator: "\n\n")
        return String(text.prefix(limit))
    }

    /// Call after the sync folder changed.
    func storageChanged() {
        ensureCoreFiles()
        Task { await reindex() }
    }

    func setLibrary(_ url: URL?) {
        libraryURL?.stopAccessingSecurityScopedResource()
        libraryURL = url
        _ = url?.startAccessingSecurityScopedResource()
        if let url, let data = try? url.bookmarkData(options: .withSecurityScope) {
            UserDefaults.standard.set(data, forKey: Self.libraryKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.libraryKey)
        }
        Task { await reindex() }
    }

    func capture(_ thought: String) {
        let trimmed = thought.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appendToDaily("- \(Self.time), \(trimmed)")
    }

    func logExchange(question: String, answer: String) {
        let short = answer.count > 280 ? String(answer.prefix(280)) + " …" : answer
        appendToDaily("- \(Self.time), \(tr("Frage", "Question")): \(question)\n  Fenn: \(short.replacingOccurrences(of: "\n", with: " "))")
    }

    /// From the "Merken" click or Fenn's remember tool. The same fact twice stays one line.
    func remember(_ text: String) {
        let fact = Self.oneLine(text)
        guard !fact.isEmpty, !isRemembered(fact) else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        append("\n- \(formatter.string(from: Date())): \(fact)\n", to: memoryURL)
        loadMemories()
        Task { await reindex() }
    }

    func isRemembered(_ text: String) -> Bool { memories.contains(Self.oneLine(text)) }

    /// Takes a fact out of MEMORY.md again; the rest of the file stays as it is.
    func forget(_ text: String) {
        let fact = Self.oneLine(text)
        guard let content = try? String(contentsOf: memoryURL, encoding: .utf8) else { return }
        let kept = content.components(separatedBy: "\n").filter { Self.memoryFact(in: $0) != fact }
        try? kept.joined(separator: "\n").write(to: memoryURL, atomically: true, encoding: .utf8)
        loadMemories()
        Task { await reindex() }
    }

    /// Re-reads MEMORY.md – it can be edited by hand.
    func loadMemories() {
        let content = (try? String(contentsOf: memoryURL, encoding: .utf8)) ?? ""
        memories = content.components(separatedBy: "\n").compactMap(Self.memoryFact)
    }

    private static func oneLine(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
    }

    /// "- 14.10.2026: fact" → "fact"; other lines (headings, notes) are not memories.
    private static func memoryFact(in line: String) -> String? {
        guard let match = line.firstMatch(of: /^- \d{2}\.\d{2}\.\d{4}: (.+)$/) else { return nil }
        return String(match.1).trimmingCharacters(in: .whitespaces)
    }

    private func appendToDaily(_ entry: String) {
        let url = dailyURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? "# \(Date().formatted(date: .complete, time: .omitted))\n\n".write(to: url, atomically: true, encoding: .utf8)
        }
        append(entry + "\n", to: url)
        Task { await reindex() }
    }

    private func append(_ text: String, to url: URL) {
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(text.utf8))
    }

    private static var time: String {
        Date().formatted(date: .omitted, time: .shortened)
    }

    private func ensureCoreFiles() {
        FennVault.prepare(brainURL)
        let templates: [(URL, String)] = [
            (soulURL, """
            # \(tr("Fenn – Persönlichkeit", "Fenn – personality"))

            \(CoachViewModel.defaultPersona)
            """),
            (memoryURL, """
            # \(tr("Gedächtnis", "Memory"))

            \(tr("Entscheidungen, Erkenntnisse und laufende Projekte. Fenn ergänzt hier nur, wenn du „Merken“ klickst.",
                 "Decisions, lessons and active projects. Fenn only adds here when you click “Remember”."))

            """),
            (goalsURL, """
            # \(tr("Ziele", "Goals"))

            \(tr("Ziele, die du im Journal setzt, landen hier. Fenn richtet Vorschläge und Pläne danach aus.",
                 "Goals you set in the journal land here. Fenn aligns suggestions and plans with them."))

            """),
            (habitsURL, """
            # \(tr("Gewohnheiten", "Habits"))

            - [ ] \(tr("Den Tag am Morgen planen", "Plan the day in the morning"))
            - [ ] \(tr("Ein Fokusblock vor dem Mittag", "One focus block before noon"))
            - [ ] \(tr("Mails nur zu festen Zeiten", "Email only at fixed times"))
            - [ ] \(tr("Feierabend-Ritual", "Shutdown ritual"))

            """)
        ]
        for (url, content) in templates where !FileManager.default.fileExists(atPath: url.path) {
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

/// Opens a note in the default Markdown app, falling back to TextEdit.
func openTextFile(_ url: URL) {
    if !NSWorkspace.shared.open(url),
       let textEdit = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
        NSWorkspace.shared.open([url], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration())
    }
}
