import SwiftUI
#if os(macOS)
import AppKit
#endif

/// The focus length is set on a dial: 5-min steps up to 2 h (where most focus blocks live), then 15 min up to 4 h,
/// then 30 min up to 8 h.
enum FocusDial {
    static let steps: [Int] = Array(stride(from: 5, through: 120, by: 5))
        + Array(stride(from: 135, through: 240, by: 15))
        + Array(stride(from: 270, through: 480, by: 30))
    static let presets = [25, 50, 90]

    /// Degrees of turning from step i to i+1: slow and precise from 25 min to 2 h, quick below and above,
    /// plus a small detent around 25, 50 and 90 min so they're easy to hit.
    static func cost(from i: Int) -> Double {
        let target = steps[i + 1]
        let base: Double = target <= 25 ? 8 : (target <= 120 ? 12 : 5)
        return base + (presets.contains(steps[i]) || presets.contains(target) ? 4 : 0)
    }

    private static let offsets: [Double] = steps.indices.map { i in (0..<i).reduce(0) { $0 + cost(from: $1) } }

    /// Where step i sits on the dial, 0…1 of a full turn.
    static func position(of i: Int) -> Double { offsets[i] / (offsets.last ?? 1) }

    static func index(of minutes: Int) -> Int {
        steps.enumerated().min { abs($0.element - minutes) < abs($1.element - minutes) }?.offset ?? 4
    }

    static func minutes(at index: Int) -> Int { steps[min(max(index, 0), steps.count - 1)] }

    /// Classic ratio: 5 min after a short block, 10 after up to an hour, 15 after longer ones.
    static func breakMinutes(for work: Int) -> Int { work <= 30 ? 5 : (work <= 60 ? 10 : 15) }

    static func label(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : (minutes % 60 == 0 ? "\(minutes / 60) h" : String(format: "%d:%02d h", minutes / 60, minutes % 60))
    }
}

/// The focus timer as a dial: turn a finger (or the mouse) around it to set the length – clockwise longer,
/// anticlockwise shorter. One full turn spans 5 min…8 h; the knob sits at the chosen length.
struct FocusDialTimer: View {
    let minutes: Int
    let text: String
    let caption: String
    var size: CGFloat = 250
    let set: (Int) -> Void
    @StateObject private var turner = DialTurner()

    private var index: Int { FocusDial.index(of: minutes) }
    private var fraction: Double { FocusDial.position(of: index) }

    var body: some View {
        ZStack {
            AuraTimer(text: text, progress: fraction, caption: caption, palette: .steady, size: size)
            let angle = fraction * 2 * .pi - .pi / 2
            let radius = size / 2 - 10
            Circle()
                .fill(Color.white)
                .frame(width: size * 0.072, height: size * 0.072)
                .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
                .offset(x: cos(angle) * radius, y: sin(angle) * radius)
                .allowsHitTesting(false)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let angle = atan2(value.location.y - size / 2, value.location.x - size / 2) * 180 / .pi
                    defer { turner.lastAngle = angle }
                    guard let last = turner.lastAngle else { return }
                    var delta = angle - last
                    if delta > 180 { delta -= 360 } else if delta < -180 { delta += 360 }
                    turner.turn(by: delta, from: index, set: set)
                }
                .onEnded { _ in turner.reset() }
        )
        // No wheel turning: the dial sits on a scrolling page, so the wheel scrolls the page – turn it by dragging.
        .sensoryFeedback(.selection, trigger: minutes)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("Fokusdauer", "Focus length"))
        .accessibilityValue(FocusDial.label(minutes))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(FocusDial.minutes(at: index + 1))
            case .decrement: set(FocusDial.minutes(at: index - 1))
            @unknown default: break
            }
        }
    }
}

/// Collects turning (degrees) and turns it into dial steps – each step costs FocusDial.cost, so the fine range turns slower.
@MainActor
final class DialTurner: ObservableObject {
    var lastAngle: Double?
    private var carried = 0.0

    func turn(by degrees: Double, from start: Int, set: (Int) -> Void) {
        carried += degrees
        var index = start
        while index < FocusDial.steps.count - 1, carried >= FocusDial.cost(from: index) {
            carried -= FocusDial.cost(from: index)
            index += 1
        }
        while index > 0, carried <= -FocusDial.cost(from: index - 1) {
            carried += FocusDial.cost(from: index - 1)
            index -= 1
        }
        // At either end the extra turning is dropped, so turning back reacts at once.
        if (index == 0 && carried < 0) || (index == FocusDial.steps.count - 1 && carried > 0) { carried = 0 }
        if index != start { set(FocusDial.minutes(at: index)) }
    }

    func reset() {
        lastAngle = nil
        carried = 0
    }
}
