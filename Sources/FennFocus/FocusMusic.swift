import AVFoundation
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// A music file the person imported for focus sessions.
struct FocusTrack: Identifiable, Hashable {
    let url: URL
    let title: String

    var id: URL { url }

    /// Imported tracks live in the app's own container – device-local, never in the sync folder.
    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FennFocus/Music", isDirectory: true)
    }

    static func all() -> [FocusTrack] {
        let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aiff", "caf"]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { audioExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { FocusTrack(url: $0, title: $0.deletingPathExtension().lastPathComponent) }
    }

    /// Copies a picked file (security-scoped) into the app, so it keeps working after the pick.
    static func importTrack(from url: URL) throws -> FocusTrack {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
        try FileManager.default.copyItem(at: url, to: target)
        return FocusTrack(url: target, title: target.deletingPathExtension().lastPathComponent)
    }
}

/// Focus music during a pomodoro: Spotify (the app, or the web player) and tracks imported into Fenn.
@MainActor
final class FocusMusic: ObservableObject {
    static let shared = FocusMusic()

    enum Source: String, CaseIterable, Identifiable {
        case spotify, local
        var id: String { rawValue }
        var title: String { self == .spotify ? "Spotify" : tr("Hinterlegt", "Saved") }
    }

    @Published var source: Source {
        didSet { UserDefaults.standard.set(source.rawValue, forKey: "fenn.focus.music.source") }
    }
    @Published var query: String {
        didSet { UserDefaults.standard.set(query, forKey: "fenn.focus.music.query") }
    }
    @Published var autoplay: Bool {
        didSet { UserDefaults.standard.set(autoplay, forKey: "fenn.focus.music.auto") }
    }
    @Published private(set) var tracks: [FocusTrack] = []
    @Published var selectedPath: String? {
        didSet { UserDefaults.standard.set(selectedPath, forKey: "fenn.focus.music.track") }
    }
    @Published private(set) var playing = false

    private var player: AVAudioPlayer?
    private var openedSpotify = false

    static var presets: [(title: String, query: String)] {
        [
            (tr("Deep Focus", "Deep Focus"), "deep focus"),
            (tr("Lo-Fi", "Lo-Fi"), "lofi hip hop"),
            (tr("Ambient", "Ambient"), "ambient focus"),
            (tr("Klassik", "Classical"), "classical focus playlist"),
        ]
    }

    private init() {
        let defaults = UserDefaults.standard
        source = Source(rawValue: defaults.string(forKey: "fenn.focus.music.source") ?? "") ?? .spotify
        query = defaults.string(forKey: "fenn.focus.music.query") ?? "deep focus"
        autoplay = defaults.object(forKey: "fenn.focus.music.auto") as? Bool ?? true
        selectedPath = defaults.string(forKey: "fenn.focus.music.track")
        reload()
    }

    func reload() { tracks = FocusTrack.all() }

    var selectedTrack: FocusTrack? {
        tracks.first { $0.url.path == selectedPath } ?? tracks.first
    }

    func sessionBegan() {
        guard autoplay else { return }
        switch source {
        case .spotify:
            guard !openedSpotify else { return }
            openedSpotify = true
            openSpotify()
        case .local:
            guard !playing, let track = selectedTrack else { return }
            play(track)
        }
    }

    func sessionPaused() {
        player?.pause()
        playing = false
    }

    func sessionEnded() {
        player?.stop()
        player = nil
        playing = false
        openedSpotify = false
    }

    func openSpotify() {
        let raw = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("spotify:"), let url = URL(string: raw) {
            open(url)
            return
        }
        if raw.contains("://"), let url = URL(string: raw) {
            open(url)
            return
        }
        let term = raw.isEmpty ? "deep focus" : raw
        let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? term
        #if os(iOS)
        guard let app = URL(string: "spotify:search:\(encoded)") else { return }
        UIApplication.shared.open(app) { opened in
            if !opened, let web = URL(string: "https://open.spotify.com/search/\(encoded)") {
                UIApplication.shared.open(web)
            }
        }
        #else
        if let app = URL(string: "spotify:search:\(encoded)"), NSWorkspace.shared.urlForApplication(toOpen: app) != nil {
            NSWorkspace.shared.open(app)
        } else if let web = URL(string: "https://open.spotify.com/search/\(encoded)") {
            NSWorkspace.shared.open(web)
        }
        #endif
    }

