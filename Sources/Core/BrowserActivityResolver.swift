import Foundation

/// Pure helper that classifies a set of pane IDs into browser activities
/// (resolved locally from `Workspace`) and terminal pane IDs (which the
/// caller forwards to its backend — daemon or in-memory tmux state).
///
/// A browser pane with any loaded URL counts as active. The displayed
/// "command" follows a graceful fallback: page title → host → full URL.
/// This matches the existing close-confirmation copy template ("Closing
/// this tab will terminate \"\(command)\"") — for browser panes the user
/// sees the page title rather than a process name.
///
/// Lives in Core (Foundation-only) so both the daemon-backed and
/// tmux-backed activity adapters can call it without duplicating logic.
public enum BrowserActivityResolver {

    /// Split `paneIds` into (browser activities, remaining terminal IDs).
    /// Browser panes always produce an entry in the activities list, even
    /// when they have no loaded URL — the caller's `PaneActivity` semantics
    /// require one entry per requested ID.
    @MainActor
    public static func partition(
        paneIds: [String],
        workspace: Workspace?
    ) -> (browsers: [PaneActivity], terminalIds: [String]) {
        guard let workspace else {
            // No workspace → can't classify. Treat everything as terminal so
            // the daemon/tmux path can fail-open without losing entries.
            return (browsers: [], terminalIds: paneIds)
        }

        var byId: [String: Pane] = [:]
        for project in workspace.projects {
            for tab in project.tabs {
                for pane in tab.panes { byId[pane.id] = pane }
            }
        }

        var browsers: [PaneActivity] = []
        var terminalIds: [String] = []
        for id in paneIds {
            guard let pane = byId[id] else {
                // Pane not in workspace — punt to the terminal path; the
                // backend will report it idle and the caller will discard it.
                terminalIds.append(id)
                continue
            }
            switch pane.kind {
            case .browser:
                browsers.append(activity(for: pane))
            case .terminal:
                terminalIds.append(id)
            }
        }
        return (browsers, terminalIds)
    }

    /// A browser pane with a URL is active; the command string is the
    /// best-available page identifier.
    @MainActor
    private static func activity(for pane: Pane) -> PaneActivity {
        guard let state = pane.browserState, let url = state.url else {
            return PaneActivity(paneId: pane.id, isActive: false, command: nil)
        }
        let name = displayName(title: state.pageTitle, url: url)
        return PaneActivity(paneId: pane.id, isActive: true, command: name)
    }

    /// Page title if non-empty, else the host (with port if non-default for
    /// the scheme), else the absolute string. Made `internal` (default) for
    /// direct unit testing.
    static func displayName(title: String, url: URL) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty { return trimmedTitle }
        if let hp = hostAndPort(url), !hp.isEmpty { return hp }
        return url.absoluteString
    }

    /// Returns `host[:port]` for the URL, including the port only when it
    /// is not the default for the scheme (http: 80, https: 443, ftp: 21).
    /// Returns nil if the URL has no host.
    static func hostAndPort(_ url: URL) -> String? {
        guard let host = url.host() else { return nil }
        let defaultPort: Int? = {
            switch url.scheme?.lowercased() {
            case "http":  return 80
            case "https": return 443
            case "ftp":   return 21
            default:      return nil
            }
        }()
        if let port = url.port, port != defaultPort {
            return "\(host):\(port)"
        }
        return host
    }
}
