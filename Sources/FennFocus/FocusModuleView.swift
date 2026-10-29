import SwiftUI
import FennFocusCore

/// Pomodoro: the dial first, interval presets right under it (4 × 25 is the classic Pomodoro),
/// the rhythm (work, break, rounds) as three small tiles, one prominent start – and what happens during focus below.
struct FocusModuleView: View {
    @ObservedObject var focus: FocusTimer
    /// Today's priorities from the journal's day plan.
    let tasks: [String]
    @ObservedObject private var store = TaskStore.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if focus.isActive { running } else { setup }
                taskPicker
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle(tr("Während des Fokus", "During focus"))
                    MacBlockCard(blocker: MacBlocker.shared)
                    FocusMusicCard()
                }
                .frame(maxWidth: 460)
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.never)
    }

    // MARK: Before the start

    private var setup: some View {
        VStack(spacing: 16) {
            FocusDialTimer(minutes: focus.focusMinutes, text: focus.label,
                           caption: focus.usesStarter ? tr("Arbeitstag, 50/10", "Work day, 50/10")
                                                      : "\(rounds) × \(focus.focusMinutes) min",
                           size: 210) { minutes in
                setIntervals(work: FocusDial.minutes(at: FocusDial.index(of: minutes)), brk: focus.breakMinutes, rounds: rounds)
            }
            .padding(.top, 6)
            .help(tr("Im Kreis ziehen", "Drag around"))
            presets
            rhythm
            Button { focus.start() } label: {
                Text(tr("Jetzt starten", "Start now")).frame(maxWidth: .infinity)
            }
            .buttonStyle(FennPillButtonStyle(prominent: true))
            .frame(maxWidth: 460)
            Text(windowNote)
                .font(.fenn(size: 12, weight: .light))
                .foregroundStyle(Fenn.fg.opacity(0.55))
                .multilineTextAlignment(.center)
        }
    }

    /// Four presets: 4 × 25 (5 min breaks), 3 × 50, 2 × 90 and the work day (8 h in 50/10 blocks).
    private static let intervals: [(work: Int, brk: Int, rounds: Int)] = [(25, 5, 4), (50, 10, 3), (90, 15, 2)]

    private var presets: some View {
        HStack(spacing: 8) {
            ForEach(Self.intervals, id: \.work) { item in
                chip("\(item.rounds) × \(item.work)", selected: !focus.usesStarter && focus.focusMinutes == item.work
                     && focus.breakMinutes == item.brk && rounds == item.rounds) {
                    setIntervals(work: item.work, brk: item.brk, rounds: item.rounds)
                }
            }
            chip(tr("Arbeitstag", "Work day"), selected: focus.usesStarter) { focus.applyStarter() }
        }
        .frame(maxWidth: 460)
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.fenn(size: 13, weight: selected ? .medium : .regular))
                .lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(selected ? Fenn.onSelected : Fenn.fg)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(Capsule().fill(selected ? Fenn.selected : Fenn.fill))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Work, break and rounds side by side, each with − and +.
    private var rhythm: some View {
        let work = focus.focusMinutes, brk = focus.breakMinutes, count = rounds
        return HStack(spacing: 0) {
            tile(tr("ARBEIT", "WORK"), "\(work) min",
                 minus: { setIntervals(work: max(5, work - 5), brk: brk, rounds: count) },
                 plus: { setIntervals(work: work + 5, brk: brk, rounds: count) })
            Divider().overlay(Fenn.hairline).padding(.vertical, 12)
            tile(tr("PAUSE", "BREAK"), "\(brk) min",
                 minus: { setIntervals(work: work, brk: max(1, brk - 1), rounds: count) },
                 plus: { setIntervals(work: work, brk: brk + 1, rounds: count) })
            Divider().overlay(Fenn.hairline).padding(.vertical, 12)
            tile(tr("RUNDEN", "ROUNDS"), "\(count)×",
                 minus: { setIntervals(work: work, brk: brk, rounds: count - 1) },
                 plus: { setIntervals(work: work, brk: brk, rounds: count + 1) })
        }
        .fennGlass(cornerRadius: 20, shadow: false)
        .frame(maxWidth: 460)
    }

    private func tile(_ label: String, _ value: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            Text(label).font(.fenn(size: 10, weight: .medium)).tracking(1).foregroundStyle(Fenn.fg.opacity(0.55))
            Text(value).font(Fenn.display(19)).foregroundStyle(Fenn.fg).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
            HStack(spacing: 6) {
                stepButton("minus", tr("weniger", "less"), action: minus)
                stepButton("plus", tr("mehr", "more"), action: plus)
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func stepButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.fenn(size: 12, weight: .medium))
                .foregroundStyle(Fenn.fg)
                .frame(width: 34, height: 26)
                .background(Capsule().fill(Fenn.fill))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// "Gesamt 1:55 h · danach 15–30 min lange Pause" – the Pomodoro rule after a set of four.
    private var windowNote: String {
        let total = tr("Gesamt \(FocusDial.label(focus.totalMinutes))", "Total \(FocusDial.label(focus.totalMinutes))")
        guard !focus.usesStarter, focus.focusMinutes <= 30, rounds >= 3 else {
            return tr("\(total), \(focus.breakMinutes) min Pause zwischen den Runden", "\(total), \(focus.breakMinutes) min break between rounds")
        }
        return tr("\(total), danach 15–30 min lange Pause", "\(total), then a long break of 15–30 min")
    }

    // MARK: Running

    private var running: some View {
        VStack(spacing: 16) {
            AuraTimer(text: focus.label, progress: focus.progress,
                      caption: "\(focus.phaseTitle), \(tr("Runde \(currentRound) von \(rounds)", "round \(currentRound) of \(rounds)"))",
                      palette: isBreak ? .stone : .steady, size: 210)
                .padding(.top, 6)
            if rounds <= 12 { roundDots }
            HStack(spacing: 8) {
                Button(focus.isRunning ? tr("Pause", "Pause") : tr("Weiter", "Resume")) {
                    focus.isRunning ? focus.pause() : focus.start()
                }
                .buttonStyle(FennPillButtonStyle(prominent: true))
                Button(tr("Beenden", "Stop")) { focus.stop() }
                    .buttonStyle(FennPillButtonStyle())
                Button("+5 min") { focus.addFiveMinutes() }
                    .buttonStyle(FennPillButtonStyle())
            }
            Text(tr("Noch \(focus.sessionLabel) insgesamt", "\(focus.sessionLabel) left in total"))
                .font(.fenn(size: 12, weight: .light)).foregroundStyle(Fenn.fg.opacity(0.55))
                .monospacedDigit()
        }
    }

    /// One dot per round: filled when done, ringed for the one running.
    private var roundDots: some View {
        HStack(spacing: 10) {
            ForEach(0..<rounds, id: \.self) { index in
                let done = index < focus.completedBlocks
                let current = index == focus.completedBlocks && !isBreak
                Circle()
                    .fill(done ? Fenn.accent : Color.clear)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().strokeBorder(done || current ? Fenn.accent : Fenn.fg.opacity(0.25), lineWidth: 1.5))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("\(min(focus.completedBlocks, rounds)) von \(rounds) Runden geschafft",
                               "\(min(focus.completedBlocks, rounds)) of \(rounds) rounds done"))
    }

    // MARK: What you're working on (Mac only: tasks are right here)

    private var taskPicker: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "pencil").font(.fenn(size: 12)).foregroundStyle(Fenn.fg.opacity(0.45))
                TextField(tr("Woran arbeitest du?", "What are you working on?"), text: $focus.taskTitle)
                    .textFieldStyle(.plain)
                    .font(.fenn(size: 14))
                    .foregroundStyle(Fenn.fg)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: 460, minHeight: 38)
            .background(Capsule().fill(Fenn.field))
            .overlay(Capsule().strokeBorder(Fenn.hairline))
            let next = store.next(3)
            if !next.isEmpty {
                HStack(spacing: 6) {
                    ForEach(next) { task in
                        let selected = focus.taskId == task.id
                        taskChip(task.title, dot: task.priority.color, selected: selected) {
                            focus.focus(on: selected ? nil : task)
                        }
                        .help(task.estimateMinutes.map { tr("Geschätzt \(TaskFormat.duration($0)), bisher \(TaskFormat.duration(task.spentMinutes))", "Estimate \(TaskFormat.duration($0)), so far \(TaskFormat.duration(task.spentMinutes))") } ?? task.topicTitle)
                    }
                }
            } else if !tasks.isEmpty {
                HStack(spacing: 6) {
                    ForEach(tasks.prefix(3), id: \.self) { task in
                        taskChip(task, dot: nil, selected: focus.taskTitle == task) {
                            focus.focus(on: nil)
                            focus.taskTitle = task
                        }
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private func taskChip(_ title: String, dot: Color?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let dot { Circle().fill(dot).frame(width: 6, height: 6) }
                Text(title).lineLimit(1).truncationMode(.tail).frame(maxWidth: 140)
            }
            .font(.fenn(size: 12, weight: .medium))
            .foregroundStyle(selected ? Fenn.onSelected : Fenn.fg)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(selected ? Fenn.selected : Fenn.fill))
        }
        .buttonStyle(.plain)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased()).font(.fenn(size: 11, weight: .medium)).tracking(1.2).foregroundStyle(Fenn.fg.opacity(0.5))
    }

    // MARK: Rounds on top of the Mac's window/work/break settings

    private var isBreak: Bool { focus.phase == .shortBreak || focus.phase == .longBreak }

    /// The window holds n work blocks with n − 1 breaks between them – the "rounds".
    private var rounds: Int {
        let cycle = focus.focusMinutes + focus.breakMinutes
        return max(1, Int((Double(focus.totalMinutes + focus.breakMinutes) / Double(max(1, cycle))).rounded()))
    }

    private var currentRound: Int { min(rounds, focus.completedBlocks + (isBreak ? 0 : 1)) }

    private func setIntervals(work: Int, brk: Int, rounds: Int) {
        let count = min(max(1, rounds), 16)
        focus.setWorkMinutes(work)
        focus.setBreakMinutes(brk)
        focus.setTotalMinutes(count * work + (count - 1) * brk)
    }
}
