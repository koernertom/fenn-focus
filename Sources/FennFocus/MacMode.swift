import SwiftUI
import AppKit

/// A mode is what the moment is about – Fokus, Freizeit, Erholung or one of your own. It swaps the module bar,
/// blocks the Mac apps you picked for it and can open the apps you need. "Meine Leiste" brings your own bar back
/// exactly as it was and lifts the mode's blocks.
struct MacMode: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    /// Clay picture (base name, the seasonal variant is picked when shown).
    var art: String
    /// The bar this mode brings; nil = your own bar.
    var moduleIds: [String]?
    /// Covered by Fenn's lock layer while the mode is on.
    var blockedApps: [MacBlocker.BlockedApp] = []
    /// Also block the social apps Fenn found on this Mac.
    var blocksSocial = false
    /// Opened when the mode starts.
    var openApps: [MacBlocker.BlockedApp] = []
    /// The few home tiles this mode brings (HomeModule ids); nil = the built-in pick (or your own home for your own
    /// modes), ["-"] = your own home.
    var homeTiles: [String]? = nil

    /// At most this many tiles per mode – a mode's home stays calm.
    static let maxHomeTiles = 4
    private static let defaultHome: [String: [String]] = [
        "work": ["tasks", "calendar", "focus"],
        "free": ["habits", "journal"],
        "recover": ["habits", "journal"],
    ]

    /// The home tiles while this mode is on; nil = your own home ("Startseite anpassen").
    var home: [HomeModule]? {
        guard !isOwn, let raw = homeTiles ?? Self.defaultHome[id], raw != ["-"] else { return nil }
        return raw.compactMap(HomeModule.init(rawValue:))
    }

    static let key = "fenn.mac.mode"
    static let orderKey = "fenn.mac.moduleOrder"
    static let countKey = "fenn.mac.mainModuleCount"
    static let listKey = "fenn.mac.modes"
    private static let ownKey = "fenn.mac.mode.ownOrder"
    /// Every module that can sit in the bar, in the default order.
    static let orderable: [IslandModule] = [.today, .tasks, .habits, .focus, .ideas, .notes, .journal, .connectors]
    /// Clay pictures to choose from for a mode.
    static let artChoices = ["Page-focus", "Page-tasks", "Page-ideas", "Page-notes", "Page-journal",
                             "Page-habits", "Clay-sun", "Clay-moon", "Clay-campfire", "Clay-books", "Clay-wave",
                             "Clay-bed", "Clay-brain", "Set-friends", "Set-palette", "Set-envelope", "Set-globe"]

    static let own = MacMode(id: "own", title: tr("Meine Leiste", "My bar"), art: "Set-bar", moduleIds: nil)

    static let builtIn: [MacMode] = [
        own,
        MacMode(id: "work", title: tr("Fokus", "Focus"), art: "Page-focus",
                moduleIds: ["today", "tasks", "focus", "notes", "ideas"], blocksSocial: true),
        MacMode(id: "free", title: tr("Freizeit", "Free time"), art: "Clay-campfire",
                moduleIds: ["today", "habits", "journal", "ideas", "notes"]),
        MacMode(id: "recover", title: tr("Erholung", "Recovery"), art: "Clay-moon", moduleIds: ["today", "habits", "journal", "notes"]),
    ]

    var isOwn: Bool { id == Self.own.id }
    var isBuiltIn: Bool { Self.builtIn.contains { $0.id == id } }
    var modules: [IslandModule]? { moduleIds?.compactMap(IslandModule.init(rawValue:)) }
    var shownArt: String? { FennArt.pick(art) }

    @MainActor var detail: String {
        guard let modules else { return tr("Deine eigene Auswahl", "Your own pick") }
        var parts = [modules.dropFirst().map(\.title).joined(separator: ", ")]
        let blocked = blockedApps.count + (blocksSocial ? MacBlocker.shared.socialApps.count : 0)
        if blocked > 0 { parts.append(tr("\(blocked) Apps gesperrt", "\(blocked) apps blocked")) }
        if !openApps.isEmpty { parts.append(tr("öffnet \(openApps.map(\.name).joined(separator: ", "))", "opens \(openApps.map(\.name).joined(separator: ", "))")) }
        return parts.joined(separator: " · ")
    }

    // MARK: Stored list

    static var all: [MacMode] {
        get {
            guard let data = UserDefaults.standard.data(forKey: listKey),
                  var list = try? JSONDecoder().decode([MacMode].self, from: data), !list.isEmpty else { return builtIn }
            // "Meine Leiste" always exists and comes first.
            list.removeAll { $0.isOwn }
            return [own] + list
        }
        set {
            if let data = try? JSONEncoder().encode(newValue.filter { !$0.isOwn }) { UserDefaults.standard.set(data, forKey: listKey) }
        }
    }

    @MainActor static func save(_ mode: MacMode) {
        var list = all
        if let index = list.firstIndex(where: { $0.id == mode.id }) { list[index] = mode } else { list.append(mode) }
        all = list
        // Editing the mode that's on: apply the new bar and blocks right away.
        if current.id == mode.id || UserDefaults.standard.string(forKey: key) == mode.id { mode.activate() }
    }

    /// Keeps a change (like a reordered home) without switching the mode on again – no apps reopen.
    static func store(_ mode: MacMode) {
        var list = all
        guard let index = list.firstIndex(where: { $0.id == mode.id }) else { return }
        list[index] = mode
        all = list
    }

    @MainActor static func delete(_ mode: MacMode) {
        guard !mode.isOwn else { return }
        if UserDefaults.standard.string(forKey: key) == mode.id { own.activate() }
        all = all.filter { $0.id != mode.id }
    }

    private static func order(_ raw: String?) -> [IslandModule] {
        (raw ?? "").split(separator: ",").compactMap { IslandModule(rawValue: String($0)) }
    }

    /// The stored mode – but once the bar was changed by hand it no longer is that mode.
    static var current: MacMode {
        let defaults = UserDefaults.standard
        guard let id = defaults.string(forKey: key), let mode = all.first(where: { $0.id == id }), let modules = mode.modules else { return own }
        let count = defaults.integer(forKey: countKey)
        return Array(order(defaults.string(forKey: orderKey)).prefix(count)) == modules ? mode : own
    }

    @MainActor
    func activate() {
        let defaults = UserDefaults.standard
        if Self.current.isOwn {
            let raw = defaults.string(forKey: Self.orderKey) ?? Self.orderable.map(\.rawValue).joined(separator: ",")
            let count = defaults.object(forKey: Self.countKey) as? Int ?? 6
            defaults.set("\(raw)|\(count)", forKey: Self.ownKey)
        }
        if let modules {
            let rest = Self.orderable.filter { !modules.contains($0) }
            defaults.set((modules + rest).map(\.rawValue).joined(separator: ","), forKey: Self.orderKey)
            defaults.set(modules.count, forKey: Self.countKey)
        } else if let own = defaults.string(forKey: Self.ownKey)?.split(separator: "|"), own.count == 2 {
            defaults.set(String(own[0]), forKey: Self.orderKey)
            defaults.set(Int(own[1]) ?? 6, forKey: Self.countKey)
        }
        defaults.set(id, forKey: Self.key)
        // The mode's app rules: its blocks replace the previous mode's, its apps open.
        let blocker = MacBlocker.shared
        var blocked = blockedApps
        if blocksSocial {
            if blocker.socialApps.isEmpty { blocker.discoverSocialApps() }
            blocked += blocker.socialApps.filter { app in !blocked.contains { $0.bundleId == app.bundleId } }
        }
        blocker.setModeBlock(blocked, title: isOwn ? nil : title)
        for app in openApps {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleId) else { continue }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

/// The modes as small clay chips; a click swaps the bar and the app rules. "+" makes a new one, right-click edits.
struct MacModeSwitcher: View {
    var edit: ((MacMode?) -> Void)? = nil
    @AppStorage(MacMode.orderKey) private var orderRaw = ""
    @AppStorage(MacMode.countKey) private var count = 6
    @AppStorage(MacMode.key) private var modeRaw = MacMode.own.id
    @AppStorage(MacMode.listKey) private var listData = Data()
    /// Folded in: only the active mode shows; the chevron (or a click on it) slides the others back out.
    @AppStorage("fenn.mac.modes.collapsed") private var collapsed = false

    var body: some View {
        let _ = (orderRaw, count, modeRaw, listData)
        let current = MacMode.current
        HStack(spacing: 6) {
            ForEach(collapsed ? [current] : MacMode.all) { mode in
                let on = mode.id == current.id
                Button {
                    if collapsed { withAnimation(.snappy) { collapsed = false } } else { withAnimation(.snappy) { mode.activate() } }
                } label: {
                    HStack(spacing: 5) {
                        if let art = mode.shownArt {
                            Image(art).resizable().interpolation(.high).scaledToFit().frame(width: 18, height: 18)
                        } else {
                            Image(systemName: "circle.grid.2x2").font(.fenn(size: 11, weight: .semibold))
                        }
                        Text(mode.title).font(.fenn(size: 12, weight: .semibold)).lineLimit(1)
                        if on && (!mode.blockedApps.isEmpty || mode.blocksSocial) {
                            Image(systemName: "lock.fill").font(.fenn(size: 8, weight: .bold)).opacity(0.7)
                        }
                    }
                    .foregroundStyle(on ? Fenn.onSelected : Fenn.fg)
                    .padding(.leading, 7).padding(.trailing, 10)
                    .frame(height: 28)
                    .background(Capsule().fill(on ? Fenn.selected : Fenn.fill))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(mode.detail)
                .contextMenu {
                    if let edit, !mode.isOwn {
                        Button(tr("Bearbeiten …", "Edit …"), systemImage: "slider.horizontal.3") { edit(mode) }
                        if !mode.isBuiltIn {
                            Button(tr("Löschen", "Delete"), systemImage: "trash", role: .destructive) { withAnimation { MacMode.delete(mode) } }
                        }
                    }
                }
                .accessibilityLabel(tr("Modus \(mode.title)", "\(mode.title) mode"))
                .accessibilityAddTraits(on ? .isSelected : [])
                .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
            }
            if let edit, !collapsed {
                Button { edit(nil) } label: {
                    Image(systemName: "plus").font(.fenn(size: 11, weight: .bold)).foregroundStyle(Fenn.fg.opacity(0.7))
                        .frame(width: 28, height: 28).background(Circle().fill(Fenn.fill))
                }
                .buttonStyle(.plain)
                .help(tr("Eigenen Modus anlegen", "Create your own mode"))
                .accessibilityLabel(tr("Modus anlegen", "Add mode"))
                .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
            }
            Button {
                withAnimation(.snappy) { collapsed.toggle() }
            } label: {
                Image(systemName: collapsed ? "chevron.right" : "chevron.left")
                    .font(.fenn(size: 10, weight: .bold)).foregroundStyle(Fenn.fg.opacity(0.55))
                    .frame(width: 24, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(collapsed ? tr("Modi ausfahren", "Show all modes") : tr("Modi einfahren", "Fold the modes in"))
            .accessibilityLabel(collapsed ? tr("Modi ausfahren", "Show all modes") : tr("Modi einfahren", "Fold the modes in"))
        }
    }
}

/// Create or change a mode: name and clay picture, which modules sit in the bar, which apps get blocked or opened.
struct MacModeEditor: View {
    @State var mode: MacMode
    let done: () -> Void
    @ObservedObject private var blocker = MacBlocker.shared

    init(mode: MacMode?, done: @escaping () -> Void) {
        _mode = State(initialValue: mode ?? MacMode(id: UUID().uuidString, title: "", art: "Clay-sun",
                                                       moduleIds: ["today", "tasks", "focus"]))
        self.done = done
    }

    private var isNew: Bool { !MacMode.all.contains { $0.id == mode.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(isNew ? tr("Neuer Modus", "New mode") : tr("Modus bearbeiten", "Edit mode"))
                    .font(.fenn(size: 16, weight: .semibold)).foregroundStyle(Fenn.fg)
                Spacer()
                Button(tr("Abbrechen", "Cancel"), action: done).buttonStyle(FennPillButtonStyle())
                Button(tr("Sichern", "Save")) {
                    if mode.title.trimmingCharacters(in: .whitespaces).isEmpty { mode.title = tr("Mein Modus", "My mode") }
                    MacMode.save(mode)
                    done()
                }
                .buttonStyle(FennPillButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
            }
            .padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section(tr("Name und Bild", "Name and picture")) {
                        TextField(tr("z. B. Deep Work, Abends, Wochenende", "e.g. Deep work, Evening, Weekend"), text: $mode.title)
                            .textFieldStyle(.plain).font(.fenn(size: 15))
                            .padding(.horizontal, 12).frame(height: 36)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Fenn.field))
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(40), spacing: 6), count: 11), alignment: .leading, spacing: 6) {
                            ForEach(MacMode.artChoices, id: \.self) { art in
                                Button { mode.art = art } label: {
                                    Image(FennArt.pick(art) ?? art).resizable().interpolation(.high).scaledToFit()
                                        .frame(width: 28, height: 28).frame(width: 40, height: 40)
                                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(mode.art == art ? Fenn.accent.opacity(0.18) : Fenn.fill))
                                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(mode.art == art ? Fenn.accent : .clear, lineWidth: 1.5))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    section(tr("Module in der Leiste", "Modules in the bar"),
                            footer: tr("In dieser Reihenfolge; Heute steht immer vorne.", "In this order; Today always comes first.")) {
                        ForEach(MacMode.orderable.filter { $0 != .today }) { module in
                            let on = mode.moduleIds?.contains(module.rawValue) == true
                            Button { toggle(module) } label: {
                                HStack(spacing: 10) {
                                    if let art = module.art {
                                        Image(art).resizable().interpolation(.high).scaledToFit().frame(width: 22, height: 22)
                                    }
                                    Text(module.title).font(.fenn(size: 13)).foregroundStyle(Fenn.fg)
                                    Spacer()
                                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(on ? Fenn.accent : Fenn.fg.opacity(0.3))
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    section(tr("Startseite", "Home"),
                            footer: tr("Höchstens \(MacMode.maxHomeTiles) Kacheln, damit es ruhig bleibt. Aus: deine eigene Startseite.",
                                       "At most \(MacMode.maxHomeTiles) tiles, so it stays calm. Off: your own home.")) {
                        Toggle(isOn: Binding(get: { mode.home != nil }, set: { on in
                            mode.homeTiles = on ? (mode.home ?? []).map(\.rawValue) : ["-"]
                        })) {
                            Text(tr("Eigene Startseite für diesen Modus", "Own home for this mode")).font(.fenn(size: 13))
                        }
                        .toggleStyle(.switch).controlSize(.small).tint(Fenn.accent)
                        if let tiles = mode.home {
                            ChipFlow(spacing: 6) {
                                ForEach(HomeModule.allCases) { tile in
                                    let on = tiles.contains(tile)
                                    Button { toggleHome(tile) } label: {
                                        Label(tile.title, systemImage: on ? "checkmark" : tile.symbol)
                                            .font(.fenn(size: 12, weight: .medium))
                                            .foregroundStyle(on ? Fenn.onSelected : Fenn.fg.opacity(0.8))
                                            .padding(.horizontal, 10).padding(.vertical, 5)
                                            .background(Capsule().fill(on ? Fenn.selected : Fenn.fill))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!on && tiles.count >= MacMode.maxHomeTiles)
                                    .opacity(!on && tiles.count >= MacMode.maxHomeTiles ? 0.45 : 1)
                                }
                            }
                        }
                    }
                    section(tr("Diese Apps sperren", "Block these apps"),
                            footer: tr("Solange der Modus an ist, legt Fenn seine Sperre über diese Apps.",
                                       "While the mode is on, Fenn covers these apps with its lock.")) {
                        Toggle(isOn: $mode.blocksSocial) {
                            Text(tr("Social-Apps (\(blocker.socialApps.map(\.name).prefix(3).joined(separator: ", ")) …)",
                                    "Social apps (\(blocker.socialApps.map(\.name).prefix(3).joined(separator: ", ")) …)"))
                                .font(.fenn(size: 13))
                        }
                        .toggleStyle(.switch).controlSize(.small).tint(Fenn.accent)
                        appList($mode.blockedApps)
                    }
                    section(tr("Beim Start öffnen", "Open on start"),
                            footer: tr("Zum Beispiel Notizen und Kalender für Fokus, Musik für Freizeit.",
                                       "For example notes and calendar for focus, music for free time.")) {
                        appList($mode.openApps)
                    }
                    if !isNew && !mode.isBuiltIn {
                        Button(tr("Modus löschen", "Delete mode"), role: .destructive) { MacMode.delete(mode); done() }
                            .buttonStyle(.plain).font(.fenn(size: 13, weight: .medium)).foregroundStyle(Fenn.danger)
                    }
                }
                .padding(.bottom, 12)
            }
            .scrollIndicators(.never)
        }
    }

    private func toggleHome(_ tile: HomeModule) {
        var tiles = (mode.home ?? []).map(\.rawValue)
        if tiles.contains(tile.rawValue) { tiles.removeAll { $0 == tile.rawValue } }
        else if tiles.count < MacMode.maxHomeTiles { tiles.append(tile.rawValue) }
        mode.homeTiles = tiles
    }

    private func toggle(_ module: IslandModule) {
        var ids = mode.moduleIds ?? ["today"]
        if ids.contains(module.rawValue) { ids.removeAll { $0 == module.rawValue } } else { ids.append(module.rawValue) }
        if !ids.contains("today") { ids.insert("today", at: 0) }
        mode.moduleIds = ids
    }

    /// Picked apps as removable chips, plus "App wählen" and the apps running right now.
    private func appList(_ apps: Binding<[MacBlocker.BlockedApp]>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ChipFlow(spacing: 6) {
                ForEach(apps.wrappedValue) { app in
                    HStack(spacing: 6) {
                        AppIcon(bundleId: app.bundleId)
                        Text(app.name).font(.fenn(size: 12, weight: .medium)).foregroundStyle(Fenn.fg)
                        Button { apps.wrappedValue.removeAll { $0 == app } } label: {
                            Image(systemName: "xmark").font(.fenn(size: 9, weight: .bold)).foregroundStyle(Fenn.fg.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(tr("\(app.name) entfernen", "Remove \(app.name)"))
                    }
                    .padding(.horizontal, 10).frame(height: 28)
                    .background(Capsule().fill(Fenn.fill))
                }
            }
            HStack(spacing: 8) {
                Button(tr("App wählen …", "Choose app …")) {
                    for app in Self.pickApps() where !apps.wrappedValue.contains(app) { apps.wrappedValue.append(app) }
                }
                .buttonStyle(FennPillButtonStyle())
                Menu(tr("Laufende Apps", "Running apps")) {
                    ForEach(Self.running.filter { !apps.wrappedValue.contains($0) }) { app in
                        Button(app.name) { apps.wrappedValue.append(app) }
                    }
                }
                .menuStyle(.borderlessButton).fixedSize()
                .font(.fenn(size: 12, weight: .medium))
            }
        }
    }

    private static var running: [MacBlocker.BlockedApp] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app in app.bundleIdentifier.map { MacBlocker.BlockedApp(bundleId: $0, name: app.localizedName ?? $0) } }
            .sorted { $0.name < $1.name }
    }

    private static func pickApps() -> [MacBlocker.BlockedApp] {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.compactMap { url in
            guard let id = Bundle(url: url)?.bundleIdentifier else { return nil }
            return MacBlocker.BlockedApp(bundleId: id, name: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, footer: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.fenn(size: 11, weight: .medium)).tracking(1.1).foregroundStyle(Fenn.fg.opacity(0.55))
            VStack(alignment: .leading, spacing: 10) { content() }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fennGlass(cornerRadius: 18, shadow: false)
            if let footer {
                Text(footer).font(.fenn(size: 11.5)).foregroundStyle(Fenn.fg.opacity(0.55))
            }
        }
    }
}

/// The app's own icon, small.
private struct AppIcon: View {
    let bundleId: String

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 16, height: 16)
        }
    }
}
