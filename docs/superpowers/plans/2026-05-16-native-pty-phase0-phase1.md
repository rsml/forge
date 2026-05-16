# Native PTY Architecture — Phase 0 + Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace tmux control mode with direct Ghostty PTY ownership so TUI apps (Claude Code, vim, htop) render perfectly — no grid mismatches, no encoding overhead, no rendering bugs.

**Architecture:** Ghostty surfaces own their PTYs natively via EXEC mode. No middleman in the data path. Input, output, and resize flow directly between Ghostty and the shell process. A feature flag (`nativePTY`) enables the new path; tmux code stays for fallback.

**Tech Stack:** Swift 6.0, GhosttyKit (Zig/C), SwiftUI, macOS PTY APIs

**Spec:** `docs/superpowers/specs/2026-05-16-native-pty-architecture-design.md`

---

## File Structure

### New Files
- `Sources/Core/Ports/ProcessPort.swift` — port protocol for process lifecycle
- `Sources/Infrastructure/Process/ProcessAdapter.swift` — ProcessPort implementation using GhosttyKit EXEC mode
- `Sources/Infrastructure/Process/CWDTracker.swift` — working directory tracking via `proc_pidinfo`

### Modified Files
- `vendor/ghostty/include/ghostty.h` — add EXTERNAL_FD io mode enum value (Phase 2 prep)
- `Sources/Infrastructure/Terminal/GhosttyApp.swift` — implement `action_cb`, `read_clipboard_cb`
- `Sources/Infrastructure/Terminal/GhosttyRenderer.swift` — add EXEC mode path (no MANUAL IO)
- `Sources/Infrastructure/Terminal/GhosttyNSView.swift` — remove input bypass, let Ghostty handle keys
- `Sources/Infrastructure/Config/ForgeConfig.swift` — add `nativePTY` flag
- `Sources/Features/Terminal/PaneSplitView.swift` — wire resize_paused via Ghostty API
- `Sources/Features/Terminal/TerminalArea.swift` — branch on nativePTY flag
- `Sources/WorkspaceController.swift` — branch on nativePTY for connect flow
- `Sources/WorkspaceController+Actions.swift` — branch on nativePTY for pane creation
- `Sources/WorkspaceController+Rendering.swift` — EXEC mode renderer creation

---

## Phase 0: GhosttyKit Prerequisites

### Task 1: Implement action_cb dispatch in GhosttyApp

**Files:**
- Modify: `Sources/Infrastructure/Terminal/GhosttyApp.swift:137-140`

This is the foundation — Ghostty delivers bell, title changes, cell size, child exit, and command completion via this callback. Currently stubbed as `return false`.

- [ ] **Step 1: Implement action_cb with a switch on action tag**

```swift
// In GhosttyApp.swift, replace the stub:
runtime.action_cb = { userdata, surface, actionPtr in
    guard let userdata, let actionPtr else { return false }
    let app = Unmanaged<GhosttyApp>.fromOpaque(userdata).takeUnretainedValue()
    let action = actionPtr.pointee
    switch action.tag {
    case GHOSTTY_ACTION_RING_BELL:
        DispatchQueue.main.async {
            app.onBell?(surface)
        }
        return true

    case GHOSTTY_ACTION_SET_TITLE:
        let title = String(cString: action.value.set_title.title)
        DispatchQueue.main.async {
            app.onSetTitle?(surface, title)
        }
        return true

    case GHOSTTY_ACTION_CELL_SIZE:
        let w = action.value.cell_size.width
        let h = action.value.cell_size.height
        DispatchQueue.main.async {
            app.onCellSize?(surface, w, h)
        }
        return true

    case GHOSTTY_ACTION_SHOW_CHILD_EXITED:
        DispatchQueue.main.async {
            app.onChildExited?(surface)
        }
        return true

    case GHOSTTY_ACTION_COMMAND_FINISHED:
        DispatchQueue.main.async {
            app.onCommandFinished?(surface)
        }
        return true

    case GHOSTTY_ACTION_PWD:
        let pwd = String(cString: action.value.pwd.pwd)
        DispatchQueue.main.async {
            app.onPwd?(surface, pwd)
        }
        return true

    default:
        return false
    }
}
```

Add callback properties to GhosttyApp:
```swift
var onBell: ((ghostty_surface_t?) -> Void)?
var onSetTitle: ((ghostty_surface_t?, String) -> Void)?
var onCellSize: ((ghostty_surface_t?, UInt32, UInt32) -> Void)?
var onChildExited: ((ghostty_surface_t?) -> Void)?
var onCommandFinished: ((ghostty_surface_t?) -> Void)?
var onPwd: ((ghostty_surface_t?, String) -> Void)?
```

