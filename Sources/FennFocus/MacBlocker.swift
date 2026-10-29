import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Combine
import FennFocusCore

/// App block on the Mac. macOS has no Screen Time API for third-party apps, so Fenn watches which app comes to
/// the front: while a block runs, a chosen app gets covered by Fenn's lock layer and can be hidden with one click.
/// Nothing leaves the Mac; it only needs the bundle IDs of the apps you pick.
@MainActor
final class MacBlocker: ObservableObject {
    struct BlockedApp: Codable, Hashable, Identifiable {
        var bundleId: String
        var name: String
        /// Absent on older saves; "social" marks apps used by social-media rules.
        var role: String?
        var id: String { bundleId }

        init(bundleId: String, name: String, role: String? = nil) {
            self.bundleId = bundleId
            self.name = name
            self.role = role
        }
    }

    static let shared = MacBlocker()

    @Published var apps: [BlockedApp] { didSet { save() } }
    @Published var socialApps: [BlockedApp] { didSet { saveSocial() } }
    @Published var rules: [DistractionRule] = []
    @Published var withFocus: Bool { didSet { UserDefaults.standard.set(withFocus, forKey: "fenn.mac.block.withFocus") } }
    @Published private(set) var endsAt: Date?
    @Published private(set) var fromFocus = false
    @Published private(set) var scheduleEnds: Date?
    /// The apps the current mode blocks (Fokus: social apps …) and its name – blocked until another mode is chosen.
    @Published private(set) var modeApps: [BlockedApp] = []
    @Published private(set) var modeTitle: String?

    private var observer: NSObjectProtocol?
    private var ticker: Timer?
    private var scheduleTicker: Timer?
    private var overlay: NSPanel?
    private var dismissedSocial: Set<String>
    private var lastScheduleNotice: String?

    init() {
        apps = UserDefaults.standard.data(forKey: "fenn.mac.block.apps").flatMap { try? JSONDecoder().decode([BlockedApp].self, from: $0) } ?? []
        socialApps = UserDefaults.standard.data(forKey: "fenn.mac.block.social").flatMap { try? JSONDecoder().decode([BlockedApp].self, from: $0) } ?? []
        dismissedSocial = Set(UserDefaults.standard.stringArray(forKey: "fenn.mac.block.social.dismissed") ?? [])
        withFocus = UserDefaults.standard.bool(forKey: "fenn.mac.block.withFocus")
        endsAt = UserDefaults.standard.object(forKey: "fenn.mac.block.endsAt") as? Date
        let seeded = UserDefaults.standard.bool(forKey: FennBlockNames.rulesSeededKey)
        let stored = UserDefaults.standard.data(forKey: FennBlockNames.rulesKey).flatMap { try? JSONDecoder().decode([DistractionRule].self, from: $0) } ?? []
        rules = DistractionSchedule.seed(stored, seeded: seeded).rules
        if socialApps.isEmpty { discoverSocialApps() }
        persistRules()
        modeApps = UserDefaults.standard.data(forKey: "fenn.mac.block.modeApps").flatMap { try? JSONDecoder().decode([BlockedApp].self, from: $0) } ?? []
        modeTitle = UserDefaults.standard.string(forKey: "fenn.mac.block.modeTitle")
        if isActive || !modeApps.isEmpty { arm() } else { endsAt = nil }
        armSchedule()
    }

    /// A mode turned on: its apps are blocked from now until the next mode (none for "Meine Leiste").
    func setModeBlock(_ apps: [BlockedApp], title: String?) {
        modeApps = apps.filter { $0.bundleId != Bundle.main.bundleIdentifier }
        modeTitle = modeApps.isEmpty ? nil : title
        UserDefaults.standard.set(try? JSONEncoder().encode(modeApps), forKey: "fenn.mac.block.modeApps")
        UserDefaults.standard.set(modeTitle, forKey: "fenn.mac.block.modeTitle")
        if !modeApps.isEmpty { arm() }
        if let front = NSWorkspace.shared.frontmostApplication { check(front) } else { hideOverlay() }
    }

    var isActive: Bool { (endsAt ?? .distantPast) > Date() }

