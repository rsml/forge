import SwiftUI
import ForgeCore

/// Recursive view that renders a split pane layout from a SplitNode tree.
/// Leaf nodes render either a PaneTerminalView or BrowserPaneView based on
/// pane.kind. Split nodes delegate to SplitContainer which owns the
/// draggable divider state.
struct PaneSplitView: View {
    let node: SplitNode
    let panes: ArraySlice<Pane>
    let renderers: [String: any PaneRenderer]
    @Environment(WorkspaceController.self) private var controller

    var body: some View {
        switch node {
        case .leaf:
            if let pane = panes.first, let renderer = renderers[pane.id] {
                if pane.kind == .browser, let browser = renderer as? any BrowserRenderer {
                    BrowserPaneView(pane: pane, renderer: browser)
                        .id(pane.id)
                } else if let terminal = renderer as? any TerminalRenderer {
                    // Context menu is attached via AppKit's `NSView.menu` inside
                    // PaneTerminalView. SwiftUI's `.contextMenu` doesn't fire
                    // here — GhosttyNSView intercepts right-click events.
                    PaneTerminalView(renderer: terminal, pane: pane)
                        .id(pane.id)
                } else {
                    Color(red: 0.1, green: 0.1, blue: 0.1)
                }
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
    let renderers: [String: any PaneRenderer]
    @Environment(WorkspaceController.self) private var controller

    @State private var proportions: [CGFloat]
    @State private var dragStartProportions: [CGFloat]?

    private let minProportion: CGFloat = 0.05

    /// Divider hit-target size. In tmux mode it matches tmux's 1-cell divider so pixel
    /// allocation is identical. In native PTY mode it shrinks to a flush 6px hit-area
    /// around the 1px visible line.
    private var dividerSize: CGFloat {
        if controller.config.isNativePTY {
            return 6
        }
        let cell = controller.terminalCellSize
        if direction == .horizontal {
            return cell.width > 0 ? cell.width : 8
        } else {
            return cell.height > 0 ? cell.height : 8
        }
    }

    init(direction: SplitDirection, children: [SplitNode], tmuxProportions: [CGFloat],
         panes: ArraySlice<Pane>, renderers: [String: any PaneRenderer]) {
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

        // Write dragged proportions back to the split tree on the Tab model
        // so they persist to workspace.json.
        updateSplitTreeProportions()

        // Compute target cell counts from the NEW proportions and write them
        // into pendingResizes. Without this, flushPendingResizes sends the
        // current renderer sizes (which haven't changed) — a no-op.
        let cellSize = controller.terminalCellSize
        if cellSize.width > 0, cellSize.height > 0 {
            let slices = slicePanes()
            for (i, child) in children.enumerated() {
                guard i < proportions.count, i < slices.count else { continue }
                // Leaf panes get their size directly; nested splits inherit from parent
                let leafPanes = slices[i]
                for pane in leafPanes where pane.kind == .terminal {
                    if let renderer = renderers[pane.id] {
                        let frame = renderer.view.frame
                        let cols = Int(frame.width / cellSize.width)
                        let rows = Int(frame.height / cellSize.height)
                        if cols > 0, rows > 0 {
                            controller.pendingResizes[pane.id] = (cols, rows)
                        }
                    }
                }
            }
        }

        controller.sendResizePaneOnFlush = true
        controller.flushPendingResizes()
    }

    /// Write the current @State proportions back into the Tab's splitTree
    /// so they persist to workspace.json. Finds this container's node in the
    /// tree by matching the pane leaf indices.
    private func updateSplitTreeProportions() {
        guard let tab = controller.workspace.activeProject?.tabs.first(
            where: { $0.id == controller.workspace.activeTabId }),
              var tree = tab.splitTree else { return }

        // Find the first pane ID in our slice — use its index in tab.panes
        // to locate this node in the tree.
        guard let firstPaneId = panes.first?.id,
              let firstPaneIndex = tab.panes.firstIndex(where: { $0.id == firstPaneId }) else { return }

        var leafIndex = 0
        tree = updateProportionsAt(node: tree, targetLeaf: firstPaneIndex,
                                    currentLeaf: &leafIndex,
                                    newProportions: proportions.map { CGFloat($0) })
        tab.splitTree = tree
    }

    /// Walk the tree to find the split node that contains targetLeaf as its
    /// first child leaf, then update its proportions.
    private func updateProportionsAt(node: SplitNode, targetLeaf: Int,
                                      currentLeaf: inout Int,
                                      newProportions: [CGFloat]) -> SplitNode {
        switch node {
        case .leaf:
            currentLeaf += 1
            return .leaf
        case .split(let dir, let children, let oldProportions):
            let startLeaf = currentLeaf
            let newChildren = children.map { child in
                updateProportionsAt(node: child, targetLeaf: targetLeaf,
                                   currentLeaf: &currentLeaf, newProportions: newProportions)
            }
            // If this split starts at our target leaf, update its proportions
            if startLeaf == targetLeaf && newProportions.count == children.count {
                return .split(dir, newChildren, proportions: newProportions)
            }
            return .split(dir, newChildren, proportions: oldProportions)
        }
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