- [ ] **Step 2: Implement read_clipboard_cb**

```swift
// Replace the stub:
runtime.read_clipboard_cb = { userdata, surface, location in
    guard let surface else { return false }
    DispatchQueue.main.async {
        let content = NSPasteboard.general.string(forType: .string) ?? ""
        content.withCString { cString in
            ghostty_surface_complete_clipboard_request(
                surface, cString, location, false
            )
        }
    }
    return true
}
```

- [ ] **Step 3: Build and verify**

Run: `swift build`
Expected: compiles with no errors. The callbacks are wired but no consumer uses them yet.

- [ ] **Step 4: Commit**

```bash
git add Sources/Infrastructure/Terminal/GhosttyApp.swift
git commit -m "feat: implement action_cb and read_clipboard_cb in GhosttyApp"
```

---

### Task 2: Add ProcessPort protocol to Core

**Files:**
- Create: `Sources/Core/Ports/ProcessPort.swift`

- [ ] **Step 1: Create the port protocol**

```swift
import Foundation

/// Handle to a terminal surface with a running process.
/// Opaque to the domain — implementation details stay in Infrastructure.
public final class PaneHandle: @unchecked Sendable {
    public let id: String
    public let surface: AnyObject  // GhosttyRenderer, opaque to Core
    public init(id: String, surface: AnyObject) {
        self.id = id
        self.surface = surface
    }
}

/// Creates and manages terminal processes.
/// Resize and status are NOT here — Ghostty handles resize internally
/// via setFrameSize, and status arrives via action_cb events.
@MainActor
public protocol ProcessPort {
    func create(cwd: String, env: [String: String]) -> PaneHandle
    func kill(_ handle: PaneHandle)
}
```

- [ ] **Step 2: Build and verify**

Run: `swift build`
Expected: compiles. Protocol has no consumers yet.

- [ ] **Step 3: Commit**

```bash
git add Sources/Core/Ports/ProcessPort.swift
git commit -m "feat: add ProcessPort protocol to Core"
```

---

### Task 3: Add nativePTY feature flag

**Files:**
- Modify: `Sources/Infrastructure/Config/ForgeConfig.swift:50`

- [ ] **Step 1: Add the flag to GeneralSettings**

```swift
// In ForgeConfig.GeneralSettings, add:
var nativePTY: Bool?
```

- [ ] **Step 2: Add computed property to ForgeConfigStore**

```swift
// In ForgeConfigStore, add:
var isNativePTY: Bool {
    config.general?.nativePTY ?? false
}
```

- [ ] **Step 3: Build and commit**

```bash
swift build
git add Sources/Infrastructure/Config/ForgeConfig.swift Sources/Infrastructure/Config/ForgeConfigStore.swift
git commit -m "feat: add nativePTY feature flag"
```

---

### Task 4: Add CWD tracker

**Files:**
- Create: `Sources/Infrastructure/Process/CWDTracker.swift`

- [ ] **Step 1: Create the CWD tracker**

```swift
import Foundation
import Darwin

enum CWDTracker {
    /// Get the current working directory of a process by PID.
    /// Uses proc_pidinfo which works regardless of who owns the PTY.
    static func currentWorkingDirectory(pid: pid_t) -> String? {
        let size = MemoryLayout<proc_vnodepathinfo>.size
        let pathInfo = UnsafeMutablePointer<proc_vnodepathinfo>.allocate(capacity: 1)
        defer { pathInfo.deallocate() }
        let ret = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, pathInfo, Int32(size))
        guard ret == size else { return nil }
        return withUnsafePointer(to: &pathInfo.pointee.pvi_cdir.vip_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { cPath in
                String(cString: cPath)
            }
        }
    }
}
```

- [ ] **Step 2: Build and commit**

```bash
swift build
git add Sources/Infrastructure/Process/CWDTracker.swift
git commit -m "feat: add CWD tracker via proc_pidinfo"
```

---

## Phase 1: Native PTY Mode

### Task 5: Create GhosttyRenderer EXEC mode

**Files:**
- Modify: `Sources/Infrastructure/Terminal/GhosttyRenderer.swift`

Currently GhosttyRenderer uses `GHOSTTY_SURFACE_IO_MANUAL`. Add an alternative initializer that uses EXEC mode (Ghostty forks the shell and owns the PTY).

- [ ] **Step 1: Add EXEC mode initializer**

