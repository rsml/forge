import SwiftUI
import ForgeCore

/// Recursive view that renders a split pane layout from a SplitNode tree.
/// Leaf nodes render a PaneTerminalView. Split nodes delegate to
/// SplitContainer which owns the draggable divider state.
struct PaneSplitView: View {
    let node: SplitNode
    let panes: ArraySlice<Pane>
    let renderers: [String: any TerminalRenderer]

    var body: some View {
        switch node {
        case .leaf:
            if let pane = panes.first, let renderer = renderers[pane.id] {
                PaneTerminalView(renderer: renderer).id(pane.id)
            } else {
                Color(red: 0.1, green: 0.1, blue: 0.1)
            }
        case .split(let direction, let children, let proportions):
            SplitContainer(
                direction: direction,
                children: children,
                tmuxProportions: proportions,
                panes: panes,
                renderers: renderers
            )
        }
    }
}

// MARK: - SplitContainer

/// Lays out child split nodes with draggable dividers between them.
/// Proportions are initialized from the tmux layout string and updated
/// locally during drag. After drag ends, the next tmux refresh overwrites
/// proportions with the authoritative layout dimensions.
private struct SplitContainer: View {
    let direction: SplitDirection
    let children: [SplitNode]
    let tmuxProportions: [CGFloat]
    let panes: ArraySlice<Pane>
    let renderers: [String: any TerminalRenderer]
    @Environment(WorkspaceController.self) private var controller

    @State private var proportions: [CGFloat]
    @State private var dragStartProportions: [CGFloat]?

    private let minProportion: CGFloat = 0.05

    /// Divider size matches tmux's 1-cell divider so pixel allocation is identical.
    /// Falls back to 8px before cell size is known.
    private var dividerSize: CGFloat {
        let cell = controller.terminalCellSize
        if direction == .horizontal {
            return cell.width > 0 ? cell.width : 8
        } else {
            return cell.height > 0 ? cell.height : 8
        }
    }

    init(direction: SplitDirection, children: [SplitNode], tmuxProportions: [CGFloat],
         panes: ArraySlice<Pane>, renderers: [String: any TerminalRenderer]) {
        self.direction = direction
        self.children = children
        self.tmuxProportions = tmuxProportions
        self.panes = panes
        self.renderers = renderers
        self._proportions = State(initialValue: tmuxProportions)
    }

    var body: some View {
        GeometryReader { geo in
            let axis = direction == .horizontal ? geo.size.width : geo.size.height
            let totalDividers = CGFloat(children.count - 1) * dividerSize
            let available = max(axis - totalDividers, 0)
            let sizes = proportions.map { $0 * available }
            let slices = slicePanes()

            if direction == .horizontal {
                HStack(spacing: 0) {
                    ForEach(Array(children.indices), id: \.self) { i in
                        PaneSplitView(node: children[i], panes: slices[i], renderers: renderers)
                            .frame(width: sizes[i])
                        if i < children.count - 1 {
                            PaneDivider(direction: direction, size: dividerSize) { delta in
                                handleDrag(at: i, delta: delta, available: available)
                            } onDragEnd: {
                                endDrag()
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(children.indices), id: \.self) { i in
                        PaneSplitView(node: children[i], panes: slices[i], renderers: renderers)
                            .frame(height: sizes[i])
                        if i < children.count - 1 {
                            PaneDivider(direction: direction, size: dividerSize) { delta in
                                handleDrag(at: i, delta: delta, available: available)
                            } onDragEnd: {
                                endDrag()
                            }
                        }
                    }
                }
            }
        }
        // No onChange: local proportions are authoritative.
        // tmux is told to match via resize-pane, but its layout response
        // (which rounds to cell boundaries) never overwrites local state.
        // Proportions reinitialize from tmux only when the tree structure
        // changes (pane added/removed), which recreates this view.
    }

    // MARK: - Drag Handling

    private func handleDrag(at index: Int, delta: CGFloat, available: CGFloat) {
        if dragStartProportions == nil {
            dragStartProportions = proportions
            controller.suppressPaneResize = true
        }
        guard let start = dragStartProportions else { return }
        let proportionDelta = delta / available
        var p = start
        p[index] = max(minProportion, start[index] + proportionDelta)
        p[index + 1] = max(minProportion, start[index + 1] - proportionDelta)
        let sum = p.reduce(0, +)
        if sum > 0 { proportions = p.map { $0 / sum } }
    }

    private func endDrag() {
        dragStartProportions = nil
        controller.suppressPaneResize = false
        controller.sendResizePaneOnFlush = true
        controller.flushPendingResizes()
    }

    // MARK: - Pane Distribution

    private func slicePanes() -> [ArraySlice<Pane>] {
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
