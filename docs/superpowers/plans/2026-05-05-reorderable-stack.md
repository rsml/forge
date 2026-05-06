# ReorderableStack Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `.onDrag`/`.onDrop`/`ReorderDropDelegate` with a custom `DragGesture`-based `ReorderableStack` container view that eliminates drag opacity, jitter, position limitations, and drop delay.

**Architecture:** A generic `ReorderableStack<Item, Content>` container owns layout, gesture, hit testing, and animation. Consumers provide items + content builder + reorder callback. Three call sites migrated: `WindowTabBar` (horizontal), `SessionRow` (vertical), `SidebarView` (vertical, renamed to `SidebarProjectList`).

**Tech Stack:** SwiftUI, macOS 14+, Swift 6.0

**Spec:** `docs/superpowers/specs/2026-05-05-reorderable-stack-design.md`

---

### Task 1: Build ReorderableStack — Geometry & Layout

**Files:**
- Create: `Sources/App/Views/ReorderableStack.swift`

This task builds the container shell: it lays out items in an HStack or VStack, measures their frames via a PreferenceKey, and exposes the public API. No drag behavior yet — just layout and measurement.

- [ ] **Step 1: Create ReorderableStack.swift with the PreferenceKey and container struct**

```swift
import SwiftUI

// MARK: - Frame Measurement

struct ItemFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
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
```

- [ ] **Step 2: Build and verify it compiles**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/App/Views/ReorderableStack.swift
git commit -m "feat: add ReorderableStack shell with geometry measurement"
```

---

### Task 2: Add Drag Gesture & Hit Testing

**Files:**
- Modify: `Sources/App/Views/ReorderableStack.swift`

Add the `DragGesture` to each item, compute `insertionIndex` from cursor position vs item midpoints, and implement the full gesture lifecycle (start, changed, ended).

- [ ] **Step 1: Add the hit-testing helper and drag gesture to each item**

Add these methods to `ReorderableStack`:

```swift
// MARK: - Hit Testing

