import AppKit
import Foundation
import ForgeCore

/// Saves and loads workspace structure for native PTY mode.
/// Written on every structural change. Read on startup for reconnection.
@MainActor
enum WorkspacePersistence {

    struct PersistedWorkspace: Codable {
        var version: Int = 1
        var projects: [PersistedProject]
        var activeProjectId: String?
        var activeTabId: String?
        var windowFrame: WindowFrame?
        var fullscreen: Bool?
    }

    struct PersistedProject: Codable {
        var id: String
        var name: String
        var path: String?
        var tabs: [PersistedTab]
    }

    struct PersistedTab: Codable {
        var id: String
        var name: String
        var panes: [PersistedPane]
        var splitTree: PersistedSplitNode?
    }

    struct PersistedPane: Codable {
        var id: String
        var cwd: String
    }

    indirect enum PersistedSplitNode: Codable {
        case leaf
        case split(direction: String, children: [PersistedSplitNode], proportions: [Double])
    }

    struct WindowFrame: Codable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
    }

    private static let filePath: String = {
        let dir = NSHomeDirectory() + "/.config/forge"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir + "/workspace.json"
    }()

    // MARK: - Save

    static func save(workspace: Workspace, windowFrame: NSRect?) {
        var projects: [PersistedProject] = []
        for project in workspace.projects {
            var tabs: [PersistedTab] = []
            for tab in project.tabs {
                let panes = tab.panes.map { PersistedPane(id: $0.id, cwd: $0.currentPath) }
                let tree = tab.splitTree.map { encodeSplitNode($0) }
                tabs.append(PersistedTab(id: tab.id, name: tab.name, panes: panes, splitTree: tree))
            }
            projects.append(PersistedProject(id: project.id, name: project.name, path: project.path, tabs: tabs))
        }

        let frame: WindowFrame? = windowFrame.map {
            WindowFrame(x: $0.origin.x, y: $0.origin.y, width: $0.size.width, height: $0.size.height)
        }

        let isFullscreen = NSApp.mainWindow?.styleMask.contains(.fullScreen) ?? false

        let ws = PersistedWorkspace(
            projects: projects,
            activeProjectId: workspace.activeProjectId,
            activeTabId: workspace.activeTabId,
            windowFrame: frame,
            fullscreen: isFullscreen
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(ws)
            try data.write(to: URL(fileURLWithPath: filePath), options: .atomic)
        } catch {
            ForgeLog.log("[workspace] Failed to save: \(error)")
        }
    }

    // MARK: - Load

    static func load() -> PersistedWorkspace? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else { return nil }
        return try? JSONDecoder().decode(PersistedWorkspace.self, from: data)
    }

    // MARK: - SplitNode ↔ PersistedSplitNode

    static func encodeSplitNode(_ node: SplitNode) -> PersistedSplitNode {
        switch node {
        case .leaf:
            return .leaf
        case .split(let direction, let children, let proportions):
            let dir = direction == .horizontal ? "horizontal" : "vertical"
            return .split(
                direction: dir,
                children: children.map { encodeSplitNode($0) },
                proportions: proportions.map { Double($0) }
            )
        }
    }

    static func decodeSplitNode(_ node: PersistedSplitNode) -> SplitNode {
        switch node {
        case .leaf:
            return .leaf
        case .split(let direction, let children, let proportions):
            let dir: SplitDirection = direction == "horizontal" ? .horizontal : .vertical
            return .split(
                dir,
                children.map { decodeSplitNode($0) },
                proportions: proportions.map { CGFloat($0) }
            )
        }
    }
}
