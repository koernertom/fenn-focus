import SwiftUI
import AppKit
import FennFocusCore

/// Dates follow the app language, not the system region (no "24. Sep at 15:24").
var fennLocale: Locale { Locale(identifier: L10n.usesEnglish ? "en_GB" : "de_DE") }

/// Inline DE/EN copy for the island UI, following `L10n.usesEnglish`.
func tr(_ de: String, _ en: String) -> String {
    L10n.usesEnglish ? en : de
}

/// Colour scheme — greyish petrol around #0e4243,
/// sage as the contrast. Default is Fenn Grün. Orange is gone; an old stored value falls back to green.
/// Read once at launch (More › Darstellung › Farbschema, or `-fenn.theme petrol`).
enum FennScheme: String, CaseIterable, Identifiable {
    case white, green, seasonal, clean, autumn, christmas, spring, summer, stone, earth, bark, midnight, cobalt, petrol, petrolChalk

    static let key = "fenn.theme"
    /// What is stored – `.seasonal` stays itself here, so the picker knows what was chosen.
    static let stored: FennScheme = {
        // The October redesign: Fenn on the Mac turns white once; the old look stays one click away in Design.
        let defaults = UserDefaults.standard
        var migrate = !defaults.bool(forKey: "fenn.mac.whiteRedesign")
        #if DEBUG
        // QA runs share the real app's settings – they pass -fenn.theme / -fenn.appearance instead.
        if defaults.bool(forKey: "FennQANoFocus") { migrate = false }
        #endif
        if migrate {
            defaults.set(true, forKey: "fenn.mac.whiteRedesign")
            defaults.set(FennScheme.white.rawValue, forKey: key)
            defaults.set(FennAppearance.light.rawValue, forKey: FennAppearance.key)
        }
        return FennScheme(rawValue: defaults.string(forKey: key) ?? "") ?? .white
    }()
    /// The scheme the app paints with (seasonal resolved to today's season).
    static let current = stored.resolved()
    var id: String { rawValue }

    /// "Mit den Jahreszeiten": spring March–May, summer June–August, autumn September–November,
    /// Christmas in December, the clean look in January and February.
    func resolved(on date: Date = Date()) -> FennScheme {
        guard self == .seasonal else { return self }
        switch Calendar.current.component(.month, from: date) {
        case 3...5: return .spring
        case 6...8: return .summer
        case 9...11: return .autumn
        case 12: return .christmas
        default: return .clean
        }
    }

    var title: String {
        switch self {
        case .white: return tr("Fenn Weiß", "Fenn white")
        case .green: return tr("Fenn Grün", "Fenn green")
        case .seasonal: return tr("Mit den Jahreszeiten", "With the seasons")
        case .clean: return tr("Clean", "Clean")
        case .autumn: return tr("Herbst", "Autumn")
        case .christmas: return tr("Weihnachten", "Christmas")
        case .spring: return tr("Frühling", "Spring")
        case .summer: return tr("Sommer", "Summer")
        case .stone: return tr("Stein und Petrol", "Stone and petrol")
        case .earth: return tr("Erde und Petrol", "Earth and petrol")
        case .bark: return tr("Erdbraun", "Earth brown")
        case .midnight: return tr("Mitternacht und Lavendel", "Midnight and lavender")
        case .cobalt: return tr("Graphit und Kobalt", "Graphite and cobalt")
        case .petrol: return tr("Petrol und Bordeaux", "Petrol and bordeaux")
        case .petrolChalk: return tr("Petrol und Kreide", "Petrol and chalk")
        }
    }

