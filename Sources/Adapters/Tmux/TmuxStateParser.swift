import Foundation
import ForgeDomain

/// Parses tmux format string output into domain info structs
enum TmuxStateParser {
    static let sessionFormat = "#{session_id}\t#{session_name}\t#{session_windows}\t#{session_attached}\t#{session_path}"
    static let windowFormat = "#{window_id}\t#{session_id}\t#{window_index}\t#{window_name}\t#{window_active}\t#{window_panes}"
    static let paneFormat = "#{pane_id}\t#{window_id}\t#{pane_index}\t#{pane_active}\t#{pane_current_command}\t#{pane_current_path}\t#{pane_width}\t#{pane_height}\t#{pane_pid}"

    static func parseSessions(_ output: String) -> [SessionInfo] {
        output.split(separator: "\n").compactMap { line in
            let p = line.split(separator: "\t", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
            guard p.count >= 5 else { return nil }
            return SessionInfo(id: p[0], name: p[1], windowCount: Int(p[2]) ?? 0,
                             attached: p[3] != "0", path: p[4].isEmpty ? nil : p[4])
        }
    }

    static func parseWindows(_ output: String) -> [WindowInfo] {
        output.split(separator: "\n").compactMap { line in
            let p = line.split(separator: "\t", maxSplits: 5, omittingEmptySubsequences: false).map(String.init)
            guard p.count >= 6 else { return nil }
            return WindowInfo(id: p[0], sessionId: p[1], index: Int(p[2]) ?? 0,
                            name: p[3], active: p[4] != "0", paneCount: Int(p[5]) ?? 0)
        }
    }

    static func parsePanes(_ output: String) -> [PaneInfo] {
        output.split(separator: "\n").compactMap { line in
            let p = line.split(separator: "\t", maxSplits: 8, omittingEmptySubsequences: false).map(String.init)
            guard p.count >= 9 else { return nil }
            return PaneInfo(id: p[0], windowId: p[1], index: Int(p[2]) ?? 0,
                          active: p[3] != "0", currentCommand: p[4], currentPath: p[5],
                          width: Int(p[6]) ?? 80, height: Int(p[7]) ?? 24, pid: Int(p[8]) ?? 0)
        }
    }
}
