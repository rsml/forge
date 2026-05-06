import Foundation
import AppKit
import ForgeCore

/// Response handlers for each debug server endpoint.
extension DebugServer {

    func screenshotResponse() async -> HTTPResponse {
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

        let path = "/tmp/forge-screenshot.png"
        try? pngData.write(to: URL(fileURLWithPath: path))

        return HTTPResponse(status: "200 OK", contentType: "image/png", body: pngData)
    }

    func stateResponse() -> HTTPResponse {
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

    func actionResponse(body: String?) async -> HTTPResponse {
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
            await ctrl.syncEngine.refresh()
            return jsonResponse(["ok": true])

        default:
            return jsonResponse(["error": "Unknown action: \(action)"], status: "400 Bad Request")
        }
    }

    func logsResponse() -> HTTPResponse {
        let path = ForgeLog.logFile
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let text = String(data: data, encoding: .utf8) else {
            return jsonResponse(["logs": ""])
        }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let recent = lines.suffix(50).joined(separator: "\n")
        return jsonResponse(["logs": recent])
    }

    func jsonResponse(_ dict: [String: Any], status: String = "200 OK") -> HTTPResponse {
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