    struct Tones {
        var accent: (Double, Double, Double), accentOnPaper: (Double, Double, Double)
        var onAccent: (Double, Double, Double)
        var brand: (Double, Double, Double)
        var light: (Double, Double, Double), lightOnPaper: (Double, Double, Double)
        var pale: (Double, Double, Double), paleOnPaper: (Double, Double, Double)
        var deep: (Double, Double, Double), deeper: (Double, Double, Double), deepest: (Double, Double, Double)
        var cream: (Double, Double, Double), creamOnPaper: (Double, Double, Double)
        var muted: (Double, Double, Double)
        var smoke: (Double, Double, Double), glass: (Double, Double, Double)
        var freshInk: (Double, Double, Double)
        var paper: (Double, Double, Double), night: (Double, Double, Double)
        var avatar: String
        var onAccentOnPaper: (Double, Double, Double) = (1, 1, 1)
        var stoneAuras = false
        var petrolAurasInDark = false
        var brownGround = false
        var richBrown = false
        var accentPills = false
        var backdrop: String? = nil
        var avatarCutout = false
        var glassOnPaper: (Double, Double, Double) = (1, 1, 1)
        /// Seasonal clay pictures: "Page-training-autumn" etc. stand in for the plain ones where they exist.
        var iconSet: String? = nil
        /// The clean look: SF Symbols instead of clay pictures.
        var plainIcons = false
        /// Fenn Weiß: in light mode cards are solid white on a bright panel instead of tinted glass.
        var solidWhite = false
    }

