import SwiftUI
import AppKit

/// Connections: what Fenn knows about you, the AI model, the Fenn Focus folder, the calendar and the MCP server.
struct ConnectorsModuleView: View {
    @ObservedObject var cloud: FennCloudFolder
    @ObservedObject var ai: AISettings
    let connectCloud: (SyncProvider) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("Verbindungen", "Connections"))
                        .font(Fenn.display(22))
                        .foregroundStyle(Fenn.fg)
                    Text(tr("Schlüssel liegen nur im Schlüsselbund dieses Macs.",
                            "Keys stay in this Mac's Keychain only."))
                        .font(.fenn(size: 13))
                        .foregroundStyle(Fenn.fg.opacity(0.6))
                }

                section(tr("Über dich", "About you")) { AboutYouCard(store: PersonProfileStore.shared) }
                section(tr("KI-Modell", "AI model")) { AIModelCard(ai: ai) }
                section(tr("Fenn-Ordner", "Fenn folder")) { SyncFolderCard(cloud: cloud, connect: connectCloud) }
                section(tr("Kalender (optional)", "Calendar (optional)")) { CalendarSettingsCard(calendar: WorkCalendar.shared) }
                section(tr("Fenn als MCP-Server (optional)", "Fenn as an MCP server (optional)")) { MCPServerCard() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.fenn(size: 11, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(Fenn.fg.opacity(0.5))
            content()
        }
    }
}

/// The Fenn folder – iCloud Drive or any folder: where tasks, routines, notes and journal live.
struct SyncFolderCard: View {
    @ObservedObject var cloud: FennCloudFolder
    let connect: (SyncProvider) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ClaySymbol(symbol: cloud.provider?.symbol ?? "icloud", size: 26)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Fenn.accent.opacity(0.14)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(cloud.provider.map { tr("Verbunden, \($0.title)", "Connected, \($0.title)") } ?? tr("Nicht verbunden", "Not connected"))
                        .font(.fenn(size: 14, weight: .regular))
                    Text(cloud.current.map { $0.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
                         ?? tr("Ohne Ordner bleibt alles in der App auf diesem Mac.",
                               "Without a folder everything stays inside the app on this Mac."))
                        .font(.fenn(size: 12)).foregroundStyle(Fenn.fg.opacity(0.6))
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                if cloud.isConnected {
                    Button(tr("Im Finder zeigen", "Show in Finder")) {
                        if let url = cloud.current { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    }
                    .buttonStyle(FennPillButtonStyle())
                    Button(tr("Trennen", "Disconnect")) { cloud.disconnect() }.buttonStyle(FennPillButtonStyle())
                } else {
                    Button("iCloud Drive") { connect(.iCloud) }.buttonStyle(FennPillButtonStyle(prominent: true))
                    Button(tr("Anderer Ordner", "Other folder")) { connect(.other) }.buttonStyle(FennPillButtonStyle())
                }
            }
            if !cloud.isConnected {
                Text(tr("Unterordner legt Fenn selbst an – alles Markdown und JSON.",
                        "Fenn creates the subfolders itself – all Markdown and JSON."))
                    .font(.fenn(size: 11))
                    .foregroundStyle(Fenn.fg.opacity(0.45))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Fenn.fill))
    }
}

/// Provider (local first, then the person's own key), model, and a test.
struct AIModelCard: View {
    @ObservedObject var ai: AISettings
    @ObservedObject private var store = LocalModelStore.shared
    @State private var key = ""
    @State private var servers = LocalServers.Found()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            providerRow(tr("Lokal", "Local"), AIProvider.offered.filter(\.isLocalKind))
            providerRow(tr("Eigener Schlüssel", "Your own key"), AIProvider.offered.filter { !$0.isLocalKind })
            Text(ai.config.provider.detail)
                .font(.fenn(size: 12))
                .foregroundStyle(Fenn.fg.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)

