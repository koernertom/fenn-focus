import SwiftUI
import FennFocusCore

/// Fenn the agent: say what you want, Fenn does it – actions show as small lines, questions as buttons.
struct CoachModuleView: View {
    @ObservedObject var agent: FennAgent
    let hasKey: Bool
    let openConnectors: () -> Void
    @ObservedObject var knowledge: KnowledgeStore
    let send: (String) -> Void
    /// The pebble sits on the empty page – click it and talk.
    var listening = false
    var listen: () -> Void = {}
    @State private var showsMemory = false
    @State private var jumps = 0
    @State private var cheer = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let examples = [
        tr("Plan meinen Tag", "Plan my day"),
        tr("25 Minuten Fokus auf die wichtigste Aufgabe", "25 minutes focus on the top task"),
        tr("Was steht diese Woche noch an?", "What's still due this week?"),
        tr("Erinner mich morgen an das Angebot", "Remind me about the proposal tomorrow"),
    ]

    var body: some View {
        if hasKey {
            conversation
        } else {
            VStack(spacing: 14) {
                Spacer()
                FennAvatar(size: 72)
                Text(tr("Wähle ein KI-Modell", "Pick an AI model"))
                    .font(Fenn.display(20))
                    .foregroundStyle(Fenn.fg)
                Text(tr("Fenn braucht ein Modell mit Tool Calling: Fenn Brain (eingebaut, offline), Claude oder ein OpenAI-kompatibler Server. Einstellen unter Verbindungen.",
                        "Fenn needs a model with tool calling: Fenn Brain (built in, offline), Claude or an OpenAI-compatible server. Set it up under Connections."))
                    .font(.fenn(size: 13))
                    .foregroundStyle(Fenn.fg.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
                Button(tr("Zu den Verbindungen", "Open connections"), action: openConnectors)
                    .buttonStyle(FennPillButtonStyle(prominent: true))
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var conversation: some View {
        VStack(spacing: 8) {
            chatBar
            messages
        }
    }

    /// "Neuer Chat" and what Fenn remembers – always reachable, also while Fenn is still working.
    private var chatBar: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Button { showsMemory.toggle() } label: {
                Label { Text(tr("Gedächtnis", "Memory")) } icon: { ClaySymbol(symbol: "brain.head.profile", size: 18) }
            }
            .buttonStyle(FennPillButtonStyle())
            .help(tr("Was Fenn sich gemerkt hat", "What Fenn remembers"))
            .popover(isPresented: $showsMemory, arrowEdge: .bottom) { MemoryList(knowledge: knowledge) }
            if agent.hasConversation || agent.isWorking {
                Button { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { agent.reset() } } label: {
                    Label(tr("Neuer Chat", "New chat"), systemImage: "square.and.pencil")
                }
                .buttonStyle(FennPillButtonStyle())
                .help(tr("Gespräch beenden und neu anfangen – auch mitten in einer Antwort", "End this conversation and start over – even mid-answer"))
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .font(.fenn(size: 12, weight: .medium))
        .onAppear { knowledge.loadMemories() }
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if agent.items.isEmpty { welcome }
                    ForEach(agent.items) { item in
                        row(item).id(item.id)
                    }
                    if agent.isWorking {
                        HStack(spacing: 10) {
                            FennThinking(state: .working, text: agent.status ?? tr("Denkt nach …", "Thinking …"))
                            Button(tr("Stopp", "Stop"), systemImage: "stop.fill") { agent.stop() }
                                .buttonStyle(FennPillButtonStyle())
                                .font(.fenn(size: 12, weight: .medium))
                                .help(tr("Anfrage abbrechen", "Cancel the request"))
                        }
                        .id("working")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 6)
            }
            .scrollIndicators(.never)
            .onChange(of: agent.items.count) {
                if let last = agent.items.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                if case .user = agent.items.last?.kind { return }
                jump()
                cheer = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { cheer = false }
            }
            .onChange(of: agent.isWorking) {
                if agent.isWorking { withAnimation { proxy.scrollTo("working", anchor: .bottom) } }
            }
        }
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            pebble
            Text(listening ? tr("Ich höre zu …", "Listening …") : tr("Was willst du tun?", "What do you want to do?"))
                .font(Fenn.display(20)).foregroundStyle(Fenn.fg)
                .contentTransition(.opacity)
            VStack(spacing: 6) {
                ForEach(Self.examples, id: \.self) { example in
                    Button { send(example) } label: {
                        Text(example)
                            .font(.fenn(size: 13))
                            .foregroundStyle(Fenn.fg.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .frame(minHeight: 30)
                            .background(Capsule().fill(Fenn.fill))
                            .overlay(Capsule().strokeBorder(Fenn.hairline))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 36)
    }

    // MARK: The pebble

    private var mood: PebbleFace.Mood {
        if listening { return .listening }
        if agent.isWorking { return .thinking }
        if cheer { return .happy }
        return .content
    }

    /// Breathes, wakes up while listening, squash-and-jumps on a click or an answer. Click = talk / stop talking.
    private var pebble: some View {
        let size: CGFloat = 170
        return Button {
            jump()
            listen()
        } label: {
            Image(PebbleMac.image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .overlay { PebbleFace(mood: mood, blush: true) }
                .compositingGroup()
                .frame(width: size, height: size)
                .background {
                    Circle()
                        .fill(RadialGradient(colors: [Fenn.accent.opacity(0.25), .clear], center: .center, startRadius: 0, endRadius: size * 0.65))
                        .frame(width: size * 1.3, height: size * 1.3)
                        .allowsHitTesting(false)
                }
                .keyframeAnimator(initialValue: PebbleJump(), trigger: jumps) { stone, jump in
                    stone.scaleEffect(x: jump.stretchX, y: jump.stretchY, anchor: .bottom).offset(y: -jump.lift * size)
                } keyframes: { _ in
                    KeyframeTrack(\.stretchX) {
                        SpringKeyframe(1.16, duration: 0.1)
                        SpringKeyframe(0.9, duration: 0.16)
                        CubicKeyframe(1.0, duration: 0.22)
                        SpringKeyframe(1.12, duration: 0.08)
                        SpringKeyframe(1.0, duration: 0.3, spring: .bouncy)
                    }
                    KeyframeTrack(\.stretchY) {
                        SpringKeyframe(0.82, duration: 0.1)
                        SpringKeyframe(1.14, duration: 0.16)
                        CubicKeyframe(1.0, duration: 0.22)
                        SpringKeyframe(0.88, duration: 0.08)
                        SpringKeyframe(1.0, duration: 0.3, spring: .bouncy)
                    }
                    KeyframeTrack(\.lift) {
                        LinearKeyframe(0, duration: 0.1)
                        CubicKeyframe(0.2, duration: 0.2)
                        CubicKeyframe(0, duration: 0.18)
                        LinearKeyframe(0, duration: 0.38)
                    }
                }
                .scaleEffect(listening ? 1.06 : 1)
                .phaseAnimator(reduceMotion ? [false] : [false, true]) { stone, up in
                    stone.scaleEffect(up ? 1.025 : 0.985).offset(y: up ? -size * 0.012 : size * 0.012)
                } animation: { _ in .easeInOut(duration: 3.2) }
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: listening)
                .padding(.top, size * 0.22)
        }
        .buttonStyle(PebblePressStyle())
        .help(listening ? tr("Zuhören beenden", "Stop listening") : tr("Klicken und sprechen", "Click and talk"))
        .accessibilityLabel(listening ? tr("Fenn – Zuhören beenden", "Fenn – stop listening") : tr("Fenn – klicken und sprechen", "Fenn – click and talk"))
    }

    private func jump() {
        guard !reduceMotion else { return }
        jumps += 1
    }

    @ViewBuilder
    private func row(_ item: AgentItem) -> some View {
        switch item.kind {
        case .user:
            HStack {
                Spacer(minLength: 60)
                Text(item.text)
                    .font(.fenn(size: 14))
                    .foregroundStyle(Fenn.fg)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Fenn.fillStrong))
                    .textSelection(.enabled)
            }
        case .fenn:
            HStack(alignment: .top, spacing: 10) {
                FennAvatar(size: 24)
                VStack(alignment: .leading, spacing: 6) {
                    FennMarkdown(text: item.text).textSelection(.enabled)
                    HStack {
                        Spacer(minLength: 0)
                        let kept = knowledge.isRemembered(item.text)
                        Button {
                            if kept { knowledge.forget(item.text) } else { knowledge.remember(item.text) }
                        } label: {
                            Label(kept ? tr("Gemerkt", "Remembered") : tr("Merken", "Remember"),
                                  systemImage: kept ? "checkmark.circle.fill" : "brain.head.profile")
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(.plain)
                        .font(.fenn(size: 11, weight: .medium))
                        .foregroundStyle(Fenn.amber)
                        .help(kept ? tr("Klicken, um es wieder zu vergessen", "Click to forget it again") : tr("In MEMORY.md speichern", "Save to MEMORY.md"))
                    }
                }
            }
        case .action(let symbol):
            HStack(spacing: 8) {
                ClaySymbol(symbol: symbol, size: 20)
                Text(item.text).font(.fenn(size: 12.5, weight: .medium)).foregroundStyle(Fenn.fg.opacity(0.85)).lineLimit(2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(Fenn.accent.opacity(0.12)))
            .padding(.leading, 34)
        case .question(let options):
            HStack(alignment: .top, spacing: 10) {
                FennAvatar(size: 24)
                VStack(alignment: .leading, spacing: 8) {
                    FennMarkdown(text: item.text)
                    if !options.isEmpty {
                        ChipFlow(spacing: 6) {
                            ForEach(options, id: \.self) { option in
                                Button { send(option) } label: {
                                    Text(option)
                                        .font(.fenn(size: 12.5, weight: .medium))
                                        .foregroundStyle(Fenn.fg)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .frame(minHeight: 28)
                                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Fenn.fillStrong))
                                }
                                .buttonStyle(.plain)
                                .disabled(agent.isWorking || agent.items.last?.id != item.id)
                            }
                        }
                    }
                }
            }
        case .error:
            Text(item.text)
                .font(.fenn(size: 12))
                .foregroundStyle(Fenn.danger)
                .padding(.leading, 34)
        }
    }
}

/// The values a jump animates: squash and stretch around the bottom, and how high it lifts (share of the pebble).
private struct PebbleJump {
    var stretchX = 1.0
    var stretchY = 1.0
    var lift = 0.0
}

/// Pressing the pebble squashes it a little instead of dimming it.
private struct PebblePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(x: configuration.isPressed ? 1.04 : 1, y: configuration.isPressed ? 0.94 : 1, anchor: .bottom)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

/// The facts in MEMORY.md, each one removable – what "Merken" saved can be taken back here.
private struct MemoryList: View {
    @ObservedObject var knowledge: KnowledgeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Was Fenn sich merkt", "What Fenn remembers")).font(Fenn.display(16)).foregroundStyle(Fenn.fg)
            if knowledge.memories.isEmpty {
                Text(tr("Noch nichts. Klick bei einer Antwort auf „Merken“.", "Nothing yet. Click “Remember” on a reply."))
                    .font(.fenn(size: 12.5)).foregroundStyle(Fenn.fg.opacity(0.6))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(knowledge.memories.reversed(), id: \.self) { fact in
                            HStack(alignment: .top, spacing: 8) {
                                Text(fact).font(.fenn(size: 12.5)).foregroundStyle(Fenn.fg.opacity(0.9))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Button { withAnimation { knowledge.forget(fact) } } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(Fenn.fg.opacity(0.4))
                                }
                                .buttonStyle(.plain)
                                .help(tr("Vergessen", "Forget"))
                                .accessibilityLabel(tr("Vergessen: \(fact)", "Forget: \(fact)"))
                            }
                            .transition(.opacity)
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
            Button(tr("MEMORY.md öffnen", "Open MEMORY.md")) { openTextFile(knowledge.memoryURL) }
                .buttonStyle(.plain).font(.fenn(size: 11.5, weight: .medium)).foregroundStyle(Fenn.accent)
        }
        .padding(16)
        .frame(width: 320)
    }
}

/// Answer chips that wrap; a chip longer than the row gets the full width and breaks into lines.
struct ChipFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width ?? 400).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, point) in arrange(subviews, width: bounds.width).points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                                  proposal: Self.proposal(subviews[index], width: bounds.width))
        }
    }

    private static func proposal(_ subview: LayoutSubview, width: CGFloat) -> ProposedViewSize {
        subview.sizeThatFits(.unspecified).width > width ? ProposedViewSize(width: width, height: nil) : .unspecified
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (size: CGSize, points: [CGPoint]) {
        var points: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(Self.proposal(subview, width: width))
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), points)
    }
}
