import SwiftUI

// Fenn's visual language:
// dot-matrix numerals, soft mesh-gradient "aura" cards, fine tick rulers – calm, light, a little futuristic.

// MARK: - Light & dark

extension Color {
    /// One token, two looks: resolved per appearance.
    init(light: Color, dark: Color) {
        #if os(macOS)
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
        })
        #else
        self.init(uiColor: UIColor { traits in traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
        #endif
    }
}

/// System, light or dark – stored in "fenn.appearance".
enum FennAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    static let key = "fenn.appearance"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return tr("System", "System")
        case .light: return tr("Hell", "Light")
        case .dark: return tr("Dunkel", "Dark")
        }
    }
    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    static var current: FennAppearance {
        FennAppearance(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .system
    }
}

/// The typeface the person picks. Named faces (Futura, Avenir, Gill) apply after a restart; system designs switch live.
enum FennFontChoice: String, CaseIterable, Identifiable {
    case standard, rounded, serif, mono, futura, avenir, gillSans

    static let key = "fenn.font"
    static let current = FennFontChoice(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .standard
    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return tr("Standard", "Standard")
        case .rounded: return tr("Rund", "Rounded")
        case .serif: return tr("Serif", "Serif")
        case .mono: return tr("Mono", "Mono")
        case .futura: return "Futura"
        case .avenir: return "Avenir Next"
        case .gillSans: return "Gill Sans"
        }
    }

    var needsRestart: Bool { face(.regular) != nil }

    var design: Font.Design {
        switch self {
        case .rounded: return .rounded
        case .serif: return .serif
        case .mono: return .monospaced
        default: return .default
        }
    }

    func face(_ weight: Font.Weight) -> String? {
        let bold = weight == .bold || weight == .heavy || weight == .black
        let semi = weight == .semibold
        let light = weight == .light || weight == .thin || weight == .ultraLight
        switch self {
        case .futura: return bold || semi ? "Futura-Bold" : "Futura-Medium"
        case .avenir:
            return weight == .black || weight == .heavy ? "AvenirNext-Heavy" : bold ? "AvenirNext-Bold" : semi ? "AvenirNext-DemiBold"
                : weight == .medium ? "AvenirNext-Medium" : light ? "AvenirNext-UltraLight" : "AvenirNext-Regular"
        case .gillSans: return bold ? "GillSans-Bold" : semi ? "GillSans-SemiBold" : light ? "GillSans-Light" : "GillSans"
        default: return nil
        }
    }
}

private struct FennSchemeModifier: ViewModifier {
    @AppStorage(FennAppearance.key) private var appearance = FennAppearance.system.rawValue
    @AppStorage(FennFontChoice.key) private var font = FennFontChoice.standard.rawValue
    func body(content: Content) -> some View {
        content
            .preferredColorScheme(FennAppearance(rawValue: appearance)?.scheme)
            .fontDesign(Self.design(font))
    }

    private static func design(_ raw: String) -> Font.Design? {
        let choice = FennFontChoice(rawValue: raw) ?? .standard
        return FennFontChoice.current.needsRestart || choice.design == .default ? nil : choice.design
    }
}

extension View {
    /// Applies the appearance and the typeface the person picked.
    func fennScheme() -> some View { modifier(FennSchemeModifier()) }
}

// MARK: - Dot-matrix numerals

/// Numbers drawn as a 5×7 LED dot matrix – the signature for key figures (focus time, counts, clocks).
/// Digits, "." "," ":" "-" "+" "%" "/" and spaces; anything else is skipped.
struct DotMatrixText: View {
    let text: String
    /// Height of one line of dots.
    var height: CGFloat = 28
    var color: Color = Fenn.fg
    var glow = true
    @Environment(\.colorScheme) private var scheme

    private static let glyphs: [Character: [String]] = [
        "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
        "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
        "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
        "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
        "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
        "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
        "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
        "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
        "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
        "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
        ".": ["0", "0", "0", "0", "0", "0", "1"],
        ",": ["0", "0", "0", "0", "0", "1", "1"],
        ":": ["0", "1", "0", "0", "0", "1", "0"],
        "-": ["000", "000", "000", "111", "000", "000", "000"],
        "–": ["000", "000", "000", "111", "000", "000", "000"],
        "+": ["00000", "00100", "00100", "11111", "00100", "00100", "00000"],
        "%": ["11001", "11010", "00010", "00100", "01000", "01011", "10011"],
        "/": ["00001", "00010", "00010", "00100", "01000", "01000", "10000"],
        " ": ["00", "00", "00", "00", "00", "00", "00"]
    ]

