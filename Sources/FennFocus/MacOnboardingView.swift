import SwiftUI

/// First run on the Mac, as a conversation: Fenn asks a few questions about the person (name, work, rhythm, what to
/// help with, what distracts, how to talk), reacts to each answer, then sets up the model and the folder. Every answer
/// is saved as it is given and the step is remembered, so the setup continues where it was left.
struct MacOnboardingView: View {
    @ObservedObject var ai: AISettings
    @ObservedObject var cloud: FennCloudFolder
    let connectCloud: (SyncProvider) -> Void
    let openWindow: () -> Void
    let finish: () -> Void

    @ObservedObject private var person = PersonProfileStore.shared
    @ObservedObject private var calendar = WorkCalendar.shared
    @State private var step = min(UserDefaults.standard.integer(forKey: PersonProfileStore.stepKey), 7)
    @State private var forward = true
    /// What Fenn just said about the last answer, shown under the question for a moment.
    @State private var reaction: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let steps = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            progress
            OnboardingFenn(line: line, reaction: reaction, mood: mood, big: step == 0 || step == steps - 1)
                .id("fenn-\(step)")
            ScrollView {
                Group {
                    switch step {
                    case 0: welcome
                    case 1: aboutYou
                    case 2: rhythm
                    case 3: help
                    case 4: style
                    case 5: AIModelCard(ai: ai)
                    case 6: SyncFolderCard(cloud: cloud, connect: connectCloud)
                    default: ready
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(step)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            }
            .scrollIndicators(.never)
            buttons
        }
    }

    // MARK: What Fenn says

    private var name: String { person.firstName }

    private var line: String {
        switch step {
        case 0: return tr("Hi, ich bin Fenn! Ich helfe dir, bei einer Sache zu bleiben und deinen Tag im Griff zu haben. Darf ich dir ein paar kurze Fragen stellen?",
                          "Hi, I'm Fenn! I help you stay with one thing and keep your day in hand. May I ask you a few quick questions?")
        case 1: return tr("Schön, dass du da bist. Wie soll ich dich nennen – und was machst du so?",
                          "Glad you're here. What should I call you – and what do you do?")
        case 2: return name.isEmpty ? tr("Wie sieht dein Tag aus? Wann bist du am klarsten im Kopf?", "What does your day look like? When is your head clearest?")
            : tr("Freut mich, \(name)! Wie sieht dein Tag aus, und wann bist du am klarsten im Kopf?", "Nice to meet you, \(name)! What does your day look like, and when is your head clearest?")
        case 3: return tr("Wobei kann ich dir am meisten abnehmen? Und was willst du gerade unbedingt schaffen?",
                          "What can I take off your plate? And what do you really want to get done right now?")
        case 4: return tr("Fast geschafft. Was zieht dich am ehesten raus – und wie soll ich mit dir reden?",
                          "Almost there. What pulls you out most – and how should I talk to you?")
        case 5: return tr("Jetzt zu meinem Kopf: Welches Modell soll ich nutzen? Lokal bleibt alles auf deinem Mac.",
                          "Now my brain: which model should I use? Locally, everything stays on your Mac.")
        case 6: return tr("Und wo darf ich deine Aufgaben, Notizen und dein Profil ablegen?", "And where may I keep your tasks, notes and profile?")
        default: return name.isEmpty ? tr("Fertig! Ich hab mir alles gemerkt.", "Done! I've noted everything.")
            : tr("Schön, dich kennenzulernen, \(name)! Ich hab mir alles gemerkt.", "Lovely to meet you, \(name)! I've noted everything.")
        }
    }

    private var mood: PebbleFace.Mood {
        if reaction != nil { return .wink }
        switch step {
        case 0, steps - 1: return .happy
        case 5, 6: return .thinking
        default: return .listening
        }
    }

