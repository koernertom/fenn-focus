import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Design tokens shared by the app and the widgets.
/// Port of Design/styles-swiftui.md + tokens.md.
/// STEP-02 systemBlue / flat elevated chrome is superseded by Glass v3 here.
///
/// WidgetKit note: `.thickMaterial` is often unavailable or unreliable in
/// widget surfaces — prefer `canvasElevated` + `stroke.glass` hairline.
/// Reduce Transparency / Increase Contrast → always `canvasElevated` (no material).
public enum KZToken {
    public enum ColorSem {
        /// #090B0F — deep quiet canvas
        public static let canvas = Color(red: 0.035, green: 0.043, blue: 0.059)
        /// #0E1218 — widget solid / Reduce Transparency / Empty
        public static let canvasElevated = Color(red: 0.055, green: 0.071, blue: 0.094)
        /// Alias for widget solid fill (STEP-02 name kept for call sites).
        public static let canvasWidget = canvasElevated
        /// Panel fill when material unavailable.
        public static let elevated = canvasElevated
        /// #F4F5F7
        public static let fgPrimary = Color(red: 0.957, green: 0.961, blue: 0.969)
        /// #9CA3AF
        public static let fgSecondary = Color(red: 0.612, green: 0.639, blue: 0.686)
        /// #6B7280 — dimmer than secondary; Large/Icon only on glass
        public static let fgTertiary = Color(red: 0.420, green: 0.447, blue: 0.502)
        /// Always dark on the ember fill — white on #FF5A1F fails contrast.
        public static let fgOnAccent = Color(red: 0.035, green: 0.043, blue: 0.059)
        /// Fenn ember #FF5A1F (race red-orange)
        public static let accent = Color(red: 1.0, green: 0.353, blue: 0.122)
        /// Amber #FFB070 — event / rare
        public static let accentSecondary = Color(red: 1.0, green: 0.690, blue: 0.439)
        /// Hairline white @ 6%
        public static let strokeGlass = Color.white.opacity(0.06)
        public static let border = strokeGlass
        public static let statusTodo = fgSecondary
        public static let statusDoing = accent
        /// Soft mint #A7F3D0
        public static let statusDone = Color(red: 0.655, green: 0.953, blue: 0.816)
        /// Soft coral #FDA4AF — Error only
        public static let statusBlocked = Color(red: 0.992, green: 0.643, blue: 0.686)
        public static let kindFolder = fgSecondary
        public static let kindTask = accent
        public static let kindEvent = accentSecondary
        public static let kindNote = fgSecondary
        /// Quiet CTA halo — Variante A+ / Liquid Glass, never above 8%.
        public static let glowAccent = accent.opacity(0.07)
        public static let glowSecondary = accentSecondary.opacity(0.08)
        /// Ember focus ring 1 pt
        public static let focusRing = accent.opacity(0.55)
    }

    public enum Space {
        public static let s1: CGFloat = 4
        public static let s2: CGFloat = 8
        public static let s3: CGFloat = 12
        /// Widget PlanRow ONLY
        public static let row: CGFloat = 12
        public static let s4: CGFloat = 16
        public static let s5: CGFloat = 24
        public static let section: CGFloat = 24
        public static let s6: CGFloat = 32
        public static let s7: CGFloat = 40
        /// Editorial pause (host screens / list groups)
        public static let s8: CGFloat = 48
        /// Home card separation / pause under a display title.
        public static let s9: CGFloat = 56
    }

    public enum Radius {
        public static let sm: CGFloat = 6
        /// Non-capsule controls only; chips/Primary use Capsule()
        public static let md: CGFloat = 16
        public static let lg: CGFloat = 24
    }

    public enum TypeStyle {
        public static let display = Font.largeTitle.weight(.ultraLight)
        public static let title = Font.title3.weight(.light)
        /// Editorial: weight via color, not heavy bold
        public static let bodyPrimary = Font.body.weight(.regular)
        public static let body = Font.body
        public static let meta = Font.caption
        /// Small widget / chips only
        public static let metaDense = Font.caption2
        public static let widgetLarge = Font.title3.weight(.light)
        public static let widgetSmall = Font.caption.weight(.regular)
    }
}

