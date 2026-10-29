import AppKit
import SwiftUI

/// Fenn pops out under the notch for a moment, waves, says a word and slides back up – a hello in the morning,
/// a cheer when a task or routine is done, a nudge when the focus block ends. Its own small see-through window,
/// because the notch panel is exactly as big as the notch. Never takes focus or clicks.
@MainActor
final class FennPeek {
    static let shared = FennPeek()

    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    private var lastShown = Date.distantPast
    private static let size = CGSize(width: 150, height: 132)

    /// `anchor`: the notch panel's frame – Fenn appears right under its middle.
    func show(_ line: String, under anchor: NSRect) {
        // Not more than once every 20 s, so a burst of ticks doesn't turn into a puppet show.
        guard Date().timeIntervalSince(lastShown) > 20 else { return }
        lastShown = Date()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let origin = NSPoint(x: (anchor.midX - Self.size.width / 2).rounded(), y: (anchor.minY - Self.size.height).rounded())
        panel.contentView = Self.host(PeekView(line: line, id: UUID()))
        panel.setFrame(NSRect(origin: origin, size: Self.size), display: false)
        panel.orderFrontRegardless()
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + PeekView.duration + 0.2, execute: work)
    }

    /// Hovering the notch: Fenn drops out of it and, spinning once in the air, jumps onto `target` – his place in the
    /// opening island (screen coordinates of the pebble's centre). Without a target he lands just under the notch.
    func pop(under anchor: NSRect, target: NSPoint? = nil, width: CGFloat = 150) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let size = CGSize(width: max(width, 150), height: PopView.height)
        let origin = NSPoint(x: (anchor.midX - size.width / 2).rounded(), y: (anchor.minY - size.height).rounded())
        // In the pop's own coordinates (top-left origin).
        let landing = target.map { CGPoint(x: $0.x - origin.x, y: origin.y + size.height - $0.y) }
            ?? CGPoint(x: size.width / 2, y: 46)
        panel.contentView = Self.host(PopView(id: UUID(), start: CGPoint(x: size.width / 2, y: -44), landing: landing,
                                              landingSize: target == nil ? 80 : 52))
        // Frame after the view: the hosting view must not get a say in where and how big the window is.
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + PopView.duration + 0.05, execute: work)
    }

    /// A hosting view that never resizes the window to its content.
    private static func host<Content: View>(_ view: Content) -> NSView {
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        return host
    }

    /// Loads the spin frames ahead of the first hover, so the jump doesn't stutter while they decode.
    func warmUp() {
        for image in PopView.spinImages { _ = image.cgImage(forProposedRect: nil, context: nil, hints: nil) }
    }

    /// Out of sight and its view dropped – a hidden window would keep running the animation timeline.
    private func hide() {
        panel?.orderOut(nil)
        panel?.contentView = nil
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        return panel
    }
}

/// Drops down from under the notch, waves three times with a word beside it, and goes back up.
private struct PeekView: View {
    let line: String
    let id: UUID
    static let duration = 3.4
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSince(start)
            let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            VStack(spacing: 4) {
                PebbleMac(size: 70)
                    .rotationEffect(.degrees(reduce ? 0 : wave(t)), anchor: .bottom)
                    .offset(y: reduce ? 0 : drop(t))
                Text(line)
                    .font(.fenn(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.78)))
                    .opacity(bubble(t))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .opacity(reduce ? fade(t) : 1)
        }
        .onAppear { start = Date() }
    }

    /// From −110 (hidden under the notch) down to 4 with a little bounce, back up at the end.
    private func drop(_ t: Double) -> Double {
        let down = 0.45, up = Self.duration - 0.45
        if t < down {
            let x = t / down
            return -110 + 114 * (1 - pow(1 - x, 3)) + 6 * sin(x * .pi)
        }
        if t > up {
            let x = min(1, (t - up) / 0.45)
            return 4 - 114 * x * x
        }
        return 4
    }

    /// Three waves from side to side while it's out.
    private func wave(_ t: Double) -> Double {
        guard t > 0.5, t < 2.3 else { return 0 }
        return 14 * sin((t - 0.5) / 1.8 * 6 * .pi) * (1 - (t - 0.5) / 2.2)
    }

    private func bubble(_ t: Double) -> Double {
        if t < 0.55 { return 0 }
        if t < 0.8 { return (t - 0.55) / 0.25 }
        if t > Self.duration - 0.7 { return max(0, (Self.duration - 0.45 - t) / 0.25) }
        return 1
    }

    private func fade(_ t: Double) -> Double {
        t < 0.3 ? t / 0.3 : (t > Self.duration - 0.3 ? max(0, (Self.duration - t) / 0.3) : 1)
    }
}

/// Out of the notch, then one jump in an arc onto Fenn's place: one quick 360° turn in the air (the real turnaround
/// frames), a squashy landing with a few speed lines, then the island's own pebble takes over.
struct PopView: View {
    let id: UUID
    let start: CGPoint
    let landing: CGPoint
    let landingSize: CGFloat
    static let height: CGFloat = 170
    static let duration = 0.95
    static let frames = 24
    /// The 24 turnaround views, loaded once and kept – also used by the launcher's pebble when it turns around.
    static let spinImages: [NSImage] = (0..<frames).compactMap { NSImage(named: "FennSpin/\(String(format: "%02d", $0))") }

