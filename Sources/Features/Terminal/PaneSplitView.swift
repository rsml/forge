import SwiftUI
import ForgeCore

/// Recursive view that renders a split pane layout from a SplitNode tree.
/// Leaf nodes render a PaneTerminalView. Branch nodes split horizontally or
/// vertically with child PaneSplitViews.
struct PaneSplitView: View {
    let node: SplitNode
    let panes: ArraySlice<Pane>
    let renderers: [String: any TerminalRenderer]

    var body: some View {
        switch node {
        case .leaf:
            leafView
        case .split(let direction, let children):
            splitView(direction: direction, children: children)
        }
    }

    @ViewBuilder
    private var leafView: some View {
        if let pane = panes.first, let renderer = renderers[pane.id] {
            PaneTerminalView(renderer: renderer)
                .id(pane.id)
        } else {
            Color(red: 0.1, green: 0.1, blue: 0.1)
        }
    }

    @ViewBuilder
    private func splitView(direction: SplitDirection, children: [SplitNode]) -> some View {
        let slices = slicePanes(children: children)
        if direction == .horizontal {
            HStack(spacing: 1) {
                ForEach(Array(zip(children, slices).enumerated()), id: \.offset) { _, pair in
                    PaneSplitView(node: pair.0, panes: pair.1, renderers: renderers)
                }
            }
        } else {
            VStack(spacing: 1) {
                ForEach(Array(zip(children, slices).enumerated()), id: \.offset) { _, pair in
                    PaneSplitView(node: pair.0, panes: pair.1, renderers: renderers)
                }
            }
        }
    }

    /// Distribute the flat pane slice across child subtrees based on leaf count.
    /// Panes are in leaf-order (tmux's list-panes output matches tree traversal).
    private func slicePanes(children: [SplitNode]) -> [ArraySlice<Pane>] {
        var result: [ArraySlice<Pane>] = []
        var offset = panes.startIndex
        for child in children {
            let count = child.leafCount
            let end = min(offset + count, panes.endIndex)
            result.append(panes[offset..<end])
            offset = end
        }
        return result
    }
}
