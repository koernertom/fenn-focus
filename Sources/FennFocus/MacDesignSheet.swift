import SwiftUI
import AppKit

/// Settings › Design (a page in the panel, like Legal): colour scheme, light/dark and typeface as small previews instead of names – a mini screen per
/// scheme in dark and light with its palette, the appearance as screens, the typefaces as a sample line, and the modes.
struct MacDesignSheet: View {
    let close: () -> Void
    @AppStorage(FennAppearance.key) private var appearance = FennAppearance.system.rawValue
    @AppStorage(FennScheme.key) private var theme = FennScheme.green.rawValue
    @AppStorage(FennFontChoice.key) private var font = FennFontChoice.standard.rawValue

    private var picked: FennScheme { FennScheme(rawValue: theme) ?? .green }
    private var needsRestart: Bool {
        theme != FennScheme.stored.rawValue
            || (font != FennFontChoice.current.rawValue && (FennFontChoice(rawValue: font)?.needsRestart == true || FennFontChoice.current.needsRestart))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Design").font(.fenn(size: 18, weight: .semibold)).foregroundStyle(Fenn.fg)
                Spacer()
                Button(tr("Fertig", "Done"), action: close)
                    .buttonStyle(FennPillButtonStyle(prominent: true))
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.bottom, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if needsRestart {
                        Label(tr("Farbschema und Schrift wechseln beim nächsten Start von Fenn.", "Colour scheme and typeface switch the next time Fenn starts."),
                              systemImage: "arrow.clockwise")
                            .font(.fenn(size: 12, weight: .medium)).foregroundStyle(Fenn.fg.opacity(0.75))
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Fenn.fill))
                    }

                    label(tr("MODUS", "MODE"))
                    MacModeSwitcher()

                    label(tr("FARBSCHEMA", "COLOUR SCHEME"))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                        ForEach(FennScheme.allCases) { scheme in
                            Button { theme = scheme.rawValue } label: { schemeCard(scheme) }
                                .buttonStyle(.plain)
                        }
                    }

                    label(tr("DARSTELLUNG", "APPEARANCE"))
                    HStack(spacing: 10) {
                        ForEach(FennAppearance.allCases) { mode in
                            Button { appearance = mode.rawValue } label: { appearanceCard(mode) }
                                .buttonStyle(.plain)
                        }
                    }

                    label(tr("SCHRIFT", "TYPEFACE"))
                    VStack(spacing: 6) {
                        ForEach(FennFontChoice.allCases) { choice in
                            Button { font = choice.rawValue } label: { fontRow(choice) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.bottom, 20)
            }
            .scrollIndicators(.never)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.fenn(size: 11, weight: .semibold)).tracking(1).foregroundStyle(Fenn.fg.opacity(0.55))
    }

    // MARK: Colour scheme

    private func schemeCard(_ scheme: FennScheme) -> some View {
        let on = scheme == picked
        let p = Palette(scheme.tones)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                MiniScreen(palette: p, dark: true)
                MiniScreen(palette: p, dark: false)
            }
            HStack(spacing: 3) {
                ForEach(Array(p.swatches.enumerated()), id: \.offset) { _, color in
                    Circle().fill(color).frame(width: 11, height: 11)
                        .overlay(Circle().strokeBorder(Fenn.fg.opacity(0.15), lineWidth: 0.5))
                }
                Spacer(minLength: 0)
                if on { Image(systemName: "checkmark.circle.fill").foregroundStyle(Fenn.accent) }
            }
            Text(scheme.title).font(.fenn(size: 12, weight: .semibold)).foregroundStyle(Fenn.fg)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            if scheme == .seasonal {
                Text(tr("Gerade: \(scheme.resolved().title)", "Now: \(scheme.resolved().title)"))
                    .font(.fenn(size: 10)).foregroundStyle(Fenn.fg.opacity(0.6))
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Fenn.fill))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? Fenn.accent : .clear, lineWidth: 2))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(scheme.title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: Appearance

    private func appearanceCard(_ mode: FennAppearance) -> some View {
        let on = appearance == mode.rawValue
        let p = Palette(picked.tones)
        return VStack(spacing: 6) {
            Group {
                switch mode {
                case .light: MiniScreen(palette: p, dark: false)
                case .dark: MiniScreen(palette: p, dark: true)
                case .system:
                    ZStack {
                        MiniScreen(palette: p, dark: false)
                        MiniScreen(palette: p, dark: true).mask(alignment: .trailing) { Rectangle().frame(maxWidth: .infinity).padding(.leading, 31) }
                    }
                }
            }
            HStack(spacing: 4) {
                if on { Image(systemName: "checkmark.circle.fill").font(.fenn(size: 12)).foregroundStyle(Fenn.accent) }
                Text(mode.title).font(.fenn(size: 12, weight: .semibold)).foregroundStyle(Fenn.fg)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Fenn.fill))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? Fenn.accent : .clear, lineWidth: 2))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Typeface

    private func fontRow(_ choice: FennFontChoice) -> some View {
        let on = font == choice.rawValue
        return HStack(spacing: 12) {
            Text("Aa").font(sample(choice, size: 22, weight: .semibold)).foregroundStyle(Fenn.fg).frame(width: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(tr("Dranbleiben, leicht gemacht.", "Staying with it, made easy.")).font(sample(choice, size: 14, weight: .regular))
                    .foregroundStyle(Fenn.fg).lineLimit(1)
                Text(choice.title).font(.system(size: 11)).foregroundStyle(Fenn.fg.opacity(0.55))
            }
            Spacer(minLength: 0)
            if on { Image(systemName: "checkmark.circle.fill").font(.fenn(size: 16)).foregroundStyle(Fenn.accent) }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Fenn.fill))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? Fenn.accent : .clear, lineWidth: 2))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func sample(_ choice: FennFontChoice, size: CGFloat, weight: Font.Weight) -> Font {
        if let face = choice.face(weight) { return .custom(face, size: size) }
        return .system(size: size, weight: weight, design: choice.design)
    }
}

