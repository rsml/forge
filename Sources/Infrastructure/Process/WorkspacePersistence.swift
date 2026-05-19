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
        /// Pane-kind discriminator. Absent in legacy workspaces (decoded as `.terminal()`).
        var content: PersistedPaneContent?

        enum CodingKeys: String, CodingKey { case id, cwd, content }

        init(id: String, cwd: String, content: PersistedPaneContent?) {
            self.id = id
            self.cwd = cwd
            self.content = content
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try c.decode(String.self, forKey: .id)
            self.cwd = (try? c.decode(String.self, forKey: .cwd)) ?? ""
            // Missing `content` field → legacy workspace → default to terminal.
            self.content = (try? c.decode(PersistedPaneContent.self, forKey: .content)) ?? .terminal
        }
    }

    /// Discriminated union for pane content. Adding new cases here is the
    /// expected place to extend persistence for new pane kinds.
    enum PersistedPaneContent: Codable, Equatable {
        case terminal
        case browser(url: String?)

        private enum CodingKeys: String, CodingKey { case kind, url }
        private enum Kind: String, Codable { case terminal, browser }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .terminal:
                try c.encode(Kind.terminal, forKey: .kind)
            case .browser(let url):
                try c.encode(Kind.browser, forKey: .kind)
                try c.encodeIfPresent(url, forKey: .url)
            }
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try c.decode(Kind.self, forKey: .kind)
            switch kind {
            case .terminal:
                self = .terminal
            case .browser:
                let url = try c.decodeIfPresent(String.self, forKey: .url)
                self = .browser(url: url)
            }
        }
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
                let panes = tab.panes.map { pane -> PersistedPane in
                    let content: PersistedPaneContent
                    switch pane.content {
                    case .terminal:
                        content = .terminal
                    case .browser(let bs):
                        content = .browser(url: bs.url?.absoluteString)
                    }
                    return PersistedPane(
                        id: pane.id,
                        cwd: pane.terminalState?.currentPath ?? "",
                        content: content
                    )
                }
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
