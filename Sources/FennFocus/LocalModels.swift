import Foundation

/// One model Fenn Focus can download and run itself with MLX. Nothing ships inside the app: the person picks a model,
/// it downloads from Hugging Face into Application Support/FennFocus/Models and stays there. See docs/MODELS.md.
struct LocalModel: Identifiable, Hashable {
    /// The Hugging Face repository, e.g. "mlx-community/Qwen3.5-4B-MLX-4bit".
    let id: String
    let title: String
    let detailDE: String
    let detailEN: String
    let downloadGB: Double
    /// Unified memory the model needs to run comfortably next to everything else.
    let minMemoryGB: Int

    var detail: String { tr(detailDE, detailEN) }
    var folderName: String { id.replacingOccurrences(of: "/", with: "--") }
    var fits: Bool { LocalModels.memoryGB >= minMemoryGB }
    var sizeLabel: String { String(format: "%.1f GB", downloadGB) }
}

enum LocalModels {
    /// Small to large, as in docs/MODELS.md. All Apache-2.0.
    static let catalog: [LocalModel] = [
        LocalModel(id: "mlx-community/Qwen3.5-2B-MLX-4bit", title: "Qwen 3.5 2B",
                   detailDE: "Am schnellsten – Notizen, kurze Antworten. Als Agent schwächer.",
                   detailEN: "Fastest – notes, short answers. Weaker as an agent.", downloadGB: 1.7, minMemoryGB: 8),
        LocalModel(id: "mlx-community/Qwen3.5-4B-MLX-4bit", title: "Qwen 3.5 4B",
                   detailDE: "Empfohlen ab 8 GB – bester Agent unter 4 GB, gutes Deutsch.",
                   detailEN: "Recommended from 8 GB – best agent under 4 GB, good German.", downloadGB: 3.1, minMemoryGB: 8),
        LocalModel(id: "mlx-community/Qwen3.5-9B-MLX-4bit", title: "Qwen 3.5 9B",
                   detailDE: "Empfohlen ab 16 GB – deutlich besser mit Werkzeugen und Deutsch.",
                   detailEN: "Recommended from 16 GB – clearly better with tools and German.", downloadGB: 6.0, minMemoryGB: 16),
        LocalModel(id: "mlx-community/gemma-4-26b-a4b-it-4bit", title: "Gemma 4 26B A4B",
                   detailDE: "Ab 32 GB – große Qualität, dank Mixture-of-Experts trotzdem flott.",
                   detailEN: "From 32 GB – big-model quality, still quick thanks to mixture-of-experts.", downloadGB: 15.4, minMemoryGB: 32),
        LocalModel(id: "mlx-community/Qwen3.6-35B-A3B-4bit", title: "Qwen 3.6 35B A3B",
                   detailDE: "Ab 32 GB – Qwens schnelles Mixture-of-Experts-Modell.",
                   detailEN: "From 32 GB – Qwen's fast mixture-of-experts model.", downloadGB: 20.4, minMemoryGB: 32),
        LocalModel(id: "mlx-community/Qwen3.8-27B-4bit", title: "Qwen 3.8 27B",
                   detailDE: "Ab 48 GB – das stärkste, aber langsamer als die MoE-Modelle.",
                   detailEN: "From 48 GB – the strongest, but slower than the MoE models.", downloadGB: 16.1, minMemoryGB: 48),
    ]

    static var memoryGB: Int { Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded()) }

    /// What a first-time user should download on this Mac.
    static var recommended: LocalModel { catalog.first { $0.id.hasSuffix(memoryGB >= 16 ? "9B-MLX-4bit" : "4B-MLX-4bit") }! }

    static func model(_ id: String) -> LocalModel? { catalog.first { $0.id == id } }

    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FennFocus/Models", isDirectory: true)
    }

    /// A model folder in MLX format (has config.json). `-FennModelDir <folder>` points at one for development.
    static func directory(_ id: String) -> URL? {
        if id == devID, let dev = devDirectory { return dev }
        guard let model = model(id) else { return nil }
        let url = root.appendingPathComponent(model.folderName, isDirectory: true)
        return FileManager.default.fileExists(atPath: url.appendingPathComponent("config.json").path) ? url : nil
    }

    static let devID = "dev"

    private static var devDirectory: URL? {
        guard let path = UserDefaults.standard.string(forKey: "FennModelDir") else { return nil }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        return FileManager.default.fileExists(atPath: url.appendingPathComponent("config.json").path) ? url : nil
    }

    static var installed: [LocalModel] { catalog.filter { directory($0.id) != nil } }

    static var isAvailable: Bool { devDirectory != nil || !installed.isEmpty }

    /// A model id if it is installed; "auto" → the largest installed model that fits this Mac, "fast" → the smallest
    /// (quick jobs like tidying a note). The dev folder wins over both.
    static func resolve(_ choice: String) -> (id: String, url: URL)? {
        if let url = directory(choice) { return (choice, url) }
        if let dev = devDirectory { return (devID, dev) }
        let ready = installed
        let pick = choice == "fast" ? ready.first : (ready.last(where: \.fits) ?? ready.first)
        guard let pick, let url = directory(pick.id) else { return nil }
        return (pick.id, url)
    }
}

/// Downloads catalog models from Hugging Face – file by file, with progress, resumable by starting again.
@MainActor
final class LocalModelStore: NSObject, ObservableObject {
    static let shared = LocalModelStore()

    @Published private(set) var progress: [String: Double] = [:]
    @Published private(set) var failures: [String: String] = [:]
    @Published private(set) var installedIDs: Set<String> = Set(LocalModels.installed.map(\.id))

    private var jobs: [String: Task<Void, Never>] = [:]

