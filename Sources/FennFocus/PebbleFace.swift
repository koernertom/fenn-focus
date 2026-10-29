import SwiftUI

/// The pebble wakes up: drawn over `PebbleMac.image` (which sleeps with closed eyes), it opens its eyes and smiles
/// while listening, glances around while thinking and squints happily when an answer is in.
/// Lay it as an overlay on the fitted image so it scales and breathes with the stone.
struct PebbleFace: View {
    enum Mood: Equatable {
        case asleep, listening, thinking, happy
        /// Eyes open, corners down – waiting for the first focus round.
        case sad
        /// Eyes squeezed shut, mouth wide open – the morning stretch.
        case yawn
        /// One eye open, one squinting – a little joke between the two of you.
        case wink
        /// Awake and at ease: eyes open, a small smile. Fenn's face when nothing is going on.
        case content
        /// The painted closed eyes stay, with a small smile under them – dozing happily.
        case dozy
    }

    let mood: Mood
    /// A warm touch on the cheeks.
    var blush = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Where the closed eyes sit on the picture (fractions of the image).
    private struct Spot {
        let left: CGFloat, right: CGFloat, y: CGFloat
        /// Width of one closed eye, as a fraction of the image width.
        let eye: CGFloat
        /// Where the cover comes from, in eye widths: above the eyes, or from the side where a hat brim sits close.
        var dx: CGFloat = 0
        var dy: CGFloat = 0.75
    }

    private static let spot = Spot(left: 0.354, right: 0.642, y: 0.491, eye: 0.089)

    private static let ink = Color(red: 0.22, green: 0.19, blue: 0.17)
    private static let cheek = Color(red: 0.86, green: 0.52, blue: 0.46)

    var body: some View {
        GeometryReader { proxy in
            let spot = Self.spot
            let size = proxy.size
            let eye = spot.eye * size.width
            let awake = mood != .asleep && mood != .dozy
            let shown = mood != .asleep
            ZStack {
                // The closed lids vanish under the stone's own surface from just above them (or, under a hat brim,
                // from the middle of the face) – same grain, same light.
                if awake {
                    ForEach([spot.left, spot.right], id: \.self) { x in
                        Image(PebbleMac.image)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: size.width, height: size.height)
                            .offset(x: eye * spot.dx * (x < 0.5 ? -1 : 1), y: eye * spot.dy)
                            .mask {
                                Ellipse()
                                    .frame(width: eye * (spot.dx == 0 ? 1.8 : 1.4), height: eye * 0.72)
                                    .blur(radius: eye * 0.08)
                                    .position(x: x * size.width, y: spot.y * size.height)
                            }
                    }
                    ForEach([spot.left, spot.right], id: \.self) { x in
                        eyeView(eye: eye, right: x > 0.5)
                            .position(x: x * size.width, y: spot.y * size.height)
                    }
                }
                if blush && shown {
                    ForEach([spot.left - spot.eye * 0.3, spot.right + spot.eye * 0.3], id: \.self) { x in
                        Ellipse()
                            .fill(Self.cheek.opacity(0.42))
                            .frame(width: eye * 0.62, height: eye * 0.32)
                            .blur(radius: eye * 0.09)
                            .position(x: x * size.width, y: spot.y * size.height + eye * 0.52)
                    }
                    .transition(.opacity)
                }
                if mood == .yawn {
                    Ellipse()
                        .fill(Self.ink.opacity(0.85))
                        .frame(width: eye * 0.55, height: eye * 0.75)
                        .position(x: (spot.left + spot.right) / 2 * size.width, y: spot.y * size.height + eye * 0.85)
                        .transition(.scale(scale: 0.2, anchor: .top).combined(with: .opacity))
                } else {
                    let small = mood == .content || mood == .dozy
                    Smile(happy: mood == .happy || mood == .wink, sad: mood == .sad)
                        .trim(from: 0, to: shown ? 1 : 0)
                        .stroke(Self.ink.opacity(0.85), style: StrokeStyle(lineWidth: eye * 0.085, lineCap: .round))
                        .frame(width: eye * (mood == .happy ? 0.85 : small ? 0.5 : 0.62), height: eye * (mood == .happy ? 0.3 : small ? 0.15 : 0.2))
                        .position(x: (spot.left + spot.right) / 2 * size.width, y: spot.y * size.height + eye * (mood == .sad ? 0.72 : 0.62))
                }
            }
            .opacity(shown ? 1 : 0)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.spring(response: 0.32, dampingFraction: 0.62), value: mood)
    }

    @ViewBuilder
    private func eyeView(eye: CGFloat, right: Bool) -> some View {
        if mood == .yawn {
            // Squeezed shut: the drawn sleepy curve, pressed a little flatter.
            Squint()
                .stroke(Self.ink, style: StrokeStyle(lineWidth: eye * 0.1, lineCap: .round, lineJoin: .round))
                .frame(width: eye * 0.55, height: eye * 0.18)
                .rotationEffect(.degrees(180))
        } else if mood == .happy || (mood == .wink && right) {
            // ^ ^ – squinting with joy.
            Squint()
                .stroke(Self.ink, style: StrokeStyle(lineWidth: eye * 0.1, lineCap: .round, lineJoin: .round))
                .frame(width: eye * 0.5, height: eye * 0.24)
                .transition(.scale(scale: 0.4).combined(with: .opacity))
        } else {
            let open = mood != .asleep
            Capsule()
                .fill(Self.ink)
                .frame(width: eye * 0.4, height: eye * 0.56)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(.white.opacity(0.9))
                        .frame(width: eye * 0.14, height: eye * 0.14)
                        .offset(x: -eye * 0.06, y: eye * 0.08)
                }
                .modifier(Glance(active: mood == .thinking && !reduceMotion, eye: eye))
                .modifier(Blink(active: open && !reduceMotion))
                .scaleEffect(x: 1, y: open ? 1 : 0.08)
        }
    }
}

