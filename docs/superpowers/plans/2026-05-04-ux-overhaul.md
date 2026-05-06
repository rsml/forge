# Forge UX Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix title bar reliability, drag-and-drop bugs, add sidebar/layout options, font system, theme application, and various UX polish items.

**Architecture:** All layout preferences (sidebar position, tab bar position) stored in ForgeConfigStore and read reactively. Font system uses 3 font configs (primary, secondary, terminal) stored in config. Theme application pipes parsed colors into SwiftTerm via NSViewRepresentable updates.

**Tech Stack:** SwiftUI, AppKit (NSWindow), SwiftTerm, macOS 14+

---

## Stream 1: Title Bar + Window Chrome

### Task 1: Fix title bar visibility

The `.hiddenTitleBar` window style causes the title bar content to be hidden behind macOS traffic light buttons inconsistently. Fix: switch back to `.windowStyle(.automatic)` and use AppDelegate to configure the window with persistent observers that re-apply settings.

**Files:**
- Modify: `Sources/ForgeApp.swift` — change `.hiddenTitleBar` back to `.automatic`, beef up AppDelegate window config
- Modify: `Sources/App/Views/MainView.swift` — restore robust window configuration with multiple observers

**Changes:**
- [ ] In ForgeApp.swift: change `.windowStyle(.hiddenTitleBar)` to `.windowStyle(.automatic)`
- [ ] In AppDelegate: add a `configureMainWindow()` method that:
  1. Finds the main window
  2. Sets `titlebarAppearsTransparent = true`, `titleVisibility = .hidden`, `styleMask.insert(.fullSizeContentView)`
  3. Uses KVO observer on the window to re-apply when properties change
  4. Also observes `didExitFullScreenNotification`, `didBecomeKeyNotification`, `didBecomeMainNotification`
- [ ] In MainView: simplify `configureWindow()` since AppDelegate handles it

### Task 2: Tab underline flips when tabs on bottom

When tab bar is at bottom, the active indicator line should appear ABOVE the tab text instead of below.

**Files:**
- Modify: `Sources/App/Views/Detail/WindowTabBar.swift` — WindowTab accepts `indicatorOnTop` param

**Changes:**
- [ ] Add `var indicatorOnTop: Bool = false` parameter to `WindowTab`
- [ ] In WindowTab.body, conditionally render the indicator RoundedRectangle before or after the HStack
- [ ] In WindowTabBar, read tab bar position from ForgeConfigStore and pass `indicatorOnTop: tabBarPosition == "bottom"` to each WindowTab

---

## Stream 4: Small UX Fixes

### Task 3: Fix drag-and-drop reordering

Current issues: can't drag to last position, janky sync, items jump back.

**Files:**
- Modify: `Sources/App/Views/ReorderDropDelegate.swift` — fix `dropEntered` index calculation, add trailing drop zone
- Modify: `Sources/App/Views/Sidebar/SidebarView.swift` — add trailing drop zone for sessions
- Modify: `Sources/App/Views/Detail/WindowTabBar.swift` — add trailing drop zone for tabs

**Changes:**
- [ ] In ReorderDropDelegate: fix the `onMove` call. Currently uses `IndexSet(integer: from), to` but `List.move(fromOffsets:toOffset:)` expects the toOffset to be the position BEFORE removal. Add +1 when dragging forward: `let dest = from < to ? to + 1 : to`
- [ ] In SidebarView: after the ForEach of sessions, add an invisible drop target (Color.clear with `.onDrop`) that accepts drops at the end position
- [ ] In WindowTabBar: after the ForEach of tabs in HStack, add similar trailing drop zone
- [ ] Clear `draggedItemId` on `dropExited` to prevent stale state

### Task 4: Project picker auto-browse when no recents

**Files:**
- Modify: `Sources/App/Views/Picker/ProjectPickerView.swift`

**Changes:**
- [ ] In `.onAppear`, after loading recents: if `recentPaths.isEmpty`, immediately call `browseForFolder()`

### Task 5: Notification panel minimum height

**Files:**
- Modify: `Sources/App/Views/Sidebar/NotificationPanel.swift`

**Changes:**
- [ ] Wrap the empty state VStack with `.frame(minHeight: 120)` and add `.padding(.vertical, 20)`

### Task 6: Shortcuts settings multi-column layout

**Files:**
- Modify: `Sources/App/Views/Settings/ShortcutsSettingsPane.swift`

**Changes:**
- [ ] Split categories into two columns using an HStack with two VStacks
- [ ] Left column: File, View, Splits (first 3 categories)
- [ ] Right column: Tabs, Projects, App (last 3 categories)
- [ ] Each column is a VStack with the same styling as current

### Task 7: About Forge menu item shows version

**Files:**
- Modify: `Sources/ForgeApp.swift` — add `CommandGroup(replacing: .appInfo)` with version display

**Changes:**
- [ ] Add `CommandGroup(replacing: .appInfo)` in ForgeMenuCommands that shows "About Forge" button
- [ ] The button opens the Settings window to the About tab (or shows an NSAlert with the same info)

### Task 8: Default project directory picker opens at saved path

**Files:**
- Modify: `Sources/App/Views/Settings/GeneralSettingsPane.swift`

**Changes:**
- [ ] In `pickDirectory()`, set `panel.directoryURL` to the current saved path before showing

---

## Stream 2: Layout System

### Task 9: Add sidebar position (left/right) to config

**Files:**
- Modify: `Sources/Adapters/Config/ForgeConfig.swift` — add `sidebarPosition` to GeneralSettings
- Modify: `Sources/App/Views/Settings/GeneralSettingsPane.swift` — add Layout section with sidebar position + tab bar position
- Modify: `Sources/App/Views/Settings/TerminalSettingsPane.swift` — remove tab bar position (moved to General)