```swift
/// Creates a renderer in EXEC mode — Ghostty owns the PTY and spawns the shell.
/// No manual feed/input wiring needed. All I/O is handled by Ghostty's Termio thread.
init(ghosttyApp: GhosttyApp, cwd: String, env: [String: String] = [:]) {
    nsView = GhosttyNSView(frame: .zero)

    guard let app = ghosttyApp.app else {
        ForgeLog.log("[ghostty] Cannot create renderer — app not initialized")
        return
    }

    var config = ghostty_surface_config_new()
    config.io_mode = GHOSTTY_SURFACE_IO_EXEC
    config.platform_tag = GHOSTTY_PLATFORM_MACOS
    config.platform = ghostty_platform_u(
        macos: ghostty_platform_macos_s(
            nsview: Unmanaged.passUnretained(nsView).toOpaque()
        )
    )
    config.context = GHOSTTY_SURFACE_CONTEXT_SPLIT

    // Set working directory
    cwd.withCString { cwdPtr in
        config.working_directory = cwdPtr

        // Set environment variables
        var envVars: [ghostty_env_var_s] = env.map { key, value in
            // These will be copied by ghostty, safe to use stack pointers
            ghostty_env_var_s(key: strdup(key), value: strdup(value))
        }
        config.env_vars = envVars.isEmpty ? nil : &envVars
        config.env_var_count = envVars.count

        surface = ghostty_surface_new(app, &config)
        nsView.surface = surface

        // Free strdup'd env vars
        for v in envVars {
            free(UnsafeMutablePointer(mutating: v.key))
            free(UnsafeMutablePointer(mutating: v.value))
        }
    }

    // No onInput/onResize wiring needed — Ghostty handles I/O natively.
    // No io_write_cb — EXEC mode writes directly to the PTY.

    if let surface {
        ghostty_surface_set_content_scale(surface, 2.0, 2.0)
        ForgeLog.log("[ghostty] EXEC surface created successfully")
    } else {
        ForgeLog.log("[ghostty] Failed to create EXEC surface")
    }
}
```

- [ ] **Step 2: Build and verify**

Run: `swift build`
Expected: compiles. The new initializer exists alongside the MANUAL IO one.

- [ ] **Step 3: Commit**

```bash
git add Sources/Infrastructure/Terminal/GhosttyRenderer.swift
git commit -m "feat: add EXEC mode initializer to GhosttyRenderer"
```

---

### Task 6: Create ProcessAdapter

**Files:**
- Create: `Sources/Infrastructure/Process/ProcessAdapter.swift`

- [ ] **Step 1: Implement ProcessPort**

```swift
import AppKit
import ForgeCore

/// ProcessPort implementation using GhosttyKit EXEC mode.
/// Each create() spawns a Ghostty surface that owns its PTY natively.
@MainActor
final class ProcessAdapter: ProcessPort {
    private let ghosttyApp: GhosttyApp

    init(ghosttyApp: GhosttyApp) {
        self.ghosttyApp = ghosttyApp
    }

    func create(cwd: String, env: [String: String]) -> PaneHandle {
        let id = UUID().uuidString
        let renderer = GhosttyRenderer(ghosttyApp: ghosttyApp, cwd: cwd, env: env)
        return PaneHandle(id: id, surface: renderer)
    }

    func kill(_ handle: PaneHandle) {
        // Surface destruction closes Ghostty's fd → SIGHUP → process dies
        // The GhosttyRenderer deinit handles ghostty_surface_free
    }
}
```

- [ ] **Step 2: Build and commit**

```bash
swift build
git add Sources/Infrastructure/Process/ProcessAdapter.swift
git commit -m "feat: add ProcessAdapter implementing ProcessPort via GhosttyKit EXEC mode"
```

---

### Task 7: Remove input bypass from GhosttyNSView (nativePTY path)

**Files:**
- Modify: `Sources/Infrastructure/Terminal/GhosttyNSView.swift`

In EXEC mode, Ghostty handles key encoding natively. The `sendKeyEvent()` bypass and `performKeyEquivalent` override should delegate to Ghostty's native key handling when in EXEC mode. We need a flag to distinguish modes.

- [ ] **Step 1: Add execMode flag and native key handling**

```swift
// Add property to GhosttyNSView:
/// When true, Ghostty handles all key encoding natively (EXEC mode).
/// When false, keys are intercepted and sent via onKeyInput (MANUAL IO mode).
var execMode = false
```