    private var columns: [[String]] { text.compactMap { Self.glyphs[$0] } }
    private var pitch: CGFloat { height / 7 }
    private var width: CGFloat {
        let cols = columns.reduce(0) { $0 + ($1.first?.count ?? 0) } + max(0, columns.count - 1)
        return CGFloat(cols) * pitch
    }

    var body: some View {
        Canvas { g, _ in
            let r = pitch * 0.36
            var x: CGFloat = 0
            for glyph in columns {
                for (row, line) in glyph.enumerated() {
                    for (col, bit) in line.enumerated() where bit == "1" {
                        let cx = x + CGFloat(col) * pitch + pitch / 2, cy = CGFloat(row) * pitch + pitch / 2
                        g.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)), with: .color(color))
                    }
                }
                x += CGFloat((glyph.first?.count ?? 0) + 1) * pitch
            }
        }
        .frame(width: width, height: height)
        .shadow(color: glow ? color.opacity(scheme == .dark ? 0.55 : 0.18) : .clear, radius: glow ? pitch * 0.9 : 0)
        .accessibilityElement()
        .accessibilityLabel(text)
    }
}

/// Dot-matrix value with a small unit in light type, e.g. "16.2 mg".
struct MetricValue: View {
    let value: String
    var unit: String? = nil
    var height: CGFloat = 26
    var color: Color = Fenn.fg

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 5) {
            DotMatrixText(text: value, height: height, color: color)
            if let unit {
                Text(unit).font(.fenn(size: max(10, height * 0.38), weight: .light)).foregroundStyle(color.opacity(0.65))
            }
        }
    }
}

// MARK: - Mesh aura

/// The soft multi-colour glow behind aura cards; drifts slowly (paused with Reduce Motion).
struct MeshAura: View {
    /// One petrol family (deep → mid → pale) plus stone neutrals – state shows in intensity, not in hue.
    enum Palette {
        case fresh, steady, tired, level, stone, ember

        var colors: [Color] {
            let tones = Fenn.scheme
            guard tones.stoneAuras else { return petrolColors }
            guard tones.petrolAurasInDark else { return stoneColors }
            return zip(stoneColors, petrolColors).map { Color(light: $0, dark: $1) }
        }

        private var petrolColors: [Color] {
            let ember = Fenn.ember, accent = Fenn.brand
            let tones = Fenn.scheme
            let amber = Color(tones.light), peach = Color(tones.pale)
            let cream = Color(light: Color(tones.creamOnPaper), dark: Color(tones.cream))
            let stoneDark = Color(light: Color(red: 0.80, green: 0.76, blue: 0.73), dark: Color(red: 0.20, green: 0.18, blue: 0.17))
            let stoneMid = Color(light: Color(red: 0.89, green: 0.86, blue: 0.83), dark: Color(red: 0.33, green: 0.29, blue: 0.27))
            let stoneLight = Color(light: Color(red: 0.96, green: 0.94, blue: 0.92), dark: Color(red: 0.46, green: 0.40, blue: 0.37))
            switch self {
            case .fresh: return [cream, peach, amber, accent]
            case .steady: return [peach, amber, accent, ember]
            case .tired: return [stoneLight, stoneMid, stoneDark, Color(tones.muted)]
            case .level: return [amber, accent, ember, Color(tones.deepest)]
            case .stone: return [peach.opacity(0.9), stoneLight, stoneMid, stoneDark]
            case .ember: return [amber, accent, ember, Color(tones.deeper)]
            }
        }

