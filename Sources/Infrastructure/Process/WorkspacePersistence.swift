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

    // Recursive split tree
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

    /// Save current workspace state.
    static func save(workspace: Workspace, windowFrame: NSRect?) {
        var projects: [PersistedProject] = []
        for project in workspace.projects {
            var tabs: [PersistedTab] = []
            for tab in project.tabs {
                let panes = tab.panes.map { PersistedPane(id: $0.id, cwd: $0.currentPath) }
                // TODO: persist split tree from tab.splitTree when available
                tabs.append(PersistedTab(id: tab.id, name: tab.name, panes: panes, splitTree: nil))
            }
            projects.append(PersistedProject(id: project.id, name: project.name, path: project.path, tabs: tabs))
        }

        let frame: WindowFrame? = windowFrame.map {
            WindowFrame(x: $0.origin.x, y: $0.origin.y, width: $0.size.width, height: $0.size.height)
        }

        let ws = PersistedWorkspace(
            projects: projects,
            activeProjectId: workspace.activeProjectId,
            activeTabId: workspace.activeTabId,
            windowFrame: frame
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

    /// Load persisted workspace state.
    static func load() -> PersistedWorkspace? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else { return nil }
        return try? JSONDecoder().decode(PersistedWorkspace.self, from: data)
    }
}
