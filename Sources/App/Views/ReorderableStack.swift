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
    @ViewBuilder let content: (Item, Bool) -> Content
    let onReorder: (Int, Int) -> Void

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
        @ViewBuilder content: @escaping (Item, Bool) -> Content,
        onReorder: @escaping (Int, Int) -> Void
    ) {
        self.items = items
        self.axis = axis
        self.spacing = spacing
        self.content = content
        self.onReorder = onReorder
    }

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
    }
}