        private var stoneColors: [Color] {
            let tones = Fenn.scheme
            let rich = tones.richBrown
            let stoneDark = Color(light: Color(red: 0.76, green: 0.70, blue: 0.65), dark: rich ? Color(red: 0.29, green: 0.22, blue: 0.17) : Color(red: 0.30, green: 0.26, blue: 0.23))
            let stoneMid = Color(light: Color(red: 0.86, green: 0.81, blue: 0.76), dark: rich ? Color(red: 0.44, green: 0.34, blue: 0.26) : Color(red: 0.42, green: 0.37, blue: 0.32))
            let stoneLight = Color(light: Color(red: 0.94, green: 0.91, blue: 0.87), dark: rich ? Color(red: 0.58, green: 0.46, blue: 0.36) : Color(red: 0.55, green: 0.48, blue: 0.42))
            let sage = Color(light: Color(red: 0.86, green: 0.82, blue: 0.75), dark: Color(red: 0.31, green: 0.37, blue: 0.35))
            switch self {
            case .fresh: return [stoneLight, stoneMid, stoneLight, sage]
            case .steady: return [stoneMid, stoneLight, stoneMid, sage]
            case .tired, .stone: return [Color(light: Color(red: 0.90, green: 0.86, blue: 0.80), dark: Color(tones.pale)).opacity(0.9), stoneLight, stoneMid, stoneDark]
            case .level, .ember: return [stoneMid, stoneDark, Color(light: Color(red: 0.62, green: 0.58, blue: 0.55), dark: Color(red: 0.16, green: 0.15, blue: 0.14)), Fenn.brand]
            }
        }

        var ink: Color {
            let tones = Fenn.scheme
            guard tones.stoneAuras else { return petrolInk }
            guard tones.petrolAurasInDark else { return stoneInk }
            return Color(light: stoneInk, dark: petrolInk)
        }

        private var petrolInk: Color {
            switch self {
            case .fresh: return Color(Fenn.scheme.freshInk)
            case .tired, .stone: return Color(light: Color(red: 0.16, green: 0.13, blue: 0.12), dark: .white)
            case .steady, .level, .ember: return .white
            }
        }

        private var stoneInk: Color {
            switch self {
            case .level, .ember: return .white
            default: return Color(light: Color(red: 0.16, green: 0.13, blue: 0.12), dark: .white)
            }
        }
    }

    var palette: Palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let c = palette.colors
        TimelineView(.animation(minimumInterval: 1.0 / 12, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
            if #available(iOS 18.0, macOS 15.0, *) {
                let d = Float(sin(t * 0.35)) * 0.12, e = Float(cos(t * 0.27)) * 0.12
                MeshGradient(width: 3, height: 3, points: [
                    [0, 0], [0.5 + d, 0], [1, 0],
                    [0, 0.5 - e], [0.5 + e, 0.5 + d], [1, 0.5 + e],
                    [0, 1], [0.5 - d, 1], [1, 1]
                ], colors: [c[0], c[1], c[2], c[1], c[2], c[3], c[2], c[3], c[0]])
            } else {
                ZStack {
                    c[0]
                    RadialGradient(colors: [c[1], .clear], center: UnitPoint(x: 0.3 + 0.1 * sin(t * 0.3), y: 0.3), startRadius: 0, endRadius: 180)
                    RadialGradient(colors: [c[2], .clear], center: UnitPoint(x: 0.8, y: 0.7 + 0.1 * cos(t * 0.25)), startRadius: 0, endRadius: 200)
                    RadialGradient(colors: [c[3].opacity(0.8), .clear], center: .bottomLeading, startRadius: 0, endRadius: 160)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A glass card on a mesh aura: small light label, a dot-matrix hero value, caption and optional tick ruler.
struct AuraCard<Footer: View>: View {
    let title: String
    let value: String
    var unit: String? = nil
    var caption: String? = nil
    var palette: MeshAura.Palette
    var valueHeight: CGFloat = 34
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        VStack(spacing: 8) {
            Text(title).font(.fenn(size: 12, weight: .regular)).foregroundStyle(palette.ink.opacity(0.85))
            Spacer(minLength: 2)
            MetricValue(value: value, unit: unit, height: valueHeight, color: palette.ink)
            if let caption {
                Text(caption).font(.fenn(size: 11, weight: .light)).foregroundStyle(palette.ink.opacity(0.8)).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 2)
            footer().environment(\.auraInk, palette.ink)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 170)
        .background {
            ZStack {
                MeshAura(palette: palette)
                // Frosted veil + grain-like dot texture, like light through glass.
                LinearGradient(colors: [.white.opacity(0.18), .clear, .black.opacity(0.18)], startPoint: .top, endPoint: .bottom)
                Canvas { g, size in
                    var y: CGFloat = 3
                    while y < size.height {
                        var x: CGFloat = 3
                        while x < size.width {
                            g.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 0.9, height: 0.9)), with: .color(.white.opacity(0.10)))
                            x += 5
                        }
                        y += 5
                    }
                }
            }
            .clipShape(shape)
        }
        .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
        .shadow(color: palette.colors[1].opacity(0.35), radius: 18, y: 8)
    }
}