    func start(minutes: Int, fromFocus: Bool = false) {
        guard !apps.isEmpty, minutes > 0 else { return }
        endsAt = Date().addingTimeInterval(TimeInterval(minutes * 60))
        self.fromFocus = fromFocus
        UserDefaults.standard.set(endsAt, forKey: "fenn.mac.block.endsAt")
        arm()
        if let front = NSWorkspace.shared.frontmostApplication { check(front) }
    }

    func stop() {
        endsAt = nil
        fromFocus = false
        UserDefaults.standard.removeObject(forKey: "fenn.mac.block.endsAt")
        ticker?.invalidate()
        ticker = nil
        if let front = NSWorkspace.shared.frontmostApplication { check(front) } else { hideOverlay() }
    }

    func add(_ app: BlockedApp) {
        guard !apps.contains(app), app.bundleId != Bundle.main.bundleIdentifier else { return }
        apps.append(app)
    }

    func remove(_ app: BlockedApp) { apps.removeAll { $0 == app } }

    /// Picks an app from /Applications (user-selected, sandbox-friendly).
    func chooseApp(social: Bool = false) {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.prompt = tr("Sperren", "Block")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { continue }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            let app = BlockedApp(bundleId: id, name: name, role: social ? "social" : "manual")
            if social { addSocial(app) } else { add(app) }
        }
    }

    /// Regular apps that are running right now – quick picks.
    var runningCandidates: [BlockedApp] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app in app.bundleIdentifier.map { BlockedApp(bundleId: $0, name: app.localizedName ?? $0) } }
            .filter { !apps.contains($0) }
            .sorted { $0.name < $1.name }
    }

    // MARK: Watching

    private func arm() {
        if observer == nil {
            observer = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                Task { @MainActor in
                    guard let self, let app else { return }
                    self.check(app)
                }
            }
        }
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if !self.isActive { self.stop() }
            }
        }
    }

    private func check(_ app: NSRunningApplication) {
        if !isActive, let endsAt, endsAt <= Date() { self.endsAt = nil; fromFocus = false; UserDefaults.standard.removeObject(forKey: "fenn.mac.block.endsAt") }
        guard let id = app.bundleIdentifier, shields(id) else {
            if app.bundleIdentifier != Bundle.main.bundleIdentifier { hideOverlay() }
            return
        }
        showOverlay(for: app)
    }

    private func shields(_ bundleId: String) -> Bool {
        if isActive, apps.contains(where: { $0.bundleId == bundleId }) { return true }
        if modeApps.contains(where: { $0.bundleId == bundleId }) { return true }
        let active = rules.filter { DistractionSchedule.isActive($0, at: Date()) }
        for rule in active {
            let pool = rule.isSocial ? socialApps : apps
            if pool.contains(where: { $0.bundleId == bundleId }) { return true }
        }
        return false
    }

    private func showOverlay(for app: NSRunningApplication) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        let panel = overlay ?? {
            let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.isReleasedWhenClosed = false
            panel.appearance = NSAppearance(named: .darkAqua)
            return panel
        }()
        panel.setFrame(screen.frame, display: true)
        let until = [isActive ? endsAt : nil, scheduleEnds].compactMap { $0 }.max() ?? Date().addingTimeInterval(60)
        let byMode = modeApps.contains { $0.bundleId == app.bundleIdentifier } && !(isActive && apps.contains { $0.bundleId == app.bundleIdentifier })
        panel.contentView = NSHostingView(rootView: BlockOverlayView(
            appName: app.localizedName ?? tr("Diese App", "This app"),
            endsAt: until,
            mode: byMode ? modeTitle : nil,
            hide: { [weak self] in
                app.hide()
                self?.hideOverlay()
            }
        ))
        overlay = panel
        panel.orderFrontRegardless()
    }

    private func hideOverlay() {
        overlay?.orderOut(nil)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(apps) { UserDefaults.standard.set(data, forKey: "fenn.mac.block.apps") }
    }

    private func saveSocial() {
        if let data = try? JSONEncoder().encode(socialApps) { UserDefaults.standard.set(data, forKey: "fenn.mac.block.social") }
    }

    // MARK: Time rules
    // macOS has no Screen Time API for third-party apps. A rule hides the chosen apps behind Fenn's lock
    // while its window is open. Websites inside a browser stay reachable unless that browser is blocked too.

    @discardableResult
    func upsert(_ draft: DistractionVoiceDraft) -> DistractionRule {
        if draft.social { discoverSocialApps() }
        if let index = rules.firstIndex(where: { $0.startMinutes == draft.startMinutes && $0.endMinutes == draft.endMinutes && $0.isSocial == draft.social }) {
            rules[index].enabled = true
            rules[index].weekdays = draft.weekdays
            rules[index].title = draft.title
            commitRules()
            return rules[index]
        }
        let rule = DistractionRule(title: draft.title, startMinutes: draft.startMinutes, endMinutes: draft.endMinutes,
                                   weekdays: draft.weekdays, enabled: true, target: draft.social ? "social" : "custom")
        rules.append(rule)
        commitRules()
        return rule
    }

    func updateRule(_ rule: DistractionRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { rules.append(rule); commitRules(); return }
        rules[index] = rule
        commitRules()
    }

    func deleteRule(_ id: UUID) { rules.removeAll { $0.id == id }; commitRules() }

    func setRuleEnabled(_ enabled: Bool, id: UUID) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[index].enabled = enabled
        commitRules()
    }

    func removeSocial(_ app: BlockedApp) {
        socialApps.removeAll { $0.bundleId == app.bundleId }
        dismissedSocial.insert(app.bundleId)
        UserDefaults.standard.set(Array(dismissedSocial), forKey: "fenn.mac.block.social.dismissed")
    }

    func addSocial(_ app: BlockedApp) {
        dismissedSocial.remove(app.bundleId)
        UserDefaults.standard.set(Array(dismissedSocial), forKey: "fenn.mac.block.social.dismissed")
        guard !socialApps.contains(where: { $0.bundleId == app.bundleId }) else { return }
        socialApps.append(BlockedApp(bundleId: app.bundleId, name: app.name, role: "social"))
    }

    private func commitRules() {
        persistRules()
        syncSchedule()
    }

    private func persistRules() {
        if let data = try? JSONEncoder().encode(rules) { UserDefaults.standard.set(data, forKey: FennBlockNames.rulesKey) }
        UserDefaults.standard.set(true, forKey: FennBlockNames.rulesSeededKey)
    }

    private func armSchedule() {
        if observer == nil {
            observer = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                Task { @MainActor in
                    guard let self, let app else { return }
                    self.check(app)
                }
            }
        }
        scheduleTicker?.invalidate()
        scheduleTicker = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.syncSchedule() }
        }
        syncSchedule()
    }

    private func syncSchedule() {
        let active = rules.filter { DistractionSchedule.isActive($0, at: Date()) }
        scheduleEnds = active.compactMap { DistractionSchedule.windowEnd($0, from: Date()) }.max()
        if !isActive, (endsAt ?? .distantFuture) <= Date() { endsAt = nil }
        if let front = NSWorkspace.shared.frontmostApplication { check(front) }
        else if active.isEmpty, !isActive { hideOverlay() }
        notifySchedule(active)
    }

    private func notifySchedule(_ active: [DistractionRule]) {
        let key = active.map { "\($0.id.uuidString)-\(DistractionRule.clock($0.startMinutes))" }.sorted().joined(separator: "|")
        guard !key.isEmpty, key != lastScheduleNotice else {
            if key.isEmpty { lastScheduleNotice = nil }
            return
        }
        lastScheduleNotice = key
        let names = active.map(\.title).joined(separator: ", ")
        let until = scheduleEnds?.formatted(date: .omitted, time: .shortened) ?? ""
        FennNotificationBrand.schedulePhase(after: 1, title: tr("Sperre aktiv", "Block on"),
                                            body: tr("\(names) bis \(until).", "\(names) until \(until)."), url: "fennfocus://focus",
                                            identifier: "fenn.block.schedule")
    }

    func discoverSocialApps() {
        var found: [BlockedApp] = []
        let roots = [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications")]
        for root in roots {
            let items = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            for url in items where url.pathExtension == "app" {
                guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { continue }
                if dismissedSocial.contains(id) || id == Bundle.main.bundleIdentifier { continue }
                let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
                guard let match = Self.socialName(id: id, name: name) else { continue }
                found.append(BlockedApp(bundleId: id, name: match, role: "social"))
            }
        }
        for app in found where !socialApps.contains(where: { $0.bundleId == app.bundleId }) {
            socialApps.append(app)
        }
        saveSocial()
    }

    private static let socialIDs = [
        "com.hnc.Discord": "Discord", "com.hammerandchisel.discord": "Discord",
        "ru.keepcoder.Telegram": "Telegram", "org.telegram.desktop": "Telegram",
        "net.whatsapp.WhatsApp": "WhatsApp", "org.whispersystems.signal-desktop": "Signal",
        "com.tinyspeck.slackmacgap": "Slack", "com.facebook.archon": "Messenger",
        "com.atebits.Tweetie2": "X", "com.reddit.reddit": "Reddit", "com.linkedin.LinkedIn": "LinkedIn",
    ]
    private static let socialHints = ["instagram", "facebook", "tiktok", "twitter", "reddit", "snapchat", "discord", "telegram", "whatsapp", "mastodon", "threads", "linkedin", "youtube", "messenger"]
    private static let browsers = ["safari", "chrome", "firefox", "arc", "edge", "brave", "opera", "vivaldi"]

    private static func socialName(id: String, name: String) -> String? {
        let hay = (id + " " + name).lowercased()
        if browsers.contains(where: { hay.contains($0) }) { return nil }
        if let known = socialIDs[id] { return known }
        if socialHints.contains(where: { hay.contains($0) }) { return name }
        return nil
    }
}

