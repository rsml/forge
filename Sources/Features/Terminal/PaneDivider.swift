import SwiftUI
import ForgeCore

/// Draggable divider between split panes.
/// Visually 1px, with a wider invisible hit target for comfortable dragging.
/// Changes cursor to resize arrow on hover.
struct PaneDivider: View {
    let direction: SplitDirection
    let onDrag: (CGFloat) -> Void
    let onDragEnd: () -> Void

    private let visualWidth: CGFloat = 1
    private let hitWidth: CGFloat = 8

    var body: some View {
        ZStack {
            Color.clear
            Rectangle()
                .fill(Color(white: 0.2))
                .frame(
                    width: direction == .horizontal ? visualWidth : nil,
                    height: direction == .vertical ? visualWidth : nil
                )
        }
        .frame(
            width: direction == .horizontal ? hitWidth : nil,
            height: direction == .vertical ? hitWidth : nil
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    let delta = direction == .horizontal
                        ? value.location.x - value.startLocation.x
                        : value.location.y - value.startLocation.y
                    onDrag(delta)
                }
                .onEnded { _ in
                    onDragEnd()
                }
        )
        .onHover { hovering in
            if hovering {
                (direction == .horizontal
                    ? NSCursor.resizeLeftRight
                    : NSCursor.resizeUpDown).push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