extension AuraCard where Footer == EmptyView {
    init(title: String, value: String, unit: String? = nil, caption: String? = nil, palette: MeshAura.Palette, valueHeight: CGFloat = 34) {
        self.init(title: title, value: value, unit: unit, caption: caption, palette: palette, valueHeight: valueHeight) { EmptyView() }
    }
}

// MARK: - Tick ruler

private struct AuraInkKey: EnvironmentKey { static let defaultValue: Color? = nil }

extension EnvironmentValues {
    /// Set by aura cards so rulers inside them match the card's text colour.
    var auraInk: Color? {
        get { self[AuraInkKey.self] }
        set { self[AuraInkKey.self] = newValue }
    }
}

/// Fine vertical ticks as a scale: filled up to `value`, one tall marker at the current point.
struct TickRuler: View {
    var value: Double
    var ticks = 32
    var color: Color? = nil
    var height: CGFloat = 16
    @Environment(\.auraInk) private var auraInk

    var body: some View {
        let color = self.color ?? auraInk ?? Fenn.fg
        Canvas { g, size in
            let step = size.width / CGFloat(max(1, ticks - 1))
            let marker = Int((min(1, max(0, value)) * Double(ticks - 1)).rounded())
            for i in 0..<ticks {
                let x = CGFloat(i) * step
                let isMarker = i == marker
                let h = isMarker ? size.height : (i % 4 == 0 ? size.height * 0.55 : size.height * 0.35)
                let rect = CGRect(x: x - (isMarker ? 1 : 0.5), y: (size.height - h) / 2, width: isMarker ? 2 : 1, height: h)
                g.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color.opacity(isMarker ? 1 : (i <= marker ? 0.75 : 0.22))))
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue("\(Int(value * 100)) %")
    }
}

/// Capsule version of the aura card for compact metrics (like "Water 76 oz"): small centred label,
/// dot-matrix value on the left, an optional change badge on the right, glass rim.
struct AuraPill: View {
    let title: String
    let value: String
    var unit: String? = nil
    var palette: MeshAura.Palette
    var symbol: String? = nil
    /// "4 %" – shown as a small outlined badge; `up` adds the arrow.
    var delta: String? = nil
    var up: Bool? = nil

    var body: some View {
        let shape = Capsule(style: .continuous)
        VStack(spacing: 8) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.fenn(size: 10, weight: .regular)) }
                Text(title).font(.fenn(size: 11, weight: .regular)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(palette.ink.opacity(0.85))
            HStack(alignment: .center, spacing: 6) {
                MetricValue(value: value, unit: unit, height: 20, color: palette.ink)
                    .layoutPriority(1)
                if let delta {
                    Spacer(minLength: 0)
                    DeltaBadge(text: delta, up: up, color: palette.ink)
                }
            }
            .frame(maxWidth: .infinity, alignment: delta == nil ? .center : .leading)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, minHeight: 84)
        .background {
            ZStack {
                MeshAura(palette: palette)
                LinearGradient(colors: [.white.opacity(0.24), .clear, .black.opacity(0.18)], startPoint: .top, endPoint: .bottom)
                // A faint orbit line across the capsule, like light caught in thick glass.
                Ellipse().stroke(palette.ink.opacity(0.14), lineWidth: 0.8)
                    .frame(width: 150, height: 90).offset(x: 46, y: 34)
            }
            .clipShape(shape)
        }
        .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.65), .white.opacity(0.06), .white.opacity(0.25)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
        .shadow(color: palette.colors[1].opacity(0.3), radius: 14, y: 6)
        .accessibilityElement(children: .combine)
    }
}

/// "↑ 4 %" in a thin outlined capsule – change against the previous period.
struct DeltaBadge: View {
    let text: String
    var up: Bool? = nil
    var color: Color? = nil
    @Environment(\.auraInk) private var auraInk

