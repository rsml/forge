import SwiftUI
import ForgeCore

/// Draggable divider between split panes.
/// Width matches tmux's 1-cell divider for pixel-perfect layout alignment.
/// Visually renders a 1px line centered in the cell-sized hit target.
struct PaneDivider: View {
    let direction: SplitDirection
    let size: CGFloat
    let onDrag: (CGFloat) -> Void
    let onDragEnd: () -> Void

    private let visualWidth: CGFloat = 1

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
            width: direction == .horizontal ? size : nil,
            height: direction == .vertical ? size : nil
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
