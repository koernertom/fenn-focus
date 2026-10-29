import Foundation
import Network
import SwiftUI
import AppKit

/// Fenn as an MCP server on this Mac: Claude Code, Cursor or any other agent can read and – if allowed – change
/// tasks, routines, focus and the day through the same tools Fenn's own agent uses.
/// Streamable HTTP (JSON responses, no SSE) on 127.0.0.1 only, guarded by a bearer token. Off until switched on.
@MainActor
final class FennMCPServer: ObservableObject {
    static let shared = FennMCPServer()

    enum Access: String, CaseIterable, Identifiable {
        case read, write
        var id: String { rawValue }
        var title: String { self == .read ? tr("Nur lesen", "Read only") : tr("Lesen und ändern", "Read and change") }
    }

    struct Call: Identifiable {
        let id = UUID()
        let tool: String
        let at: Date
        let ok: Bool
    }

    static let port: UInt16 = 43211
    static var endpoint: String { "http://127.0.0.1:\(port)/mcp" }
    /// Tools that only look; everything else changes something and needs "Lesen und ändern".
    static let readTools: Set<String> = ["day_schedule", "list_habits", "list_ideas", "list_tasks", "today_overview"]

    @Published var enabled: Bool { didSet { UserDefaults.standard.set(enabled, forKey: "fenn.mcp.enabled"); enabled ? start() : stop() } }
    @Published var access: Access { didSet { UserDefaults.standard.set(access.rawValue, forKey: "fenn.mcp.access") } }
    @Published private(set) var token: String
    @Published private(set) var isRunning = false
    @Published private(set) var error: String?
    @Published private(set) var calls: [Call] = []

    /// Set by the island: the agent's tools (same list Fenn's chat uses).
    var tools: () -> [AgentTool] = { FennAgent.shared.tools }
    private var listener: NWListener?

    private init() {
        enabled = UserDefaults.standard.bool(forKey: "fenn.mcp.enabled")
        access = Access(rawValue: UserDefaults.standard.string(forKey: "fenn.mcp.access") ?? "") ?? .read
        token = UserDefaults.standard.string(forKey: "fenn.mcp.token") ?? Self.newToken()
        UserDefaults.standard.set(token, forKey: "fenn.mcp.token")
    }

    func startIfEnabled() { if enabled { start() } }

    func renewToken() {
        token = Self.newToken()
        UserDefaults.standard.set(token, forKey: "fenn.mcp.token")
    }

