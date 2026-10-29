import SwiftUI

/// The building blocks of Heute.
enum HomeModule: String, CaseIterable, Identifiable {
    case calendar, tasks, habits, slipping, focus, journal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calendar: return tr("Kalender heute", "Today's calendar")
        case .habits: return tr("Routinen", "Routines")
        case .tasks: return tr("Aufgaben heute", "Today's tasks")
        case .slipping: return tr("Bleibt liegen", "Left lying")
        case .focus: return tr("Fokus starten", "Start focus")
        case .journal: return tr("Tag festhalten", "Capture the day")
        }
    }

    var source: String {
        switch self {
        case .calendar: return tr("Kalender", "Calendar")
        case .habits: return tr("Routinen", "Routines")
        case .tasks, .slipping: return tr("Aufgaben", "Tasks")
        case .focus: return tr("Fokus", "Focus")
        case .journal: return "Journal"
        }
    }

    var symbol: String {
        switch self {
        case .calendar: return "calendar.day.timeline.left"
        case .habits: return "repeat"
        case .tasks: return "checklist"
        case .slipping: return "hourglass"
        case .focus: return "timer"
        case .journal: return "book.closed"
        }
    }
}

enum HomeLayout {
    static let key = "fenn.home.modules"
    static let defaultModules = "calendar,tasks,habits,slipping,focus,journal"
    private static let none = "-"

    static func modules(_ stored: String) -> [HomeModule] {
        if stored == none { return [] }
        var order: [HomeModule] = []
        for module in stored.split(separator: ",").compactMap({ HomeModule(rawValue: String($0)) }) where !order.contains(module) {
            order.append(module)
        }
        return order.isEmpty ? modules(defaultModules) : order
    }

    static func others(_ stored: String) -> [HomeModule] {
        let shown = modules(stored)
        return HomeModule.allCases.filter { !shown.contains($0) }
    }

    static func store(_ modules: [HomeModule]) -> String {
        modules.isEmpty ? none : modules.map(\.rawValue).joined(separator: ",")
    }

    // MARK: Tile sizes

    /// Half or full width per tile, dragged at the tile's corner. Stored per Mac as "focus:s,calendar:l".
    static let sizesKey = "fenn.mac.home.sizes"

    static func size(of module: HomeModule, in stored: String) -> HomeTileSize {
        for pair in stored.split(separator: ",") {
            let parts = pair.split(separator: ":")
            if parts.count == 2, parts[0] == module.rawValue, let size = HomeTileSize(rawValue: String(parts[1])) { return size }
        }
        return defaultSize(module)
    }

    static func storing(_ size: HomeTileSize, for module: HomeModule, in stored: String) -> String {
        var pairs = stored.split(separator: ",").map(String.init).filter { !$0.hasPrefix(module.rawValue + ":") }
        pairs.append("\(module.rawValue):\(size.rawValue)")
        return pairs.joined(separator: ",")
    }

    /// Shortcuts and single numbers start small; everything with a list or a timeline starts wide.
    static func defaultSize(_ module: HomeModule) -> HomeTileSize {
        [.focus, .journal].contains(module) ? .s : .l
    }

    /// Wide tiles take a row; small ones pair up in order.
    static func rows(_ modules: [HomeModule], size: (HomeModule) -> HomeTileSize) -> [[HomeModule]] {
        var rows: [[HomeModule]] = []
        var waiting: HomeModule?
        for module in modules {
            if size(module) == .l {
                if let small = waiting { rows.append([small]); waiting = nil }
                rows.append([module])
            } else if let small = waiting {
                rows.append([small, module]); waiting = nil
            } else {
                waiting = module
            }
        }
        if let small = waiting { rows.append([small]) }
        return rows
    }
}

enum HomeTileSize: String {
    case s, l
}

/// "Startseite anpassen": what's on Heute and in which order. Up and down, because the island has no iOS edit handles.
struct HomeLayoutEditor: View {
    @AppStorage(HomeLayout.key) private var raw = HomeLayout.defaultModules
    @AppStorage(DayCalendarSize.key) private var calendarSize = DayCalendarSize.medium.rawValue
    let onDone: () -> Void

