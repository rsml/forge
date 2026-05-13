import Foundation

public enum SplitNode: Equatable, Sendable {
    case leaf
    case split(SplitDirection, [SplitNode])

    public var leafCount: Int {
        switch self {
        case .leaf: return 1
        case .split(_, let children): return children.reduce(0) { $0 + $1.leafCount }
        }
    }
}

/// Parse a tmux window_layout string into a split tree.
///
/// Layout format: `<checksum>,<WxH>,<X>,<Y>,<content>`
/// - Leaf: content is a pane ID (integer)
/// - Horizontal split: content is `{child,child,...}`
/// - Vertical split: content is `[child,child,...]`
/// Each child has the same `WxH,X,Y,<content>` structure recursively.
public enum LayoutParser {

    public static func parse(_ layout: String) -> SplitNode {
        guard let commaIdx = layout.firstIndex(of: ",") else { return .leaf }
        let body = layout[layout.index(after: commaIdx)...]
        return parseNode(body)
    }

    private static func parseNode(_ s: Substring) -> SplitNode {
        guard let braceIdx = s.firstIndex(where: { $0 == "{" || $0 == "[" }) else {
            return .leaf
        }
        let direction: SplitDirection = s[braceIdx] == "{" ? .horizontal : .vertical
        let inner = extractBracketed(s, from: braceIdx)
        let children = splitChildren(inner).map { parseNode($0) }
        return .split(direction, children)
    }

    /// Extract content between the opening bracket at `idx` and its matching close.
    private static func extractBracketed(_ s: Substring, from idx: String.Index) -> Substring {
        let start = s.index(after: idx)
        var depth = 1
        var cur = start
        while cur < s.endIndex {
            let ch = s[cur]
            if ch == "{" || ch == "[" { depth += 1 }
            else if ch == "}" || ch == "]" { depth -= 1 }
            if depth == 0 { return s[start..<cur] }
            cur = s.index(after: cur)
        }
        return s[start..<s.endIndex]
    }

    /// Split children at commas that separate top-level layout entries.
    /// Each child starts with a dimension like `95x50,` — we detect boundaries
    /// by looking for `,<digits>x<digits>` at depth 0.
    private static func splitChildren(_ s: Substring) -> [Substring] {
        var results: [Substring] = []
        var depth = 0
        var start = s.startIndex
        var i = s.startIndex
        while i < s.endIndex {
            let ch = s[i]
            if ch == "{" || ch == "[" { depth += 1 }
            else if ch == "}" || ch == "]" { depth -= 1 }
            if ch == "," && depth == 0 {
                let next = s.index(after: i)
                if next < s.endIndex && isDimensionStart(s[next...]) {
                    results.append(s[start..<i])
                    start = next
                }
            }
            i = s.index(after: i)
        }
        results.append(s[start..<s.endIndex])
        return results
    }

    /// Check if a substring starts with a dimension pattern like `190x50`.
    private static func isDimensionStart(_ s: Substring) -> Bool {
        var i = s.startIndex
        guard i < s.endIndex, s[i].isNumber else { return false }
        while i < s.endIndex, s[i].isNumber { i = s.index(after: i) }
        guard i < s.endIndex, s[i] == "x" else { return false }
        i = s.index(after: i)
        return i < s.endIndex && s[i].isNumber
    }
}