/// Full-screen lock layer over a blocked app.
struct BlockOverlayView: View {
    let appName: String
    let endsAt: Date
    /// Blocked by a mode: no countdown, the mode's name instead.
    var mode: String? = nil
    let hide: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.82)
            FennAurora(intensity: 0.8)
            VStack(spacing: 22) {
                ThinkingOrb(state: .breathing, size: 150)
                Text(tr("\(appName) ist gerade gesperrt", "\(appName) is blocked right now"))
                    .font(Fenn.display(30)).foregroundStyle(Fenn.fg)
                if let mode {
                    Text(tr("Modus „\(mode)“", "“\(mode)” mode")).font(.fenn(size: 18, weight: .semibold)).foregroundStyle(Fenn.accent)
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let left = max(0, Int(endsAt.timeIntervalSince(context.date)))
                        DotMatrixText(text: String(format: "%d:%02d", left / 60, left % 60), height: 46, color: Fenn.accent)
                    }
                }
                Text(mode == nil ? tr("Du hast dir diese Zeit bewusst gesetzt. Ein Atemzug, dann zurück an die Sache.",
                                      "You set this time on purpose. One breath, then back to what matters.")
                                 : tr("Du hast diesen Modus gewählt. Wechsel den Modus in Fenn, wenn du die App brauchst.",
                                      "You chose this mode. Switch modes in Fenn when you need the app."))
                    .font(.fenn(size: 15)).foregroundStyle(Fenn.fg.opacity(0.7))
                Button(tr("\(appName) ausblenden", "Hide \(appName)"), action: hide)
                    .buttonStyle(FennPillButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(40)
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }
}