Update `performKeyEquivalent`:
```swift
override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard event.type == .keyDown else { return false }
    guard window?.firstResponder === self else { return false }
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if flags.contains(.command) { return false }

    if execMode {
        // In EXEC mode, let Ghostty handle all keys natively via ghostty_surface_key
        if flags.contains(.control) {
            let keyEvent = buildKeyEvent(for: event, action: GHOSTTY_INPUT_KEY_PRESS)
            if let surface {
                ghostty_surface_key(surface, keyEvent)
            }
            return true
        }
        return false
    }

    // MANUAL IO mode: existing bypass logic
    if flags.contains(.control) {
        sendKeyEvent(event)
        return true
    }
    return false
}
```

Update `keyDown`:
```swift
override func keyDown(with event: NSEvent) {
    if execMode {
        // EXEC mode: delegate to Ghostty's native key handler
        let keyEvent = buildKeyEvent(for: event, action: GHOSTTY_INPUT_KEY_PRESS)
        if let surface {
            ghostty_surface_key(surface, keyEvent)
        }
    } else {
        // MANUAL IO mode: existing bypass
        sendKeyEvent(event)
    }
}
```

- [ ] **Step 2: Set execMode=true in EXEC renderer init**

In `GhosttyRenderer`'s EXEC mode init, add:
```swift
nsView.execMode = true
```

- [ ] **Step 3: Build and verify**

Run: `swift build`
Expected: compiles. EXEC mode surfaces use Ghostty's native key handling.

- [ ] **Step 4: Commit**

```bash
git add Sources/Infrastructure/Terminal/GhosttyNSView.swift Sources/Infrastructure/Terminal/GhosttyRenderer.swift
git commit -m "feat: native key handling in EXEC mode, bypass preserved for MANUAL IO"
```

---

### Task 8: Wire native PTY mode into WorkspaceController

**Files:**
- Modify: `Sources/WorkspaceController+Rendering.swift`
- Modify: `Sources/WorkspaceController+Actions.swift`
- Modify: `Sources/WorkspaceController.swift`

- [ ] **Step 1: Add processAdapter to WorkspaceController**

```swift
// In WorkspaceController.swift, add property:
var processAdapter: ProcessAdapter?
```

In `ForgeApp.swift` (or wherever GhosttyApp is initialized), create the adapter:
```swift
if configStore.isNativePTY, let ghosttyApp = controller.ghosttyApp {
    controller.processAdapter = ProcessAdapter(ghosttyApp: ghosttyApp)
}
```

- [ ] **Step 2: Add EXEC mode renderer creation in WorkspaceController+Rendering**

```swift
/// Creates an EXEC mode renderer — Ghostty owns the PTY, no tmux involvement.
func createExecRenderer(for pane: Pane, cwd: String) -> GhosttyRenderer {
    guard let ghosttyApp else {
        fatalError("nativePTY requires ghosttyApp")
    }
    let renderer = GhosttyRenderer(ghosttyApp: ghosttyApp, cwd: cwd)
    return renderer
}
```

- [ ] **Step 3: Branch updateRenderers on nativePTY flag**

In `updateRenderers()`, when `isNativePTY` is true, create EXEC renderers instead of MANUAL IO renderers:

```swift
func updateRenderers() {
    if config.isNativePTY {
        updateRenderersNativePTY()
    } else {
        updateRenderersLegacy()  // existing tmux-based logic
    }
}

private func updateRenderersNativePTY() {
    guard let project = workspace.activeProject,
          let tabId = workspace.activeTabId,
          let tab = project.tabs.first(where: { $0.id == tabId })
    else {
        paneRenderers.removeAll()
        return
    }

    let livePaneIds = Set(tab.panes.map(\.id))

    for id in paneRenderers.keys where !livePaneIds.contains(id) {
        paneRenderers.removeValue(forKey: id)
    }

    for pane in tab.panes where paneRenderers[pane.id] == nil {
        let cwd = pane.currentPath.isEmpty ? (project.path ?? NSHomeDirectory()) : pane.currentPath
        let renderer = createExecRenderer(for: pane, cwd: cwd)
        paneRenderers[pane.id] = renderer
    }

    let activePaneId = tab.panes.first(where: \.active)?.id
    for (id, renderer) in paneRenderers {
        renderer.setFocused(id == activePaneId)
    }
}
```

- [ ] **Step 4: Build and verify**

Run: `swift build`
Expected: compiles. The nativePTY path exists but flag defaults to false.

- [ ] **Step 5: Commit**

```bash
git add Sources/WorkspaceController.swift Sources/WorkspaceController+Rendering.swift Sources/WorkspaceController+Actions.swift Sources/ForgeApp.swift
git commit -m "feat: wire native PTY mode into WorkspaceController behind feature flag"
```

---

### Task 9: Wire action_cb events to domain model

**Files:**
- Modify: `Sources/ForgeApp.swift` or `Sources/WorkspaceController.swift`