    private func react(_ text: String) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { reaction = text }
        let shown = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
            if reaction == shown { withAnimation { reaction = nil } }
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 10) {
            Staggered(index: 0) { promise("timer", tr("Fokusblöcke mit Timer, Musik und gesperrten Apps", "Focus blocks with a timer, music and blocked apps")) }
            Staggered(index: 1) { promise("calendar", tr("Aufgaben, Termine und Routinen – ich plane deinen Tag mit dir", "Tasks, meetings and routines – I plan your day with you")) }
            Staggered(index: 2) { promise("lock.fill", tr("Kein Konto, kein Server: alles bleibt bei dir", "No account, no server: everything stays with you")) }
        }
    }

    private var aboutYou: some View {
        VStack(alignment: .leading, spacing: 10) {
            OnboardingField(symbol: "person.fill", placeholder: tr("Dein Vorname", "Your first name"), text: $person.profile.name)
            OnboardingField(symbol: "briefcase.fill", placeholder: tr("Was du machst, z. B. Produktmanagerin, Student, Entwickler", "What you do, e.g. product manager, student, developer"),
                            text: $person.profile.role)
        }
    }

    private var rhythm: some View {
        VStack(alignment: .leading, spacing: 14) {
            caption(tr("Deine Arbeitszeit", "Your working hours"), symbol: "clock")
            DayBar(start: $calendar.workStart, end: $calendar.workEnd)
                .onChange(of: calendar.workStart) { _, _ in person.scheduleWrite() }
                .onChange(of: calendar.workEnd) { _, _ in person.scheduleWrite() }
            caption(tr("Wann kannst du dich am besten konzentrieren?", "When do you concentrate best?"), symbol: "brain.head.profile")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(PersonProfile.FocusTime.allCases) { time in
                    OptionTile(symbol: time.symbol, title: time.title, selected: person.profile.focusTime == time, compact: true) {
                        person.profile.focusTime = person.profile.focusTime == time ? nil : time
                        if person.profile.focusTime == time { react(time.reaction) }
                    }
                }
            }
        }
    }

    private var help: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(PersonProfile.Help.allCases) { choice in
                    OptionTile(symbol: choice.symbol, title: choice.title, selected: person.profile.helpWith.contains(choice)) {
                        if let index = person.profile.helpWith.firstIndex(of: choice) {
                            person.profile.helpWith.remove(at: index)
                        } else {
                            person.profile.helpWith.append(choice)
                            react(choice.reaction)
                        }
                    }
                }
            }
            caption(tr("Dein wichtigstes Ziel gerade", "Your most important goal right now"), symbol: "flag.fill")
            OnboardingField(symbol: "target", placeholder: tr("z. B. Das Projekt bis Ende Monat abschließen", "e.g. Finish the project by the end of the month"),
                            text: $person.profile.goal)
        }
    }

    private var style: some View {
        VStack(alignment: .leading, spacing: 14) {
            caption(tr("Was lenkt dich am meisten ab?", "What distracts you most?"), symbol: "bell.badge")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(PersonProfile.Distraction.allCases) { choice in
                    OptionTile(symbol: choice.symbol, title: choice.title, selected: person.profile.distractions.contains(choice), compact: true) {
                        if let index = person.profile.distractions.firstIndex(of: choice) {
                            person.profile.distractions.remove(at: index)
                        } else {
                            person.profile.distractions.append(choice)
                            react(tr("Notiert – im Fokus halte ich dir das vom Leib.", "Noted – during focus I'll keep that away from you."))
                        }
                    }
                }
            }
            caption(tr("Wie soll ich mit dir reden?", "How should I talk to you?"), symbol: "bubble.left.and.bubble.right")
            VStack(spacing: 8) {
                ForEach(PersonProfile.Tone.allCases) { tone in
                    ToneCard(tone: tone, selected: person.profile.tone == tone) {
                        person.profile.tone = person.profile.tone == tone ? nil : tone
                    }
                }
            }
            OnboardingField(symbol: "text.bubble", placeholder: tr("Sonst noch etwas? z. B. Montags keine Meetings (optional)", "Anything else? e.g. No meetings on Mondays (optional)"),
                            text: $person.profile.note)
        }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !person.profile.isEmpty { summary }
            caption(tr("So erreichst du mich", "How to reach me"), symbol: "keyboard")
            HStack(spacing: 8) {
                shortcut("⌃⌥ F", tr("Öffnen", "Open"))
                shortcut("⌃⌥ V", tr("Diktieren", "Dictate"))
            }
            Button(action: openWindow) {
                Label(tr("Als großes Fenster öffnen", "Open as a big window"), systemImage: "macwindow")
                    .font(.fenn(size: 13, weight: .medium))
            }
            .buttonStyle(FennPillButtonStyle())
        }
        .onAppear { Celebration.shared.fire() }
    }

    /// What Fenn now knows – one line per answer, each with its icon.
    private var summary: some View {
        let p = person.profile
        let rows: [(String, String)] = [
            p.role.isEmpty ? nil : ("briefcase.fill", p.role),
            p.focusTime.map { ($0.symbol, tr("Fokus am besten: \($0.title)", "Best focus: \($0.title)")) },
            p.goal.isEmpty ? nil : ("flag.fill", p.goal),
            p.helpWith.isEmpty ? nil : ("hand.raised.fill", p.helpWith.map(\.title).joined(separator: ", ")),
            p.tone.map { ("bubble.left.fill", $0.title) },
        ].compactMap { $0 }
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                Staggered(index: index) {
                    HStack(spacing: 10) {
                        Image(systemName: row.0).font(.system(size: 13, weight: .semibold)).foregroundStyle(Fenn.accent).frame(width: 22)
                        Text(row.1).font(.fenn(size: 13)).foregroundStyle(Fenn.fg.opacity(0.85)).lineLimit(2)
                    }
                }
            }
            Text(tr("Ändern kannst du alles unter Verbindungen › Über dich.", "Change anything under Connections › About you."))
                .font(.fenn(size: 11)).foregroundStyle(Fenn.fg.opacity(0.45)).padding(.top, 2)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Fenn.fill))
    }

    // MARK: Pieces

    private var progress: some View {
        HStack(spacing: 5) {
            ForEach(0..<steps, id: \.self) { index in
                Capsule()
                    .fill(index <= step ? Fenn.accent : Fenn.fillStrong)
                    .frame(width: index == step ? 22 : 8, height: 6)
            }
            Spacer()
            if (1...4).contains(step) {
                Text(tr("Frage \(step) von 4", "Question \(step) of 4"))
                    .font(.fenn(size: 11, weight: .medium)).foregroundStyle(Fenn.fg.opacity(0.45))
                    .contentTransition(.numericText())
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: step)
    }

    private var buttons: some View {
        HStack {
            if step > 0 {
                Button { go(step - 1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(FennPillButtonStyle())
                    .help(tr("Zurück", "Back"))
            }
            Spacer()
            if (1...6).contains(step) {
                Button(tr("Überspringen", "Skip")) { go(step + 1) }
                    .buttonStyle(.plain)
                    .font(.fenn(size: 13))
                    .foregroundStyle(Fenn.fg.opacity(0.55))
            }
            Button(action: next) {
                HStack(spacing: 6) {
                    Text(step == 0 ? tr("Klar, los geht's", "Sure, let's go") : step == steps - 1 ? tr("Fertig", "Done") : tr("Weiter", "Next"))
                    Image(systemName: step == steps - 1 ? "checkmark" : "arrow.right")
                }
            }
            .buttonStyle(FennPillButtonStyle(prominent: true))
            .keyboardShortcut(.defaultAction)
        }
    }

    private func caption(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.fenn(size: 12.5, weight: .medium))
            .foregroundStyle(Fenn.fg.opacity(0.7))
    }

    private func promise(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            ClaySymbol(symbol: symbol, size: 24)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Fenn.accent.opacity(0.14)))
            Text(text).font(.fenn(size: 13.5)).foregroundStyle(Fenn.fg.opacity(0.88)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Fenn.fill))
    }

    private func shortcut(_ keys: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Text(keys)
                .font(.fenn(size: 12, weight: .semibold, design: .rounded))
                .padding(.horizontal, 8)
                .frame(minHeight: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(Fenn.fillStrong))
            Text(text).font(.fenn(size: 13))
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Fenn.fill))
    }

    /// Moves on and remembers where the setup is; the goal lands in goals.md once its step is left.
    private func go(_ target: Int) {
        if step == 3 { person.commitGoal() }
        forward = target > step
        reaction = nil
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.86)) {
            step = max(0, min(target, steps - 1))
        }
        UserDefaults.standard.set(step, forKey: PersonProfileStore.stepKey)
    }

    private func next() {
        if step < steps - 1 {
            go(step + 1)
        } else {
            person.commitGoal()
            person.writeProfile()
            UserDefaults.standard.removeObject(forKey: PersonProfileStore.stepKey)
            finish()
        }
    }
}

