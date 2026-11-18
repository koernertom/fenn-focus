import SwiftUI

/// Fenn jumps for joy: the pebble with a happy face hops twice with a little squash on landing, then just smiles.
/// Used in the island when a Pomodoro or a task is done, and in the notch notice while the island is closed.
struct CheeringPebble: View {
    var size: CGFloat
    @State private var start = Date()
    /// The timeline only runs for the hops – an idle `.animation` timeline would keep redrawing for nothing.
    @State private var settled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let hopTime = 0.62
    static let hops = 2.0

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: settled || reduceMotion)) { context in
            let t = reduceMotion || settled ? Self.hopTime * Self.hops : context.date.timeIntervalSince(start)
            let pose = Self.pose(t)
            ZStack {
                PebbleMac(size: size)
                PebbleFace(mood: .happy, blush: true)
                    .frame(width: size, height: size)
            }
            .scaleEffect(x: pose.width, y: pose.height, anchor: .bottom)
            .offset(y: -pose.lift * size)
        }
        .task {
            start = Date()
            try? await Task.sleep(for: .seconds(Self.hopTime * Self.hops + 0.1))
            settled = true
        }
        .accessibilityHidden(true)
    }

    /// Height above the ground (in pebble sizes) and the squash: wide and low when it lands, slim in the air.
    static func pose(_ t: Double) -> (lift: CGFloat, width: CGFloat, height: CGFloat) {
        guard t < hopTime * hops else { return (0, 1, 1) }
        let local = (t / hopTime).truncatingRemainder(dividingBy: 1)
        let air = sin(local * .pi)
        // The second hop is a little lower.
        let height = t < hopTime ? 0.42 : 0.26
        if local < 0.12 || local > 0.92 {
            return (CGFloat(air * height), 1.1, 0.88)
        }
        return (CGFloat(air * height), CGFloat(1 - 0.05 * air), CGFloat(1 + 0.07 * air))
    }
}

/// In the open island: Fenn hops up in the bottom corner with a speech bubble ("Pomodoro geschafft!") and goes again.
struct FennCheerOverlay: View {
    @ObservedObject var celebration = Celebration.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let cheer = celebration.cheer {
                HStack(alignment: .bottom, spacing: 6) {
                    Text(cheer.line)
                        .font(.fenn(size: 13, weight: .semibold))
                        .foregroundStyle(Fenn.onAccent)
                        .multilineTextAlignment(.trailing)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(
                            UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 14, bottomTrailingRadius: 4,
                                                   topTrailingRadius: 14, style: .continuous)
                                .fill(Fenn.accent)
                                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                        )
                        .frame(maxWidth: 240, alignment: .trailing)
                        .padding(.bottom, 34)
                    CheeringPebble(size: 58)
                }
                .padding(.trailing, 18)
                .padding(.bottom, 74)
                .id(cheer.id)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .allowsHitTesting(false)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.72), value: celebration.cheer?.id)
    }
}

/// What Fenn says when something is done – with today's numbers, so it feels earned.
@MainActor
enum FennCheerLine {
    static func taskDone() -> String {
        let count = TaskStore.shared.doneCount(in: .today)
        if count <= 1 { return tr("Das erste Häkchen heute!", "First one done today!") }
        let lines = [
            tr("Abgehakt! Schon \(count) heute.", "Done! That's \(count) today."),
            tr("Weg damit! \(count) erledigt heute.", "Off the list! \(count) done today."),
            tr("Stark, Nummer \(count) heute.", "Nice, number \(count) today."),
        ]
        return lines[count % lines.count]
    }

    /// `before` is the total focus before this block, to notice a milestone being passed.
    static func focusBlockDone(totalBefore: Int) -> String {
        let total = TaskStore.shared.sessions.reduce(0) { $0 + $1.minutes }
        if let milestone = ProgressModuleView.milestones.first(where: { $0 * 60 > totalBefore && $0 * 60 <= total }) {
            return tr("\(milestone) Stunden Fokus insgesamt!", "\(milestone) hours of focus in total!")
        }
        let today = TaskStore.shared.focusMinutes(in: .today)
        return tr("Pomodoro geschafft! \(TaskFormat.duration(today)) Fokus heute.", "Pomodoro done! \(TaskFormat.duration(today)) of focus today.")
    }
}