/// The block card in the focus module.
struct MacBlockCard: View {
    @ObservedObject var blocker: MacBlocker
    @State private var minutes = 60
    @State private var editor: DistractionRule?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(tr("APPS SPERREN", "BLOCK APPS")).font(.fenn(size: 11, weight: .medium)).tracking(1.2).foregroundStyle(Fenn.fg.opacity(0.5))
                Spacer()
                if let end = blocker.endsAt, blocker.isActive {
                    Text(timerInterval: Date()...end, countsDown: true).font(Fenn.display(14)).monospacedDigit().foregroundStyle(Fenn.accent)
                }
            }
            FlowWrap(spacing: 6) {
                ForEach(blocker.apps) { app in
                    HStack(spacing: 4) {
                        Text(app.name).font(.fenn(size: 12, weight: .medium))
                        if !blocker.isActive {
                            Button { blocker.remove(app) } label: { Image(systemName: "xmark").font(.fenn(size: 9, weight: .bold)) }
                                .buttonStyle(.plain).foregroundStyle(Fenn.fg.opacity(0.6))
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Capsule().fill(blocker.isActive ? Fenn.accent.opacity(0.25) : Fenn.fillStrong))
                }
                if !blocker.isActive {
                    Menu {
                        ForEach(blocker.runningCandidates) { app in Button(app.name) { blocker.add(app) } }
                        if !blocker.runningCandidates.isEmpty { Divider() }
                        Button(tr("Andere App wählen …", "Choose another app …")) { blocker.chooseApp() }
                    } label: {
                        Label(tr("App", "App"), systemImage: "plus").font(.fenn(size: 12, weight: .medium))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .foregroundStyle(Fenn.amber)
                }
            }
            if blocker.isActive {
                Button(tr("Sperre beenden", "End block")) { blocker.stop() }
                    .buttonStyle(FennPillButtonStyle())
            } else {
                HStack(spacing: 6) {
                    ForEach([15, 30, 60, 120], id: \.self) { value in
                        Button(value < 60 ? "\(value) min" : "\(value / 60) h") { minutes = value }
                            .buttonStyle(.plain)
                            .font(.fenn(size: 12, weight: .medium))
                            .foregroundStyle(minutes == value ? Fenn.onSelected : Fenn.fg)
                            .padding(.horizontal, 10).frame(height: 26)
                            .background(Capsule().fill(minutes == value ? Fenn.selected : Fenn.fill))
                    }
                    Spacer()
                    Button(tr("Sperren", "Block")) { blocker.start(minutes: minutes) }
                        .buttonStyle(FennPillButtonStyle(prominent: true))
                        .disabled(blocker.apps.isEmpty)
                }
                Toggle(tr("Bei jedem Fokus-Block mitsperren", "Block during every focus block"), isOn: $blocker.withFocus)
                    .toggleStyle(.switch).controlSize(.small).tint(Fenn.accent)
                    .font(.fenn(size: 12)).foregroundStyle(Fenn.fg.opacity(0.75))
            }
            scheduleRules
            Text(tr("Websites im Browser bleiben offen.", "Websites in the browser stay open."))
                .font(.fenn(size: 10)).foregroundStyle(Fenn.fg.opacity(0.4))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Fenn.fill))
        .sheet(item: $editor) { rule in
            MacRuleEditor(rule: rule) { blocker.updateRule($0); editor = nil }
        }
    }

    private var scheduleRules: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("ZEITREGELN", "TIME RULES")).font(.fenn(size: 11, weight: .medium)).tracking(1.2).foregroundStyle(Fenn.fg.opacity(0.5))
            ForEach(blocker.rules) { rule in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rule.title).font(.fenn(size: 13, weight: .medium))
                        Text("\(rule.windowLabel), \(rule.isSocial ? tr("Social Media", "Social media") : tr("eigene Apps", "chosen apps"))")
                            .font(.fenn(size: 11)).foregroundStyle(Fenn.fg.opacity(0.55))
                    }
                    Spacer()
                    Toggle("", isOn: Binding(get: { rule.enabled }, set: { blocker.setRuleEnabled($0, id: rule.id) }))
                        .toggleStyle(.switch).controlSize(.mini).labelsHidden().tint(Fenn.accent)
                    Button { editor = rule } label: { Image(systemName: "pencil") }.buttonStyle(.plain)
                    Button { blocker.deleteRule(rule.id) } label: { Image(systemName: "trash") }.buttonStyle(.plain).foregroundStyle(Fenn.fg.opacity(0.6))
                }
                if DistractionSchedule.isActive(rule, at: Date()) {
                    Text(tr("Gerade aktiv", "Active now")).font(.fenn(size: 11)).foregroundStyle(Fenn.accent)
                }
            }
            if !blocker.socialApps.isEmpty {
                FlowWrap(spacing: 6) {
                    ForEach(blocker.socialApps) { app in
                        HStack(spacing: 4) {
                            Text(app.name).font(.fenn(size: 11, weight: .medium))
                            Button { blocker.removeSocial(app) } label: { Image(systemName: "xmark").font(.fenn(size: 8, weight: .bold)) }
                                .buttonStyle(.plain).foregroundStyle(Fenn.fg.opacity(0.6))
                        }
                        .padding(.horizontal, 8).frame(height: 22)
                        .background(Capsule().fill(Fenn.fillStrong))
                    }
                }
            }
            HStack(spacing: 6) {
                Button(tr("6–8 kein Social Media", "6–8 no social media")) {
                    blocker.upsert(DistractionVoiceDraft(startMinutes: 6 * 60, endMinutes: 8 * 60, social: true, weekdays: Array(1...7), title: "Kein Social Media"))
                }
                .buttonStyle(FennPillButtonStyle(prominent: true))
                Button(tr("Social-App", "Social app")) { blocker.chooseApp(social: true) }
                    .buttonStyle(FennPillButtonStyle())
                Button(tr("Neue Regel", "New rule")) {
                    editor = DistractionRule(title: tr("Sperre", "Block"), startMinutes: 20 * 60, endMinutes: 22 * 60, weekdays: Array(1...7), enabled: true, target: "custom")
                }
                .buttonStyle(FennPillButtonStyle())
            }
        }
    }
}