/// A soft upward smile; wider and rounder when happy.
private struct Smile: Shape {
    var happy: Bool
    var sad = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if sad {
            // The corners down: a small, soft frown.
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                              control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.5))
            return path
        }
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                          control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * (happy ? 0.9 : 0.7)))
        return path
    }
}

/// "^" – one happy, squinted eye.
private struct Squint: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.6))
        return path
    }
}

/// A blink every few seconds, only on the eyes. Driven by a short task loop with explicit animations:
/// a repeating keyframe animator here piled up animations on every mood change and froze the screen for seconds.
private struct Blink: ViewModifier {
    let active: Bool
    @State private var closed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: 1, y: closed ? 0.1 : 1)
            .task(id: active) {
                closed = false
                guard active else { return }
                while !Task.isCancelled {
                    for pause in [2.6, 1.4] {
                        try? await Task.sleep(for: .seconds(pause))
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeIn(duration: 0.07)) { closed = true }
                        try? await Task.sleep(for: .seconds(0.08))
                        withAnimation(.easeOut(duration: 0.1)) { closed = false }
                    }
                }
            }
    }
}

/// Looking left and right while Fenn thinks – same loop pattern as the blink.
private struct Glance: ViewModifier {
    let active: Bool
    let eye: CGFloat
    @State private var look = CGSize.zero

    func body(content: Content) -> some View {
        content
            .offset(look)
            .task(id: active) {
                withAnimation(.easeInOut(duration: 0.3)) { look = .zero }
                guard active else { return }
                let left = CGSize(width: -eye * 0.14, height: -eye * 0.06)
                let right = CGSize(width: eye * 0.14, height: -eye * 0.06)
                while !Task.isCancelled {
                    for (target, hold) in [(left, 1.2), (right, 1.3), (CGSize.zero, 0.5)] {
                        withAnimation(.easeInOut(duration: 0.5)) { look = target }
                        try? await Task.sleep(for: .seconds(hold))
                        guard !Task.isCancelled else { return }
                    }
                }
            }
    }
}
