import SwiftUI

/// Journal on the Mac: the written kinds, stored in `journal/<day>.md` in the Fenn folder.
struct JournalModuleView: View {
    @State private var kind: JournalKind = .suggested()
    @State private var answers: [String] = []
    @State private var scales: [CheckInScale: Int] = [:]
    @State private var priorities = ""
    @State private var saved = false
    @State private var history: [(name: String, text: String)] = []
    /// The last seven days (oldest first) with their entry count and check-in mood, read from journal/<day>.md.
    @State private var week: [(key: String, entries: Int, mood: Double?)] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Journal").font(Fenn.display(22)).foregroundStyle(Fenn.fg)
                weekStrip
                Text(tr("SCHREIBEN", "WRITE")).font(.fenn(size: 11, weight: .medium)).tracking(1.2).foregroundStyle(Fenn.fg.opacity(0.5))
                formats
                    .onChange(of: kind) { _, _ in resetFields() }

                if kind == .checkIn {
                    ForEach(CheckInScale.allCases) { scale in
                        HStack {
                            Text(scale.title).font(.fenn(size: 13)).foregroundStyle(Fenn.fg).frame(width: 110, alignment: .leading)
                            Spacer()
                            ForEach(1...5, id: \.self) { value in
                                Button("\(value)") { scales[scale] = value }
                                    .buttonStyle(.plain)
                                    .font(.fenn(size: 12, weight: .medium))
                                    .foregroundStyle(scales[scale] == value ? Fenn.onSelected : Fenn.fg)
                                    .frame(width: 28, height: 28)
                                    .background(Circle().fill(scales[scale] == value ? Fenn.selected : Fenn.fill))
                            }
                        }
                    }
                }