- [ ] **Step 1: Connect GhosttyApp callbacks to WorkspaceController**

Wire the action_cb events from GhosttyApp to update the domain model:

```swift
// After creating GhosttyApp:
ghosttyApp.onBell = { [weak controller] surface in
    // Find pane by surface, trigger attention
    guard let controller, let (_, tab) = controller.findPaneBySurface(surface) else { return }
    controller.attentionManager?.handleEvent(.bell(tabUUID: tab.uuid))
}

ghosttyApp.onSetTitle = { [weak controller] surface, title in
    // Update tab title from shell escape sequence
    guard let controller, let (pane, _) = controller.findPaneBySurface(surface) else { return }
    // TODO: update tab name if this is the active pane
}

ghosttyApp.onChildExited = { [weak controller] surface in
    guard let controller, let (pane, _) = controller.findPaneBySurface(surface) else { return }
    ForgeLog.log("[app] Child exited in pane \(pane.id)")
    pane.status = .idle
}

ghosttyApp.onCommandFinished = { [weak controller] surface in
    guard let controller, let (_, tab) = controller.findPaneBySurface(surface) else { return }
    controller.attentionManager?.handleEvent(.commandCompleted(tabUUID: tab.uuid))
}

ghosttyApp.onCellSize = { [weak controller] surface, w, h in
    guard let controller else { return }
    let scale = NSScreen.main?.backingScaleFactor ?? 2.0
    controller.terminalCellSize = CGSize(
        width: CGFloat(w) / scale,
        height: CGFloat(h) / scale
    )
}
```

Add helper to find pane by surface pointer:
```swift
func findPaneBySurface(_ surface: ghostty_surface_t?) -> (Pane, Tab)? {
    guard let surface else { return nil }
    for (paneId, renderer) in paneRenderers {
        guard let ghostty = renderer as? GhosttyRenderer,
              ghostty.surface == surface else { continue }
        // Find pane and tab in workspace
        for project in workspace.projects {
            for tab in project.tabs {
                if let pane = tab.panes.first(where: { $0.id == paneId }) {
                    return (pane, tab)
                }
            }
        }
    }
    return nil
}
```

- [ ] **Step 2: Build and commit**

```bash
swift build
git add Sources/ForgeApp.swift Sources/WorkspaceController.swift
git commit -m "feat: wire GhosttyApp action_cb events to domain model"
```

---

### Task 10: Manual validation

- [ ] **Step 1: Enable the flag**

Set `nativePTY: true` in `~/.config/forge/config.json` under `general`.

- [ ] **Step 2: Build and launch**

```bash
make dev
```

- [ ] **Step 3: Verify basic terminal works**

- Open Forge → add a new project
- Type `echo hello world` → text appears
- Type `ls --color` → colored output
- Press Ctrl+C → ^C appears, no routing to wrong pane
- Press space → space character works
- Press arrow keys → cursor moves in shell

- [ ] **Step 4: Verify TUI apps**

- Run `vim /tmp/test.txt` → fills pane, all modes work
- Run `htop` → fills pane, updates live
- Run `claude` → Claude Code renders fully, input line visible at bottom
- Resize window → TUI apps redraw cleanly

- [ ] **Step 5: Verify diagnostics**

```bash
curl localhost:7654/pane-sizes | python3 -m json.tool
```

Check: all panes show `mismatch: false`.

- [ ] **Step 6: Verify split panes**

- Create horizontal split → both panes work
- Click each pane → Ctrl+C only affects focused pane
- Drag divider → panes resize, content reflows on release

- [ ] **Step 7: Commit any fixes found during testing**

```bash
git commit -m "fix: adjustments from Phase 1 manual validation"
```

---

## Notes for Phase 2 (separate plan)

Phase 2 (forged daemon) should be planned AFTER Phase 1 is validated and the user has tested the native PTY experience. Key tasks:
1. Build forged daemon binary (Unix socket, fd passing, JSON protocol)
2. Add EXTERNAL_FD io mode to GhosttyKit Zig source
3. Create DaemonAdapter implementing PersistencePort
4. Add workspace.json persistence
5. Add scrollback dump/restore
6. Implement `applicationShouldTerminate(.terminateLater)` quit flow
7. Wire reconnection flow (retrieve fds → EXTERNAL_FD surfaces → SIGWINCH)

## Notes for Phase 3 (separate plan)

Phase 3 (cleanup) is straightforward deletion after Phase 2 ships:
1. Remove all tmux infrastructure files (~1620 lines)
2. Remove bundled tmux binary
3. Remove feature flags
4. Update documentation
