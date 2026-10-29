import SwiftUI

/// A short confetti burst over the island when a task or routine is ticked off.
@MainActor
final class Celebration: ObservableObject {
    static let shared = Celebration()
    @Published private(set) var burst: (id: UUID, at: Date)?

    func fire() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let id = UUID()
        burst = (id, Date())
        // Gone again afterwards, so the overlay's timeline doesn't keep drawing an empty canvas.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) { [weak self] in
            if self?.burst?.id == id { self?.burst = nil }
        }
    }
}

/// Paper bits in Fenn's colours: out from the top middle, a little float, then down and gone in 1.6 s.
struct ConfettiOverlay: View {
    @ObservedObject var celebration = Celebration.shared
    private static let duration = 1.6

    private struct Bit {
        let angle: Double, speed: Double, spin: Double, size: CGSize, color: Color
    }

    private static func bits(seed: UUID) -> [Bit] {
        var generator = SeededGenerator(seed: UInt64(truncatingIfNeeded: seed.hashValue))
        let colors: [Color] = [Fenn.accent, Fenn.amber, Fenn.peach, Color(red: 0.93, green: 0.92, blue: 0.88), Fenn.brand]
        return (0..<44).map { _ in
            Bit(angle: Double.random(in: -.pi * 0.95 ... -.pi * 0.05, using: &generator),
                speed: Double.random(in: 180...420, using: &generator),
                spin: Double.random(in: -9...9, using: &generator),
                size: CGSize(width: Double.random(in: 5...9, using: &generator), height: Double.random(in: 3...6, using: &generator)),
                color: colors.randomElement(using: &generator) ?? .white)
        }
    }

    var body: some View {
        if let burst = celebration.burst, Date().timeIntervalSince(burst.at) < Self.duration {
            let bits = Self.bits(seed: burst.id)
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSince(burst.at)
                Canvas { canvas, size in
                    guard t < Self.duration else { return }
                    let origin = CGPoint(x: size.width / 2, y: size.height * 0.28)
                    let fade = max(0, 1 - max(0, t - 1.0) / 0.6)
                    for bit in bits {
                        // Thrown out, slowed by the air, pulled down.
                        let drag = (1 - exp(-3 * t)) / 3
                        let x = origin.x + cos(bit.angle) * bit.speed * drag
                        let y = origin.y + sin(bit.angle) * bit.speed * drag + 260 * t * t
                        var piece = canvas
                        piece.translateBy(x: x, y: y)
                        piece.rotate(by: .radians(bit.spin * t))
                        piece.opacity = fade
                        piece.fill(Path(roundedRect: CGRect(x: -bit.size.width / 2, y: -bit.size.height / 2,
                                                            width: bit.size.width, height: bit.size.height), cornerRadius: 1.5),
                                   with: .color(bit.color))
                    }
                }
            }
            .allowsHitTesting(false)
            .id(burst.id)
            .task(id: burst.id) {
                try? await Task.sleep(for: .seconds(Self.duration + 0.1))
                celebration.objectWillChange.send()
            }
        }
    }
}

/// Same confetti for the same burst, frame after frame.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