// MARK: - Glass surfaces

/// Host / app panels. Prefer material; fall back to solid elevated + hairline.
/// WidgetKit: use `KZWidgetSurface` / `kzWidgetSurface()` instead of material.
public struct KZGlassBackground: ViewModifier {
    public var soft: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(soft: Bool = false) {
        self.soft = soft
    }

    public func body(content: Content) -> some View {
        content
            .background { panelFill }
            .overlay {
                RoundedRectangle(cornerRadius: KZToken.Radius.lg, style: .continuous)
                    .strokeBorder(KZToken.ColorSem.strokeGlass, lineWidth: 0.5)
            }
    }

    @ViewBuilder
    private var panelFill: some View {
        let shape = RoundedRectangle(cornerRadius: KZToken.Radius.lg, style: .continuous)
        if reduceTransparency {
            // A11y: Reduce Transparency → solid canvasElevated (tokens.md / accessibility.md)
            shape.fill(KZToken.ColorSem.canvasElevated)
        } else {
            #if os(macOS)
            // Host: thick/regular material when available
            shape.fill(soft ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.thickMaterial))
            #else
            shape.fill(soft ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.thickMaterial))
            #endif
        }
    }
}

/// Widget-safe solid surface: canvasElevated + stroke.glass (no Wallpaper blur material).
public struct KZWidgetSurface: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        content
            .background(KZToken.ColorSem.canvasElevated)
            .overlay {
                RoundedRectangle(cornerRadius: KZToken.Radius.lg, style: .continuous)
                    .strokeBorder(KZToken.ColorSem.strokeGlass, lineWidth: 0.5)
            }
    }
}

public struct KZSourceChip: View {
    public let text: String
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(KZToken.TypeStyle.metaDense)
            .foregroundStyle(KZToken.ColorSem.fgSecondary)
            .padding(.horizontal, KZToken.Space.s2)
            .padding(.vertical, KZToken.Space.s1)
            .background { chipBackground }
            .overlay(Capsule().strokeBorder(KZToken.ColorSem.strokeGlass, lineWidth: 0.5))
            .accessibilityLabel(L10n.string(.sourcePrefix, text))
    }

    @ViewBuilder
    private var chipBackground: some View {
        if reduceTransparency {
            Capsule().fill(KZToken.ColorSem.canvasElevated)
        } else {
            // WidgetKit may ignore material — solid elevated is the safe fill.
            Capsule().fill(KZToken.ColorSem.canvasElevated)
        }
    }
}

public struct KZPrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(KZToken.TypeStyle.body.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, KZToken.Space.s5)
            .foregroundStyle(KZToken.ColorSem.fgOnAccent)
            // Host CTA: thick liquid-glass approximation (not a flat cyan fill).
            // The pressed scale is the only motion; Reduce Motion removes its animation.
            .background {
                Capsule()
                    .fill(.ultraThickMaterial)
                    .overlay {
                        // Calm specular top highlight; iridescent rim stays below 8%.
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(configuration.isPressed ? 0.08 : 0.12),
                                        KZToken.ColorSem.accent.opacity(0.06),
                                        Color.white.opacity(0.03)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .blendMode(.plusLighter)
                    }
                    .overlay {
                        Capsule()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        KZToken.ColorSem.accent.opacity(0.07),
                                        Color.pink.opacity(0.035),
                                        Color.yellow.opacity(0.025),
                                        KZToken.ColorSem.accent.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(
                        color: KZToken.ColorSem.glowAccent,
                        radius: configuration.isPressed ? 3 : 6,
                        y: 0
                    )
            }
            // Satisfying, restrained feedback for the host Sync/CTA (0.98 → 1).
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

public struct KZCardModifier: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        content
            .padding(KZToken.Space.s4)
            .modifier(KZGlassBackground(soft: false))
    }
}

public extension View {
    func kzGlass(soft: Bool = false) -> some View { modifier(KZGlassBackground(soft: soft)) }
    func kzWidgetSurface() -> some View { modifier(KZWidgetSurface()) }
    func kzCard() -> some View { modifier(KZCardModifier()) }
}