    func play(_ track: FocusTrack) {
        selectedPath = track.url.path
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        #endif
        player?.stop()
        guard let player = try? AVAudioPlayer(contentsOf: track.url) else { return }
        player.numberOfLoops = -1
        player.volume = 0.8
        player.play()
        self.player = player
        playing = true
    }

    func toggle(_ track: FocusTrack) {
        if playing, selectedPath == track.url.path {
            sessionPaused()
        } else {
            play(track)
        }
    }

    func importTrack(from url: URL) {
        guard let track = try? FocusTrack.importTrack(from: url) else { return }
        reload()
        selectedPath = track.url.path
        source = .local
    }

    private func open(_ url: URL) {
        #if os(iOS)
        UIApplication.shared.open(url)
        #else
        NSWorkspace.shared.open(url)
        #endif
    }
}

struct FocusMusicCard: View {
    @ObservedObject private var music = FocusMusic.shared
    @State private var importing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("FOKUS-MUSIK", "FOCUS MUSIC"))
                .font(.fenn(size: 11, weight: .medium)).tracking(1.2).foregroundStyle(Fenn.fg.opacity(0.5))
            FennSegments(options: FocusMusic.Source.allCases, selection: $music.source) { $0.title }
            if music.source == .spotify { spotify } else { local }
            Toggle(tr("Beim Start der Session abspielen", "Play when the session starts"), isOn: $music.autoplay)
                .font(.fenn(size: 13)).foregroundStyle(Fenn.fg).tint(Fenn.accent)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fennGlass(cornerRadius: 22)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio, .mp3, .mpeg4Audio]) { result in
            if let url = try? result.get() { music.importTrack(from: url) }
        }
    }

    private var spotify: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FocusMusic.presets, id: \.query) { preset in
                        let selected = music.query == preset.query
                        Button(preset.title) { music.query = preset.query }
                            .font(.fenn(size: 13))
                            .foregroundStyle(selected ? Fenn.onSelected : Fenn.fg)
                            .padding(.horizontal, 12).frame(height: 32)
                            .background(Capsule().fill(selected ? Fenn.selected : Fenn.fill))
                            .buttonStyle(.plain)
                    }
                }
            }
            TextField(tr("Suche oder Spotify-Link", "Search or Spotify link"), text: $music.query)
                .textFieldStyle(.plain)
                .font(.fenn(size: 14))
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Fenn.fill))
            Button { music.openSpotify() } label: {
                Label(tr("In Spotify öffnen", "Open in Spotify"), systemImage: "music.note").frame(maxWidth: .infinity)
            }
            // Secondary: the focus screen's one prominent action is "Start".
            .buttonStyle(FennPillButtonStyle())
        }
    }

    private var local: some View {
        VStack(alignment: .leading, spacing: 8) {
            if music.tracks.isEmpty {
                Text(tr("Noch kein Track hinterlegt. Importierte Fokus-Tracks liegen hier.",
                        "No track saved yet. Imported focus tracks show up here."))
                    .font(.fenn(size: 13)).foregroundStyle(Fenn.fg.opacity(0.6))
            } else {
                ForEach(music.tracks) { track in
                    let selected = music.selectedPath == track.url.path
                    Button { music.toggle(track) } label: {
                        HStack {
                            Image(systemName: music.playing && selected ? "pause.fill" : "play.fill")
                                .foregroundStyle(Fenn.accent).frame(width: 22)
                            Text(track.title).foregroundStyle(Fenn.fg).lineLimit(1)
                            Spacer()
                            if selected { Image(systemName: "checkmark").foregroundStyle(Fenn.accent) }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Button { importing = true } label: {
                Label(tr("Track hinzufügen", "Add a track"), systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(FennPillButtonStyle())
        }
    }
}