/// The colours a scheme paints with, light and dark.
private struct Palette {
    let night, paper, darkCardTop, darkCardBottom, lightCard, accent, accentOnPaper, onAccent, onAccentOnPaper: Color

    init(_ t: FennScheme.Tones) {
        night = Color(t.night)
        paper = Color(t.paper)
        if t.stoneAuras && !t.petrolAurasInDark {
            darkCardTop = Color(t.smoke); darkCardBottom = Color(t.glass)
        } else {
            darkCardTop = Color(t.brand); darkCardBottom = Color(t.deep)
        }
        lightCard = Color(t.glassOnPaper)
        accent = Color(t.accent); accentOnPaper = Color(t.accentOnPaper)
        onAccent = Color(t.onAccent); onAccentOnPaper = Color(t.onAccentOnPaper)
    }

    var swatches: [Color] { [night, darkCardTop, accent, accentOnPaper, paper] }
}

/// A tiny Fenn screen: greeting, one card with a line of text, the primary button.
private struct MiniScreen: View {
    let palette: Palette
    let dark: Bool

    var body: some View {
        let ink = dark ? Color(red: 0.957, green: 0.961, blue: 0.969) : Color(red: 0.11, green: 0.098, blue: 0.09)
        VStack(alignment: .leading, spacing: 5) {
            Text(tr("Hallo", "Hi")).font(.system(size: 9, weight: .bold)).foregroundStyle(ink).lineLimit(1)
            VStack(alignment: .leading, spacing: 3) {
                Text(tr("Lauf", "Run")).font(.system(size: 7.5, weight: .semibold)).foregroundStyle(dark ? .white : ink).lineLimit(1)
                Text("45 min").font(.system(size: 6.5)).foregroundStyle((dark ? Color.white : ink).opacity(0.7)).lineLimit(1)
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(dark ? AnyShapeStyle(LinearGradient(colors: [palette.darkCardTop, palette.darkCardBottom], startPoint: .topLeading, endPoint: .bottomTrailing))
                           : AnyShapeStyle(palette.lightCard)))
            Spacer(minLength: 0)
            Text(tr("Starten", "Start")).font(.system(size: 7.5, weight: .bold))
                .foregroundStyle(dark ? palette.onAccent : palette.onAccentOnPaper)
                .frame(maxWidth: .infinity).frame(height: 15)
                .background(Capsule().fill(dark ? palette.accent : palette.accentOnPaper))
        }
        .padding(7)
        .frame(width: 62, height: 92)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(dark ? palette.night : palette.paper))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
    }
}
