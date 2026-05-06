# ReorderableStack — Drag-and-Drop Tab Reordering

## Problem

Tab and session reordering uses SwiftUI's `.onDrag`/`.onDrop` with `NSItemProvider` and a shared `ReorderDropDelegate`. This system-level drag API is designed for inter-app transfers, not intra-view reordering, causing:

- **Translucent drag image** — system-generated, cannot be customized to full opacity
- **Shaking/jitter** — array mutates on every `dropEntered` as cursor crosses item boundaries
- **Can't drop at first/last position** — only existing items serve as drop targets; requires hacky trailing `Color.clear` zones
- **Delay on drop** — `NSItemProvider` async serialization + system drag session teardown
- **Duplicated boilerplate** — same pattern repeated in three places with the same bugs

## Solution

Replace with a `ReorderableStack` container view that uses a custom `DragGesture` for full control over the interaction.

## Consumers

Three call sites, all currently using `ReorderDropDelegate`:

1. **WindowTabBar** (`Sources/App/Views/Detail/WindowTabBar.swift`) — horizontal tabs within a session
2. **SessionRow** (`Sources/App/Views/Sidebar/SessionRow.swift`) — vertical window list within an expanded sidebar session
3. **SidebarView** (`Sources/App/Views/Sidebar/SidebarView.swift`) — vertical session list in the sidebar (rename to `SidebarProjectList.swift`)

## Public API

```swift
ReorderableStack(
    items,                              // [Item] — read-only
    axis: .horizontal,                  // .horizontal | .vertical
    spacing: 1                          // inter-item spacing
) { item, isDragging in
    WindowTab(window: item, ...)        // @ViewBuilder per item
} onReorder: { from, to in
    session.windows.move(fromOffsets: IndexSet(integer: from), toOffset: to)
}
```

- `items` is a plain `[Item]`, not a `Binding`. The container never mutates it.
- `isDragging: Bool` is passed to the content builder so items can optionally style themselves.
- `onReorder(fromIndex, toIndex)` is called once on drop. The parent decides how to commit.
- `Item` conforms to `Identifiable`.

## Internal State

```
draggedIndex: Int?          — which item is being dragged
insertionIndex: Int?        — where it would land if dropped now
dragOffset: CGFloat         — cursor translation along the drag axis
itemFrames: [Int: CGRect]   — measured frames of each item via PreferenceKey
```

## Geometry & Hit Testing

Each child is wrapped in an overlay that reports its frame via a `PreferenceKey`. The container collects these in `onPreferenceChange` into the `itemFrames` dictionary.

Insertion index is computed by comparing the dragged item's current center position against item midpoints:

- **Horizontal:** compare X against each item's `midX`
- **Vertical:** compare Y against each item's `midY`
- Cursor before the first midpoint → index 0 (first position)
- Cursor after the last midpoint → index N (last position)

**Dead zone:** insertion index only updates when the cursor crosses a midpoint by at least 4px, preventing oscillation at boundaries.

## Visual Feedback

### Dragged Item
- Stays in the layout flow at **full opacity** (1.0)
- Offset along the drag axis matching gesture translation (axis-locked)
- `.zIndex(1)` to render above neighbors
- Subtle shadow: `shadow(color: .black.opacity(0.15), radius: 4, y: 2)`
- Scale `1.03` for depth cue

### Neighbor Items
- Items between the original position and insertion index shift by the dragged item's width/height
- Animated with `.spring(response: 0.25, dampingFraction: 0.85)`
- All other items remain stationary

### No Insertion Indicator Line
The gap created by neighbor offsets is the indicator. A line on top of that would be redundant.

## Gesture Lifecycle

### Drag Start (translation > 3px)
- Set `draggedIndex`, snapshot `itemFrames`
- Begin tracking `dragOffset`

### Drag Changed
- Update `dragOffset` from gesture translation (axis-locked, clamped to container bounds)
- Recompute `insertionIndex` from cursor position vs midpoints + dead zone

### Drag Ended
- Call `onReorder(draggedIndex, insertionIndex)` if they differ
- Clear all drag state immediately
- No animation on commit — neighbors are already in position from offset animation

### Cancel (Escape Key)
- Animate `dragOffset` back to 0
- Clear drag state without calling `onReorder`

## File Structure

### New
- `Sources/App/Views/ReorderableStack.swift` — the container view, `ItemFramePreferenceKey`

### Deleted
- `Sources/App/Views/ReorderDropDelegate.swift`

### Modified
- `Sources/App/Views/Detail/WindowTabBar.swift` — replace ForEach+onDrag/onDrop with ReorderableStack, remove `@State draggedTabId`, remove trailing Color.clear drop zone
- `Sources/App/Views/Sidebar/SessionRow.swift` — replace ForEach+onDrag/onDrop with ReorderableStack, remove `@State draggedWindowId`
- `Sources/App/Views/Sidebar/SidebarView.swift` — rename to `SidebarProjectList.swift`, replace ForEach+onDrag/onDrop with ReorderableStack, remove `@State draggedSessionId`, remove trailing Color.clear drop zone

## Migration Checklist

For each consumer:
1. Replace `ForEach` + `.onDrag` + `.onDrop(delegate:)` with `ReorderableStack`
2. Remove `@State private var draggedXxxId: String?`
3. Remove trailing `Color.clear` drop zone hacks
4. Remove `.opacity(draggedXxxId == item.id ? 0.0 : 1.0)` — container handles this
5. Verify existing context menus, tap gestures, hover states still work on items
