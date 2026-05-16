import Foundation

public enum SplitNode: Sendable {
    case leaf
    case split(SplitDirection, [SplitNode], proportions: [CGFloat])

    public var leafCount: Int {
        switch self {
        case .leaf: return 1
        case .split(_, let children, _): return children.reduce(0) { $0 + $1.leafCount }
        }
    }
}

// Equatable ignores proportions — topology-only comparison.
// This preserves existing tests and avoids float-equality issues.
extension SplitNode: Equatable {
    public static func == (lhs: SplitNode, rhs: SplitNode) -> Bool {
        switch (lhs, rhs) {
        case (.leaf, .leaf): return true
        case let (.split(d1, c1, _), .split(d2, c2, _)):
            return d1 == d2 && c1 == c2
        default: return false
        }
    }
}

/// Parse a tmux window_layout string into a split tree with proportions.
///
/// Layout format: `<checksum>,<WxH>,<X>,<Y>,<content>`
/// - Leaf: content is a pane ID (integer)
/// - Horizontal split: content is `{child,child,...}`
/// - Vertical split: content is `[child,child,...]`
/// Each child has the same `WxH,X,Y,<content>` structure recursively.
///
/// Proportions are derived from the `WxH` dimensions of each child:
/// for horizontal splits, proportions come from widths; for vertical, from heights.
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
        let childStrings = splitChildren(inner)
        let children = childStrings.map { parseNode($0) }
        let proportions = computeProportions(childStrings, direction: direction, count: children.count)
        return .split(direction, children, proportions: proportions)
    }

    /// Compute proportions from child dimension strings.
    /// Each child starts with `WxH,...`. For horizontal splits, use widths;
    /// for vertical splits, use heights.
    private static func computeProportions(_ childStrings: [Substring], direction: SplitDirection, count: Int) -> [CGFloat] {
        let sizes: [Int] = childStrings.compactMap { child in
            guard let dim = parseDimension(child) else { return nil }
            return direction == .horizontal ? dim.width : dim.height
        }
        guard sizes.count == count else {
            return Array(repeating: 1.0 / CGFloat(count), count: count)
        }
        let total = CGFloat(sizes.reduce(0, +))
        guard total > 0 else {
            return Array(repeating: 1.0 / CGFloat(count), count: count)
        }
        return sizes.map { CGFloat($0) / total }
    }

    /// Parse `WxH` from the start of a node substring.
    private static func parseDimension(_ s: Substring) -> (width: Int, height: Int)? {
        var i = s.startIndex
        let wStart = i
        while i < s.endIndex, s[i].isNumber { i = s.index(after: i) }
        guard i < s.endIndex, s[i] == "x" else { return nil }
        guard let width = Int(s[wStart..<i]) else { return nil }
        i = s.index(after: i)
        let hStart = i
        while i < s.endIndex, s[i].isNumber { i = s.index(after: i) }
        guard let height = Int(s[hStart..<i]) else { return nil }
        return (width, height)
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
