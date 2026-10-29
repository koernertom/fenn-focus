import Foundation

/// One older thought brought back each day: a journal entry or a note – "Heute vor einem Monat" first,
/// otherwise a different one every day (stable within the day, so it doesn't jump around).
struct ResurfaceItem: Identifiable, Equatable {
    enum Source: Equatable { case journal, note }

    var id: String { "\(source)-\(FennVault.dayKey(date))-\(title)" }
    let source: Source
    let date: Date
    let title: String
    let text: String
    var url: URL?

    /// "Heute vor einem Jahr", "Vor 5 Wochen"
    func when(now: Date = Date()) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if let anniversary = Resurface.anniversaries.first(where: { Resurface.isAnniversary(date, $0.component, $0.value, now: now) }) {
            return anniversary.label
        }
        if days >= 60 { return tr("Vor \(days / 30) Monaten", "\(days / 30) months ago") }
        if days >= 14 { return tr("Vor \(days / 7) Wochen", "\(days / 7) weeks ago") }
        return tr("Vor \(days) Tagen", "\(days) days ago")
    }

    var sourceTitle: String { source == .journal ? "Journal" : tr("Notiz", "Note") }
}

enum Resurface {
    static var anniversaries: [(component: Calendar.Component, value: Int, label: String)] { [
        (.year, 1, tr("Heute vor einem Jahr", "One year ago today")),
        (.month, 6, tr("Heute vor einem halben Jahr", "Six months ago today")),
        (.month, 3, tr("Heute vor drei Monaten", "Three months ago today")),
        (.month, 1, tr("Heute vor einem Monat", "One month ago today")),
        (.weekOfYear, 1, tr("Heute vor einer Woche", "One week ago today")),
    ] }

    static func isAnniversary(_ date: Date, _ component: Calendar.Component, _ value: Int, now: Date) -> Bool {
        guard let then = Calendar.current.date(byAdding: component, value: -value, to: now) else { return false }
        return Calendar.current.isDate(date, inSameDayAs: then)
    }

    /// Anniversaries first, then something older than a week, then older than two days – picked by the date, not at random.
    static func pick(_ items: [ResurfaceItem], now: Date = Date()) -> ResurfaceItem? {
        let usable = items.filter { $0.text.count >= 20 }
        for anniversary in anniversaries {
            if let item = usable.first(where: { isAnniversary($0.date, anniversary.component, anniversary.value, now: now) }) { return item }
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        for minimum in [7, 2] {
            let pool = usable.filter { (calendar.dateComponents([.day], from: calendar.startOfDay(for: $0.date), to: today).day ?? 0) >= minimum }
                .sorted { $0.date > $1.date }
            guard !pool.isEmpty else { continue }
            let seed = calendar.ordinality(of: .day, in: .era, for: now) ?? 0
            return pool[seed % pool.count]
        }
        return nil
    }

    /// Markdown notes or journal days → items. The date comes from the file name ("2026-09-24 0915 …" / "2026-09-24.md").
    static func items(from files: [URL], source: ResurfaceItem.Source) -> [ResurfaceItem] {
        files.compactMap { url -> ResurfaceItem? in
            let name = url.deletingPathExtension().lastPathComponent
            guard name.count >= 10, let date = FennVault.dayFormatter.date(from: String(name.prefix(10))),
                  let text = FennVault.readText(url) else { return nil }
            var title = String(name.dropFirst(10)).trimmingCharacters(in: CharacterSet(charactersIn: " -"))
            if let range = title.range(of: #"^\d{4} "#, options: .regularExpression) { title.removeSubrange(range) }
            if !title.contains(" ") { title = title.replacingOccurrences(of: "-", with: " ") }
            if title.isEmpty { title = source == .journal ? date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: tr("de_DE", "en_GB")))) : tr("Notiz", "Note") }
            return ResurfaceItem(source: source, date: date, title: title.prefix(1).uppercased() + title.dropFirst(), text: excerpt(text), url: url)
        }
    }

    /// The readable part: no headings, front matter, table rows or tags – a few sentences.
    static func excerpt(_ markdown: String, limit: Int = 260) -> String {
        var lines: [String] = []
        var inFront = false
        for (index, raw) in markdown.components(separatedBy: .newlines).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line == "---" { if index == 0 || inFront { inFront.toggle() }; continue }
            if inFront || line.isEmpty || line.hasPrefix("#") || line.hasPrefix("|") || line.hasPrefix("_") || line.hasPrefix("<!--") { continue }
            // Journal files: bold lines are the questions, "Stimmung 4/5 · …" the scales, "> Fenn:" the coach – only the own words stay.
            if line.hasPrefix("**") && line.hasSuffix("**") { continue }
            if line.range(of: #"\b[1-5]/5\b"#, options: .regularExpression) != nil, line.count < 120 { continue }
            if line.hasPrefix("> Fenn:") || line.hasPrefix("Fenn:") { continue }
            var clean = line
            for prefix in ["- [ ] ", "- [x] ", "- ", "* ", "> "] where clean.hasPrefix(prefix) { clean = String(clean.dropFirst(prefix.count)) }
            clean = clean.replacingOccurrences(of: "**", with: "")
            // "Frage: Antwort" lines from the journal read better as just the answer.
            if let colon = clean.range(of: ": "), clean.distance(from: clean.startIndex, to: colon.lowerBound) < 60, clean.hasSuffix("?") == false,
               clean[..<colon.lowerBound].hasSuffix("?") { clean = String(clean[colon.upperBound...]) }
            guard clean.count > 2 else { continue }
            lines.append(clean)
            if lines.joined(separator: " ").count > limit { break }
        }
        let text = lines.joined(separator: " ")
        return text.count > limit ? String(text.prefix(limit)).trimmingCharacters(in: .whitespaces) + " …" : text
    }
}