    var body: some View {
        let color = self.color ?? auraInk ?? Fenn.fg
        HStack(spacing: 2) {
            if let up { Image(systemName: up ? "arrow.up" : "arrow.down").font(.fenn(size: 8, weight: .semibold)) }
            Text(text).font(.fenn(size: 10, weight: .medium)).monospacedDigit().lineLimit(1)
        }
        .foregroundStyle(color.opacity(0.9))
        .padding(.horizontal, 7)
        .frame(height: 18)
        .overlay(Capsule().strokeBorder(color.opacity(0.45), lineWidth: 0.8))
        .fixedSize()
    }
}

// MARK: - Weekly curve (frosted panel, soft line, weekday chips)

/// Seven round day chips; the chosen one is filled.
struct WeekdayChips: View {
    let labels: [String]
    @Binding var selected: Int
    var ink: Color = .white
    /// Days after this one are still to come: dimmed, not selectable.
    var lastIndex = Int.max

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                let isOn = index == selected
                Button { withAnimation(.snappy(duration: 0.3)) { selected = index } } label: {
                    Text(label)
                        .font(.fenn(size: 10, weight: .medium))
                        .foregroundStyle(isOn ? Color.black.opacity(0.85) : ink.opacity(index > lastIndex ? 0.25 : 0.55))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(isOn ? ink : .clear))
                        .overlay(Circle().strokeBorder(ink.opacity(isOn ? 0 : 0.22), lineWidth: 0.8))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(index > lastIndex)
                .accessibilityAddTraits(isOn ? .isSelected : [])
                if index < labels.count - 1 { Spacer(minLength: 2) }
            }
        }
    }
}

/// A smooth line through the values, a dotted average and a glass knob on the chosen point.
struct AuraCurve: View {
    /// The values drawn so far; `slots` spreads them over the full width (7 for a week that is still running).
    let values: [Double]
    var selected: Int
    var ink: Color = .white
    var slots: Int? = nil

