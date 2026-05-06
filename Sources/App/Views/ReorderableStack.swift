import SwiftUI

// MARK: - Frame Measurement

struct ItemFramePreferenceKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - ReorderableStack

struct ReorderableStack<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let axis: Axis
    let spacing: CGFloat
    let hitTestHeight: CGFloat?
    @ViewBuilder let content: (Item, Bool) -> Content
    let onReorder: (Int, Int) -> Void
    let onDragExit: ((_ itemIndex: Int, _ edge: Edge) -> Void)?

    @State private var draggedIndex: Int?
    @State private var insertionIndex: Int?
    @State private var dragOffset: CGFloat = 0
    @State private var itemFrames: [Int: CGRect] = [:]
    @State private var dragFrameSnapshot: [Int: CGRect] = [:]
    @State private var containerSize: CGSize = .zero

    // Unique per instance to prevent nested ReorderableStack collisions
    @State private var coordinateSpaceID = UUID()

    init(
        _ items: [Item],
        axis: Axis = .horizontal,
        spacing: CGFloat = 1,
        hitTestHeight: CGFloat? = nil,
        @ViewBuilder content: @escaping (Item, Bool) -> Content,
        onReorder: @escaping (Int, Int) -> Void,
        onDragExit: ((_ itemIndex: Int, _ edge: Edge) -> Void)? = nil
    ) {
        self.items = items
        self.axis = axis
        self.spacing = spacing
        self.hitTestHeight = hitTestHeight
        self.content = content
        self.onReorder = onReorder
        self.onDragExit = onDragExit
    }

    // MARK: - Hit Testing

    /// Compute insertion index from the dragged item's current center position.
    /// Uses snapshotted frames (captured at drag start) with a 4px dead zone.
    /// Returns a value compatible with Array.move(fromOffsets:toOffset:).
    private func computeInsertionIndex(draggedCenter: CGFloat) -> Int {
        let sortedFrames = dragFrameSnapshot.sorted { $0.key < $1.key }
        guard !sortedFrames.isEmpty else { return 0 }

        for (index, frame) in sortedFrames {
            let mid: CGFloat
            if let h = hitTestHeight {
                // Anchor hit testing to the top edge of each item (e.g. project header)
                mid = (axis == .horizontal ? frame.minX : frame.minY) + h / 2
            } else {
                mid = axis == .horizontal ? frame.midX : frame.midY
            }
            if draggedCenter < mid - 4 {
                return index
            }
        }
        return items.count
    }

    /// Compute the offset for a neighbor item based on current drag state.
    /// Uses snapshotted frames to avoid feedback loops from animated neighbor positions.
    private func neighborOffset(for index: Int) -> CGFloat {
        guard let from = draggedIndex, let to = insertionIndex, from != to else { return 0 }
        guard let draggedFrame = dragFrameSnapshot[from] else { return 0 }

        let draggedSize: CGFloat
        if let h = hitTestHeight {
            draggedSize = h
        } else {
            draggedSize = axis == .horizontal ? draggedFrame.width : draggedFrame.height
        }
        let shiftAmount = draggedSize + spacing

        if from < to {
            // Dragging forward: items in (from, to) shift backward
            if index > from && index < to {
                return -shiftAmount
            }
        } else {
            // Dragging backward: items in [to, from) shift forward
            if index >= to && index < from {
                return shiftAmount
            }
        }
        return 0
    }

    /// Clamp drag offset to container bounds so the item can't fly off-screen.
    private func clampedOffset(_ translation: CGFloat, frame: CGRect) -> CGFloat {
        let size = axis == .horizontal ? containerSize.width : containerSize.height
        let pos = axis == .horizontal ? frame.minX : frame.minY
        let itemSize = axis == .horizontal ? frame.width : frame.height
        let minOffset = -pos
        let maxOffset = size - pos - itemSize
        return min(max(translation, minOffset), maxOffset)
    }

    /// Cancel any in-progress drag, restoring all state.
    private func cancelDrag() {
        draggedIndex = nil
        insertionIndex = nil
        dragOffset = 0
        dragFrameSnapshot = [:]
    }

    // MARK: - Body

    var body: some View {
        let layout = axis == .horizontal
            ? AnyLayout(HStackLayout(spacing: spacing))
            : AnyLayout(VStackLayout(spacing: spacing))

        layout {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let isDragging = draggedIndex == index
                content(item, isDragging)
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .preference(
                                    key: ItemFramePreferenceKey.self,
                                    value: [index: geo.frame(in: .named(coordinateSpaceID))]
                                )
                        }
                    )
                    .offset(
                        x: axis == .horizontal ? (isDragging ? dragOffset : neighborOffset(for: index)) : 0,
                        y: axis == .vertical ? (isDragging ? dragOffset : neighborOffset(for: index)) : 0
                    )
                    .zIndex(isDragging ? 1 : 0)
                    .shadow(
                        color: isDragging ? .black.opacity(0.15) : .clear,
                        radius: isDragging ? 4 : 0,
                        y: isDragging ? 2 : 0
                    )
                    .scaleEffect(isDragging ? 1.03 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.85), value: neighborOffset(for: index))
                    .gesture(
                        DragGesture(minimumDistance: 3, coordinateSpace: .named(coordinateSpaceID))
                            .onChanged { value in
                                if draggedIndex == nil {
                                    // Resolve index from @State itemFrames (always current),
                                    // not captured ForEach index which is stale after reorder.
                                    let startPos = axis == .horizontal ? value.startLocation.x : value.startLocation.y
                                    var foundIndex = index
                                    for (idx, frame) in itemFrames {
                                        let lo = axis == .horizontal ? frame.minX : frame.minY
                                        let hi = axis == .horizontal ? frame.maxX : frame.maxY
                                        if startPos >= lo && startPos <= hi {
                                            foundIndex = idx
                                            break
                                        }
                                    }
                                    draggedIndex = foundIndex
                                    dragFrameSnapshot = itemFrames
                                }
                                guard let dragIdx = draggedIndex,
                                      let frame = dragFrameSnapshot[dragIdx] else { return }

                                let translation = axis == .horizontal
                                    ? value.translation.width
                                    : value.translation.height

                                // Detect drag exit before clamping
                                if let onDragExit {
                                    let unclampedCenter: CGFloat
                                    if axis == .horizontal {
                                        unclampedCenter = frame.midX + translation
                                    } else {
                                        unclampedCenter = frame.midY + translation
                                    }
                                    let containerExtent = axis == .horizontal ? containerSize.width : containerSize.height
                                    if unclampedCenter < -20 {
                                        let exitEdge: Edge = axis == .horizontal ? .leading : .top
                                        onDragExit(dragIdx, exitEdge)
                                        cancelDrag()
                                        return
                                    } else if unclampedCenter > containerExtent + 20 {
                                        let exitEdge: Edge = axis == .horizontal ? .trailing : .bottom
                                        onDragExit(dragIdx, exitEdge)
                                        cancelDrag()
                                        return
                                    }
                                }

                                dragOffset = clampedOffset(translation, frame: frame)

                                // Compute dragged item's current center using snapshotted frame
                                let center = axis == .horizontal
                                    ? frame.midX + dragOffset
                                    : frame.midY + dragOffset
                                insertionIndex = computeInsertionIndex(draggedCenter: center)
                            }
                            .onEnded { _ in
                                let from = draggedIndex
                                let to = insertionIndex

                                // Clear state before mutation to prevent visual jumps
                                cancelDrag()

                                // Array.move(fromOffsets:toOffset:) treats to == from and
                                // to == from+1 as no-ops; skip both to avoid false snap-backs
                                if let from, let to, from != to, to != from + 1 {
                                    onReorder(from, to)
                                }
                            }
                    )
            }
        }
        .coordinateSpace(name: coordinateSpaceID)
        .onPreferenceChange(ItemFramePreferenceKey.self) { frames in
            itemFrames = frames
        }
        .background(
            GeometryReader { geo in
                Color.clear.onAppear { containerSize = geo.size }
                    .onChange(of: geo.size) { _, new in containerSize = new }
            }
        )
        .onKeyPress(.escape) {
            guard draggedIndex != nil else { return .ignored }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                cancelDrag()
            }
            return .handled
        }
        .onChange(of: items.count) {
            // Cancel drag if items array changes (e.g., tmux event adds/removes a window)
            if draggedIndex != nil { cancelDrag() }
        }
    }
}