// MARK: - Onboarding pieces

/// Fenn with a speech bubble: the pebble floats a little and wakes up, the line types itself in, and a short reaction
/// to the last answer pops up underneath.
private struct OnboardingFenn: View {
    let line: String
    let reaction: String?
    let mood: PebbleFace.Mood
    var big = false
    @State private var shown = 0
    @State private var float = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(PebbleMac.image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .overlay { PebbleFace(mood: mood, blush: true) }
                .compositingGroup()
                .frame(width: big ? 84 : 58, height: big ? 84 : 58)
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                .offset(y: float ? -3 : 3)
                .animation(reduceMotion ? nil : .easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: float)
            VStack(alignment: .leading, spacing: 6) {
                Text(String(line.prefix(shown)))
                    .font(.fenn(size: big ? 16 : 14.5))
                    .foregroundStyle(Fenn.fg)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Keeps the bubble at its final height while the text types in.
                    .background(alignment: .topLeading) {
                        Text(line).font(.fenn(size: big ? 16 : 14.5)).hidden().fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(BubbleShape().fill(Fenn.fillStrong))
                if let reaction {
                    Label(reaction, systemImage: "sparkles")
                        .font(.fenn(size: 12.5, weight: .medium))
                        .foregroundStyle(Fenn.accent)
                        .padding(.leading, 14)
                        .transition(.scale(scale: 0.85, anchor: .leading).combined(with: .opacity))
                }
            }
        }
        .task(id: line) {
            float = true
            guard !reduceMotion else { shown = line.count; return }
            shown = 0
            for count in 1...max(1, line.count) {
                try? await Task.sleep(for: .milliseconds(14))
                if Task.isCancelled { return }
                shown = count
            }
        }
    }
}