    var tones: Tones {
        if self == .seasonal { return resolved().tones }
        var t = Tones(accent: (0.44, 0.04, 0.03), accentOnPaper: (0.19, 0.004, 0.004), onAccent: (1, 1, 1),
                      brand: (0.21, 0.37, 0.37),
                      light: (0.58, 0.69, 0.68), lightOnPaper: (0.20, 0.34, 0.34),
                      pale: (0.83, 0.87, 0.86), paleOnPaper: (0.16, 0.27, 0.27),
                      deep: (0.055, 0.259, 0.263), deeper: (0.04, 0.16, 0.17), deepest: (0.03, 0.12, 0.13),
                      cream: (0.74, 0.80, 0.79), creamOnPaper: (0.93, 0.95, 0.945), muted: (0.30, 0.40, 0.40),
                      smoke: (0.03, 0.09, 0.09), glass: (0.02, 0.06, 0.06), freshInk: (0.05, 0.15, 0.15),
                      paper: (0.945, 0.952, 0.948), night: (0.012, 0.032, 0.034), avatar: "FennAvatar")
        if self == .green || self == .white || self == .stone || self == .earth || self == .bark {
            t.accent = (0.42, 0.60, 0.55); t.accentOnPaper = (0.10, 0.30, 0.29); t.onAccent = (0.03, 0.12, 0.13)
            t.stoneAuras = true
            t.avatar = "FennAvatarStone"
            t.smoke = (0.33, 0.29, 0.26); t.glass = (0.24, 0.21, 0.19); t.glassOnPaper = (0.93, 0.89, 0.85)
            t.accentOnPaper = (0.21, 0.31, 0.29)
            t.paper = (0.955, 0.937, 0.905); t.creamOnPaper = (0.95, 0.92, 0.87)
            t.lightOnPaper = (0.40, 0.33, 0.28); t.paleOnPaper = (0.33, 0.28, 0.24)
            t.night = (0.035, 0.10, 0.10)
        }
        if self == .green {
            t.night = (0.03, 0.09, 0.09)
            t.smoke = (0.09, 0.24, 0.24); t.glass = (0.05, 0.17, 0.17)
            t.petrolAurasInDark = true; t.accentPills = true
            t.backdrop = "FennBackdrop"
            t.avatarCutout = true
        }
        if self == .white {
            // White paper, near-black type, the petrol green only as the accent – clay icons bring the colour.
            t.night = (0.03, 0.09, 0.09)
            t.smoke = (0.09, 0.24, 0.24); t.glass = (0.05, 0.17, 0.17)
            t.petrolAurasInDark = true; t.accentPills = true; t.avatarCutout = true
            t.paper = (0.968, 0.968, 0.96); t.glassOnPaper = (1, 1, 1); t.creamOnPaper = (0.955, 0.955, 0.945)
            t.accentOnPaper = (0.07, 0.34, 0.31); t.onAccentOnPaper = (1, 1, 1)
            t.lightOnPaper = (0.13, 0.40, 0.36); t.paleOnPaper = (0.10, 0.30, 0.28)
            t.solidWhite = true
        }
        if self == .earth {
            t.night = (0.085, 0.068, 0.056)
            t.smoke = (0.09, 0.24, 0.24); t.glass = (0.05, 0.17, 0.17)
            t.petrolAurasInDark = true; t.brownGround = true
        }
        if self == .bark {
            t.night = (0.085, 0.066, 0.052)
            t.smoke = (0.36, 0.28, 0.22); t.glass = (0.25, 0.19, 0.15)
            t.brownGround = true; t.richBrown = true
        }
        if self == .midnight {
            t = Tones(accent: (0.71, 0.69, 0.94), accentOnPaper: (0.27, 0.25, 0.55), onAccent: (0.07, 0.08, 0.18),
                      brand: (0.25, 0.29, 0.48),
                      light: (0.62, 0.64, 0.82), lightOnPaper: (0.28, 0.30, 0.50),
                      pale: (0.84, 0.84, 0.93), paleOnPaper: (0.20, 0.22, 0.40),
                      deep: (0.10, 0.13, 0.27), deeper: (0.07, 0.09, 0.20), deepest: (0.05, 0.06, 0.14),
                      cream: (0.78, 0.79, 0.90), creamOnPaper: (0.94, 0.94, 0.98), muted: (0.36, 0.38, 0.52),
                      smoke: (0.06, 0.08, 0.18), glass: (0.04, 0.05, 0.13), freshInk: (0.08, 0.09, 0.20),
                      paper: (0.955, 0.955, 0.975), night: (0.03, 0.04, 0.09), avatar: "FennAvatar")
        }
        if self == .cobalt {
            t = Tones(accent: (0.36, 0.50, 1.0), accentOnPaper: (0.15, 0.30, 0.85), onAccent: (1, 1, 1),
                      brand: (0.33, 0.37, 0.44),
                      light: (0.70, 0.73, 0.78), lightOnPaper: (0.28, 0.31, 0.38),
                      pale: (0.88, 0.89, 0.91), paleOnPaper: (0.20, 0.22, 0.28),
                      deep: (0.13, 0.15, 0.20), deeper: (0.09, 0.10, 0.13), deepest: (0.06, 0.065, 0.08),
                      cream: (0.82, 0.84, 0.87), creamOnPaper: (0.96, 0.965, 0.97), muted: (0.38, 0.40, 0.45),
                      smoke: (0.10, 0.11, 0.13), glass: (0.07, 0.075, 0.09), freshInk: (0.08, 0.09, 0.12),
                      paper: (0.955, 0.958, 0.962), night: (0.035, 0.037, 0.042), avatar: "FennAvatar")
        }
        if self == .clean {
            // Nothing but white, greys and black: no photo, no clay, the accent is ink.
            t = Tones(accent: (0.96, 0.96, 0.965), accentOnPaper: (0.09, 0.09, 0.10), onAccent: (0.06, 0.06, 0.07),
                      brand: (0.45, 0.46, 0.48),
                      light: (0.72, 0.73, 0.75), lightOnPaper: (0.35, 0.36, 0.38),
                      pale: (0.88, 0.88, 0.89), paleOnPaper: (0.25, 0.25, 0.27),
                      deep: (0.14, 0.14, 0.15), deeper: (0.10, 0.10, 0.11), deepest: (0.07, 0.07, 0.08),
                      cream: (0.85, 0.85, 0.86), creamOnPaper: (0.965, 0.965, 0.97), muted: (0.42, 0.42, 0.45),
                      smoke: (0.11, 0.11, 0.12), glass: (0.08, 0.08, 0.09), freshInk: (0.09, 0.09, 0.10),
                      paper: (0.985, 0.985, 0.985), night: (0.035, 0.035, 0.04), avatar: "FennAvatarStone")
            t.accentPills = true; t.avatarCutout = true; t.plainIcons = true
        }
        if self == .autumn {
            // Rust leaves and warm wood: amber-rust accent, chestnut glows, cream paper, a dark forest-floor brown.
            t = Tones(accent: (0.88, 0.53, 0.30), accentOnPaper: (0.62, 0.27, 0.12), onAccent: (0.14, 0.06, 0.03),
                      brand: (0.45, 0.25, 0.15),
                      light: (0.85, 0.66, 0.50), lightOnPaper: (0.48, 0.27, 0.15),
                      pale: (0.93, 0.85, 0.77), paleOnPaper: (0.36, 0.20, 0.12),
                      deep: (0.24, 0.12, 0.07), deeper: (0.17, 0.09, 0.05), deepest: (0.12, 0.06, 0.04),
                      cream: (0.88, 0.78, 0.68), creamOnPaper: (0.96, 0.92, 0.86), muted: (0.48, 0.36, 0.28),
                      smoke: (0.26, 0.15, 0.10), glass: (0.19, 0.11, 0.07), freshInk: (0.16, 0.09, 0.06),
                      paper: (0.965, 0.935, 0.89), night: (0.09, 0.05, 0.035), avatar: "FennAvatarStone")
            t.glassOnPaper = (0.97, 0.92, 0.86); t.accentPills = true; t.avatarCutout = true; t.iconSet = "autumn"
        }
        if self == .christmas {
            // Fir and cranberry: deep fir-green ground and glass, a warm red for everything you act on, snow paper.
            t = Tones(accent: (0.88, 0.30, 0.30), accentOnPaper: (0.66, 0.10, 0.14), onAccent: (1, 1, 1),
                      brand: (0.12, 0.33, 0.25),
                      light: (0.62, 0.78, 0.68), lightOnPaper: (0.12, 0.34, 0.25),
                      pale: (0.86, 0.92, 0.88), paleOnPaper: (0.10, 0.26, 0.19),
                      deep: (0.06, 0.20, 0.15), deeper: (0.04, 0.14, 0.10), deepest: (0.03, 0.10, 0.07),
                      cream: (0.80, 0.88, 0.83), creamOnPaper: (0.95, 0.96, 0.95), muted: (0.30, 0.42, 0.36),
                      smoke: (0.07, 0.20, 0.15), glass: (0.05, 0.14, 0.11), freshInk: (0.05, 0.14, 0.10),
                      paper: (0.975, 0.97, 0.96), night: (0.025, 0.08, 0.06), avatar: "FennAvatarStone")
            t.accentPills = true; t.avatarCutout = true; t.iconSet = "christmas"
        }
        if self == .spring {
            // Fresh leaves and blossom: a young green accent, soft lilac glows, light paper.
            t = Tones(accent: (0.60, 0.84, 0.52), accentOnPaper: (0.24, 0.50, 0.22), onAccent: (0.06, 0.16, 0.05),
                      brand: (0.58, 0.50, 0.70),
                      light: (0.80, 0.74, 0.88), lightOnPaper: (0.42, 0.32, 0.55),
                      pale: (0.93, 0.90, 0.96), paleOnPaper: (0.32, 0.25, 0.42),
                      deep: (0.20, 0.24, 0.20), deeper: (0.13, 0.17, 0.13), deepest: (0.09, 0.12, 0.09),
                      cream: (0.86, 0.92, 0.84), creamOnPaper: (0.96, 0.97, 0.94), muted: (0.40, 0.46, 0.40),
                      smoke: (0.16, 0.22, 0.16), glass: (0.11, 0.16, 0.11), freshInk: (0.10, 0.14, 0.10),
                      paper: (0.975, 0.98, 0.965), night: (0.06, 0.09, 0.06), avatar: "FennAvatarStone")
            t.accentPills = true; t.avatarCutout = true; t.iconSet = "spring"
        }
        if self == .summer {
            // Sea and sand: turquoise accent, ocean glows, sand-coloured paper, a deep sea-blue night.
            t = Tones(accent: (0.36, 0.80, 0.86), accentOnPaper: (0.05, 0.47, 0.58), onAccent: (0.02, 0.14, 0.18),
                      brand: (0.16, 0.45, 0.55),
                      light: (0.62, 0.84, 0.88), lightOnPaper: (0.08, 0.40, 0.48),
                      pale: (0.86, 0.94, 0.95), paleOnPaper: (0.06, 0.30, 0.36),
                      deep: (0.04, 0.22, 0.30), deeper: (0.03, 0.15, 0.22), deepest: (0.02, 0.10, 0.16),
                      cream: (0.80, 0.90, 0.92), creamOnPaper: (0.97, 0.95, 0.90), muted: (0.30, 0.45, 0.50),
                      smoke: (0.05, 0.20, 0.27), glass: (0.03, 0.14, 0.20), freshInk: (0.04, 0.14, 0.19),
                      paper: (0.975, 0.96, 0.925), night: (0.02, 0.07, 0.10), avatar: "FennAvatarStone")
            t.glassOnPaper = (1, 0.99, 0.96); t.accentPills = true; t.avatarCutout = true; t.iconSet = "summer"
        }
        if self == .petrolChalk {
            t.accent = (0.925, 0.91, 0.87); t.accentOnPaper = (0.055, 0.259, 0.263); t.onAccent = (0.04, 0.16, 0.17)
        }
        return t
    }
}