    private static func newToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return "fenn_" + bytes.map { String(format: "%02x", $0) }.joined()
    }

    var claudeCodeCommand: String {
        "claude mcp add --transport http fenn \(Self.endpoint) --header \"Authorization: Bearer \(token)\""
    }

    var jsonConfig: String {
        """
        {
          "mcpServers": {
            "fenn-focus": {
              "type": "http",
              "url": "\(Self.endpoint)",
              "headers": { "Authorization": "Bearer \(token)" }
            }
          }
        }
        """
    }

    // MARK: Listener

    private func start() {
        guard listener == nil else { return }
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready: self?.isRunning = true; self?.error = nil
                    case .failed(let failure):
                        self?.isRunning = false
                        self?.error = tr("Port \(Self.port) ist belegt oder gesperrt: \(failure.localizedDescription)",
                                         "Port \(Self.port) is taken or blocked: \(failure.localizedDescription)")
                        self?.listener?.cancel()
                        self?.listener = nil
                    case .cancelled: self?.isRunning = false
                    default: break
                    }
                }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(connection, buffer: Data())
    }

    /// Reads one HTTP request (headers + Content-Length body), answers it, closes the connection.
    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, complete, failure in
            Task { @MainActor in
                guard let self else { return }
                var buffer = buffer
                if let data { buffer.append(data) }
                if let request = HTTPRequest(buffer) {
                    let response = await self.respond(to: request)
                    connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
                } else if complete || failure != nil || buffer.count > 4 << 20 {
                    connection.cancel()
                } else {
                    self.receive(connection, buffer: buffer)
                }
            }
        }
    }

    // MARK: HTTP + JSON-RPC

    private func respond(to request: HTTPRequest) async -> Data {
        // Browsers send an Origin: only local pages may talk to Fenn (DNS-rebinding guard from the MCP spec).
        if let origin = request.headers["origin"], !(origin.contains("://127.0.0.1") || origin.contains("://localhost")) {
            return HTTPRequest.reply(403, json: ["error": "origin not allowed"])
        }
        guard request.headers["authorization"] == "Bearer \(token)" else {
            return HTTPRequest.reply(401, json: ["error": "missing or wrong bearer token"])
        }
        guard request.path.hasPrefix("/mcp") else { return HTTPRequest.reply(404, json: ["error": "not found"]) }
        switch request.method {
        case "POST": break
        case "DELETE": return HTTPRequest.reply(200, json: [:])
        default: return HTTPRequest.reply(405, json: ["error": "use POST"])
        }
        guard let object = try? JSONSerialization.jsonObject(with: request.body) else {
            return HTTPRequest.reply(400, json: Self.failure(id: NSNull(), code: -32700, message: "Parse error"))
        }
        if let batch = object as? [[String: Any]] {
            var answers: [[String: Any]] = []
            for message in batch { if let answer = await handle(message) { answers.append(answer) } }
            return answers.isEmpty ? HTTPRequest.reply(202, body: Data()) : HTTPRequest.reply(200, jsonArray: answers)
        }
        guard let message = object as? [String: Any] else {
            return HTTPRequest.reply(400, json: Self.failure(id: NSNull(), code: -32600, message: "Invalid Request"))
        }
        guard let answer = await handle(message) else { return HTTPRequest.reply(202, body: Data()) }
        return HTTPRequest.reply(200, json: answer)
    }

    /// One JSON-RPC message; nil for notifications.
    private func handle(_ message: [String: Any]) async -> [String: Any]? {
        let id = message["id"]
        let method = message["method"] as? String ?? ""
        let params = message["params"] as? [String: Any] ?? [:]
        guard let id else { return nil } // notifications/initialized and friends
        switch method {
        case "initialize":
            let asked = params["protocolVersion"] as? String
            let supported = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
            return Self.success(id: id, result: [
                "protocolVersion": supported.contains(asked ?? "") ? asked! : supported[0],
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "fenn-focus", "title": "Fenn Focus", "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"],
                "instructions": "Fenn ist der Coach und Tagesplaner dieser Person (Aufgaben, Routinen, Fokus, Termine). "
                    + "Antworte auf Deutsch, wenn die Person Deutsch spricht. Ändere nur, worum gebeten wurde.",
            ])
        case "ping":
            return Self.success(id: id, result: [:])
        case "tools/list":
            let list = allowedTools.map { tool -> [String: Any] in
                ["name": tool.name, "description": tool.description, "inputSchema": tool.parameters,
                 "annotations": ["readOnlyHint": Self.readTools.contains(tool.name)]]
            }
            return Self.success(id: id, result: ["tools": list])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            guard let tool = tools().first(where: { $0.name == name }) else {
                return Self.failure(id: id, code: -32602, message: "Unknown tool: \(name)")
            }
            guard allowedTools.contains(where: { $0.name == name }) else {
                log(name, ok: false)
                return Self.success(id: id, result: ["isError": true, "content": [["type": "text", "text":
                    "Fenn erlaubt gerade nur Lesen. Die Person kann unter Verbindungen › Fenn als MCP-Server „Lesen und ändern“ einschalten."]]])
            }
            let result = await tool.run(arguments)
            log(name, ok: true)
            if let action = result.action { FennAgent.shared.show(AgentItem(kind: .action(symbol: result.symbol), text: "MCP: " + action)) }
            return Self.success(id: id, result: ["isError": false, "content": [["type": "text", "text": result.text]]])
        default:
            return Self.failure(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    private var allowedTools: [AgentTool] {
        tools().filter { access == .write || Self.readTools.contains($0.name) }
    }

    private func log(_ tool: String, ok: Bool) {
        calls.insert(Call(tool: tool, at: Date(), ok: ok), at: 0)
        if calls.count > 12 { calls.removeLast(calls.count - 12) }
    }

    private static func success(id: Any, result: [String: Any]) -> [String: Any] { ["jsonrpc": "2.0", "id": id, "result": result] }
    private static func failure(id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }
}

/// Just enough HTTP/1.1 for a local MCP endpoint: request line, headers, a Content-Length body.
private struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    /// nil until the whole request is in the buffer.
    init?(_ data: Data) {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: data[data.startIndex..<end.lowerBound], encoding: .utf8) else { return nil }
        var lines = head.components(separatedBy: "\r\n")
        let start = lines.removeFirst().split(separator: " ")
        guard start.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = end.upperBound
        guard data.count - (bodyStart - data.startIndex) >= length else { return nil }
        method = String(start[0])
        path = String(start[1])
        self.headers = headers
        body = data[bodyStart..<(bodyStart + length)]
    }

    static func reply(_ status: Int, json: [String: Any]) -> Data {
        reply(status, body: (try? JSONSerialization.data(withJSONObject: json)) ?? Data(), type: "application/json")
    }

    static func reply(_ status: Int, jsonArray: [[String: Any]]) -> Data {
        reply(status, body: (try? JSONSerialization.data(withJSONObject: jsonArray)) ?? Data(), type: "application/json")
    }

    static func reply(_ status: Int, body: Data, type: String? = nil) -> Data {
        let reason = [200: "OK", 202: "Accepted", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden",
                      404: "Not Found", 405: "Method Not Allowed"][status] ?? "OK"
        var head = "HTTP/1.1 \(status) \(reason)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
        if let type { head += "Content-Type: \(type)\r\n" }
        head += "\r\n"
        return Data(head.utf8) + body
    }
}