    private var shown: [HomeModule] { HomeLayout.modules(raw) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(tr("Startseite anpassen", "Customise home")).font(.fenn(size: 16, weight: .semibold)).foregroundStyle(Fenn.fg)
                Spacer()
                Button(tr("Fertig", "Done"), action: onDone).buttonStyle(FennPillButtonStyle(prominent: true))
            }
            .padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section(tr("Auf deiner Startseite", "On your home screen"),
                            footer: tr("Oben steht, was dir am wichtigsten ist. Minus blendet aus.",
                                       "What matters most goes on top. Minus hides it.")) {
                        ForEach(Array(shown.enumerated()), id: \.element) { index, module in
                            row(module) {
                                HStack(spacing: 4) {
                                    stepButton("chevron.up", help: tr("Nach oben", "Move up")) {
                                        move(module, by: -1)
                                    }
                                    .disabled(index == 0)
                                    stepButton("chevron.down", help: tr("Nach unten", "Move down")) {
                                        move(module, by: 1)
                                    }
                                    .disabled(index == shown.count - 1)
                                    stepButton("minus.circle.fill", help: tr("Ausblenden", "Hide")) {
                                        raw = HomeLayout.store(shown.filter { $0 != module })
                                    }
                                }
                            }
                        }
                    }
                    let others = HomeLayout.others(raw)
                    if !others.isEmpty {
                        section(tr("Weitere Bausteine", "More blocks"),
                                footer: tr("Tippen, um den Baustein unten anzuhängen.", "Tap to add the block at the bottom.")) {
                            ForEach(others) { module in
                                Button {
                                    withAnimation(.snappy) { raw = HomeLayout.store(shown + [module]) }
                                } label: {
                                    row(module) {
                                        Image(systemName: "plus.circle.fill").foregroundStyle(Fenn.accent)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if shown.contains(.calendar) {
                        section(tr("Kalender heute", "Today's calendar"),
                                footer: tr("Auch direkt auf der Karte änderbar, über das Größen-Symbol.",
                                           "Also changeable right on the card, via the size icon.")) {
                            Picker(tr("Größe", "Size"), selection: $calendarSize) {
                                ForEach(DayCalendarSize.allCases) { Text($0.title).tag($0.rawValue) }
                            }
                            .pickerStyle(.radioGroup)
                            .labelsHidden()
                        }
                    }
                    Button(tr("Zurücksetzen", "Reset")) {
                        withAnimation(.snappy) { raw = HomeLayout.defaultModules }
                    }
                    .buttonStyle(FennPillButtonStyle())
                }
                .padding(.bottom, 8)
            }
        }
    }

    private func move(_ module: HomeModule, by step: Int) {
        var modules = shown
        guard let index = modules.firstIndex(of: module) else { return }
        let target = min(max(index + step, 0), modules.count - 1)
        modules.remove(at: index)
        modules.insert(module, at: target)
        withAnimation(.snappy) { raw = HomeLayout.store(modules) }
    }

    private func stepButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.fenn(size: 14)).frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Fenn.fg.opacity(0.7))
        .help(help)
    }

    private func section<Content: View>(_ title: String, footer: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.fenn(size: 12, weight: .semibold)).foregroundStyle(Fenn.fg.opacity(0.55))
            content()
            Text(footer).font(.fenn(size: 11)).foregroundStyle(Fenn.fg.opacity(0.45))
        }
    }

    private func row<Trailing: View>(_ module: HomeModule, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            ClaySymbol(symbol: module.symbol, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(module.title).font(.fenn(size: 14)).foregroundStyle(Fenn.fg)
                Text(tr("aus ", "from ") + module.source).font(.fenn(size: 11)).foregroundStyle(Fenn.fg.opacity(0.5))
            }
            Spacer(minLength: 0)
            trailing()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Fenn.fill))
    }
}

// MARK: - Compact blocks

struct HomeShortcutCardMac: View {
    let title: String
    let subtitle: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ClaySymbol(symbol: symbol, size: 28)
                    .frame(width: 40, height: 40).background(Circle().fill(Fenn.fill))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.fenn(size: 15)).foregroundStyle(Fenn.fg)
                    Text(subtitle).font(.fenn(size: 12)).foregroundStyle(Fenn.fg.opacity(0.55))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.fenn(size: 12, weight: .semibold)).foregroundStyle(Fenn.fg.opacity(0.3))
            }
            .padding(12)
            .fennGlass(cornerRadius: 22, shadow: false)
        }
        .buttonStyle(.plain)
    }
}
