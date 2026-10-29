import AppKit

enum IslandModule: String, CaseIterable, Identifiable {
    case today
    case tasks
    case habits
    case focus
    case notes
    case coach
    case ideas
    case journal
    case connectors

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return tr("Heute", "Today")
        case .tasks: return tr("Aufgaben", "Tasks")
        case .habits: return tr("Routinen", "Routines")
        case .coach: return "Fenn"
        case .notes: return tr("Notizen", "Notes")
        case .focus: return tr("Fokus", "Focus")
        case .ideas: return tr("Ideen", "Ideas")
        case .journal: return "Journal"
        case .connectors: return tr("Verbindungen", "Connections")
        }
    }

    var symbol: String {
        switch self {
        case .today: return "sun.max"
        case .tasks: return "checklist"
        case .habits: return "repeat"
        case .coach: return "sparkles"
        case .notes: return "note.text"
        case .focus: return "timer"
        case .ideas: return "lightbulb"
        case .journal: return "book.closed"
        case .connectors: return "powerplug"
        }
    }
}

/// Where Fenn lives: at the notch / under the menu bar, or docked to a screen edge.
enum IslandPlacement: String, CaseIterable, Identifiable {
    case top
    case left
    case right

    var id: String { rawValue }

    var title: String {
        switch self {
        case .top: return tr("Oben (Notch)", "Top (notch)")
        case .left: return tr("Links am Rand", "Left edge")
        case .right: return tr("Rechts am Rand", "Right edge")
        }
    }

    static let defaultsKey = "fenn.placement"
}

struct IslandGeometry: Equatable {
    static let sideWidth: CGFloat = 84
    static let defaultPanelSize = CGSize(width: 480, height: 620)
    static let minPanelSize = CGSize(width: 420, height: 520)
    static let edgePillSize = CGSize(width: 46, height: 136)
    static let gap: CGFloat = 10
    /// Room around the panel so its SwiftUI shadow isn't clipped by the window.
    static let shadowMargin: CGFloat = 32

    var placement: IslandPlacement
    var hasNotch: Bool
    var notchWidth: CGFloat
    var barHeight: CGFloat
    /// The panel can be dragged bigger; remembered across launches.
    var panelSize = IslandGeometry.defaultPanelSize
    /// The edge pill can be made smaller (Normal / Klein / Mini).
    var pillScale: CGFloat = 1

    var usesNotch: Bool { placement == .top && hasNotch }
    var isVertical: Bool { placement != .top }

    var collapsedSize: CGSize {
        switch placement {
        case .left, .right: return CGSize(width: (Self.edgePillSize.width * pillScale).rounded(), height: (Self.edgePillSize.height * pillScale).rounded())
        case .top: return hasNotch ? CGSize(width: notchWidth + 2 * Self.sideWidth, height: barHeight) : CGSize(width: 210, height: 34)
        }
    }

    var expandedWindowSize: CGSize {
        let panel = panelSize
        let margin = Self.shadowMargin
        if isVertical {
            return CGSize(width: collapsedSize.width + Self.gap + panel.width + margin, height: panel.height + 2 * margin)
        }
        return CGSize(width: panel.width + 2 * margin, height: collapsedSize.height + Self.gap + panel.height + margin)
    }

    static func forScreen(_ screen: NSScreen, placement: IslandPlacement, panelSize: CGSize, pillScale: CGFloat = 1) -> IslandGeometry {
        let top = screen.safeAreaInsets.top
        var geometry: IslandGeometry
        if top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            geometry = IslandGeometry(placement: placement, hasNotch: true, notchWidth: screen.frame.width - left.width - right.width, barHeight: top)
        } else {
            geometry = IslandGeometry(placement: placement, hasNotch: false, notchWidth: 0, barHeight: 0)
        }
        geometry.pillScale = pillScale
        geometry.panelSize = clamp(panelSize, on: screen, geometry: geometry)
        return geometry
    }

    /// Never smaller than the minimum, never bigger than the screen minus the bar.
    static func clamp(_ size: CGSize, on screen: NSScreen, geometry: IslandGeometry) -> CGSize {
        let visible = screen.visibleFrame
        let margin = shadowMargin * 2 + gap
        let maxWidth = visible.width - (geometry.isVertical ? geometry.collapsedSize.width + margin : margin)
        let maxHeight = visible.height - (geometry.isVertical ? margin : geometry.collapsedSize.height + margin)
        #if DEBUG
        // QA only: -FennQAPanelHeight 1600 makes the panel taller than the screen so a snapshot shows the whole page.
        let qaHeight = UserDefaults.standard.double(forKey: "FennQAPanelHeight")
        if qaHeight > 0 { return CGSize(width: min(max(size.width, minPanelSize.width), maxWidth), height: qaHeight) }
        #endif
        return CGSize(width: min(max(size.width, minPanelSize.width), maxWidth),
                      height: min(max(size.height, minPanelSize.height), maxHeight))
    }
}

@MainActor
final class IslandModel: ObservableObject {
    @Published var isExpanded = false
    /// Fenn first: opening shows only Fenn and the input; asking or "Startseite" grows it into the full panel.
    @Published var launcher = false
    static let launcherHeight: CGFloat = 234
    /// The pop from the notch is still flying to the launcher's pebble – the pebble shows once he has landed.
    @Published var popInFlight = false
    static let fennFirstKey = "fenn.mac.fennFirst"
    static var fennFirst: Bool { UserDefaults.standard.object(forKey: fennFirstKey) as? Bool ?? true }
    @Published var module: IslandModule = .today
    /// The idea project open in the Ideas module (nil = the list).
    @Published var openIdea: String?
    @Published var geometry = IslandGeometry(placement: .top, hasNotch: false, notchWidth: 0, barHeight: 0)
    /// The size the person dragged the panel to.
    @Published var panelSize: CGSize = IslandModel.storedPanelSize {
        didSet { UserDefaults.standard.set([panelSize.width, panelSize.height], forKey: Self.panelSizeKey) }
    }
    /// Size of the pill on the screen edge – remembered.
    @Published var pillScale: CGFloat = CGFloat(UserDefaults.standard.object(forKey: IslandModel.pillScaleKey) as? Double ?? 1) {
        didSet { UserDefaults.standard.set(Double(pillScale), forKey: Self.pillScaleKey) }
    }
    static let pillScaleKey = "fenn.pill.scale"
    static let pillSizes: [(title: String, scale: CGFloat)] = [
        (tr("Normal", "Normal"), 1), (tr("Klein", "Small"), 0.78), (tr("Mini", "Mini"), 0.6),
    ]
    @Published var needsOnboarding = !FennDemo.isOn && !UserDefaults.standard.bool(forKey: IslandModel.onboardingKey)

    static let onboardingKey = "fenn.mac.onboarding.completed.v1"
    private static let panelSizeKey = "fenn.panelSize"

    private static var storedPanelSize: CGSize {
        guard let values = UserDefaults.standard.array(forKey: panelSizeKey) as? [Double], values.count == 2 else {
            return IslandGeometry.defaultPanelSize
        }
        return CGSize(width: values[0], height: values[1])
    }
}