    static func spinImage(_ index: Int) -> Image {
        spinImages.indices.contains(index) ? Image(nsImage: spinImages[index]) : Image("FennSpin/\(String(format: "%02d", index))")
    }
    private static let startSize: CGFloat = 80
    @State private var began = Date()

    var body: some View {
        TimelineView(.animation) { context in
            frame(at: context.date.timeIntervalSince(began), reduce: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        }
        .onAppear { began = Date() }
        .allowsHitTesting(false)
    }

    /// Fenn at time `t` of the pop – also drawn frame by frame for QA.
    func frame(at t: Double, reduce: Bool) -> some View {
        let squash = reduce ? 1 : Self.squash(t)
        let point = reduce ? landing : position(t)
        let size = reduce ? landingSize : Self.startSize + (landingSize - Self.startSize) * Self.ease(Self.flight(t))
        return ZStack(alignment: .topLeading) {
            Color.clear
            if !reduce { LandingLines(t: t, width: landingSize).position(x: landing.x, y: landing.y + landingSize * 0.42) }
            Self.spinImage(reduce ? 0 : Self.spinIndex(t))
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .scaleEffect(x: 2 - squash, y: squash, anchor: .bottom)
                .shadow(color: .black.opacity(0.22), radius: 6, y: 3)
                .position(point)
                .opacity(Self.opacity(t, reduce: reduce))
        }
    }

    /// 0…1 over the jump (0.12 s to 0.62 s).
    private static func flight(_ t: Double) -> Double { min(max((t - 0.12) / 0.5, 0), 1) }

    private static func ease(_ p: Double) -> Double { p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2 }

    /// Out of the notch first (straight down), then an arc to the landing spot, a little higher than both ends.
    private func position(_ t: Double) -> CGPoint {
        let out = CGPoint(x: start.x, y: 12)
        if t < 0.12 {
            let p = 1 - pow(1 - t / 0.12, 3)
            return CGPoint(x: start.x, y: start.y + (out.y - start.y) * p)
        }
        let p = Self.flight(t)
        let e = Self.ease(p)
        let lift = 46 * sin(p * .pi)
        return CGPoint(x: out.x + (landing.x - out.x) * e, y: out.y + (landing.y - out.y) * e - lift)
    }

    /// All 24 views once during the jump, front again on landing.
    private static func spinIndex(_ t: Double) -> Int {
        Int((ease(flight(t)) * Double(frames)).rounded()) % frames
    }

    /// Stretched in the air, squashed on landing, back to round.
    private static func squash(_ t: Double) -> Double {
        if t < 0.12 { return 1.04 }
        if t < 0.62 { return 1 + 0.06 * sin(flight(t) * .pi) }
        if t < 0.7 { return 1 - 0.16 * sin((t - 0.62) / 0.08 * .pi / 2) }
        if t < 0.84 { let x = (t - 0.7) / 0.14; return 0.84 + 0.16 * (1 - pow(1 - x, 2)) + 0.04 * sin(x * .pi) }
        return 1
    }

    private static func opacity(_ t: Double, reduce: Bool) -> Double {
        if reduce { return t < 0.2 ? t / 0.2 : max(0, (duration - t) / 0.3) }
        if t < 0.06 { return t / 0.06 }
        // The island's pebble appears at 0.8 s – this one fades out underneath it.
        return t > 0.8 ? max(0, (duration - t) / 0.15) : 1
    }

    /// A small burst of speed lines around the feet on landing.
    private struct LandingLines: View {
        let t: Double
        let width: CGFloat

        var body: some View {
            let p = (t - 0.62) / 0.25
            Canvas { canvas, size in
                guard p > 0, p < 1 else { return }
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                for side in [-1.0, 1.0] {
                    for index in 0..<3 {
                        let angle = (side < 0 ? Double.pi : 0) + side * (Double(index) - 1) * 0.45
                        let inner = width * 0.55 + 14 * p, outer = inner + 9 * (1 - p)
                        var line = Path()
                        line.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner * 0.5))
                        line.addLine(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer * 0.5))
                        canvas.stroke(line, with: .color(Fenn.accent.opacity(0.9 * (1 - p))), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    }
                }
            }
            .frame(width: width * 2 + 60, height: 40)
        }
    }

    #if DEBUG
    /// QA: the pop as a strip of stills (-FennQAPop <file.png>), jumping to the launcher's pebble on the left.
    static var strip: some View {
        let pop = PopView(id: UUID(), start: CGPoint(x: 300, y: -44), landing: CGPoint(x: 76, y: 54), landingSize: 52)
        return VStack(spacing: 0) {
            ForEach([0.06, 0.14, 0.24, 0.34, 0.44, 0.54, 0.64, 0.72, 0.85], id: \.self) { t in
                pop.frame(at: t, reduce: false).frame(width: 600, height: height)
                    .overlay(alignment: .topTrailing) { Text(String(format: "%.2f s", t)).font(.system(size: 10)).foregroundStyle(.white).padding(4) }
                    .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.2)).frame(height: 1) }
            }
        }
        .background(Color.black)
    }
    #endif
}
