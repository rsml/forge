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
isDragging: Bool            — true after translation exceeds threshold
```

## Geometry & Hit Testing

Each child is wrapped in an overlay that reports its frame via a `PreferenceKey`. The container collects these in `onPreferenceChange` into the `itemFrames` dictionary. All frames are measured in the container's local coordinate space using a named `CoordinateSpace` defined on the outer stack.

Insertion index is computed by comparing the dragged item's current center position against item midpoints:

- **Horizontal:** compare X against each item's `midX`
- **Vertical:** compare Y against each item's `midY`
- Cursor before the first midpoint → index 0 (first position)
- Cursor after the last midpoint → index N (last position)

**Dead zone:** insertion index only updates when the cursor crosses a midpoint by at least 4px, preventing oscillation at boundaries.

**`onReorder` index semantics:** `toIndex` uses `Array.move(fromOffsets:toOffset:)` convention — it is the destination index in the original array (before removal). All three consumers already call `move(fromOffsets:toOffset:)`, so no translation is needed.

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

## Gesture & ScrollView Interaction

The `DragGesture` is attached to each item view. `WindowTabBar` wraps tabs in `ScrollView(.horizontal)` and `SidebarView` wraps sessions in `ScrollView`. To prevent gesture conflict:

- The `DragGesture` uses `minimumDistance: 3` on the drag axis. This is enough to disambiguate from taps but small enough to feel responsive.
- Attach the drag gesture via `.gesture()` (not `.highPriorityGesture()`). On macOS, `ScrollView` scrolling is driven by scroll wheel / trackpad scroll events, not drag gestures, so there is no conflict — `DragGesture` responds to mouse-down-and-drag, `ScrollView` responds to scroll events. These are distinct input channels on macOS.
- `.onTapGesture` is attached to item content inside the `@ViewBuilder`, not to the container wrapper. Since tap and drag have different minimum distances, SwiftUI disambiguates them correctly. The 3px drag threshold is sufficient — normal clicks produce < 1px of movement.

## Gesture Lifecycle

### Drag Start (translation > 3px)
- Set `draggedIndex`, snapshot `itemFrames`
- Begin tracking `dragOffset`

### Drag Changed
- Update `dragOffset` from gesture translation (axis-locked, clamped to container bounds)
- Recompute `insertionIndex` from cursor position vs midpoints + dead zone

### Drag Ended
- Clear offsets and drag state first, then call `onReorder(draggedIndex, insertionIndex)` if they differ. Clearing state before the mutation ensures the SwiftUI re-render from the array change sees zero offsets, preventing visual jumps.

### Cancel (Escape Key)
- Use `.onKeyPress(.escape)` on the container view (the container is focused during drag via mouse-down). If focus proves unreliable, fall back to `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` installed on drag start and removed on drag end.
- Animate `dragOffset` back to 0, clear drag state without calling `onReorder`.

## Inline Rename & Drag Suppression

Both `WindowTabBar` and `SessionRow` replace item content with `InlineRenameField` during rename. Dragging a text field is meaningless. The container does not need special logic for this — the `DragGesture(minimumDistance: 3)` will not interfere with text field interaction because the text field captures mouse events first. If an item is in rename mode, the content builder simply renders the text field instead of the draggable tab content, and the text field's own gesture handling takes priority.

## LazyVStack Consideration

`SidebarView.projectList` currently uses `LazyVStack`. `PreferenceKey` values from off-screen children in `LazyVStack` are unreliable because SwiftUI deallocates off-screen views. Switch to `VStack` for the reorderable section. Session lists are small (typically < 20 items) and the performance difference is negligible.

## Non-Reorderable Zones

`WindowTabBar` has a trailing `Color.clear` area with double-tap (new tab) and context menu. `SidebarView` has a background double-tap (new project). These zones are **outside** the `ReorderableStack` — they remain as sibling views in the parent layout. The trailing `Color.clear` drop zone hack is removed since `ReorderableStack` handles last-position drops natively.

## File Structure

### New
- `Sources/App/Views/ReorderableStack.swift` — the container view, `ItemFramePreferenceKey`

### Deleted
- `Sources/App/Views/ReorderDropDelegate.swift`

### Modified
- `Sources/App/Views/Detail/WindowTabBar.swift` — replace ForEach+onDrag/onDrop with ReorderableStack, remove `@State draggedTabId`, remove trailing Color.clear drop zone (preserve its double-tap and context menu on the remaining spacer)
- `Sources/App/Views/Sidebar/SessionRow.swift` — replace ForEach+onDrag/onDrop with ReorderableStack, remove `@State draggedWindowId`
- `Sources/App/Views/Sidebar/SidebarView.swift` — rename to `SidebarProjectList.swift` (separate commit from functional changes), replace ForEach+onDrag/onDrop with ReorderableStack, remove `@State draggedSessionId`, remove trailing Color.clear drop zone, switch `LazyVStack` to `VStack`

## Migration Checklist

For each consumer:
1. Replace `ForEach` + `.onDrag` + `.onDrop(delegate:)` with `ReorderableStack`
2. Remove `@State private var draggedXxxId: String?`
3. Remove trailing `Color.clear` drop zone hacks (preserve sibling double-tap/context menu zones)
4. Remove `.opacity(draggedXxxId == item.id ? 0.0 : 1.0)` — container handles this
5. Verify existing context menus, tap gestures, hover states still work on items
6. Verify inline rename still works (text field should capture input without drag interference)