extension Color {
    init(_ rgb: (Double, Double, Double)) { self.init(red: rgb.0, green: rgb.1, blue: rgb.2) }
}

/// Fenn palette. One petrol family (`ember` is #0e4243; `amber` and `peach`
/// keep their names) plus one contrast colour (`accent`, sage in Fenn Grün).
enum Fenn {
    private static let tones = FennScheme.current.tones
    static let accent = Color(light: Color(tones.accentOnPaper), dark: Color(tones.accent))
    static let onAccent = Color(light: Color(tones.onAccentOnPaper), dark: Color(tones.onAccent))
    static let brand = Color(tones.brand)
    static let amber = Color(light: Color(tones.lightOnPaper), dark: Color(tones.light))
    static let peach = Color(light: Color(tones.paleOnPaper), dark: Color(tones.pale))
    static let ember = Color(tones.deep)
    static let danger = Color(light: Color(red: 0.80, green: 0.18, blue: 0.16), dark: Color(red: 1.0, green: 0.42, blue: 0.42))
    static let fg = Color(light: Color(red: 0.11, green: 0.098, blue: 0.09), dark: Color(red: 0.957, green: 0.961, blue: 0.969))
    static let canvas = Color(light: Color(tones.paper), dark: Color(tones.night))
    static let selected = tones.accentPills ? accent : fg
    static let onSelected = tones.accentPills ? onAccent : canvas
    static let fill = Color(light: Color.black.opacity(0.05), dark: Color.white.opacity(0.07))
    static let fillStrong = Color(light: Color.black.opacity(0.09), dark: Color.white.opacity(0.14))
    static let hairline = Color(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.08))
    /// Inset input fields.
    static let field = Color(light: Color.white.opacity(0.85), dark: Color.black.opacity(0.35))
    static let scheme = FennScheme.current.tones

    /// Light, calm display type by default (SF Pro); heavy/black keep the wide race-bib look (Archivo Expanded if installed).
    static func display(_ size: CGFloat, weight: Font.Weight = .light) -> Font {
        guard weight == .heavy || weight == .black else { return .fenn(size: size, weight: weight) }
        if let archivo = archivoExpanded(size: size, weight: weight) {
            return Font(archivo)
        }
        return .fenn(size: size, weight: weight).width(.expanded)
    }

    private static func archivoExpanded(size: CGFloat, weight: Font.Weight) -> NSFont? {
        guard let base = NSFont(name: "Archivo-Regular", size: size) ?? NSFont(name: "Archivo", size: size) else {
            return nil
        }
        let wght: Double = weight == .black ? 900 : (weight == .heavy ? 800 : 700)
        // Variation axis tags: 'wght' and 'wdth'.
        let variation: [NSNumber: Double] = [NSNumber(value: 0x7767_6874): wght, NSNumber(value: 0x7764_7468): 125]
        let key = NSFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)
        return NSFont(descriptor: base.fontDescriptor.addingAttributes([key: variation]), size: size)
    }
}