/// A speech bubble with a small tail towards Fenn on the left.
private struct BubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: 16, style: .continuous)
        path.move(to: CGPoint(x: rect.minX + 1, y: rect.minY + 16))
        path.addLine(to: CGPoint(x: rect.minX - 7, y: rect.minY + 22))
        path.addLine(to: CGPoint(x: rect.minX + 1, y: rect.minY + 28))
        path.closeSubpath()
        return path
    }
}

/// A choice as a tile with its icon; picking it bounces the icon and shows a check.
private struct OptionTile: View {
    let symbol: String
    let title: String
    let selected: Bool
    var compact = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { action() } }) {
            Group {
                if compact {
                    VStack(spacing: 6) {
                        icon
                        Text(title).font(.fenn(size: 12, weight: .medium)).multilineTextAlignment(.center).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 74)
                } else {
                    HStack(spacing: 10) {
                        icon
                        Text(title).font(.fenn(size: 12.5, weight: .medium)).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                }
            }
            .foregroundStyle(Fenn.fg)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(selected ? Fenn.accent.opacity(0.22) : Fenn.fill))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(selected ? Fenn.accent : (hover ? Fenn.hairline : .clear), lineWidth: selected ? 1.5 : 1))
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Fenn.accent)
                        .padding(6)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .scaleEffect(selected ? 1.02 : (hover ? 1.01 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
    }

    private var icon: some View {
        Image(systemName: symbol)
            .font(.system(size: compact ? 18 : 15, weight: .semibold))
            .foregroundStyle(selected ? Fenn.accent : Fenn.fg.opacity(0.7))
            .frame(width: 30, height: 30)
            .background(Circle().fill(selected ? Fenn.accent.opacity(0.18) : Fenn.fillStrong))
            .symbolEffect(.bounce, value: selected)
    }
}

