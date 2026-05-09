import Foundation
import ForgeCore

/// Parses tmux format string output into domain info structs
enum TmuxStateParser {
    static let projectFormat = "#{session_id}\t#{session_name}\t#{session_windows}\t#{session_attached}\t#{session_path}"
    static let tabFormat = "#{window_id}\t#{session_id}\t#{window_index}\t#{window_name}\t#{window_active}\t#{window_panes}\t#{window_bell_flag}"
    static let paneFormat = "#{pane_id}\t#{window_id}\t#{pane_index}\t#{pane_active}\t#{pane_current_command}\t#{pane_current_path}\t#{pane_width}\t#{pane_height}\t#{pane_pid}"

    static func parseProjects(_ output: String) -> [ProjectInfo] {
        output.split(separator: "\n").compactMap { line in
            let p = line.split(separator: "\t", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
            guard p.count >= 5 else {
                ForgeLog.log("[tmux] Failed to parse project line: \(line)")
                return nil
            }
            return ProjectInfo(id: p[0], name: p[1], tabCount: Int(p[2]) ?? 0,
                             attached: p[3] != "0", path: p[4].isEmpty ? nil : p[4])
        }
    }

    static func parseTabs(_ output: String) -> [TabInfo] {
        output.split(separator: "\n").compactMap { line in
            let p = line.split(separator: "\t", maxSplits: 6, omittingEmptySubsequences: false).map(String.init)
            guard p.count >= 7 else {
                ForgeLog.log("[tmux] Failed to parse tab line: \(line)")
                return nil
            }
            return TabInfo(id: p[0], projectId: p[1], index: Int(p[2]) ?? 0,
                            name: p[3], active: p[4] != "0", paneCount: Int(p[5]) ?? 0,
                            hasBell: p[6] != "0")
        }
    }

    static func parsePanes(_ output: String) -> [PaneInfo] {
        output.split(separator: "\n").compactMap { line in
            let p = line.split(separator: "\t", maxSplits: 8, omittingEmptySubsequences: false).map(String.init)
            guard p.count >= 9 else {
                ForgeLog.log("[tmux] Failed to parse pane line: \(line)")
                return nil
            }
            return PaneInfo(id: p[0], tabId: p[1], index: Int(p[2]) ?? 0,
                          active: p[3] != "0", currentCommand: p[4], currentPath: p[5],
                          width: Int(p[6]) ?? 80, height: Int(p[7]) ?? 24, pid: Int(p[8]) ?? 0)
        }
    }
}