/// The glowing ember orb — Fenn's presence in the island.
struct FennOrb: View {
    var size: CGFloat

    var body: some View {
        Circle()
            .fill(AngularGradient(
                colors: [Fenn.accent, Fenn.amber, Fenn.peach, Fenn.ember, Fenn.accent],
                center: .center,
                angle: .degrees(200)
            ))
            .overlay(
                Circle().fill(RadialGradient(
                    colors: [.white.opacity(0.55), .white.opacity(0)],
                    center: UnitPoint(x: 0.32, y: 0.28),
                    startRadius: 0,
                    endRadius: size * 0.36
                ))
            )
            .frame(width: size, height: size)
            .shadow(color: Fenn.accent.opacity(0.65), radius: size * 0.45)
            .accessibilityHidden(true)
    }
}

/// Fenn the pebble, the mascot – in the island instead of the orb.
struct PebbleMac: View {
    var size: CGFloat

    /// The picture every pebble view draws (sleeps with closed eyes; `PebbleFace` wakes it up).
    static let image = "RankTierHD0"

    var body: some View {
        Image(Self.image)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.35), radius: size * 0.12, y: size * 0.05)
            .accessibilityHidden(true)
    }
}

struct FennAvatar: View {
    var size: CGFloat

    var body: some View {
        if Fenn.scheme.avatarCutout {
            Image(Fenn.scheme.avatar)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.25), radius: size * 0.08, y: size * 0.05)
                .accessibilityLabel("Fenn")
        } else {
            Image(Fenn.scheme.avatar)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
                .accessibilityLabel("Fenn")
        }
    }
}

