import SwiftUI
import ForgeCore

/// Draggable divider between split panes.
/// Visually renders a 1px line centered in the cell-sized hit target.
struct PaneDivider: View {
    let direction: SplitDirection
    let size: CGFloat
    let onDrag: (CGFloat) -> Void
    let onDragEnd: () -> Void

    /// True hairline: 1 device pixel on whichever screen the window is on
    /// (0.5pt @ 2x retina, ~0.333pt @ 3x), floored at 0.33pt so it never
    /// fades to invisibility on hypothetical super-dense displays.
    @Environment(\.displayScale) private var displayScale
    private var visualWidth: CGFloat { max(1.0 / displayScale, 0.33) }

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