                if kind == .planDay {
                    TextField(tr("Bis zu drei Prioritäten, eine pro Zeile", "Up to three priorities, one per line"), text: $priorities, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.fenn(size: 14))
                        .lineLimit(3...5)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Fenn.field))
                }

                ForEach(Array(kind.questions.enumerated()), id: \.offset) { index, question in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(question).font(.fenn(size: 13, weight: .medium)).foregroundStyle(Fenn.fg)
                        TextField(tr("Antwort", "Answer"), text: binding(index), axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.fenn(size: 14))
                            .lineLimit(2...5)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Fenn.field))
                    }
                }

                Button {
                    save()
                } label: {
                    Label(saved ? tr("Gespeichert", "Saved") : tr("Ins Journal", "Save to journal"), systemImage: saved ? "checkmark" : "book.closed")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FennPillButtonStyle(prominent: true))
                .disabled(!canSave)

                if !history.isEmpty {
                    Text(tr("Letzte Tage", "Recent days")).font(.fenn(size: 12, weight: .semibold)).foregroundStyle(Fenn.fg.opacity(0.55))
                    ForEach(history, id: \.name) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(Self.dayTitle(item.name)).font(.fenn(size: 12, weight: .medium)).foregroundStyle(Fenn.accent)
                            JournalPreview(markdown: item.text)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fennGlass(cornerRadius: 16, shadow: false)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
        .onAppear {
            resetFields()
            loadHistory()
            loadWeek()
        }
    }

    // MARK: Week

    /// Seven days with the check-in mood as a bar – a glance at how the week felt.
    private var weekStrip: some View {
        let entries = week.reduce(0) { $0 + $1.entries }
        let moods = week.compactMap(\.mood)
        let average = moods.isEmpty ? nil : moods.reduce(0, +) / Double(moods.count)
        let today = FennVault.dayKey(Date())
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(tr("LETZTE 7 TAGE", "LAST 7 DAYS")).font(.fenn(size: 11, weight: .medium)).tracking(1.2).foregroundStyle(Fenn.fg.opacity(0.5))
                Spacer()
                Text(tr("\(entries) Einträge", "\(entries) entries")
                     + (average.map { tr(", Stimmung Ø \(Self.decimal($0))", ", mood avg \(Self.decimal($0))") } ?? ""))
                    .font(.fenn(size: 12)).foregroundStyle(Fenn.fg.opacity(0.55))
            }
            HStack(spacing: 6) {
                ForEach(week, id: \.key) { day in
                    let isToday = day.key == today
                    let ink = isToday ? Fenn.onSelected : Fenn.fg
                    let date = Self.keyDate(day.key)
                    VStack(spacing: 7) {
                        Text(date.formatted(.dateTime.weekday(.narrow).locale(Locale(identifier: tr("de_DE", "en_GB")))))
                            .font(.fenn(size: 11, weight: .semibold)).foregroundStyle(ink.opacity(0.6))
                        ZStack(alignment: .bottom) {
                            Capsule().fill(ink.opacity(isToday ? 0.22 : 0.08)).frame(width: 8, height: 40)
                            if let mood = day.mood {
                                Capsule().fill(isToday ? Fenn.onSelected : Fenn.accent).frame(width: 8, height: max(8, 40 * mood / 5))
                            } else if day.entries > 0 {
                                Circle().fill(isToday ? Fenn.onSelected : Fenn.accent).frame(width: 8, height: 8)
                            }
                        }
                        Text("\(Calendar.current.component(.day, from: date))").font(Fenn.display(15)).foregroundStyle(ink)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background { if isToday { Capsule().fill(Fenn.selected) } }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Self.dayTitle(day.key) + (day.mood.map { tr(", Stimmung \(Self.decimal($0))", ", mood \(Self.decimal($0))") } ?? "")
                                        + tr(", \(day.entries) Einträge", ", \(day.entries) entries"))
                }
            }
        }
        .padding(16)
        .fennGlass(cornerRadius: 26, shadow: false)
    }

    /// The four kinds as tiles, two per row – the chosen one filled, its questions below.
    private var formats: some View {
        let kinds = JournalKind.writable
        let rows = stride(from: 0, to: kinds.count, by: 2).map { Array(kinds[$0..<min($0 + 2, kinds.count)]) }
        return VStack(spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 10) {
                    ForEach(row, id: \.self) { item in
                        let selected = item == kind
                        Button { withAnimation(.snappy) { kind = item } } label: {
                            HStack(spacing: 10) {
                                ClaySymbol(symbol: item.symbol, size: 26, tint: selected ? Fenn.onSelected : Fenn.accent)
                                    .frame(width: 32, height: 32)
                                    .background(Circle().fill(selected ? Fenn.onSelected.opacity(0.16) : Fenn.accent.opacity(0.13)))
                                Text(item.title).font(.fenn(size: 14, weight: .semibold))
                                    .foregroundStyle(selected ? Fenn.onSelected : Fenn.fg)
                                    .lineLimit(1).minimumScaleFactor(0.85)
                                Spacer(minLength: 0)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background {
                                if selected { RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Fenn.selected) }
                            }
                            .fennGlass(cornerRadius: 20, shadow: false)
                            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
        }
    }

    private static func keyDate(_ key: String) -> Date {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        return parser.date(from: key) ?? Date()
    }

    private static func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: tr("de_DE", "en_GB"))))
    }

    /// Entries are the "## " headings; mood is "Stimmung 4/5" (or "Mood 4/5") in a check-in line.
    private func loadWeek() {
        let calendar = Calendar.current
        week = (0..<7).reversed().map { back in
            let date = calendar.date(byAdding: .day, value: -back, to: Date()) ?? Date()
            let key = FennVault.dayKey(date)
            let text = FennVault.readText(FennStorage.url(.journal(key))) ?? ""
            let lines = text.components(separatedBy: .newlines)
            let entries = lines.filter { $0.hasPrefix("## ") }.count
            let moods = lines.compactMap { line -> Double? in
                guard let range = line.range(of: #"(Stimmung|Mood) ([1-5])/5"#, options: .regularExpression) else { return nil }
                return line[range].split(separator: " ").last.flatMap { Double($0.prefix(1)) }
            }
            return (key, entries, moods.isEmpty ? nil : moods.reduce(0, +) / Double(moods.count))
        }
    }

    private var canSave: Bool {
        answers.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            || !priorities.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !scales.isEmpty
    }

    private func binding(_ index: Int) -> Binding<String> {
        Binding(get: { index < answers.count ? answers[index] : "" },
                set: { new in
                    if answers.count != kind.questions.count { answers = Array(repeating: "", count: kind.questions.count) }
                    if index < answers.count { answers[index] = new }
                })
    }

    private func resetFields() {
        answers = Array(repeating: "", count: kind.questions.count)
        scales = [:]
        priorities = ""
        saved = false
    }

    private func save() {
        var entry = JournalEntry(kind: kind, date: Date())
        entry.scales = scales
        entry.priorities = priorities
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(3)
            .map { $0 }
        entry.answers = zip(kind.questions, answers).map { JournalAnswer(question: $0.0, answer: $0.1) }
        let rendered = JournalMarkdown.render([entry])
        let body = rendered.components(separatedBy: "\n").drop(while: { !$0.hasPrefix("## ") }).joined(separator: "\n")
        let url = FennStorage.url(.journal(entry.day))
        if (FennVault.readText(url) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            FennVault.writeText(rendered, to: url)
        } else {
            FennVault.append("\n" + body + "\n", to: url, header: "")
        }
        if kind == .goals {
            let block = JournalMarkdown.goalBlock(entry)
            if !block.isEmpty {
                FennVault.append(block, to: FennStorage.url(.goals), header: "# \(tr("Ziele", "Goals"))\n")
            }
        }
        saved = true
        loadHistory()
        loadWeek()
    }

    /// "2026-10-04" → "Sonntag, 4. Oktober".
    private static func dayTitle(_ name: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: name) else { return name }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: tr("de_DE", "en_GB"))))
    }

    private func loadHistory() {
        let files = FennVault.files(in: FennStorage.url(.journalFolder), extension: "md").prefix(6)
        history = files.compactMap { url in
            guard let text = FennVault.readText(url), !text.isEmpty else { return nil }
            let clipped = String(text.prefix(700))
            return (url.deletingPathExtension().lastPathComponent, clipped)
        }
    }
}

/// A journal day as you'd read it, not as Markdown: section titles, bold questions, ticked or open boxes.
private struct JournalPreview: View {
    let markdown: String

    private enum Line: Hashable {
        case section(String)
        case text(String)
    }

    private var lines: [Line] {
        markdown.components(separatedBy: .newlines).compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("# ") { return nil }
            if line.hasPrefix("## ") { return .section(String(line.dropFirst(3))) }
            if line.hasPrefix("- [ ] ") { return .text("○ " + line.dropFirst(6)) }
            if line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") { return .text("✓ " + line.dropFirst(6)) }
            if line.hasPrefix("- ") { return .text("· " + line.dropFirst(2)) }
            return .text(line)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(lines.prefix(10).enumerated()), id: \.offset) { index, line in
                switch line {
                case .section(let title):
                    Text(title.uppercased())
                        .font(.fenn(size: 10, weight: .semibold)).tracking(1).foregroundStyle(Fenn.fg.opacity(0.5))
                        .padding(.top, index == 0 ? 0 : 6)
                case .text(let text):
                    Text((try? AttributedString(markdown: text)) ?? AttributedString(text))
                        .font(.fenn(size: 13)).foregroundStyle(Fenn.fg.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .textSelection(.enabled)
    }
}
