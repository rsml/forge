import Foundation

/// Scans pane content for patterns indicating the terminal is waiting for user input.
/// Maintains per-pane dedup state so events fire only on the first poll cycle where
/// a pattern matches, not on subsequent cycles while the same prompt is visible.
@MainActor
public final class ContentDetector {
    private var activeMatches: Set<String> = []

    public static let defaultPatterns: [String] = [
        "Enter to select",
        "Allow once",
        "Allow always",
        "\\[y/[nN]\\]",
        "\\(y/N\\)",
        "Do you want to",
    ]

    public init() {}

    /// Returns `true` only on the first poll cycle where a pattern matches for this pane.
    /// Subsequent cycles with the same prompt visible return `false` (dedup).
    /// When content stops matching (user responded), state resets so new prompts fire again.
    public func scan(paneId: String, content: String, patterns: [String]) -> Bool {
        let matched = patterns.contains { pattern in
            content.range(of: pattern, options: .regularExpression) != nil
        }
        if matched && !activeMatches.contains(paneId) {
            activeMatches.insert(paneId)
            return true
        }
        if !matched {
            activeMatches.remove(paneId)
        }
        return false
    }

    public func isActive(paneId: String) -> Bool {
        activeMatches.contains(paneId)
    }

    public func paneRemoved(_ paneId: String) {
        activeMatches.remove(paneId)
    }
}