/// Connections › "Fenn als MCP-Server": on/off, read or change, and the lines to paste into Claude Code or Cursor.
struct MCPServerCard: View {
    @ObservedObject var server = FennMCPServer.shared
    @State private var copied: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $server.enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Fenn für andere KI-Agenten öffnen", "Open Fenn to other AI agents")).font(.fenn(size: 14, weight: .medium))
                    Text(tr("Claude Code, Cursor & Co. sehen dann deine Aufgaben, Routinen und deinen Tag – nur auf diesem Mac.",
                            "Claude Code, Cursor & co. can then see your tasks, routines and day – on this Mac only."))
                        .font(.fenn(size: 12)).foregroundStyle(Fenn.fg.opacity(0.6))
                }
            }
            .toggleStyle(.switch).tint(Fenn.accent)
            if server.enabled {
                Picker(tr("Zugriff", "Access"), selection: $server.access) {
                    ForEach(FennMCPServer.Access.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(server.access == .read
                     ? tr("Agenten können nur nachsehen. Anlegen, abhaken oder Fokus starten geht erst nach deiner Freigabe hier.",
                          "Agents can only look. Adding, ticking off or starting focus needs your go-ahead here first.")
                     : tr("Agenten dürfen Aufgaben anlegen, abhaken, Fokus starten und Modi wechseln. Jede Änderung erscheint im Fenn-Chat.",
                          "Agents may add and tick off tasks, start focus and switch modes. Every change shows up in Fenn's chat."))
                    .font(.fenn(size: 12)).foregroundStyle(Fenn.fg.opacity(0.6))
                HStack(spacing: 6) {
                    Circle().fill(server.isRunning ? Color.green : Fenn.danger).frame(width: 7, height: 7)
                    Text(server.isRunning ? FennMCPServer.endpoint : (server.error ?? tr("Startet …", "Starting …")))
                        .font(.fenn(size: 12).monospaced()).foregroundStyle(Fenn.fg.opacity(0.8)).textSelection(.enabled)
                }
                copyRow(tr("Claude Code", "Claude Code"), server.claudeCodeCommand)
                copyRow(tr("Cursor / JSON", "Cursor / JSON"), server.jsonConfig)
                HStack {
                    Button(tr("Neuen Schlüssel erzeugen", "New key")) { server.renewToken() }
                        .buttonStyle(.plain).font(.fenn(size: 12, weight: .medium)).foregroundStyle(Fenn.accent)
                    Text(tr("Alte Verbindungen müssen dann neu eingerichtet werden.", "Existing connections then need setting up again."))
                        .font(.fenn(size: 11)).foregroundStyle(Fenn.fg.opacity(0.5))
                }
                if !server.calls.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("ZULETZT", "RECENT")).font(.fenn(size: 10, weight: .medium)).tracking(1.1).foregroundStyle(Fenn.fg.opacity(0.5))
                        ForEach(server.calls) { call in
                            HStack(spacing: 6) {
                                Image(systemName: call.ok ? "checkmark.circle" : "hand.raised").foregroundStyle(call.ok ? Fenn.accent : Fenn.danger)
                                Text(call.tool).font(.fenn(size: 12).monospaced())
                                Spacer()
                                Text(call.at.formatted(date: .omitted, time: .shortened)).font(.fenn(size: 11)).foregroundStyle(Fenn.fg.opacity(0.5))
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .fennGlass(cornerRadius: 18, shadow: false)
    }

    private func copyRow(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.fenn(size: 12, weight: .semibold)).foregroundStyle(Fenn.fg.opacity(0.8))
                Spacer()
                Button(copied == title ? tr("Kopiert", "Copied") : tr("Kopieren", "Copy")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = title
                }
                .buttonStyle(.plain).font(.fenn(size: 12, weight: .medium)).foregroundStyle(Fenn.accent)
            }
            Text(text).font(.system(size: 11, design: .monospaced)).foregroundStyle(Fenn.fg.opacity(0.75))
                .lineLimit(8).textSelection(.enabled)
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Fenn.fill))
        }
    }
}