/// Real behind-window blur, so the desktop shows through the glass.
struct VisualEffectBackground: NSViewRepresentable {
    var light = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = light ? .popover : .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = light ? .popover : .hudWindow
    }
}

/// macOS 26 Liquid Glass behind the window: refracts the desktop, tinted smoky petrol so text stays readable.
@available(macOS 26.0, *)
struct LiquidGlassBackground: NSViewRepresentable {
    var cornerRadius: CGFloat
    var light = false

    private var tint: NSColor {
        let glass = Fenn.scheme.glass
        return light
            ? NSColor(red: Fenn.scheme.glassOnPaper.0, green: Fenn.scheme.glassOnPaper.1, blue: Fenn.scheme.glassOnPaper.2, alpha: 0.45)
            : NSColor(red: glass.0, green: glass.1, blue: glass.2, alpha: 0.55)
    }

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.style = .regular
        view.tintColor = tint
        view.cornerRadius = cornerRadius
        return view
    }

    func updateNSView(_ nsView: NSGlassEffectView, context: Context) {
        nsView.cornerRadius = cornerRadius
        nsView.tintColor = tint
    }
}

struct FennGlass: ViewModifier {
    var cornerRadius: CGFloat
    var shadow = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let light = scheme == .light
        if light && Fenn.scheme.solidWhite {
            // Fenn Weiß: the big panel is bright paper, everything on it a white card with a soft lift.
            let panel = cornerRadius >= 28
            content
                .background(shape.fill(panel ? Fenn.canvas : Color.white))
                .overlay(shape.strokeBorder(Color.black.opacity(panel ? 0.06 : 0.05), lineWidth: 1))
                .shadow(color: .black.opacity(panel ? (shadow ? 0.16 : 0) : 0.05), radius: panel ? 28 : 10, y: panel ? 18 : 3)
        } else {
        content
            .background {
                ZStack {
                    if reduceTransparency {
                        light ? Color(Fenn.scheme.glassOnPaper) : Color(Fenn.scheme.glass)
                    } else if #available(macOS 26.0, *) {
                        LiquidGlassBackground(cornerRadius: cornerRadius, light: light)
                        LinearGradient(
                            colors: light
                                ? [Color(Fenn.scheme.glassOnPaper).opacity(0.55), Color(Fenn.scheme.glassOnPaper).opacity(0.28)]
                                : [Color(Fenn.scheme.smoke).opacity(0.45), Color(Fenn.scheme.glass).opacity(0.62)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        RadialGradient(colors: [Fenn.brand.opacity(light ? 0.08 : 0.16), Fenn.brand.opacity(0)],
                                       center: .bottomLeading, startRadius: 0, endRadius: 360)
                    } else {
                        VisualEffectBackground(light: light)
                        LinearGradient(
                            colors: light
                                ? [Color(Fenn.scheme.glassOnPaper).opacity(0.62), Color(Fenn.scheme.glassOnPaper).opacity(0.38)]
                                : [Color(Fenn.scheme.smoke).opacity(0.55), Color(Fenn.scheme.glass).opacity(0.72)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        RadialGradient(colors: [Fenn.brand.opacity(light ? 0.08 : 0.18), Fenn.brand.opacity(0)],
                                       center: .bottomLeading, startRadius: 0, endRadius: 360)
                        LinearGradient(colors: [.white.opacity(light ? 0.4 : 0.13), .white.opacity(0)],
                                       startPoint: .topLeading, endPoint: UnitPoint(x: 0.55, y: 0.4))
                    }
                }
                .clipShape(shape)
            }
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: light
                                    ? [.white.opacity(0.9), .black.opacity(0.05), Fenn.brand.opacity(0.14)]
                                    : [.white.opacity(0.34), .white.opacity(0.04), Fenn.brand.opacity(0.22)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
            )
            .shadow(color: .black.opacity(shadow ? (light ? 0.15 : 0.45) : 0), radius: 24, y: 16)
        }
    }
}

extension View {
    func fennGlass(cornerRadius: CGFloat, shadow: Bool = true) -> some View {
        modifier(FennGlass(cornerRadius: cornerRadius, shadow: shadow))
    }
}

struct FennIconButtonStyle: ButtonStyle {
    var isActive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.fenn(size: 14, weight: .semibold))
            .foregroundStyle(isActive ? Fenn.fg : Fenn.fg.opacity(0.6))
            .frame(width: 36, height: 36)
            .modifier(IconSurface(isActive: isActive, isPressed: configuration.isPressed))
            .contentShape(Circle())
    }
}