/// Compute insertion index from the dragged item's current center position.
/// Uses snapshotted frames (captured at drag start) with a 4px dead zone.
/// Returns a value compatible with Array.move(fromOffsets:toOffset:).
private func computeInsertionIndex(draggedCenter: CGFloat) -> Int {
    let sortedFrames = dragFrameSnapshot.sorted { $0.key < $1.key }
    guard !sortedFrames.isEmpty else { return 0 }

    for (index, frame) in sortedFrames {
        let mid = axis == .horizontal ? frame.value.midX : frame.value.midY
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

    let draggedSize = axis == .horizontal ? draggedFrame.width : draggedFrame.height
    let shiftAmount = draggedSize + spacing

    // Items between `from` and `to` need to shift to make room
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
```

Update `body` to attach the drag gesture and apply offsets:

```swift
var body: some View {
    let layout = axis == .horizontal
        ? AnyLayout(HStackLayout(spacing: spacing))
        : AnyLayout(VStackLayout(spacing: spacing))

    layout {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            let isDragging = draggedIndex == index
            content(item, isDragging)
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
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .preference(
                                key: ItemFramePreferenceKey.self,
                                value: [index: geo.frame(in: .named(coordinateSpaceID))]
                            )
                    }
                )
                .gesture(
                    DragGesture(minimumDistance: 3, coordinateSpace: .named(coordinateSpaceID))
                        .onChanged { value in
                            if draggedIndex == nil {
                                draggedIndex = index
                                dragFrameSnapshot = itemFrames
                            }
                            guard let frame = dragFrameSnapshot[index] else { return }

                            let translation = axis == .horizontal
                                ? value.translation.width
                                : value.translation.height
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

                            // computeInsertionIndex returns values compatible with
                            // Array.move(fromOffsets:toOffset:) — no conversion needed
                            if let from, let to, from != to {
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
```

- [ ] **Step 2: Build and verify it compiles**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/App/Views/ReorderableStack.swift
git commit -m "feat: add drag gesture, hit testing, and visual feedback to ReorderableStack"
```

---

### Task 3: Migrate WindowTabBar (Horizontal Tabs)

**Files:**
- Modify: `Sources/App/Views/Detail/WindowTabBar.swift:33-98` (the ScrollView + ForEach block)

Replace the `ForEach` with `.onDrag`/`.onDrop` with `ReorderableStack`. Remove `@State draggedTabId`. Remove the `.onDrop` from the trailing `Color.clear` zone (keep the zone itself for double-tap and context menu).

- [ ] **Step 1: Remove `@State private var draggedTabId: String?` from WindowTabBar**

Delete line 12:
```swift
@State private var draggedTabId: String?
```

- [ ] **Step 2: Replace the ScrollView contents**

Replace the `ScrollView` block (lines 33-98) with:

```swift
ScrollView(.horizontal, showsIndicators: false) {
    ReorderableStack(session.windows, axis: .horizontal, spacing: 1) { window, isDragging in
        if renamingWindowId == window.id {
            InlineRenameField(text: $renameText, font: .system(.caption, weight: .regular), onCancel: { renamingWindowId = nil }) {
                if !renameText.isEmpty {
                    controller.renameWindow(window, to: renameText)
                }
                renamingWindowId = nil
            }
            .fixedSize()
            .frame(height: 28)
        } else {
            WindowTab(
                window: window,
                isActive: window.id == controller.workspace.activeWindowId,
                tabIndex: session.windows.firstIndex(where: { $0.id == window.id }).map { $0 + 1 } ?? 0,
                indicatorOnTop: tabBarOnBottom
            )
            .onTapGesture {
                controller.selectWindow(window)
            }
            .contextMenu {
                Button("New Tab") {
                    controller.addWindow(in: session)
                }
                .keyboardShortcut(KeyboardShortcuts.newTab.key, modifiers: KeyboardShortcuts.newTab.modifiers)
                Button("New Browser Tab") {}
                Divider()
                Button("Rename") {
                    renamingWindowId = window.id
                    renameText = window.name
                }
                .keyboardShortcut(KeyboardShortcuts.renameTab.key, modifiers: KeyboardShortcuts.renameTab.modifiers)
                if attention.isHidden(window.uuid) {
                    Button("Unhide from Stack View") {
                        attention.unhide(window.uuid)
                    }
                } else {
                    Button("Hide from Stack View") {
                        attention.hide(window.uuid)
                    }
                }
                Button("Close Tab", role: .destructive) {
                    controller.removeWindow(window, in: session)
                }
                .keyboardShortcut(KeyboardShortcuts.closePane.key, modifiers: KeyboardShortcuts.closePane.modifiers)
            }
        }
    } onReorder: { from, to in
        session.windows.move(fromOffsets: IndexSet(integer: from), toOffset: to)
    }
    .padding(.horizontal, 4)
}
.fixedSize(horizontal: true, vertical: false)
```

- [ ] **Step 3: Simplify the trailing Color.clear zone**

Remove the `.onDrop` from the trailing `Color.clear` spacer (lines 107-119). Keep the double-tap gesture and context menu. The result:

```swift
Color.clear
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .contentShape(Rectangle())
    .onTapGesture(count: 2) {
        controller.addWindow(in: session)
    }
    .contextMenu {
        Button("New Tab") {
            controller.addWindow(in: session)
        }
        .keyboardShortcut(KeyboardShortcuts.newTab.key, modifiers: KeyboardShortcuts.newTab.modifiers)
        Button("New Browser Tab") {}
    }
```

- [ ] **Step 4: Build and verify**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add Sources/App/Views/Detail/WindowTabBar.swift
git commit -m "refactor: migrate WindowTabBar to ReorderableStack"
```

---

### Task 4: Migrate SessionRow (Sidebar Window List)

**Files:**
- Modify: `Sources/App/Views/Sidebar/SessionRow.swift:91-136` (the expanded window list)

Replace the `ForEach` with `.onDrag`/`.onDrop` with `ReorderableStack`. Remove `@State draggedWindowId`.

- [ ] **Step 1: Remove `@State private var draggedWindowId: String?` from SessionRow**

Delete line 31:
```swift
@State private var draggedWindowId: String?
```

- [ ] **Step 2: Replace the expanded window list**

Replace the `if isExpanded` block (lines 91-136) with:

```swift
if isExpanded {
    ReorderableStack(session.windows, axis: .vertical, spacing: 0) { window, isDragging in
        SidebarTabRow(
            window: window,
            isActive: isActive && window.id == activeWindowId,
            isHovered: hoveredWindowId == window.id,
            isRenaming: renamingWindowId == window.id,
            tabIndex: session.windows.firstIndex(where: { $0.id == window.id }).map { $0 + 1 } ?? 0,
            renameText: $renameText,
            onRenameCommit: onRenameWindowCommit,
            onRenameCancel: onRenameWindowCancel
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredWindowId = hovering ? window.id : nil
        }
        .onTapGesture {
            onSelectWindow(window)
        }
        .contextMenu {
            Button("Rename") { onStartWindowRename(window) }
                .keyboardShortcut(KeyboardShortcuts.renameTab.key, modifiers: KeyboardShortcuts.renameTab.modifiers)
            Button("Close Tab", role: .destructive) {
                onSelectWindow(window)
            }
            .keyboardShortcut(KeyboardShortcuts.closePane.key, modifiers: KeyboardShortcuts.closePane.modifiers)
        }
    } onReorder: { from, to in
        session.windows.move(fromOffsets: IndexSet(integer: from), toOffset: to)
    }
    .padding(.leading, 0)
    .transition(.opacity.combined(with: .move(edge: .top)))
}
```

- [ ] **Step 3: Build and verify**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/App/Views/Sidebar/SessionRow.swift
git commit -m "refactor: migrate SessionRow to ReorderableStack"
```

---

### Task 5: Rename SidebarView → SidebarProjectList

**Files:**
- Rename: `Sources/App/Views/Sidebar/SidebarView.swift` → `Sources/App/Views/Sidebar/SidebarProjectList.swift`
- Modify: `Sources/App/Views/MainView.swift` (if the struct name changes)

This is a cosmetic rename in a separate commit before the functional migration.

- [ ] **Step 1: Rename the file via git mv**

```bash
git mv Sources/App/Views/Sidebar/SidebarView.swift Sources/App/Views/Sidebar/SidebarProjectList.swift
```

- [ ] **Step 2: Rename the struct inside the file**

In `SidebarProjectList.swift`, rename `struct SidebarView` to `struct SidebarProjectList`. Update the reference in `MainView.swift` (`SidebarView(` → `SidebarProjectList(`).

- [ ] **Step 3: Build and verify**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/App/Views/Sidebar/SidebarProjectList.swift Sources/App/Views/MainView.swift
git commit -m "refactor: rename SidebarView to SidebarProjectList"
```

---

### Task 6: Migrate SidebarProjectList (Session List)

**Files:**
- Modify: `Sources/App/Views/Sidebar/SidebarProjectList.swift:80-183` (the projectList computed property)

Replace the `ForEach` with `.onDrag`/`.onDrop` with `ReorderableStack`. Remove `@State draggedSessionId`. Switch `LazyVStack` to `VStack`. Remove trailing `Color.clear` drop zone.

- [ ] **Step 1: Remove `@State private var draggedSessionId: String?` from SidebarProjectList**

Delete line 12:
```swift
@State private var draggedSessionId: String?
```

- [ ] **Step 2: Replace projectList body**

Replace the `projectList` computed property with:

```swift
@ViewBuilder
private var projectList: some View {
    ScrollView {
        VStack(alignment: .leading, spacing: 2) {
            ReorderableStack(controller.workspace.sessions, axis: .vertical, spacing: 2) { session, isDragging in
                SessionRow(
                    session: session,
                    isActive: session.id == controller.workspace.activeSessionId,
                    activeWindowId: controller.workspace.activeWindowId,
                    isExpanded: Binding(
                        get: { expandedSessions.contains(session.id) },
                        set: {
                            if $0 { expandedSessions.insert(session.id) } else { expandedSessions.remove(session.id) }
                            let names = controller.workspace.sessions
                                .filter { expandedSessions.contains($0.id) }
                                .map(\.name)
                            controller.saveUIState(expandedSessionNames: names)
                        }
                    ),
                    isRenaming: renamingSessionId == session.id,
                    renameText: $renameText,
                    onRenameCommit: {
                        if !renameText.isEmpty {
                            session.name = renameText
                            controller.renameSession(session, to: renameText)
                        }
                        renamingSessionId = nil
                    },
                    onRenameCancel: { renamingSessionId = nil },
                    onSelect: {
                        controller.selectSession(session)
                    },
                    onSelectWindow: { window in
                        controller.selectSession(session)
                        controller.selectWindow(window)
                    },
                    renamingWindowId: renamingWindowId,
                    onStartWindowRename: { window in
                        renamingSessionId = nil
                        renamingWindowId = window.id
                        renameText = window.name
                    },
                    onRenameWindowCommit: {
                        if !renameText.isEmpty,
                           let window = session.windows.first(where: { $0.id == renamingWindowId }) {
                            window.name = renameText
                            controller.renameWindow(window, to: renameText)
                        }
                        renamingWindowId = nil
                    },
                    onRenameWindowCancel: { renamingWindowId = nil },
                    projectIndex: controller.workspace.sessions.firstIndex(where: { $0.id == session.id }).map { $0 + 1 } ?? 0
                )
                .contextMenu {
                    Button("Rename...") {
                        renamingWindowId = nil
                        renameText = session.name
                        renamingSessionId = session.id
                    }
                    Divider()
                    Button("New Tab") { controller.addWindow(in: session) }
                    Divider()
                    Button("Close Project", role: .destructive) { controller.removeSession(session) }
                }
            } onReorder: { from, to in
                controller.workspace.sessions.move(fromOffsets: IndexSet(integer: from), toOffset: to)
            }
        }
        .padding(.horizontal, 0)
        .padding(.top, 4)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .contentShape(Rectangle())
    .onTapGesture(count: 2) {
        NotificationCenter.default.post(name: .forgeNewProject, object: nil)
    }
}
```

Key changes from original:
- `LazyVStack` → `VStack` (PreferenceKey reliability)
- `ForEach` + `.onDrag`/`.onDrop` → `ReorderableStack`
- Removed `.opacity(draggedSessionId == ...)` — container handles this
- Removed trailing `Color.clear` drop zone — container handles last-position drops
- `projectIndex` now computed from `firstIndex` instead of `enumerated()` index (since the ForEach is inside ReorderableStack)

- [ ] **Step 3: Build and verify**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/App/Views/Sidebar/SidebarProjectList.swift
git commit -m "refactor: migrate SidebarProjectList to ReorderableStack"
```

---

### Task 7: Delete ReorderDropDelegate & Final Verification

**Files:**
- Delete: `Sources/App/Views/ReorderDropDelegate.swift`

- [ ] **Step 1: Verify no remaining references to ReorderDropDelegate**

Run: `grep -r "ReorderDropDelegate" Sources/`
Expected: No output (all references removed in Tasks 3-6)

- [ ] **Step 2: Delete the file**

```bash
git rm Sources/App/Views/ReorderDropDelegate.swift
```

- [ ] **Step 3: Verify no remaining references to onDrag or draggedTabId/draggedWindowId/draggedSessionId**

Run: `grep -rn "onDrag\|draggedTabId\|draggedWindowId\|draggedSessionId" Sources/App/Views/`
Expected: No output

- [ ] **Step 4: Build and verify clean compile**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git rm Sources/App/Views/ReorderDropDelegate.swift
git commit -m "refactor: remove ReorderDropDelegate — fully replaced by ReorderableStack"
```

---

### Task 8: Manual Smoke Test

No automated tests for this — it's gesture/animation behavior that requires visual verification.

- [ ] **Step 1: Launch the app**

Run: `make run` or launch from Xcode

- [ ] **Step 2: Test horizontal tab reordering (WindowTabBar)**

Verify:
- Dragging a tab shows full opacity, slight shadow, slight scale-up
- Neighbor tabs slide apart smoothly to make room
- Can drag to first position
- Can drag to last position
- Dropping commits instantly with no delay
- Tab click (select) still works
- Tab context menu still works
- Double-click empty area creates new tab
- Inline rename (right-click → Rename) still works during/after drag

- [ ] **Step 3: Test vertical window reordering (SessionRow in sidebar)**

Verify:
- Expand a session with multiple windows
- Drag a window up/down — same visual behavior as tabs
- Hover states still work
- Click to select still works
- Context menu still works

- [ ] **Step 4: Test vertical session reordering (SidebarProjectList)**

Verify:
- Drag a session up/down in the sidebar
- Expand/collapse chevrons still work
- Context menu still works
- Double-click empty area creates new project

- [ ] **Step 5: Edge cases**

- Drag with only 1 item (should be a no-op, no crash)
- Drag to the same position (should be a no-op)
- Rapid drag back and forth (should not jitter)
- Drag while scrolled in tab bar (if many tabs)