    var body: some View {
        GeometryReader { proxy in
            let points = Self.points(values, in: proxy.size, slots: slots ?? values.count)
            ZStack(alignment: .topLeading) {
                Canvas { g, size in
                    guard points.count > 1 else { return }
                    // Dotted mid line – the average.
                    var average = Path()
                    let mean = Self.points([values.reduce(0, +) / Double(values.count)], in: size, range: Self.range(values), slots: 1).first?.y ?? size.height / 2
                    average.move(to: CGPoint(x: 0, y: mean))
                    average.addLine(to: CGPoint(x: size.width, y: mean))
                    g.stroke(average, with: .color(ink.opacity(0.22)), style: StrokeStyle(lineWidth: 0.8, dash: [1.5, 3]))
                    g.stroke(Self.smooth(points), with: .color(ink.opacity(0.9)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                }
                if points.indices.contains(selected) {
                    let point = points[selected]
                    Path { path in
                        path.move(to: CGPoint(x: point.x, y: point.y))
                        path.addLine(to: CGPoint(x: point.x, y: proxy.size.height))
                    }
                    .stroke(ink.opacity(0.35), style: StrokeStyle(lineWidth: 0.8, dash: [1.5, 3]))
                    Circle()
                        .fill(ink.opacity(0.16))
                        .overlay(Circle().strokeBorder(ink.opacity(0.55), lineWidth: 0.8))
                        .overlay(Circle().fill(ink).frame(width: 5, height: 5))
                        .frame(width: 22, height: 22)
                        .position(point)
                }
            }
            .animation(.snappy(duration: 0.35), value: selected)
        }
        .accessibilityHidden(true)
    }

    private static func range(_ values: [Double]) -> ClosedRange<Double> {
        let low = values.min() ?? 0, high = values.max() ?? 1
        return high - low < 0.0001 ? (low - 1)...(high + 1) : low...high
    }

    private static func points(_ values: [Double], in size: CGSize, range: ClosedRange<Double>? = nil, slots: Int) -> [CGPoint] {
        let range = range ?? Self.range(values)
        let inset: CGFloat = 14, top: CGFloat = 16, bottom: CGFloat = 10
        let span = range.upperBound - range.lowerBound
        let step = slots > 1 ? (size.width - 2 * inset) / CGFloat(slots - 1) : 0
        return values.enumerated().map { index, value in
            let t = CGFloat((value - range.lowerBound) / span)
            return CGPoint(x: slots > 1 ? inset + CGFloat(index) * step : size.width / 2,
                           y: top + (1 - t) * (size.height - top - bottom))
        }
    }

    /// Catmull-Rom through every point, drawn as cubic curves.
    private static func smooth(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for i in 0..<(points.count - 1) {
            let p0 = points[max(0, i - 1)], p1 = points[i], p2 = points[i + 1], p3 = points[min(points.count - 1, i + 2)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }
}

/// The week in one frosted panel: title and value, the curve with a knob, weekday chips and "‹ week ›".
/// Always dark smoked glass with a warm aura in the corners, so it reads the same in light and dark.
struct AuraWeekCard: View {
    let title: String
    let values: [Double]
    let dayLabels: [String]
    /// Formatted value of one day, e.g. "8.412".
    let valueText: (Int) -> String
    var unit: String? = nil
    let weekTitle: String
    /// Last day with data so far (today in the running week); later days stay empty.
    var lastIndex: Int
    var canGoBack = true
    var canGoForward = false
    var back: () -> Void = {}
    var forward: () -> Void = {}
    var open: (() -> Void)? = nil
    @State private var selected: Int

    init(title: String, values: [Double], dayLabels: [String], valueText: @escaping (Int) -> String, unit: String? = nil,
         weekTitle: String, selected: Int, lastIndex: Int? = nil, canGoBack: Bool = true, canGoForward: Bool = false,
         back: @escaping () -> Void = {}, forward: @escaping () -> Void = {}, open: (() -> Void)? = nil) {
        self.title = title; self.values = values; self.dayLabels = dayLabels; self.valueText = valueText; self.unit = unit
        self.weekTitle = weekTitle; self.lastIndex = lastIndex ?? values.count - 1; self.canGoBack = canGoBack; self.canGoForward = canGoForward
        self.back = back; self.forward = forward; self.open = open
        _selected = State(initialValue: selected)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 34, style: .continuous)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.fenn(size: 14, weight: .regular)).foregroundStyle(.white.opacity(0.9))
                    MetricValue(value: valueText(min(selected, max(0, values.count - 1))), unit: unit, height: 20, color: .white)
                }
                Spacer()
                if let open {
                    Button(action: open) {
                        Image(systemName: "arrow.up.right").font(.fenn(size: 12, weight: .regular))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 38, height: 38)
                            .overlay(Circle().strokeBorder(.white.opacity(0.28), lineWidth: 0.8))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tr("Öffnen", "Open"))
                }
            }
            AuraCurve(values: Array(values.prefix(lastIndex + 1)), selected: selected, slots: values.count).frame(height: 96)
            WeekdayChips(labels: dayLabels, selected: $selected, lastIndex: lastIndex)
            HStack(spacing: 14) {
                Spacer()
                Button(action: back) { Image(systemName: "chevron.left").frame(width: 28, height: 24).contentShape(Rectangle()) }
                    .disabled(!canGoBack)
                    .accessibilityLabel(tr("Woche davor", "Previous week"))
                Text(weekTitle).font(.fenn(size: 11, weight: .regular)).monospacedDigit()
                Button(action: forward) { Image(systemName: "chevron.right").frame(width: 28, height: 24).contentShape(Rectangle()) }
                    .disabled(!canGoForward)
                    .accessibilityLabel(tr("Woche danach", "Next week"))
                Spacer()
            }
            .buttonStyle(.plain)
            .font(.fenn(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.7))
        }
        .padding(18)
        .background {
            ZStack {
                Color(red: 0.07, green: 0.05, blue: 0.05)
                MeshAura(palette: .level).opacity(0.55).blur(radius: 30)
                LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.55), .black.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                FennGrain(opacity: 0.07)
            }
            .clipShape(shape)
        }
        .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.05), .white.opacity(0.14)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
        .shadow(color: Fenn.ember.opacity(0.25), radius: 24, y: 12)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Segmented capsule & grain

/// A calm capsule switch (7 / 30 / 90 days …): the chosen option is a filled pill that slides over.
struct FennSegmented<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    @Namespace private var space

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let isOn = option.value == selection
                Button { withAnimation(.snappy(duration: 0.3)) { selection = option.value } } label: {
                    Text(option.title)
                        .font(.fenn(size: 13, weight: .medium))
                        .foregroundStyle(isOn ? Fenn.canvas : Fenn.fg.opacity(0.6))
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background {
                            if isOn { Capsule().fill(Fenn.fg).matchedGeometryEffect(id: "pill", in: space) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Fenn.fill))
        .overlay(Capsule().strokeBorder(Fenn.hairline, lineWidth: 1))
    }
}

