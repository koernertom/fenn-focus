import SwiftUI
import AppKit

/// Fenn's clay icons ("Knet-Optik"): SF symbol → clay asset.
enum ClayArt {
    private static let table: [String: String] = [
        "drop": "Food-water", "drop.fill": "Food-water",
        "book": "Clay-books", "book.fill": "Clay-books",
        "leaf": "Page-meditation", "leaf.fill": "Page-meditation",
        "pencil": "Set-pen", "pencil.line": "Set-pen",
        "figure.yoga": "Clay-yogamat", "figure.flexibility": "Clay-yogamat", "figure.mind.and.body": "Clay-yogamat",
        "figure.walk": "Clay-footprints", "figure.run": "Set-shoe",
        "dumbbell": "Page-training", "dumbbell.fill": "Page-training",
        "bed.double": "Clay-bed", "bed.double.fill": "Clay-bed",
        "iphone.slash": "Page-block", "lock": "Page-block", "lock.fill": "Page-block",
        "heart": "Set-heart", "heart.fill": "Set-heart",
        "pills": "Food-pills", "pills.fill": "Food-pills",
        "snowflake": "Clay-snowflake", "sparkles": "Set-sparkles",
        "cup.and.saucer": "Food-coffee", "cup.and.saucer.fill": "Food-coffee",
        "carrot": "Food-carrot", "carrot.fill": "Food-carrot",
        "brain.head.profile": "Clay-brain", "brain": "Clay-brain", "flag.checkered": "Run-flag",
        "sun.max": "Clay-sun", "sun.max.fill": "Clay-sun",
        "sun.horizon": "Page-today", "sunrise": "Page-today",
        "moon": "Clay-moon", "moon.stars": "Clay-moon", "moon.fill": "Clay-moon", "moon.zzz": "Clay-moon",
        "clock": "Page-focus", "timer": "Page-focus", "hourglass": "Page-focus",
        "fork.knife": "Page-food",
        "flame": "Clay-campfire", "flame.fill": "Clay-campfire", "cloud.rain": "Clay-raincloud", "water.waves": "Clay-wave",
        "speaker.slash": "Clay-feather", "wind": "Clay-feather", "headphones": "Run-headphones", "music.note": "Run-note",
        "lightbulb": "Page-ideas", "note.text": "Page-notes", "checklist": "Page-tasks", "trophy": "Page-rank",
        "square": "Clay-wave", "figure.cooldown": "Clay-yogamat", "bell": "Set-bell", "bell.fill": "Set-bell",
        "book.closed": "Page-journal", "repeat": "Page-habits", "chart.line.uptrend.xyaxis": "Page-progress",
        "fork.knife.circle": "Page-food", "doc.text": "Page-notes", "scope": "Page-focus",
        "target": "Page-training", "figure.strengthtraining.traditional": "Page-training",
        "figure.hiking": "Clay-footprints", "shoeprints.fill": "Clay-footprints", "figure.pool.swim": "Clay-wave",
        "mountain.2": "Page-progress", "mountain.2.fill": "Page-progress",
        "trophy.fill": "Page-rank", "rosette": "Page-rank", "flag": "Run-flag", "flag.fill": "Run-flag",
        "star": "Set-points", "star.fill": "Set-points", "wand.and.stars": "Set-sparkles",
        "heart.text.square": "Set-healthbox", "heart.text.square.fill": "Set-healthbox",
        "link": "Set-link", "person.2": "Set-friends", "person.2.fill": "Set-friends",
        "icloud": "Set-cloud", "icloud.fill": "Set-cloud", "folder": "Set-folder", "folder.fill": "Set-folder",
        "envelope": "Set-envelope", "envelope.fill": "Set-envelope", "globe": "Set-globe",
        "map": "Set-map", "map.fill": "Set-map", "paintpalette": "Set-palette", "paintpalette.fill": "Set-palette",
        "stopwatch": "Run-stopwatch", "stopwatch.fill": "Run-stopwatch", "music.note.list": "Run-note",
        "calendar": "Page-today", "calendar.day.timeline.left": "Page-today", "bubble.left": "Set-help",
        "questionmark.circle": "Set-help", "slider.horizontal.3": "Set-sliders", "person": "Set-profile",
        "person.crop.circle": "Set-profile", "applewatch": "Set-watch", "waveform.path.ecg": "Set-pulse",
        "bicycle": "Run-route", "figure.outdoor.cycle": "Run-route", "location": "Run-compass", "magnifyingglass": "Run-search",
        "play.circle": "Run-play", "square.grid.2x2": "Set-cards", "gearshape": "Set-sliders", "paintbrush": "Set-palette",
    ]

    static func name(for symbol: String) -> String? {
        table[symbol].flatMap { NSImage(named: $0) != nil ? FennArt.pick($0) : nil }
    }
}

/// Which clay picture to show for a base asset name under the current scheme: the seasonal variant
/// ("Page-training-autumn") where one exists, none at all in the clean look.
enum FennArt {
    static func pick(_ base: String) -> String? {
        let tones = FennScheme.current.tones
        if tones.plainIcons { return nil }
        if let set = tones.iconSet, NSImage(named: "\(base)-\(set)") != nil { return "\(base)-\(set)" }
        return base
    }
}

extension IslandModule {
    /// The clay page icon of this area.
    var art: String? {
        let name: String?
        switch self {
        case .today: name = "Page-today"
        case .tasks: name = "Page-tasks"
        case .habits: name = "Page-habits"
        case .coach: name = nil
        case .notes: name = "Page-notes"
        case .focus: name = "Page-focus"
        case .ideas: name = "Page-ideas"
        case .journal: name = "Page-journal"
        case .connectors: name = "Set-link"
        }
        return name.flatMap { NSImage(named: $0) != nil ? FennArt.pick($0) : nil }
    }
}

/// A clay icon where there is one, the SF symbol in the accent colour otherwise.
struct ClaySymbol: View {
    let symbol: String
    var size: CGFloat = 22
    var tint: Color = Fenn.accent

    var body: some View {
        if let art = ClayArt.name(for: symbol) {
            Image(art).resizable().interpolation(.high).scaledToFit()
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.18), radius: 1.2, x: 0.6, y: 1)
        } else {
            Image(systemName: symbol).font(.fenn(size: size * 0.6)).foregroundStyle(tint).frame(width: size, height: size)
        }
    }
}

/// The module's clay picture (or its symbol), for the bar and menus.
struct ModuleIcon: View {
    let module: IslandModule
    var size: CGFloat = 24

    var body: some View {
        if let art = module.art {
            Image(art).resizable().interpolation(.high).scaledToFit()
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.2), radius: 1.2, x: 0.6, y: 1)
        } else {
            Image(systemName: module.symbol)
        }
    }
}