            if ai.config.provider.hasEndpoint {
                field(tr("Server-Adresse", "Server address"), text: Binding(get: { ai.config.baseURL }, set: { ai.config.baseURL = $0 }))
            }
            if let found = serverLine {
                Text(found)
                    .font(.fenn(size: 12, weight: .medium))
                    .foregroundStyle(Fenn.accent)
            }
            if ai.config.provider == .fennBrain {
                brainPicker
            } else if ai.config.provider != .apple {
                HStack(spacing: 6) {
                    field(tr("Modell", "Model"), text: Binding(get: { ai.config.model }, set: { ai.config.model = $0 }))
                    if !ai.models.isEmpty {
                        Menu {
                            ForEach(ai.models, id: \.self) { name in
                                Button(name) { ai.config.model = name; ai.save() }
                            }
                        } label: {
                            Image(systemName: "chevron.down.circle").foregroundStyle(Fenn.fg.opacity(0.7))
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help(tr("Modelle auf dem Server", "Models on the server"))
                    }
                }
            }
            if ai.config.provider.acceptsKey {
                HStack(spacing: 6) {
                    SecureField(ai.hasKey(ai.config.provider)
                                ? tr("Schlüssel gespeichert – neuen einfügen zum Ersetzen", "Key saved – paste a new one to replace")
                                : (ai.config.provider == .claude ? "sk-ant-…" : tr("API-Schlüssel (optional bei vLLM)", "API key (optional for vLLM)")),
                                text: $key)
                        .textFieldStyle(.plain)
                        .font(.fenn(size: 13))
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(Capsule().fill(Fenn.field))
                        .overlay(Capsule().strokeBorder(Fenn.hairline))
                        .onSubmit(saveKey)
                    if !key.isEmpty {
                        Button(tr("Speichern", "Save"), action: saveKey).buttonStyle(FennPillButtonStyle(prominent: true))
                    } else if ai.hasKey(ai.config.provider) {
                        Button(tr("Entfernen", "Remove")) { ai.removeKey() }.buttonStyle(FennPillButtonStyle())
                    }
                }
            }
            if ai.needsConsent {
                Toggle(isOn: $ai.cloudConsent) {
                    Text(tr("Ich stimme der Übertragung an \(ai.config.provider.title) zu", "I agree to sending data to \(ai.config.provider.title)"))
                        .font(.fenn(size: 12, weight: .medium)).foregroundStyle(Fenn.fg)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Fenn.accent)
                Text(FennAI.consentText(ai.config))
                    .font(.fenn(size: 11))
                    .foregroundStyle(Fenn.fg.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let hint {
                Text(hint)
                    .font(.fenn(size: 11, design: .monospaced))
                    .foregroundStyle(Fenn.fg.opacity(0.5))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button(ai.isTesting ? tr("Teste …", "Testing …") : tr("Verbindung testen", "Test connection")) {
                    Task { await ai.test() }
                }
                .buttonStyle(FennPillButtonStyle(prominent: ai.config.provider != .claude || ai.hasKey(.claude)))
                .disabled(ai.isTesting)
                if ai.isTesting { ThinkingOrb(state: .searching, size: 20) }
                if ai.config.provider == .claude {
                    Link(tr("Schlüssel holen", "Get a key"), destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                        .font(.fenn(size: 12)).foregroundStyle(Fenn.amber)
                }
                Spacer()
            }
            if let result = ai.testResult {
                Text(result)
                    .font(.fenn(size: 12))
                    .foregroundStyle(ai.testFailed ? Fenn.danger : Fenn.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Fenn.fill))
        .task {
            await ai.loadModels()
            servers = await LocalServers.probe()
        }
        .onChange(of: ai.config) { _, _ in ai.save() }
    }

    private func providerRow(_ label: String, _ providers: [AIProvider]) -> some View {
        HStack(spacing: 6) {
            Text(label.uppercased())
                .font(.fenn(size: 10, weight: .medium))
                .tracking(1)
                .foregroundStyle(Fenn.fg.opacity(0.45))
                .frame(width: 92, alignment: .leading)
            ForEach(providers) { provider in
                let selected = ai.config.provider == provider
                Button { ai.select(provider) } label: {
                    Text(provider == .openAICompatible ? tr("OpenAI-kompatibel", "OpenAI-compatible") : (provider == .apple ? "Apple" : provider.title))
                        .font(.fenn(size: 12, weight: .medium))
                        .foregroundStyle(selected ? Fenn.canvas : Fenn.fg)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(Capsule().fill(selected ? Fenn.fg : Fenn.fillStrong))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Ollama or LM Studio already running on this Mac – said once, with what they have.
    private var serverLine: String? {
        switch ai.config.provider {
        case .ollama:
            guard let names = servers.ollama else { return nil }
            return names.isEmpty ? tr("Ollama läuft – noch kein Modell geladen.", "Ollama is running – no model pulled yet.")
                : tr("Ollama läuft – \(names.count) Modell(e) gefunden.", "Ollama is running – \(names.count) model(s) found.")
        case .lmStudio:
            guard let names = servers.lmStudio else { return nil }
            return tr("LM Studio läuft – \(names.count) Modell(e) verfügbar.", "LM Studio is running – \(names.count) model(s) available.")
        default:
            return nil
        }
    }

    private var hint: String? {
        switch ai.config.provider {
        case .fennBrain: return nil
        case .ollama: return servers.ollama == nil
            ? "brew install ollama   ·   ollama serve   ·   ollama pull \(LocalModels.memoryGB >= 16 ? "qwen3.5:9b" : "qwen3.5:4b")"
            : (servers.ollama?.isEmpty == true ? "ollama pull \(LocalModels.memoryGB >= 16 ? "qwen3.5:9b" : "qwen3.5:4b")" : nil)
        case .lmStudio: return servers.lmStudio == nil
            ? tr("LM Studio → Developer → Start Server (Port 1234)", "LM Studio → Developer → Start Server (port 1234)") : nil
        case .openAICompatible: return "vllm serve Qwen/Qwen3.5-9B   →   http://localhost:8000/v1"
        case .openRouter: return "openrouter.ai → Keys"
        case .apple: return FennAI.appleModelAvailable ? nil : tr("Apple Intelligence ist auf diesem Mac nicht aktiv (macOS 26, Einstellungen → Apple Intelligence).",
                                                                   "Apple Intelligence isn't active on this Mac (macOS 26, Settings → Apple Intelligence).")
        case .claude: return nil
        }
    }

    /// The downloadable models: what each is for, its size, the one recommended for this Mac, download progress.
    private var brainPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(LocalModels.catalog) { model in modelRow(model) }
            Text(tr("Läuft komplett auf diesem Mac mit Apple MLX. Dieser Mac hat \(LocalModels.memoryGB) GB Arbeitsspeicher. Mehr dazu in docs/MODELS.md.",
                    "Runs entirely on this Mac with Apple MLX. This Mac has \(LocalModels.memoryGB) GB of memory. More in docs/MODELS.md."))
                .font(.fenn(size: 11)).foregroundStyle(Fenn.fg.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func modelRow(_ model: LocalModel) -> some View {
        let installed = store.installedIDs.contains(model.id)
        let selected = installed && (ai.config.model == model.id || (ai.config.model == "auto" && LocalModels.resolve("auto")?.id == model.id))
        let recommended = model == LocalModels.recommended
        return HStack(alignment: .top, spacing: 8) {
            Button { if installed { ai.config.model = model.id; ai.save() } } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: selected ? "largecircle.fill.circle" : (installed ? "circle" : "arrow.down.circle"))
                        .foregroundStyle(selected ? Fenn.accent : Fenn.fg.opacity(0.35))
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(model.title).font(.fenn(size: 13, weight: .medium)).foregroundStyle(Fenn.fg)
                            Text(model.sizeLabel).font(.fenn(size: 11)).foregroundStyle(Fenn.fg.opacity(0.45))
                            if recommended {
                                Text(tr("Empfohlen", "Recommended"))
                                    .font(.fenn(size: 10, weight: .medium))
                                    .foregroundStyle(Fenn.canvas)
                                    .padding(.horizontal, 6).frame(height: 16)
                                    .background(Capsule().fill(Fenn.accent))
                            }
                        }
                        Text(model.fits ? model.detail : tr("Braucht \(model.minMemoryGB) GB Arbeitsspeicher.", "Needs \(model.minMemoryGB) GB of memory."))
                            .font(.fenn(size: 11.5)).foregroundStyle(Fenn.fg.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)
                        if let fraction = store.progress[model.id] {
                            ProgressView(value: fraction).tint(Fenn.accent).frame(maxWidth: 220)
                        }
                        if let failure = store.failures[model.id] {
                            Text(failure).font(.fenn(size: 11)).foregroundStyle(Fenn.danger)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 4)
            if store.isDownloading(model) {
                Button(tr("Abbrechen", "Cancel")) { store.cancel(model) }.buttonStyle(FennPillButtonStyle())
            } else if installed {
                Button(tr("Löschen", "Delete")) { store.delete(model) }.buttonStyle(FennPillButtonStyle())
            } else {
                Button(tr("Laden", "Download")) {
                    store.download(model) {
                        if ai.config.provider == .fennBrain { ai.config.model = model.id; ai.save() }
                    }
                }
                .buttonStyle(FennPillButtonStyle(prominent: recommended))
                .disabled(!model.fits)
            }
        }
        .opacity(model.fits || installed ? 1 : 0.5)
    }

    private func saveKey() {
        ai.setKey(key)
        key = ""
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        TextField(label, text: text)
            .textFieldStyle(.plain)
            .font(.fenn(size: 13))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Capsule().fill(Fenn.field))
            .overlay(Capsule().strokeBorder(Fenn.hairline))
            .onSubmit { ai.save(); Task { await ai.loadModels() } }
    }
}

/// The answers from the first-run questions, editable any time. Saved as they change (see `PersonProfileStore`).
struct AboutYouCard: View {
    @ObservedObject var store: PersonProfileStore
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation { expanded.toggle() } } label: {
                HStack(spacing: 12) {
                    FennAvatar(size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.profile.name.isEmpty ? tr("Noch nichts über dich", "Nothing about you yet") : store.profile.name)
                            .font(.fenn(size: 14))
                        Text(summary).font(.fenn(size: 12)).foregroundStyle(Fenn.fg.opacity(0.6)).lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").foregroundStyle(Fenn.fg.opacity(0.5))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                field(tr("Name", "Name"), text: $store.profile.name)
                field(tr("Was du beruflich machst", "What you do"), text: $store.profile.role)
                field(tr("Wichtigstes Ziel gerade", "Most important goal right now"), text: $store.profile.goal)
                    .onSubmit { store.commitGoal() }
                chips(PersonProfile.FocusTime.allCases, title: \.title, isOn: { store.profile.focusTime == $0 }) {
                    store.profile.focusTime = store.profile.focusTime == $0 ? nil : $0
                }
                chips(PersonProfile.Help.allCases, title: \.title, isOn: { store.profile.helpWith.contains($0) }) { choice in
                    if let index = store.profile.helpWith.firstIndex(of: choice) { store.profile.helpWith.remove(at: index) } else { store.profile.helpWith.append(choice) }
                }
                chips(PersonProfile.Distraction.allCases, title: \.title, isOn: { store.profile.distractions.contains($0) }) { choice in
                    if let index = store.profile.distractions.firstIndex(of: choice) { store.profile.distractions.remove(at: index) } else { store.profile.distractions.append(choice) }
                }
                chips(PersonProfile.Tone.allCases, title: \.title, isOn: { store.profile.tone == $0 }) {
                    store.profile.tone = store.profile.tone == $0 ? nil : $0
                }
                field(tr("Sonst noch etwas", "Anything else"), text: $store.profile.note)
                Text(tr("Steht für Fenn in profile/profile.md – deine eigenen Zeilen darunter bleiben unberührt.",
                        "Kept for Fenn in profile/profile.md – your own lines below it stay untouched."))
                    .font(.fenn(size: 11)).foregroundStyle(Fenn.fg.opacity(0.45))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Fenn.fill))
    }

    private var summary: String {
        let p = store.profile
        let parts = [p.role, p.goal.isEmpty ? "" : tr("Ziel: \(p.goal)", "Goal: \(p.goal)"), p.focusTime.map { tr("Fokus: \($0.title)", "Focus: \($0.title)") } ?? ""]
            .filter { !$0.isEmpty }
        return parts.isEmpty ? tr("Ein paar Antworten machen Fenn zu deinem Assistenten.", "A few answers make Fenn your assistant.") : parts.joined(separator: ", ")
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        TextField(label, text: text)
            .textFieldStyle(.plain)
            .font(.fenn(size: 13))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Capsule().fill(Fenn.field))
            .overlay(Capsule().strokeBorder(Fenn.hairline))
    }

    private func chips<Item: Identifiable>(_ items: [Item], title: KeyPath<Item, String>, isOn: @escaping (Item) -> Bool,
                                           toggle: @escaping (Item) -> Void) -> some View {
        FlowWrap(spacing: 6) {
            ForEach(items) { item in
                let selected = isOn(item)
                Button { toggle(item) } label: {
                    Text(item[keyPath: title])
                        .font(.fenn(size: 12, weight: .medium))
                        .foregroundStyle(selected ? Fenn.canvas : Fenn.fg)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(Capsule().fill(selected ? Fenn.fg : Fenn.fillStrong))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
