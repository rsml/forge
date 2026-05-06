import Foundation
import AppKit
import Network
import ForgeCore

/// Lightweight HTTP debug server running inside Forge.
/// Lets Claude (or any tool) take screenshots, read state, and send actions.
///
/// Endpoints:
///   GET  /screenshot    — PNG of the app window
///   GET  /state         — JSON workspace state
///   POST /action        — execute an action (body: {"action": "...", "args": {...}})
///   GET  /logs          — recent log lines
///   GET  /ping          — health check
@MainActor
final class DebugServer {
    private var listener: NWListener?
    private weak var controller: WorkspaceController?
    let port: UInt16

    init(port: UInt16 = 7654) {
        self.port = port
    }

    func start(controller: WorkspaceController) {
        self.controller = controller

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        guard let listener = try? NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!) else {
            ForgeLog.log("[debug] Failed to create listener on port \(port)")
            return
        }

        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handleConnection(connection)
            }
        }

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                ForgeLog.log("[debug] Server listening on http://localhost:\(self.port)")
            case .failed(let error):
                ForgeLog.log("[debug] Server failed: \(error)")
            default:
                break
            }
        }

        listener.start(queue: .main)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        // Accumulate data until we have the full HTTP request (headers + body)
        receiveFullRequest(connection: connection, accumulated: Data())
    }

    private func receiveFullRequest(connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            guard let data, error == nil else { connection.cancel(); return }

            var all = accumulated
            all.append(data)

            let text = String(data: all, encoding: .utf8) ?? ""

            // Check if we have the full request (headers + body based on Content-Length)
            if let headerEnd = text.range(of: "\r\n\r\n") {
                let headers = String(text[..<headerEnd.lowerBound])
                let bodyReceived = text[headerEnd.upperBound...]

                // Parse Content-Length
                var expectedLength = 0
                for line in headers.split(separator: "\r\n") {
                    if line.lowercased().hasPrefix("content-length:") {
                        expectedLength = Int(line.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "0") ?? 0
                    }
                }

                if bodyReceived.utf8.count >= expectedLength || isComplete {
                    Task { @MainActor in
                        let response = await self.handleRequest(text)
                        self.sendResponse(connection: connection, response: response)
                    }
                    return
                }
            }

            if isComplete {
                Task { @MainActor in
                    let response = await self.handleRequest(text)
                    self.sendResponse(connection: connection, response: response)
                }
            } else {
                // Need more data
                self.receiveFullRequest(connection: connection, accumulated: all)
            }
        }
    }

    private func sendResponse(connection: NWConnection, response: HTTPResponse) {
        var header = "HTTP/1.1 \(response.status)\r\n"
        header += "Content-Type: \(response.contentType)\r\n"
        header += "Content-Length: \(response.body.count)\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "Connection: close\r\n"
        header += "\r\n"

        var fullData = header.data(using: .utf8)!
        fullData.append(response.body)

        connection.send(content: fullData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Request Routing

    private func handleRequest(_ raw: String) async -> HTTPResponse {
        let lines = raw.split(separator: "\r\n", maxSplits: 1)
        guard let requestLine = lines.first else {
            return HTTPResponse(status: "400 Bad Request", body: "Bad request".data(using: .utf8)!)
        }

        let parts = requestLine.split(separator: " ")
        let method = parts.count > 0 ? String(parts[0]) : "GET"
        let path = parts.count > 1 ? String(parts[1]) : "/"

        // Extract body for POST
        let body: String? = {
            guard let bodyStart = raw.range(of: "\r\n\r\n") else { return nil }
            let bodyStr = String(raw[bodyStart.upperBound...])
            return bodyStr.isEmpty ? nil : bodyStr
        }()

        switch (method, path) {
        case ("GET", "/ping"):
            return jsonResponse(["status": "ok", "app": "Forge"])

        case ("GET", "/screenshot"):
            return await screenshotResponse()

        case ("GET", "/state"):
            return stateResponse()

        case ("POST", "/action"):
            return await actionResponse(body: body)

        case ("GET", "/logs"):
            return logsResponse()

        default:
            return jsonResponse(["error": "Not found", "path": path], status: "404 Not Found")
        }
    }

    // MARK: - /screenshot

    private func screenshotResponse() async -> HTTPResponse {
        guard let window = NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }) else {
            return jsonResponse(["error": "No visible window"], status: "404 Not Found")
        }

        guard let cgImage = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            CGWindowID(window.windowNumber),
            [.boundsIgnoreFraming]
        ) else {
            return jsonResponse(["error": "Failed to capture window"], status: "500 Internal Server Error")
        }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return jsonResponse(["error": "Failed to encode PNG"], status: "500 Internal Server Error")
        }

        // Also save to disk so Claude can Read the file
        let path = "/tmp/forge-screenshot.png"
        try? pngData.write(to: URL(fileURLWithPath: path))

        return HTTPResponse(status: "200 OK", contentType: "image/png", body: pngData)
    }

    // MARK: - /state

    private func stateResponse() -> HTTPResponse {
        guard let ctrl = controller else {
            return jsonResponse(["error": "No controller"])
        }

        let ws = ctrl.workspace
        let sessions: [[String: Any]] = ws.projects.map { project in
            let windows: [[String: Any]] = project.tabs.map { tab in
                let panes: [[String: Any]] = tab.panes.map { pane in
                    [
                        "id": pane.id,
                        "index": pane.index,
                        "active": pane.active,
                        "command": pane.currentCommand,
                        "path": pane.currentPath,
                        "status": pane.status.rawValue,
                        "hasBell": pane.hasBell,
                        "size": "\(pane.width)x\(pane.height)"
                    ]
                }
                return [
                    "id": tab.id,
                    "index": tab.index,
                    "name": tab.name,
                    "active": tab.active,
                    "panes": panes
                ]
            }
            return [
                "id": project.id,
                "name": project.name,
                "tabCount": project.tabCount,
                "attached": project.attached,
                "path": project.path ?? "",
                "needsAttention": project.needsAttention,
                "windows": windows
            ]
        }

        let state: [String: Any] = [
            "connected": ws.connected,
            "activeProjectId": ws.activeProjectId ?? "",
            "activeTabId": ws.activeTabId ?? "",
            "activePaneId": ws.activePaneId ?? "",
            "sessionCount": ws.projects.count,
            "sessions": sessions
        ]

        return jsonResponse(state)
    }

    // MARK: - /action

    private func actionResponse(body: String?) async -> HTTPResponse {
        guard let ctrl = controller else {
            return jsonResponse(["error": "No controller"])
        }

        guard let body, let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = json["action"] as? String else {
            return jsonResponse(["error": "Invalid body. Expected {\"action\": \"...\", \"args\": {...}}"],
                              status: "400 Bad Request")
        }

        let args = json["args"] as? [String: Any] ?? [:]

        switch action {
        case "selectProject":
            if let id = args["id"] as? String,
               let project = ctrl.workspace.project(byId: id) {
                ctrl.selectProject(project)
                return jsonResponse(["ok": true, "selected": project.name])
            }
            // Also support by name
            if let name = args["name"] as? String,
               let project = ctrl.workspace.projects.first(where: { $0.name == name }) {
                ctrl.selectProject(project)
                return jsonResponse(["ok": true, "selected": project.name])
            }
            return jsonResponse(["error": "Project not found"], status: "404 Not Found")

        case "selectTab":
            if let id = args["id"] as? String,
               let project = ctrl.workspace.activeProject,
               let tab = project.tabs.first(where: { $0.id == id }) {
                ctrl.selectTab(tab)
                return jsonResponse(["ok": true, "selected": tab.name])
            }
            if let index = args["index"] as? Int,
               let project = ctrl.workspace.activeProject,
               let tab = project.tabs.first(where: { $0.index == index }) {
                ctrl.selectTab(tab)
                return jsonResponse(["ok": true, "selected": tab.name])
            }
            return jsonResponse(["error": "Tab not found"], status: "404 Not Found")

        case "addProject":
            let name = args["name"] as? String ?? "new-project"
            let path = args["path"] as? String ?? NSHomeDirectory()
            await ctrl.addProject(name: name, path: path)
            return jsonResponse(["ok": true, "created": name])

        case "removeProject":
            if let name = args["name"] as? String,
               let project = ctrl.workspace.projects.first(where: { $0.name == name }) {
                ctrl.removeProject(project)
                return jsonResponse(["ok": true, "removed": name])
            }
            return jsonResponse(["error": "Project not found"], status: "404 Not Found")

        case "addTab":
            if let project = ctrl.workspace.activeProject {
                ctrl.addTab(in: project)
                return jsonResponse(["ok": true, "project": project.name])
            }
            return jsonResponse(["error": "No active project"])

        case "refresh":
            await ctrl.refresh()
            return jsonResponse(["ok": true])

        default:
            return jsonResponse(["error": "Unknown action: \(action)"], status: "400 Bad Request")
        }
    }

    // MARK: - /logs

    private func logsResponse() -> HTTPResponse {
        let path = ForgeLog.logFile
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let text = String(data: data, encoding: .utf8) else {
            return jsonResponse(["logs": ""])
        }

        // Return last 50 lines
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let recent = lines.suffix(50).joined(separator: "\n")
        return jsonResponse(["logs": recent])
    }

    // MARK: - Helpers

    private func jsonResponse(_ dict: [String: Any], status: String = "200 OK") -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted))
            ?? "{}".data(using: .utf8)!
        return HTTPResponse(status: status, contentType: "application/json", body: data)
    }
}

struct HTTPResponse {
    let status: String
    let contentType: String
    let body: Data

    init(status: String = "200 OK", contentType: String = "application/json", body: Data) {
        self.status = status
        self.contentType = contentType
        self.body = body
    }
}
