import Foundation
import Observation

public enum PaneStatus: String, Sendable, Codable {
    case idle, running, needsAttention, error

    public static func from(command: String) -> PaneStatus {
        let lower = command.lowercased()
        let shells: Set<String> = ["zsh", "bash", "fish", "sh", "nu", "pwsh"]
        if lower.isEmpty || shells.contains(lower) { return .idle }
        return .running
    }
}

public enum PaneKind: String, Sendable, Codable { case terminal, browser }

@Observable @MainActor
public final class TerminalState {
    public var currentCommand: String
    public var currentPath: String
    public var width: Int
    public var height: Int
    public var pid: Int
    public var status: PaneStatus
    public var hasBell: Bool
    public var hasContentMatch: Bool
    /// The command that was running before the most recent command change.
    public var previousCommand: String

    /// True if this pane needs user attention (idle, bell, content match, error).
    /// Idle shells and silent agents both count — attention is the inverse of busy.
    public var needsAttention: Bool {
        status == .idle || hasBell || hasContentMatch || status == .needsAttention || status == .error
    }

    public init(currentCommand: String = "", currentPath: String = "",
                width: Int = 80, height: Int = 24, pid: Int = 0) {
        self.currentCommand = currentCommand
        self.currentPath = currentPath
        self.width = width
        self.height = height
        self.pid = pid
        self.status = PaneStatus.from(command: currentCommand)
        self.hasBell = false
        self.hasContentMatch = false
        self.previousCommand = ""
    }
}

@Observable @MainActor
public final class BrowserState {
    public var url: URL?
    public var pageTitle: String
    public var canGoBack: Bool
    public var canGoForward: Bool
    public var isLoading: Bool
    public var loadingProgress: Double
    /// Raw favicon bytes (PNG/JPEG). Renderer converts to NSImage; Core stays pure.
    public var faviconData: Data?

    public init(url: URL? = nil) {
        self.url = url
        self.pageTitle = ""
        self.canGoBack = false
        self.canGoForward = false
        self.isLoading = false
        self.loadingProgress = 0.0
        self.faviconData = nil
    }
}

public enum PaneContent {
    case terminal(TerminalState)
    case browser(BrowserState)
}

@Observable @MainActor
public final class Pane: Identifiable {
    public let id: String
    public let tabId: String
    public var index: Int
    public var active: Bool
    public var content: PaneContent

    /// Convenience — returns the terminal sub-state when this pane is a terminal, else nil.
    public var terminalState: TerminalState? {
        if case let .terminal(s) = content { return s } else { return nil }
    }

    /// Convenience — returns the browser sub-state when this pane is a browser, else nil.
    public var browserState: BrowserState? {
        if case let .browser(s) = content { return s } else { return nil }
    }

    public var kind: PaneKind {
        switch content {
        case .terminal: return .terminal
        case .browser:  return .browser
        }
    }

    public var needsAttention: Bool {
        terminalState?.needsAttention ?? false
    }

    public init(id: String, tabId: String, index: Int = 0, active: Bool = false,
                currentCommand: String = "", currentPath: String = "",
                width: Int = 80, height: Int = 24, pid: Int = 0) {
        self.id = id
        self.tabId = tabId
        self.index = index
        self.active = active
        self.content = .terminal(TerminalState(
            currentCommand: currentCommand, currentPath: currentPath,
            width: width, height: height, pid: pid
        ))
    }

    public static func browser(id: String, tabId: String, index: Int = 0,
                                active: Bool = false, url: URL? = nil) -> Pane {
        let p = Pane(id: id, tabId: tabId, index: index, active: active)
        p.content = .browser(BrowserState(url: url))
        return p
    }
}