private struct MacRuleEditor: View {
    @State var rule: DistractionRule
    var onSave: (DistractionRule) -> Void
    @Environment(\.dismiss) private var dismiss
    private let days: [(Int, String)] = [(2, "Mo"), (3, "Di"), (4, "Mi"), (5, "Do"), (6, "Fr"), (7, "Sa"), (1, "So")]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tr("Zeitregel", "Time rule")).font(Fenn.display(20))
            TextField(tr("Name", "Name"), text: $rule.title).textFieldStyle(.roundedBorder)
            HStack {
                timePicker(tr("Von", "From"), minutes: rule.startMinutes) { rule.startMinutes = $0 }
                timePicker(tr("Bis", "Until"), minutes: rule.endMinutes) { rule.endMinutes = $0 }
            }
            HStack(spacing: 4) {
                ForEach(days, id: \.0) { day, label in
                    let on = rule.weekdays.contains(day)
                    Button(label) {
                        if on { rule.weekdays.removeAll { $0 == day } } else { rule.weekdays.append(day) }
                    }
                    .buttonStyle(.plain)
                    .font(.fenn(size: 11, weight: .medium))
                    .foregroundStyle(on ? Fenn.canvas : Fenn.fg)
                    .frame(width: 28, height: 24)
                    .background(Capsule().fill(on ? Fenn.fg : Fenn.fill))
                }
            }
            FennSegments(options: ["social", "custom"], selection: $rule.target) { $0 == "social" ? "Social Media" : tr("Eigene Apps", "Chosen apps") }
            HStack {
                Button(tr("Abbrechen", "Cancel")) { dismiss() }.buttonStyle(FennPillButtonStyle())
                Button(tr("Sichern", "Save")) { onSave(rule) }
                    .buttonStyle(FennPillButtonStyle(prominent: true))
                    .disabled(rule.weekdays.isEmpty || rule.startMinutes == rule.endMinutes)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func timePicker(_ title: String, minutes: Int, set: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.fenn(size: 11)).foregroundStyle(Fenn.fg.opacity(0.55))
            DatePicker("", selection: Binding(
                get: { Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date() },
                set: { set(Calendar.current.component(.hour, from: $0) * 60 + Calendar.current.component(.minute, from: $0)) }
            ), displayedComponents: .hourAndMinute).labelsHidden()
        }
    }
}

/// Wrapping row for chips.
struct FlowWrap: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(subviews, width: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, point) in layout(subviews, width: bounds.width).points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func layout(_ subviews: Subviews, width: CGFloat) -> (size: CGSize, points: [CGPoint]) {
        var points: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += row + spacing; row = 0 }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            row = max(row, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + row), points)
    }
}