    func isDownloading(_ model: LocalModel) -> Bool { jobs[model.id] != nil }

    func download(_ model: LocalModel, then done: (() -> Void)? = nil) {
        guard jobs[model.id] == nil else { return }
        failures[model.id] = nil
        progress[model.id] = 0
        jobs[model.id] = Task {
            do {
                try await fetch(model)
                installedIDs.insert(model.id)
                done?()
            } catch is CancellationError {
            } catch {
                failures[model.id] = error.localizedDescription
            }
            progress[model.id] = nil
            jobs[model.id] = nil
        }
    }

    func cancel(_ model: LocalModel) {
        jobs[model.id]?.cancel()
    }

    func delete(_ model: LocalModel) {
        cancel(model)
        try? FileManager.default.removeItem(at: LocalModels.root.appendingPathComponent(model.folderName))
        installedIDs.remove(model.id)
        Task { await LocalBrain.shared.unload() }
    }

    private struct RepoFile: Decodable {
        let type: String
        let path: String
        let size: Int64?
    }

    private func fetch(_ model: LocalModel) async throws {
        let listURL = URL(string: "https://huggingface.co/api/models/\(model.id)/tree/main?recursive=true")!
        let (data, response) = try await URLSession.shared.data(from: listURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw AIError.http((response as? HTTPURLResponse)?.statusCode ?? 0, tr("Modell auf Hugging Face nicht gefunden.", "Model not found on Hugging Face."))
        }
        // Weights, configs and tokenizer – not the model card.
        let files = try JSONDecoder().decode([RepoFile].self, from: data)
            .filter { $0.type == "file" && !$0.path.hasSuffix(".md") && !$0.path.hasPrefix(".") }
        let total = max(1, files.reduce(Int64(0)) { $0 + ($1.size ?? 0) })
        let partial = LocalModels.root.appendingPathComponent(model.folderName + ".partial", isDirectory: true)
        try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)

        var finished: Int64 = 0
        for file in files {
            try Task.checkCancellation()
            let target = partial.appendingPathComponent(file.path)
            let size = file.size ?? 0
            // Already there from an earlier, interrupted run.
            if let existing = try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize, Int64(existing) == size, size > 0 {
                finished += size
                progress[model.id] = Double(finished) / Double(total)
                continue
            }
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let remote = URL(string: "https://huggingface.co/\(model.id)/resolve/main/\(file.path)")!
            let base = finished
            let id = model.id
            let temp = try await FileDownload.run(remote) { received in
                Task { @MainActor in self.progress[id] = Double(base + received) / Double(total) }
            }
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: temp, to: target)
            finished += size
        }
        let final = LocalModels.root.appendingPathComponent(model.folderName, isDirectory: true)
        try? FileManager.default.removeItem(at: final)
        try FileManager.default.moveItem(at: partial, to: final)
    }
}

/// One file through a download task, reporting bytes as they arrive; cancelling the Swift task cancels the download.
private final class FileDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onBytes: (Int64) -> Void
    private var continuation: CheckedContinuation<URL, Error>?

    private init(onBytes: @escaping (Int64) -> Void) { self.onBytes = onBytes }

    static func run(_ url: URL, onBytes: @escaping (Int64) -> Void) async throws -> URL {
        let download = FileDownload(onBytes: onBytes)
        let session = URLSession(configuration: .default, delegate: download, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task = session.downloadTask(with: url)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                download.continuation = continuation
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        onBytes(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The system deletes `location` when this returns – keep a copy.
        let keep = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            if let status = (downloadTask.response as? HTTPURLResponse)?.statusCode, status != 200 {
                throw AIError.http(status, tr("Download fehlgeschlagen.", "Download failed."))
            }
            try FileManager.default.moveItem(at: location, to: keep)
            continuation?.resume(returning: keep)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        continuation?.resume(throwing: (error as? URLError)?.code == .cancelled ? CancellationError() : error)
        continuation = nil
    }
}

/// Local model servers that may already run on this Mac: Ollama and LM Studio, found with one quick request each.
enum LocalServers {
    struct Found: Equatable {
        var ollama: [String]?
        var lmStudio: [String]?
    }

    static func probe() async -> Found {
        async let ollama = models(AIConfig(provider: .ollama, baseURL: "", model: ""))
        async let lmStudio = models(AIConfig(provider: .lmStudio, baseURL: "", model: ""))
        return await Found(ollama: ollama, lmStudio: lmStudio)
    }

    /// nil when the server doesn't answer, else its model names (possibly empty).
    private static func models(_ config: AIConfig) async -> [String]? {
        let path = config.provider == .ollama ? "/api/tags" : "/models"
        guard let url = URL(string: config.trimmedBase + path),
              let (data, response) = try? await URLSession.shared.data(for: FennAI.request(url, timeout: 1.5)),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let list = (json["models"] ?? json["data"]) as? [[String: Any]] ?? []
        return list.compactMap { ($0["name"] ?? $0["id"]) as? String }.sorted()
    }

    /// The best of the installed server models, following docs/MODELS.md (Qwen 3.5 first, sized for this Mac).
    static func pick(_ names: [String]) -> String? {
        let order = LocalModels.memoryGB >= 16
            ? ["qwen3.5:9b", "qwen3.6", "gemma4:26b", "qwen3.8", "qwen3.5:4b", "qwen3.5", "qwen3", "gemma"]
            : ["qwen3.5:4b", "qwen3.5:2b", "qwen3.5", "qwen3", "gemma"]
        for prefix in order {
            if let hit = names.first(where: { $0.lowercased().hasPrefix(prefix) }) { return hit }
        }
        return names.first
    }
}