**Changes:**
- [ ] Add `var sidebarPosition: String?` to GeneralSettings (default "left")
- [ ] In GeneralSettingsPane, add "Layout" section with sidebar position picker (Left/Right segmented) and tab bar position picker (moved from Terminal)
- [ ] Remove tab bar position from TerminalSettingsPane

### Task 10: Implement sidebar left/right positioning

**Files:**
- Modify: `Sources/App/Views/MainView.swift` — read sidebar position, flip layout
- Modify: `Sources/App/Views/Sidebar/SidebarView.swift` — reverse toolbar icons when sidebar is on right

**Changes:**
- [ ] In MainView, read `ForgeConfigStore.shared.config.general?.sidebarPosition ?? "left"`
- [ ] If "right": render detail first, divider, then sidebar (reverse HStack order)
- [ ] In SidebarView, accept `position: String` param. When "right", reverse icon order: toggle sidebar, command palette, notifications, new project
- [ ] When sidebar is on right, the toggle sidebar icon should flip (use `sidebar.right` instead of `sidebar.left`)

### Task 11: Sidebar toolbar follows tab bar position

**Files:**
- Modify: `Sources/App/Views/Sidebar/SidebarView.swift` — move toolbar to bottom when tab bar is bottom

**Changes:**
- [ ] Read tab bar position from ForgeConfigStore
- [ ] When "bottom", render: title bar zone, scroll area, toolbar (toolbar at bottom)
- [ ] When "top" (default), render: title bar zone, toolbar, scroll area (current layout)

---

## Stream 3: Font System + Themes

### Task 12: Font config model

**Files:**
- Modify: `Sources/Adapters/Config/ForgeConfig.swift` — add FontConfig struct and font settings

**Changes:**
- [ ] Add `FontConfig` struct: `family: String?`, `size: Int?`, `useLigatures: Bool?`, `lineHeight: Double?`
- [ ] Add to ForgeConfig: `primaryFont: FontConfig?`, `secondaryFont: FontConfig?`, `terminalFont: FontConfig?`
- [ ] Primary font default: system font, 13pt (used for project names in sidebar)
- [ ] Secondary font default: system font, 11pt (used for tab names, captions)
- [ ] Terminal font default: resolved from ghostty/nerd fonts, 13pt

### Task 13: Font settings tab

**Files:**
- Create: `Sources/App/Views/Settings/FontSettingsPane.swift`
- Modify: `Sources/App/Views/Settings/SettingsView.swift` — add Fonts tab

**Changes:**
- [ ] Create FontSettingsPane with 3 sections: Primary Font, Secondary Font, Terminal Font
- [ ] Each section: font family picker (system monospace fonts + Nerd Fonts), size field + stepper, ligatures toggle, live preview text
- [ ] Terminal Font section additionally has line height slider (1.0-2.0, default 1.2)
- [ ] Font family picker should detect and list Nerd Font variants
- [ ] Add "Fonts" tab (textformat icon) to SettingsView between Theme and Terminal

### Task 14: Apply fonts reactively across UI

**Files:**
- Modify: `Sources/App/Views/Sidebar/SessionRow.swift` — use primary font
- Modify: `Sources/App/Views/Detail/WindowTabBar.swift` — use secondary font
- Modify: `Sources/App/Views/Detail/ForgeTerminalView.swift` — use terminal font with real-time updates

**Changes:**
- [ ] In SessionRow: read `ForgeConfigStore.shared.config.primaryFont` for session name text
- [ ] In WindowTab/SidebarTabRow: read `secondaryFont` for tab names
- [ ] In ForgeTerminalView.updateNSView: check if font config changed, update terminal.font if so
- [ ] For Nerd Font support: the existing `resolveTerminalFont` fallback list already includes Nerd Fonts; ensure the font picker includes them

### Task 15: Fix theme application

Themes currently don't apply to the terminal. Need to parse theme colors and apply them to SwiftTerm.

**Files:**
- Modify: `Sources/App/Views/Detail/ForgeTerminalView.swift` — apply theme colors from config store
- Modify: `Sources/Adapters/Theme/ThemeParser.swift` — ensure proper color parsing
- Modify: `Sources/App/Views/Settings/ThemePreviewCard.swift` — better preview

**Changes:**
- [ ] In ForgeTerminalView.makeNSView: read theme from ForgeConfigStore, look up ThemeDefinition, apply bg/fg/ansi colors to terminal
- [ ] In ForgeTerminalView.updateNSView: check if theme changed, re-apply colors
- [ ] For SwiftTerm color application: `terminal.nativeForegroundColor`, `terminal.nativeBackgroundColor`, and `terminal.installColors()` for ANSI palette
- [ ] In ThemePreviewCard: replace colored bars with a mini terminal mockup showing colored text lines (e.g., a prompt, a command, output in different colors)
- [ ] In ThemeSettingsPane: add slight background tint to the filter field to distinguish it from settings background

### Task 16: State persistence for selections

**Files:**
- Modify: `Sources/App/WorkspaceController.swift` — already saves activeSession/activeWindow/expandedSessions/sidebarVisible; verify it all works

**Changes:**
- [ ] Verify `saveUIState` is called on all selection changes (it already is)
- [ ] Verify `restoreUIState` properly restores on launch (it already does)
- [ ] The existing UIState already has: activeSessionName, activeWindowIndex, sidebarVisible, expandedSessionNames
- [ ] This should already be working — verify and fix any gaps