/// How Fenn would answer in this tone – a small sample reply instead of an abstract label.
private struct ToneCard: View {
    let tone: PersonProfile.Tone
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { action() } }) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: tone.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(selected ? Fenn.accent : Fenn.fg.opacity(0.7))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(selected ? Fenn.accent.opacity(0.18) : Fenn.fillStrong))
                    .symbolEffect(.bounce, value: selected)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tone.title).font(.fenn(size: 13, weight: .medium)).foregroundStyle(Fenn.fg)
                    Text("„\(tone.sample)“").font(.fenn(size: 12)).italic().foregroundStyle(Fenn.fg.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Fenn.accent : Fenn.fg.opacity(0.3))
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(selected ? Fenn.accent.opacity(0.18) : Fenn.fill))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(selected ? Fenn.accent : .clear, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// A text field with an icon, a little larger than the app's settings fields.
private struct OnboardingField: View {
    let symbol: String
    let placeholder: String
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(focused || !text.isEmpty ? Fenn.accent : Fenn.fg.opacity(0.45))
                .frame(width: 20)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.fenn(size: 14))
                .focused($focused)
            if !text.isEmpty {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Fenn.accent).transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Fenn.field))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(focused ? Fenn.accent : Fenn.hairline, lineWidth: focused ? 1.5 : 1))
        .animation(.easeOut(duration: 0.18), value: focused)
        .animation(.spring(response: 0.3), value: text.isEmpty)
    }
}

/// The working day on a 24-hour bar: the highlighted span is the working time, the steppers move its ends.
private struct DayBar: View {
    @Binding var start: Int
    @Binding var end: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let hour = geo.size.width / 24
                ZStack(alignment: .leading) {
                    Capsule().fill(Fenn.fillStrong)
                    Capsule()
                        .fill(LinearGradient(colors: [Fenn.accent.opacity(0.6), Fenn.accent], startPoint: .leading, endPoint: .trailing))
                        .frame(width: CGFloat(end - start) * hour)
                        .offset(x: CGFloat(start) * hour)
                    HStack(spacing: 0) {
                        Image(systemName: "sunrise.fill").offset(x: CGFloat(6) * hour - 7)
                        Spacer()
                        Image(systemName: "moon.stars.fill").offset(x: -CGFloat(2) * hour)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(Fenn.fg.opacity(0.35))
                }
            }
            .frame(height: 18)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: start)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: end)
            HStack {
                Stepper(tr("ab \(start):00", "from \(start):00"), value: $start, in: 4...(end - 1))
                Spacer()
                Stepper(tr("bis \(end):00", "until \(end):00"), value: $end, in: (start + 1)...23)
            }
            .font(.fenn(size: 13, weight: .medium))
        }
    }
}

/// Fades and lifts its content in, one after the other.
private struct Staggered<Content: View>: View {
    let index: Int
    @ViewBuilder let content: () -> Content
    @State private var visible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content()
            .opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : 10)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85).delay(0.25 + Double(index) * 0.12)) { visible = true }
            }
    }
}

// MARK: - Short tour

/// A few cards over the real app, once after install. The setup wizard stays separate.
struct MacIntroStep {
    var module: IslandModule
    var symbol: String
    var title: String
    var text: String
}

@MainActor
final class MacIntro: ObservableObject {
    static let shared = MacIntro()
    static let doneKey = "fenn.mac.intro.v1"

    @Published private(set) var index: Int?
    private(set) var steps: [MacIntroStep] = []

    var isRunning: Bool { index != nil }
    var current: MacIntroStep? { index.flatMap { steps.indices.contains($0) ? steps[$0] : nil } }

    /// New installs and this update see it once. Replaying from the menu does not check this.
    static var needsIntro: Bool {
        !FennDemo.isOn && !UserDefaults.standard.bool(forKey: doneKey)
    }

    func start() {
        steps = Self.make()
        index = 0
    }

    func next() {
        guard let index else { return }
        if index + 1 < steps.count { self.index = index + 1 } else { finish() }
    }

    func back() {
        guard let index, index > 0 else { return }
        self.index = index - 1
    }

    func finish() {
        index = nil
        UserDefaults.standard.set(true, forKey: Self.doneKey)
    }