/// Still film grain – scattered light specks, drawn once and cached; nothing moves.
struct FennGrain: View {
    var opacity: Double = 0.05

    var body: some View {
        Canvas { g, size in
            var seed: UInt64 = 0x2545F4914F6CDD1D
            func next() -> CGFloat {
                seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
                return CGFloat(seed % 10_000) / 10_000
            }
            let count = Int(size.width * size.height / 42)
            for _ in 0..<count {
                let x = next() * size.width, y = next() * size.height, a = next()
                g.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)), with: .color(.white.opacity(opacity * (0.4 + a))))
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Rows

/// The glass row used on Today (calendar, block, …): accent icon, light title, thin subtitle, chevron.
struct FennRow<Leading: View>: View {
    let title: String
    var subtitle: String? = nil
    var showsChevron = true
    @ViewBuilder var leading: () -> Leading

    var body: some View {
        HStack(spacing: 14) {
            leading().frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.fenn(size: 16, weight: .regular)).foregroundStyle(Fenn.fg)
                if let subtitle {
                    Text(subtitle).font(.fenn(size: 12, weight: .light)).foregroundStyle(Fenn.fg.opacity(0.6)).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.right").font(.fenn(size: 13, weight: .regular)).foregroundStyle(Fenn.fg.opacity(0.4))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fennGlass(cornerRadius: 20)
    }
}

extension FennRow where Leading == AnyView {
    init(title: String, subtitle: String? = nil, symbol: String, showsChevron: Bool = true) {
        self.init(title: title, subtitle: subtitle, showsChevron: showsChevron) {
            AnyView(ClaySymbol(symbol: symbol, size: 28))
        }
    }
}

// MARK: - Timer

/// A big countdown on an aura disc with a tick ring – focus and break timers.
struct AuraTimer: View {
    let text: String
    /// 0…1 of the phase that has passed.
    var progress: Double
    var caption: String? = nil
    var palette: MeshAura.Palette = .steady
    var size: CGFloat = 220

    var body: some View {
        ZStack {
            MeshAura(palette: palette).clipShape(Circle())
            Circle().fill(LinearGradient(colors: [.white.opacity(0.18), .clear, .black.opacity(0.15)], startPoint: .top, endPoint: .bottom))
            Canvas { g, canvas in
                let c = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
                let r = min(canvas.width, canvas.height) / 2 - 10
                let ticks = 60
                for i in 0..<ticks {
                    let a = Double(i) / Double(ticks) * 2 * .pi - .pi / 2
                    let done = Double(i) / Double(ticks) < progress
                    let len: CGFloat = i % 5 == 0 ? 9 : 5
                    var path = Path()
                    path.move(to: CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r))
                    path.addLine(to: CGPoint(x: c.x + cos(a) * (r - len), y: c.y + sin(a) * (r - len)))
                    g.stroke(path, with: .color(palette.ink.opacity(done ? 0.95 : 0.3)), lineWidth: i % 5 == 0 ? 1.6 : 1)
                }
            }
            VStack(spacing: 8) {
                DotMatrixText(text: text, height: size * (text.count > 5 ? 0.13 : 0.17), color: palette.ink)
                if let caption { Text(caption).font(.fenn(size: 13, weight: .light)).foregroundStyle(palette.ink.opacity(0.85)) }
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
        .shadow(color: palette.colors[2].opacity(0.35), radius: 24, y: 10)
    }
}

/// "42 min", "2.340 kg", "12:30" → dot-matrix number + light unit; text without a leading number stays text.
struct MetricText: View {
    let text: String
    var height: CGFloat = 16
    var color: Color = Fenn.fg

