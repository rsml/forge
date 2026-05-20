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
                        "kind": pane.kind.rawValue,
                        "command": pane.terminalState?.currentCommand ?? "",
                        "path": pane.terminalState?.currentPath ?? "",
                        "status": pane.terminalState?.status.rawValue ?? "",
                        "hasBell": pane.terminalState?.hasBell ?? false,
                        "hasContentMatch": pane.terminalState?.hasContentMatch ?? false,
                        "isSilentWaiting": pane.terminalState?.isSilentWaiting ?? false,
                        "needsAttention": pane.needsAttention,
                        "size": pane.terminalState.map { "\($0.width)x\($0.height)" } ?? ""
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
                await ctrl.removeProject(project)
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
            // Native PTY has no refresh cycle — state is event-driven.
            return jsonResponse(["ok": true])

        case "splitPane":
            let dir = (args["direction"] as? String) == "horizontal"
                ? SplitDirection.horizontal : SplitDirection.vertical
            ctrl.splitPane(direction: dir)
            return jsonResponse(["ok": true])

        case "sendKeys":
            guard let paneId = args["paneId"] as? String else {
                return jsonResponse(["error": "Missing paneId"], status: "400 Bad Request")
            }
            guard let renderer = ctrl.paneRenderers[paneId] as? GhosttyRenderer else {
                return jsonResponse(["error": "No renderer for pane"], status: "404 Not Found")
            }
            let bytes: Data
            if let text = args["text"] as? String {
                bytes = Data(text.utf8)
            } else if let hex = args["hex"] as? String {
                bytes = Data(hex.split(separator: " ").compactMap { UInt8($0, radix: 16) })
            } else {
                return jsonResponse(["error": "Provide text or hex"], status: "400 Bad Request")
            }
            renderer.sendInput(bytes)
            return jsonResponse(["ok": true, "bytes": bytes.count])

        case "stackDismiss":
            let mode = args["mode"] as? String ?? "done"
            let dismissAction: WorkspaceController.StackDismissAction
            switch mode {
            case "done":       dismissAction = .done
            case "hide":       dismissAction = .hide
            case "moveToBack": dismissAction = .moveToBack
            default:
                return jsonResponse(["error": "mode must be done|hide|moveToBack"], status: "400 Bad Request")
            }
            ctrl.stackDismiss(dismissAction)
            return jsonResponse(["ok": true, "mode": mode])

        case "setMode":
            let mode = args["mode"] as? String ?? ""
            switch mode {
            case "stack": ctrl.config.isStackMode = true
            case "list":  ctrl.config.isStackMode = false
            default:
                return jsonResponse(["error": "mode must be stack|list"], status: "400 Bad Request")
            }
            return jsonResponse(["ok": true, "mode": mode])

        default:
            return jsonResponse(["error": "Unknown action: \(action)"], status: "400 Bad Request")
        }
    }

    func titlebarResponse() -> HTTPResponse {
        guard let window = NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }),
              let themeFrame = window.contentView?.superview else {
            return jsonResponse(["error": "No window"])
        }

        func findTitlebarContainer(in view: NSView) -> NSView? {
            if String(describing: type(of: view)) == "NSTitlebarContainerView" { return view }
            for sub in view.subviews {
                if let found = findTitlebarContainer(in: sub) { return found }
            }
            return nil
        }

        guard let container = findTitlebarContainer(in: themeFrame) else {
            return jsonResponse(["error": "NSTitlebarContainerView not found"])
        }

        func hexColor(_ cgColor: CGColor?) -> String? {
            guard let c = cgColor, let rgb = c.converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil) else { return nil }
            guard let comps = rgb.components, comps.count >= 3 else { return nil }
            let r = Int(comps[0] * 255), g = Int(comps[1] * 255), b = Int(comps[2] * 255)
            let a = comps.count > 3 ? comps[3] : 1.0
            return String(format: "#%02X%02X%02X (a=%.2f)", r, g, b, a)
        }

        func dumpView(_ view: NSView, depth: Int) -> [String: Any] {
            var info: [String: Any] = [
                "class": String(describing: type(of: view)),
                "frame": "\(view.frame)",
                "isHidden": view.isHidden,
                "isOpaque": view.isOpaque,
                "alphaValue": view.alphaValue,
                "wantsLayer": view.wantsLayer,
                "depth": depth
            ]
            if let layer = view.layer {
                info["layer.backgroundColor"] = hexColor(layer.backgroundColor) ?? "nil"
                info["layer.isOpaque"] = layer.isOpaque
            }
            if view.wantsLayer, view.layer == nil {
                info["layer"] = "wantsLayer=true but layer is nil"
            }
            if let effectView = view as? NSVisualEffectView {
                info["material"] = effectView.material.rawValue
                info["blendingMode"] = effectView.blendingMode.rawValue
                info["state"] = effectView.state.rawValue
                info["isEmphasized"] = effectView.isEmphasized
            }
            if let bgColor = view.value(forKey: "backgroundColor") as? NSColor {
                info["backgroundColor(KVC)"] = hexColor(bgColor.cgColor) ?? "\(bgColor)"
            }
            if view.responds(to: NSSelectorFromString("drawsBackground")) {
                info["drawsBackground"] = view.value(forKey: "drawsBackground") as? Bool ?? "unknown"
            }
            info["subviews"] = view.subviews.map { dumpView($0, depth: depth + 1) }
            return info
        }

        let dump = dumpView(container, depth: 0)
        return jsonResponse(dump)
    }

    func paneSizesResponse() -> HTTPResponse {
        guard let ctrl = controller else {
            return jsonResponse(["error": "No controller"])
        }

        let ws = ctrl.workspace

        // Collect per-pane sizing info across all panes in the active tab.
        var paneEntries: [[String: Any]] = []
        let activePanes: [Pane] = ws.activeProject.flatMap { project in
            project.tabs.first(where: { $0.id == ws.activeTabId })?.panes
        } ?? []

        for pane in activePanes {
            guard let ts = pane.terminalState else {
                paneEntries.append(["paneId": pane.id, "kind": pane.kind.rawValue])
                continue
            }
            var entry: [String: Any] = [
                "paneId": pane.id,
                "tmux": [
                    "cols": ts.width,
                    "rows": ts.height
                ]
            ]

            if let renderer = ctrl.paneRenderers[pane.id] {
                let frame = renderer.view.frame
                entry["swiftUIFrame"] = [
                    "width": frame.width,
                    "height": frame.height
                ]

                // Grid from the renderer's last reported resize.
                let gridSize: (cols: Int, rows: Int)?
                if let ghostty = renderer as? GhosttyRenderer {
                    gridSize = ghostty.lastReportedSize
                } else {
                    gridSize = nil
                }

                if let grid = gridSize {
                    entry["rendererGrid"] = ["cols": grid.cols, "rows": grid.rows]
                    if grid.cols > 0, grid.rows > 0, frame.width > 0, frame.height > 0 {
                        entry["computedCellSize"] = [
                            "width": frame.width / CGFloat(grid.cols),
                            "height": frame.height / CGFloat(grid.rows)
                        ]
                    }
                } else {
                    entry["rendererGrid"] = "not yet reported"
                }

                // Mismatch flag — makes it easy to grep the JSON output.
                if let grid = gridSize {
                    entry["mismatch"] = grid.cols != ts.width || grid.rows != ts.height
                }
            } else {
                entry["renderer"] = "none"
            }

            paneEntries.append(entry)
        }

        var result: [String: Any] = [
            "panes": paneEntries,
            "terminalAreaSize": [
                "width": ctrl.terminalAreaSize.width,
                "height": ctrl.terminalAreaSize.height
            ],
            "terminalCellSize": [
                "width": ctrl.terminalCellSize.width,
                "height": ctrl.terminalCellSize.height
            ],
            "activeProjectId": ws.activeProjectId ?? "",
            "activeTabId": ws.activeTabId ?? ""
        ]

        // Summary: are all panes matched?
        let mismatches = paneEntries.filter { ($0["mismatch"] as? Bool) == true }
        result["summary"] = mismatches.isEmpty
            ? "ok — all renderer grids match tmux pane dimensions"
            : "\(mismatches.count) pane(s) have renderer/tmux dimension mismatch"

        return jsonResponse(result)
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