    private static func make() -> [MacIntroStep] {
        [
            MacIntroStep(module: .today, symbol: "sun.max",
                         title: tr("Dein Tag", "Your day"),
                         text: tr("Heute zeigt Kalender, Aufgaben, Routinen und Fokus. Unten unter „Startseite anpassen“ sortierst du die Karten, blendest sie aus oder holst neue dazu. Ein Rechtsklick auf eine Karte geht auch.",
                                  "Today shows calendar, tasks, routines and focus. “Customise home” at the bottom reorders cards, hides them or adds new ones. A right-click on a card works too.")),
            MacIntroStep(module: .focus, symbol: "timer",
                         title: tr("Fokus", "Focus"),
                         text: tr("Pomodoro mit eigenen Längen. Der Start ist 8 Stunden, 50 Minuten Arbeit und 10 Minuten Pause – alles frei änderbar, auch per Sprache. Dazu Fokusmusik und Zeitregeln, zum Beispiel 6–8 Uhr kein Social Media.",
                                  "A Pomodoro with your own lengths. It starts at 8 hours, 50 minutes of work and 10 minutes of break – all adjustable, by voice too. Plus focus music and time rules, for example no social media from 6 to 8.")),
            MacIntroStep(module: .tasks, symbol: "checklist",
                         title: tr("Aufgaben und Routinen", "Tasks and routines"),
                         text: tr("To-dos mit Termin und Priorität, daneben kleine Gewohnheiten mit Serie. Was du hier oder im Widget abhakst, ist dieselbe Liste.",
                                  "To-dos with dates and priorities, plus small habits with a streak. What you tick here or in the widget is the same list.")),
            MacIntroStep(module: .journal, symbol: "book.closed",
                         title: tr("Notizen und Journal", "Notes and journal"),
                         text: tr("Notizen, Ideen und das Journal – morgens planen, abends zurückblicken – liegen unter Mehr und schreiben in deinen Fenn-Ordner.",
                                  "Notes, ideas and the journal – plan in the morning, look back at night – sit under More and write to your Fenn folder.")),
            MacIntroStep(module: .coach, symbol: "sparkles",
                         title: tr("Frag Fenn", "Ask Fenn"),
                         text: tr("Eine Frage reicht: eintragen, planen, starten. ⌃⌥ F öffnet Fenn, ⌃⌥ V diktiert.",
                                  "One question is enough: log, plan, start. ⌃⌥ F opens Fenn, ⌃⌥ V dictates.")),
            MacIntroStep(module: .today, symbol: "square.grid.2x2",
                         title: tr("Widgets", "Widgets"),
                         text: tr("In der Mitteilungszentrale unter Fenn: Heute, Aufgaben, Routinen und ein Pomodoro, der weiterläuft, auch wenn Fenn zu ist.",
                                  "In Notification Center under Fenn: Today, tasks, routines and a Pomodoro that keeps running even when Fenn is closed.")),
        ]
    }
}

/// A card over the open panel. The module behind it is the one the step is about.
struct MacIntroOverlay: View {
    @ObservedObject var intro: MacIntro

    var body: some View {
        if let step = intro.current, let index = intro.index {
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.45)
                    .contentShape(Rectangle())
                    .onTapGesture {}
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        ClaySymbol(symbol: step.symbol, size: 28)
                            .frame(width: 28)
                        Text(step.title).font(Fenn.display(18)).foregroundStyle(Fenn.fg)
                            .lineLimit(2).minimumScaleFactor(0.85)
                        Spacer(minLength: 0)
                        Text("\(index + 1)/\(intro.steps.count)")
                            .font(.fenn(size: 12, weight: .medium)).monospacedDigit()
                            .foregroundStyle(Fenn.fg.opacity(0.5))
                    }
                    Text(step.text)
                        .font(.fenn(size: 13))
                        .foregroundStyle(Fenn.fg.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        if index + 1 < intro.steps.count {
                            Button(tr("Überspringen", "Skip")) { intro.finish() }
                                .buttonStyle(.plain)
                                .font(.fenn(size: 13))
                                .foregroundStyle(Fenn.fg.opacity(0.55))
                        }
                        Spacer(minLength: 0)
                        if index > 0 {
                            Button(tr("Zurück", "Back")) { intro.back() }
                                .buttonStyle(FennPillButtonStyle())
                        }
                        Button(index + 1 < intro.steps.count ? tr("Weiter", "Next") : tr("Los geht's", "Let's go")) { intro.next() }
                            .buttonStyle(FennPillButtonStyle(prominent: true))
                            .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Fenn.canvas))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Fenn.accent.opacity(0.35), lineWidth: 1))
                .padding(14)
            }
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
    }
}