/// Module switcher in the panel header: dark circles, the open module stretched into an accent capsule.
struct FennModuleButtonStyle: ButtonStyle {
    var isActive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.fenn(size: 14, weight: isActive ? .semibold : .regular))
            .foregroundStyle(isActive ? Fenn.onAccent : Fenn.fg.opacity(configuration.isPressed ? 0.9 : 0.65))
            .frame(width: isActive ? 50 : 34, height: 34)
            .background(Capsule().fill(isActive ? Fenn.accent : Fenn.fill))
            .shadow(color: isActive ? Fenn.ember.opacity(0.4) : .clear, radius: 6, y: 2)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.snappy(duration: 0.25), value: isActive)
            .contentShape(Capsule())
    }
}

/// The active icon sits on a small drop of Liquid Glass (macOS 26); inactive ones stay bare.
private struct IconSurface: ViewModifier {
    let isActive: Bool
    let isPressed: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if isActive, #available(macOS 26.0, *), !reduceTransparency {
            content.glassEffect(.regular.interactive(), in: Circle())
        } else {
            content.background(Circle().fill(isActive ? Fenn.fillStrong : (isPressed ? Fenn.fill : .clear)))
        }
    }
}

/// White pill for the one primary action (as in the 99 LAPS reference); translucent otherwise.
struct FennPillButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.fenn(size: 13, weight: prominent ? .semibold : .regular))
            .foregroundStyle(prominent ? (Fenn.scheme.accentPills ? Fenn.onAccent : Fenn.canvas) : Fenn.fg)
            .padding(.horizontal, 16)
            .frame(height: 34)
            .modifier(PillSurface(prominent: prominent))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// Accent capsule for the primary action in Fenn Grün; interactive Liquid Glass for the rest (macOS 26).
private struct PillSurface: ViewModifier {
    let prominent: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if prominent {
            content
                .background(Capsule().fill(Fenn.scheme.accentPills ? Fenn.accent : Fenn.fg))
                .shadow(color: Fenn.accent.opacity(0.28), radius: 10, y: 3)
        } else if #available(macOS 26.0, *), !reduceTransparency {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content.background(Capsule().fill(Fenn.fillStrong))
        }
    }
}
