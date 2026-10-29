import Foundation

/// Where the chosen sync folder lives.
enum SyncProvider {
    case iCloud
    case other

    var title: String {
        switch self {
        case .iCloud: return "iCloud Drive"
        case .other: return tr("Eigener Ordner", "Custom folder")
        }
    }

    var symbol: String {
        switch self {
        case .iCloud: return "icloud.fill"
        case .other: return "folder.fill"
        }
    }

    static func of(_ url: URL) -> SyncProvider {
        let path = url.path
        if path.contains("Mobile Documents") || path.contains("iCloud") { return .iCloud }
        return .other
    }
}

/// The "Fenn" folder in iCloud Drive (or anywhere else), picked once by the person. The sandbox can't reach it
/// by path, so access comes from a security-scoped bookmark.
final class FennCloudFolder: ObservableObject {
    static let shared = FennCloudFolder()
    private static let bookmarkKey = "fenn.cloudFolderBookmark"

    @Published private(set) var current: URL?

    private init() {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource() else { return }
        if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope) {
            UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey)
        }
        current = url
        FennVault.prepare(url)
    }

    static var url: URL? { shared.current }
    static var isAvailable: Bool { shared.current != nil }

    var isConnected: Bool { current != nil }
    var provider: SyncProvider? { current.map(SyncProvider.of) }

    private static var realHome: URL {
        let home = getpwuid(getuid()).flatMap { String(validatingUTF8: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home)
    }

    /// iCloud Drive of the real user (the sandbox home is the app container).
    static var iCloudDrive: URL { realHome.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs") }

    /// Connects the picked folder. Picking the drive itself (or any folder not called "FennFocus") creates "FennFocus" inside it.
    /// Everything Fenn stored on this Mac so far moves over, so nothing is lost.
    func connect(_ picked: URL) {
        _ = picked.startAccessingSecurityScopedResource()
        var folder = picked
        if picked.lastPathComponent.lowercased() != "fennfocus" {
            folder = picked.appendingPathComponent("FennFocus", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        guard let data = try? folder.bookmarkData(options: .withSecurityScope) else { return }
        current?.stopAccessingSecurityScopedResource()
        UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
        if folder != picked {
            var stale = false
            if let scoped = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale) {
                _ = scoped.startAccessingSecurityScopedResource()
                folder = scoped
            }
            picked.stopAccessingSecurityScopedResource()
        }
        FennVault.adopt(from: FennStorage.local, into: folder)
        FennVault.prepare(folder)
        current = folder
    }

    /// Files already in the folder stay there; Fenn works from its local copy again.
    @MainActor
    func disconnect() {
        if let current { FennVault.adopt(from: current, into: FennStorage.local) }
        current?.stopAccessingSecurityScopedResource()
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        current = nil
    }
}

/// Where everything Fenn writes goes: the sync folder when connected, otherwise Application Support/FennFocus.
/// Same layout either way (`FennVault`).
enum FennStorage {
    static let local: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FennFocus", isDirectory: true)
        FennVault.prepare(url)
        return url
    }()

    /// Screenshot mode (`-FennDemo YES`): a separate folder, freshly filled on every launch – the real one stays untouched.
    static let demo: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FennFocus-Demo", isDirectory: true)
        try? FileManager.default.removeItem(at: url)
        FennDemo.writeFolder(url)
        return url
    }()

    static var root: URL { FennDemo.isOn ? demo : (FennCloudFolder.url ?? local) }

    static func url(_ place: FennVault.Place) -> URL { FennVault.url(place, in: root) }
}