    var body: some View {
        let allowed = Set("0123456789.,:-+%/")
        let value = String(text.prefix { allowed.contains($0) })
        let unit = text.dropFirst(value.count).trimmingCharacters(in: .whitespaces)
        if value.isEmpty || value.allSatisfy({ !$0.isNumber }) {
            Text(text).font(.fenn(size: height * 0.9, weight: .light)).foregroundStyle(color)
        } else {
            MetricValue(value: value, unit: unit.isEmpty ? nil : unit, height: height, color: color)
        }
    }
}

// MARK: - Canvas

/// A large soft sheet – warm mesh, dark ink, quiet mono specs and dotted controls. For the one thing that matters
/// on a screen (today's session), not for every card.
struct FennCanvas<Content: View>: View {
    var palette: MeshAura.Palette = .fresh
    /// Smaller inside another card (a session in the week view), full size on its own.
    var cornerRadius: CGFloat = 34
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    MeshAura(palette: palette)
                    FennGrain(opacity: 0.10)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.75), .white.opacity(0.08), .white.opacity(0.3)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
            .shadow(color: Fenn.accent.opacity(0.20), radius: 26, y: 12)
            .environment(\.auraInk, palette.ink)
    }
}

/// Spec lines in small caps mono – "TYP: HYBRID", "DAUER: 45 MIN".
struct FennMetaLines: View {
    let lines: [(String, String)]
    var ink: Color = Fenn.fg

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text("\(line.0.uppercased()): \(line.1.uppercased())")
                    .font(.fenn(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(ink.opacity(0.62))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A field of dots with one lit knob: two measures in one glance (x grows right, y grows up). Without values
/// only the dots show – no made-up position.
struct DotPad: View {
    var x: Double?
    var y: Double?
    var ink: Color = Fenn.fg
    var columns = 9
    var rows = 7

    var body: some View {
        GeometryReader { geo in
            let inset: CGFloat = 13
            let w = geo.size.width - inset * 2, h = geo.size.height - inset * 2
            ZStack(alignment: .topLeading) {
                Canvas { g, _ in
                    for c in 0..<columns {
                        for r in 0..<rows {
                            let px = inset + w * CGFloat(c) / CGFloat(max(1, columns - 1))
                            let py = inset + h * CGFloat(r) / CGFloat(max(1, rows - 1))
                            g.fill(Path(ellipseIn: CGRect(x: px - 1.2, y: py - 1.2, width: 2.4, height: 2.4)), with: .color(ink.opacity(0.30)))
                        }
                    }
                }
                if let x, let y {
                    let cx = inset + w * CGFloat(min(1, max(0, x))), cy = inset + h * CGFloat(1 - min(1, max(0, y)))
                    Circle()
                        .fill(RadialGradient(colors: [.white, .white.opacity(0.75)], center: .topLeading, startRadius: 1, endRadius: 16))
                        .overlay(Circle().fill(Fenn.accent).frame(width: 6, height: 6))
                        .frame(width: 20, height: 20)
                        .shadow(color: ink.opacity(0.25), radius: 6, y: 3)
                        .position(x: cx, y: cy)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(ink.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(ink.opacity(0.14), lineWidth: 1))
        .animation(.snappy(duration: 0.4), value: x)
        .animation(.snappy(duration: 0.4), value: y)
    }
}

/// Small frosted circle for a canvas corner (open, more, …).
struct CanvasCircleButton: View {
    let symbol: String
    let label: String
    var ink: Color = Fenn.fg
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.fenn(size: 13, weight: .semibold))
                .foregroundStyle(ink)
                .frame(width: 36, height: 36)
                .background(Circle().fill(.white.opacity(0.42)))
                .overlay(Circle().strokeBorder(.white.opacity(0.65), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Solid capsule for the one action on a canvas ("Starten") – ember by default; on a warm canvas the canvas ink
/// reads better (set via the canvas environment).
struct FennEmberButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.auraInk) private var auraInk

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.fenn(size: 16, weight: .semibold))
            .foregroundStyle(auraInk == nil ? Fenn.onAccent : Color(red: 1.0, green: 0.95, blue: 0.9))
            .padding(.horizontal, 22)
            .frame(minHeight: 48)
            .background(Capsule().fill(auraInk ?? Fenn.accent))
            .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
            .shadow(color: (auraInk ?? Fenn.ember).opacity(0.35), radius: 10, y: 5)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension Font {
    /// Every text size comes through here, so a named typeface (Einstellungen › Schrift) reaches all screens.
    static func fenn(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design? = nil) -> Font {
        if design == nil, let face = FennFontChoice.current.face(weight) {
            return .custom(face, fixedSize: size)
        }
        return .system(size: size, weight: weight, design: design)
    }
}
