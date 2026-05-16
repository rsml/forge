# libghostty Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace SwiftTerm with libghostty (GhosttyKit) as Forge's terminal renderer, using `GHOSTTY_SURFACE_IO_MANUAL` mode to feed tmux `%output` data into GPU-accelerated ghostty surfaces.

**Architecture:** Add the rsml/ghostty fork as a submodule, build GhosttyKit.xcframework via Zig, expose the C API to Swift via SPM, then implement `GhosttyRenderer` conforming to `TerminalRenderer` protocol. The existing `%output` → `OutputRouter` → renderer pipeline stays unchanged — we swap the renderer implementation.

**Tech Stack:** Swift 6.0, Zig (GhosttyKit build), Metal (GPU rendering), ForgeCore SPM target, cmux's ghostty fork (rsml/ghostty)

**Spec:** `docs/superpowers/specs/2026-05-15-libghostty-integration-design.md`

**Reference:** cmux source at `/tmp/cmux-source` — study `GhosttyTerminalView.swift`, `AppDelegate.swift`, `ghostty/include/ghostty.h`

---

## Phase A: Build System

### Task 1: Add ghostty submodule

**Files:**
- Modify: `.gitmodules` (auto-created by git)
- Modify: `.gitignore`

- [ ] **Step 1: Add the submodule**

```bash
cd /Users/ross/Personal/forge
git submodule add https://github.com/rsml/ghostty.git vendor/ghostty
```

- [ ] **Step 2: Gitignore the build artifacts**

Add to `.gitignore`:
```
GhosttyKit.xcframework
vendor/ghostty/zig-out/
vendor/ghostty/zig-cache/
vendor/ghostty/.zig-cache/
```

- [ ] **Step 3: Verify submodule**

```bash
ls vendor/ghostty/include/ghostty.h
```
Expected: file exists

- [ ] **Step 4: Commit**

```bash
git add .gitmodules .gitignore vendor/ghostty
git commit -m "chore: add rsml/ghostty as submodule"
```

---

### Task 2: Build script for GhosttyKit.xcframework

**Files:**
- Create: `scripts/build-ghosttykit.sh`

- [ ] **Step 1: Create the build script**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
GHOSTTY_DIR="$PROJECT_DIR/vendor/ghostty"
CACHE_ROOT="$HOME/.cache/forge/ghosttykit"

cd "$PROJECT_DIR"

# Check zig
if ! command -v zig &> /dev/null; then
    echo "Error: zig is not installed. Install via: brew install zig"
    exit 1
fi

# Check submodule
if [[ ! -f "$GHOSTTY_DIR/include/ghostty.h" ]]; then
    echo "Error: vendor/ghostty submodule not initialized."
    echo "Run: git submodule update --init vendor/ghostty"
    exit 1
fi

# Cache key from ghostty commit SHA
GHOSTTY_SHA="$(git -C "$GHOSTTY_DIR" rev-parse HEAD)"
CACHE_DIR="$CACHE_ROOT/$GHOSTTY_SHA"
CACHE_XCFW="$CACHE_DIR/GhosttyKit.xcframework"
LOCAL_XCFW="$PROJECT_DIR/GhosttyKit.xcframework"

if [[ -d "$CACHE_XCFW" ]]; then
    echo "==> Reusing cached GhosttyKit.xcframework ($GHOSTTY_SHA)"
else
    echo "==> Building GhosttyKit.xcframework (this takes a few minutes)..."
    (
        cd "$GHOSTTY_DIR"
        zig build -Demit-xcframework=true -Dxcframework-target=universal -Doptimize=ReleaseFast
    )

    # The build outputs to vendor/ghostty/zig-out/lib/GhosttyKit.xcframework
    BUILT="$GHOSTTY_DIR/zig-out/lib/GhosttyKit.xcframework"
    if [[ ! -d "$BUILT" ]]; then
        # Fallback: check macos/ subdirectory (cmux layout)
        BUILT="$GHOSTTY_DIR/macos/GhosttyKit.xcframework"
    fi
    if [[ ! -d "$BUILT" ]]; then
        echo "Error: GhosttyKit.xcframework not found after build."
        echo "Check vendor/ghostty/zig-out/ for the artifact."
        exit 1
    fi

    mkdir -p "$CACHE_DIR"
    cp -R "$BUILT" "$CACHE_XCFW"
    echo "==> Cached at $CACHE_XCFW"
fi

# Refresh ranlib index (required by Xcode 26+)
MACOS_ARCHIVE="$CACHE_XCFW/macos-arm64_x86_64/libghostty.a"
if [[ -f "$MACOS_ARCHIVE" ]]; then
    xcrun ranlib "$MACOS_ARCHIVE" 2>/dev/null || true
fi

# Symlink into project root
ln -sfn "$CACHE_XCFW" "$LOCAL_XCFW"
echo "==> GhosttyKit.xcframework ready"
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x scripts/build-ghosttykit.sh
```

- [ ] **Step 3: Commit**

```bash
git add scripts/build-ghosttykit.sh
git commit -m "chore: add GhosttyKit build script"
```

---

### Task 3: Build GhosttyKit and inspect artifact

- [ ] **Step 1: Install zig if needed**

```bash
brew install zig 2>/dev/null || echo "zig already installed"
zig version
```

- [ ] **Step 2: Run the build script**

```bash
scripts/build-ghosttykit.sh
```
Expected: GhosttyKit.xcframework symlinked at project root. Takes 3-5 minutes first time.

- [ ] **Step 3: Inspect the xcframework structure**

```bash
find GhosttyKit.xcframework -name "*.modulemap" -o -name "Headers" -type d | head -10
ls GhosttyKit.xcframework/macos-arm64_x86_64/
```

This determines the SPM integration approach:
- If `Headers/ghostty.h` and a `module.modulemap` exist inside the xcframework → use `.binaryTarget`
- If not → use a custom module map with `.systemLibrary`

Document what you find. The next task depends on the answer.

- [ ] **Step 4: Do NOT commit** — the xcframework is gitignored

---

### Task 4: SPM integration

**Files:**
- Modify: `Package.swift`
- Possibly create: `GhosttyKit/module.modulemap` (if xcframework lacks headers)

- [ ] **Step 1: Based on Task 3 inspection, choose approach**

**If the xcframework contains Headers + modulemap** (likely):

Add to `Package.swift`:
```swift
.binaryTarget(
    name: "GhosttyKit",
    path: "GhosttyKit.xcframework"
),
```

And add `"GhosttyKit"` to the Forge executable target's dependencies.

**If the xcframework is a bare static library** (no headers):

Create `GhosttyKit/module.modulemap`:
```
module GhosttyKit {
    umbrella header "../vendor/ghostty/include/ghostty.h"
    export *
}
```

Add to `Package.swift`:
```swift
.systemLibrary(
    name: "GhosttyKit",
    path: "GhosttyKit"
),
```

Add to Forge target:
```swift
dependencies: ["GhosttyKit", "SwiftTerm", "ForgeCore"],
linkerSettings: [
    .unsafeFlags(["-L", "GhosttyKit.xcframework/macos-arm64_x86_64"]),
    .linkedLibrary("ghostty"),
    .linkedLibrary("c++"),
    .linkedFramework("Metal"),
    .linkedFramework("QuartzCore"),
    .linkedFramework("IOSurface"),
    .linkedFramework("Carbon"),
]
```

- [ ] **Step 2: Create a smoke test file**

Create `Sources/Infrastructure/Terminal/GhosttyImportTest.swift`:

```swift
#if canImport(GhosttyKit)
import GhosttyKit

/// Smoke test: verifies GhosttyKit links and the C API is accessible.
/// Delete this file after integration is complete.
enum GhosttyImportTest {
    static func verify() {
        // If this compiles and links, the xcframework is correctly integrated
        _ = ghostty_surface_config_new()
        ForgeLog.log("[ghostty] GhosttyKit import verified")
    }
}
#endif
```

- [ ] **Step 3: Build**

```bash
swift build 2>&1 | tail -10
```

Expected: Build succeeds with no linker errors. If it fails, iterate on the Package.swift configuration — this is the most finicky step. Check error messages carefully:
- "No such module 'GhosttyKit'" → module map issue
- "Undefined symbols" → linker path or missing framework
- "ld: framework not found" → missing `.linkedFramework`

- [ ] **Step 4: Run tests**

```bash
swift test 2>&1 | tail -5
```

Expected: All existing tests pass (GhosttyKit isn't used by tests)

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/Infrastructure/Terminal/GhosttyImportTest.swift
git add GhosttyKit/ 2>/dev/null || true  # only if module.modulemap was created
git commit -m "chore: integrate GhosttyKit.xcframework with SPM"
```

---

### Task 5: Update Makefile

**Files:**
- Modify: `Makefile`

- [ ] **Step 1: Add ghosttykit target and update dev/run**

```makefile
ghosttykit:
	scripts/build-ghosttykit.sh

run: tmux icon ghosttykit
	swift build -c release && \
	$(MAKE) bundle BUILD=.build/release && \
	open .build/release/Forge.app

dev: icon ghosttykit
	swift build && \
	$(MAKE) bundle BUILD=.build/debug && \
	open .build/debug/Forge.app
```

- [ ] **Step 2: Verify**

```bash
make dev
```
Expected: Builds GhosttyKit (if not cached), then builds Forge, then launches

- [ ] **Step 3: Commit**

```bash
git add Makefile
git commit -m "chore: add ghosttykit build target to Makefile"
```

---

## Phase B: GhosttyRenderer

### Task 6: Modify TerminalRenderer protocol

**Files:**
- Modify: `Sources/Infrastructure/Terminal/TerminalRenderer.swift`
- Modify: `Sources/Infrastructure/Terminal/SwiftTermRenderer.swift`
- Modify: `Sources/WorkspaceController+Rendering.swift`
- Modify: `Sources/Features/Terminal/PaneTerminalView.swift`

The current protocol lacks `onInput`/`onResize` (they're SwiftTermRenderer-specific properties). Remove `resize(cols:rows:)` (both SwiftTerm and Ghostty handle resize internally via frame changes).

- [ ] **Step 1: Update the protocol**

```swift
import AppKit

@MainActor
protocol TerminalRenderer: AnyObject {
    var view: NSView { get }
    func feed(_ data: Data)
    func feedScrollback(_ content: String)
    var onInput: ((Data) -> Void)? { get set }
    var onResize: ((Int, Int) -> Void)? { get set }
}
```

- [ ] **Step 2: Remove resize(cols:rows:) from SwiftTermRenderer**

Remove the `resize` method from `SwiftTermRenderer`. The `sizeChanged` delegate already fires `onResize` when SwiftTerm recalculates from its frame.

- [ ] **Step 3: Update PaneTerminalView to use protocol**

Change `let renderer: SwiftTermRenderer` to `let renderer: any TerminalRenderer`.

- [ ] **Step 4: Update WorkspaceController+Rendering.swift**

Change `activeRenderer` from `SwiftTermRenderer?` to `(any TerminalRenderer)?`. Remove any call to `renderer.resize(cols:rows:)`.

- [ ] **Step 5: Build and test**

```bash
swift build && swift test 2>&1 | tail -5
```

- [ ] **Step 6: Commit**

```bash
git add Sources/Infrastructure/Terminal/TerminalRenderer.swift Sources/Infrastructure/Terminal/SwiftTermRenderer.swift Sources/WorkspaceController+Rendering.swift Sources/Features/Terminal/PaneTerminalView.swift
git commit -m "refactor: promote onInput/onResize to TerminalRenderer protocol, remove resize method"
```

---

### Task 7: GhosttyApp singleton

**Files:**
- Create: `Sources/Infrastructure/Terminal/GhosttyApp.swift`

This manages the ghostty app lifecycle — init, config, runtime callbacks. One instance per Forge app.

Reference: cmux's `GhosttyTerminalView.swift` lines 1663-2183 for the initialization pattern. Study that file for the callback wiring.

- [ ] **Step 1: Implement GhosttyApp**

```swift
import Foundation
import AppKit
import GhosttyKit

/// Manages the ghostty app lifecycle. One instance per Forge app.
/// Created at the composition root (AppDelegate), not a global singleton.
@MainActor
final class GhosttyApp {
    private(set) var app: ghostty_app_t?
    private var config: ghostty_config_t?
    private var wakeupLock = NSLock()
    private var wakeupPending = false

    init() {
        guard ghostty_init() == GHOSTTY_SUCCESS else {
            ForgeLog.log("[ghostty] Failed to initialize ghostty")
            return
        }

        config = ghostty_config_new()
        guard let config else { return }

        // Don't load user's ghostty config — Forge config is sole source of truth.
        // Apply minimal defaults via config string.
        let defaults = """
        window-decoration = false
        confirm-close-surface = false
        mouse-hide-while-typing = true
        scrollback-limit = 10000
        cursor-style = bar
        """
        defaults.withCString { ptr in
            ghostty_config_load_string(config, ptr, UInt(defaults.utf8.count), nil)
        }
        ghostty_config_finalize(config)

        var runtime = ghostty_runtime_config_s()
        runtime.userdata = Unmanaged.passUnretained(self).toOpaque()
        runtime.wakeup_cb = { ud in
            guard let ud else { return }
            let app = Unmanaged<GhosttyApp>.fromOpaque(ud).takeUnretainedValue()
            app.handleWakeup()
        }
        runtime.action_cb = { app, target, action in
            // Minimal action handling — expand as needed
            return false
        }
        runtime.read_clipboard_cb = { ud, loc, state in
            let str = NSPasteboard.general.string(forType: .string) ?? ""
            str.withCString { ptr in
                // Complete the clipboard request
            }
        }
        runtime.confirm_read_clipboard_cb = { ud, str, state, confirm_state in
            // Auto-confirm clipboard reads
        }
        runtime.write_clipboard_cb = { ud, loc, clips, count, needs_confirm in
            // Write to pasteboard
            guard let clips, count > 0 else { return }
            let clip = clips.pointee
            if let data = clip.data {
                let str = String(cString: data)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(str, forType: .string)
            }
        }
        runtime.close_surface_cb = { ud, should_confirm in
            // Defensive — MANUAL mode shouldn't trigger this
            ForgeLog.log("[ghostty] close_surface_cb called (unexpected in MANUAL mode)")
        }

        self.app = ghostty_app_new(&runtime, config)
        if self.app == nil {
            ForgeLog.log("[ghostty] Failed to create ghostty app")
        } else {
            ForgeLog.log("[ghostty] App initialized successfully")
        }

        // Track app focus
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            if let app = self?.app { ghostty_app_set_focus(app, true) }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            if let app = self?.app { ghostty_app_set_focus(app, false) }
        }
    }

    /// Apply font and color config from ForgeConfigStore.
    func applyConfig(fontFamily: String?, fontSize: Int, foreground: String?, background: String?) {
        guard let app, let config = ghostty_config_new() else { return }
        var lines: [String] = []
        if let family = fontFamily { lines.append("font-family = \(family)") }
        lines.append("font-size = \(fontSize)")
        if let fg = foreground { lines.append("foreground = \(fg)") }
        if let bg = background { lines.append("background = \(bg)") }
        lines.append("window-decoration = false")
        lines.append("confirm-close-surface = false")
        let str = lines.joined(separator: "\n")
        str.withCString { ptr in
            ghostty_config_load_string(config, ptr, UInt(str.utf8.count), nil)
        }
        ghostty_config_finalize(config)
        ghostty_app_update_config(app, config)
        self.config = config
    }

    deinit {
        // Surfaces must be freed before the app
        if let app { ghostty_app_free(app) }
        if let config { ghostty_config_free(config) }
    }

    // MARK: - Private

    /// Coalesced wakeup — called from I/O thread.
    /// Matches cmux's pattern: lock + flag + performSelector to avoid flooding main.
    private nonisolated func handleWakeup() {
        wakeupLock.lock()
        guard !wakeupPending else { wakeupLock.unlock(); return }
        wakeupPending = true
        wakeupLock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.wakeupLock.lock()
            self.wakeupPending = false
            self.wakeupLock.unlock()
            if let app = self.app {
                ghostty_app_tick(app)
            }
        }
    }
}
```

Note: The callback implementations above are stubs. The implementer MUST study cmux's `GhosttyTerminalView.swift` lines 1663-2183 and the action callback handler to fill in proper implementations. The stubs are enough to create an app object and verify it initializes.

- [ ] **Step 2: Build**

```bash
swift build 2>&1 | tail -10
```

The build may fail if callback type signatures don't match exactly. Compare against `ghostty.h` lines 1010-1039 and fix.

- [ ] **Step 3: Commit**

```bash
git add Sources/Infrastructure/Terminal/GhosttyApp.swift
git commit -m "feat: add GhosttyApp singleton for ghostty lifecycle"
```

---

### Task 8: GhosttyNSView

**Files:**
- Create: `Sources/Infrastructure/Terminal/GhosttyNSView.swift`

NSView subclass with CAMetalLayer that forwards input to ghostty. This is the most Metal-specific code.

Reference: cmux's `GhosttyTerminalView.swift` lines 6075-6284 for `GhosttyNSView`.

- [ ] **Step 1: Implement GhosttyNSView**

```swift
import AppKit
import QuartzCore
import GhosttyKit

/// NSView with CAMetalLayer backing for ghostty terminal rendering.
/// Forwards keyboard and mouse events to the ghostty surface.
class GhosttyNSView: NSView {
    var surface: ghostty_surface_t?

    override var wantsLayer: Bool { get { true } set {} }
    override var wantsUpdateLayer: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func makeBackingLayer() -> CALayer {
        let layer = CAMetalLayer()
        layer.pixelFormat = .bgra8Unorm
        layer.isOpaque = false
        layer.framebufferOnly = false
        layer.contentsScale = window?.backingScaleFactor ?? 2.0
        return layer
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard let surface, newSize.width > 0, newSize.height > 0 else { return }
        let scale = layer?.contentsScale ?? 2.0
        let wpx = UInt32(newSize.width * scale)
        let hpx = UInt32(newSize.height * scale)
        ghostty_surface_set_size(surface, wpx, hpx)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        guard let surface else { return }
        let scale = window?.backingScaleFactor ?? 2.0
        layer?.contentsScale = scale
        ghostty_surface_set_content_scale(surface, scale, scale)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let surface, let window, let screen = window.screen else { return }
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? CGMainDisplayID()
        ghostty_surface_set_display_id(surface, displayID)

        let scale = window.backingScaleFactor
        layer?.contentsScale = scale
        ghostty_surface_set_content_scale(surface, scale, scale)
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result, let surface { ghostty_surface_set_focus(surface, true) }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result, let surface { ghostty_surface_set_focus(surface, false) }
        return result
    }

    // MARK: - Keyboard Input

    override func keyDown(with event: NSEvent) {
        guard let surface else { super.keyDown(with: event); return }
        var keyEvent = buildKeyEvent(event, action: GHOSTTY_KEY_PRESS)
        _ = ghostty_surface_key(surface, keyEvent)
    }

    override func keyUp(with event: NSEvent) {
        guard let surface else { super.keyUp(with: event); return }
        var keyEvent = buildKeyEvent(event, action: GHOSTTY_KEY_RELEASE)
        _ = ghostty_surface_key(surface, keyEvent)
    }

    override func flagsChanged(with event: NSEvent) {
        guard let surface else { super.flagsChanged(with: event); return }
        // Modifier key tracking — simplified
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        guard let surface, let str = string as? String else { return }
        str.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(str.utf8.count))
        }
    }

    // MARK: - Mouse Input

    override func mouseDown(with event: NSEvent) {
        guard let surface else { return }
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, point.x, Double(frame.height) - point.y, modsFromEvent(event))
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, modsFromEvent(event))
    }

    override func mouseUp(with event: NSEvent) {
        guard let surface else { return }
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, modsFromEvent(event))
    }

    override func mouseDragged(with event: NSEvent) {
        guard let surface else { return }
        let point = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, point.x, Double(frame.height) - point.y, modsFromEvent(event))
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }
        ghostty_surface_mouse_scroll(surface, event.scrollingDeltaX, event.scrollingDeltaY, modsFromEvent(event))
    }

    // MARK: - Helpers

    private func buildKeyEvent(_ event: NSEvent, action: ghostty_input_key_action_e) -> ghostty_input_key_s {
        var key = ghostty_input_key_s()
        key.action = action
        key.mods = modsFromEvent(event)
        key.keycode = UInt32(event.keyCode)
        key.composing = false
        return key
    }

    private func modsFromEvent(_ event: NSEvent) -> ghostty_input_mods_e {
        var mods = ghostty_input_mods_e(rawValue: 0)
        if event.modifierFlags.contains(.shift) { mods = ghostty_input_mods_e(rawValue: mods.rawValue | GHOSTTY_MODS_SHIFT.rawValue) }
        if event.modifierFlags.contains(.control) { mods = ghostty_input_mods_e(rawValue: mods.rawValue | GHOSTTY_MODS_CTRL.rawValue) }
        if event.modifierFlags.contains(.option) { mods = ghostty_input_mods_e(rawValue: mods.rawValue | GHOSTTY_MODS_ALT.rawValue) }
        if event.modifierFlags.contains(.command) { mods = ghostty_input_mods_e(rawValue: mods.rawValue | GHOSTTY_MODS_SUPER.rawValue) }
        return mods
    }
}
```

Note: The keyboard handling above is SIMPLIFIED. The implementer MUST study cmux's key handling (lines 7400-8000 of `GhosttyTerminalView.swift`) for proper `performKeyEquivalent`, IME composition, dead keys, etc. The simplified version handles basic ASCII typing and is enough for Phase B verification. Full key handling is refined in Phase C.

- [ ] **Step 2: Build**

```bash
swift build 2>&1 | tail -10
```

The ghostty C API enum values (`GHOSTTY_KEY_PRESS`, `GHOSTTY_MOUSE_LEFT`, `GHOSTTY_MODS_SHIFT`, etc.) may have different names. Check `ghostty.h` for the exact enum member names and fix compilation errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/Infrastructure/Terminal/GhosttyNSView.swift
git commit -m "feat: add GhosttyNSView with Metal layer and input forwarding"
```

---

### Task 9: GhosttyCallbackContext + GhosttyRenderer

**Files:**
- Create: `Sources/Infrastructure/Terminal/GhosttyCallbackContext.swift`
- Create: `Sources/Infrastructure/Terminal/GhosttyRenderer.swift`

- [ ] **Step 1: Create the callback context**

```swift
import Foundation

/// Bridging object for ghostty C callbacks → Swift.
/// Prevent use-after-free: use Unmanaged.passRetained when creating,
/// release explicitly when the surface is freed.
final class GhosttyCallbackContext {
    weak var renderer: GhosttyRenderer?

    init(renderer: GhosttyRenderer) {
        self.renderer = renderer
    }
}
```

- [ ] **Step 2: Create GhosttyRenderer**

```swift
import AppKit
import GhosttyKit

/// libghostty implementation of TerminalRenderer.
/// Uses GHOSTTY_SURFACE_IO_MANUAL — no child process. Data fed via process_output,
/// keyboard input captured via io_write_cb.
@MainActor
final class GhosttyRenderer: TerminalRenderer {
    private var surface: ghostty_surface_t?
    let nsView: GhosttyNSView
    private var callbackContext: Unmanaged<GhosttyCallbackContext>?
    var onInput: ((Data) -> Void)?
    var onResize: ((Int, Int) -> Void)?

    var view: NSView { nsView }

    init(ghosttyApp: GhosttyApp) {
        nsView = GhosttyNSView(frame: .zero)

        guard let app = ghosttyApp.app else {
            ForgeLog.log("[ghostty] Cannot create renderer — app not initialized")
            return
        }

        let context = GhosttyCallbackContext(renderer: self)
        let retained = Unmanaged.passRetained(context)
        self.callbackContext = retained

        var config = ghostty_surface_config_new()
        config.io_mode = GHOSTTY_SURFACE_IO_MANUAL
        config.io_write_cb = { userdata, data, len in
            // Fires from I/O thread — extract data, dispatch to main
            guard let userdata, let data else { return }
            let bytes = Data(bytes: data, count: Int(len))
            DispatchQueue.main.async {
                let ctx = Unmanaged<GhosttyCallbackContext>.fromOpaque(userdata).takeUnretainedValue()
                ctx.renderer?.onInput?(bytes)
            }
        }
        config.io_write_userdata = retained.toOpaque()
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform = ghostty_platform_u(macos: ghostty_platform_macos_s(
            nsview: Unmanaged.passUnretained(nsView).toOpaque()
        ))
        config.context = GHOSTTY_SURFACE_CONTEXT_SPLIT

        surface = ghostty_surface_new(app, &config)
        nsView.surface = surface

        if let surface {
            ForgeLog.log("[ghostty] Surface created successfully")

            // Post-creation setup
            if let window = nsView.window, let screen = window.screen {
                let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? CGMainDisplayID()
                ghostty_surface_set_display_id(surface, displayID)
                let scale = window.backingScaleFactor
                ghostty_surface_set_content_scale(surface, scale, scale)
            } else {
                // View not in window yet — viewDidMoveToWindow will handle it
                ghostty_surface_set_content_scale(surface, 2.0, 2.0)
            }
        } else {
            ForgeLog.log("[ghostty] Failed to create surface")
        }
    }

    func feed(_ data: Data) {
        guard let surface else { return }
        data.withUnsafeBytes { buffer in
            guard let ptr = buffer.baseAddress else { return }
            ghostty_surface_process_output(
                surface,
                ptr.assumingMemoryBound(to: CChar.self),
                UInt(buffer.count)
            )
        }
    }

    func feedScrollback(_ content: String) {
        feed(Data(content.utf8))
    }

    /// Pause/resume GPU rendering for hidden surfaces.
    func setOccluded(_ occluded: Bool) {
        guard let surface else { return }
        ghostty_surface_set_occlusion(surface, occluded)
    }

    deinit {
        if let surface {
            ghostty_surface_free(surface)
        }
        callbackContext?.release()
    }
}
```

- [ ] **Step 3: Build**

```bash
swift build 2>&1 | tail -10
```

Fix compilation errors — the C API type names and struct field names must match `ghostty.h` exactly. Common issues:
- `ghostty_platform_u` initialization syntax
- Enum values may be lowercase or have different prefixes
- `ghostty_surface_process_output` may need `UInt` vs `uintptr_t` for the length

- [ ] **Step 4: Commit**

```bash
git add Sources/Infrastructure/Terminal/GhosttyCallbackContext.swift Sources/Infrastructure/Terminal/GhosttyRenderer.swift
git commit -m "feat: add GhosttyRenderer with MANUAL IO mode"
```

---

## Phase C: Integration

### Task 10: Wire GhosttyApp at composition root

**Files:**
- Modify: `Sources/ForgeApp.swift` (AppDelegate)
- Modify: `Sources/WorkspaceController.swift`
- Modify: `Sources/WorkspaceController+Rendering.swift`

- [ ] **Step 1: Create GhosttyApp in AppDelegate**

Add to `AppDelegate`:

```swift
private(set) var ghosttyApp: GhosttyApp?
```

In `applicationDidFinishLaunching`, after other initialization:

```swift
if configStore.isNativePaneRendering {
    ghosttyApp = GhosttyApp()
}
```

- [ ] **Step 2: Add ghosttyApp to WorkspaceController**

Add property:
```swift
var ghosttyApp: GhosttyApp?
```

Wire in AppDelegate after controller creation:
```swift
controller.ghosttyApp = ghosttyApp
```

- [ ] **Step 3: Swap createRenderer to use GhosttyRenderer**

In `WorkspaceController+Rendering.swift`, update `createRenderer`:

```swift
func createRenderer(for pane: Pane) -> any TerminalRenderer {
    let paneId = pane.id

    let renderer: any TerminalRenderer
    if let ghosttyApp {
        let gr = GhosttyRenderer(ghosttyApp: ghosttyApp)
        renderer = gr
    } else {
        // Fallback to SwiftTerm
        let font = resolvedTerminalFont
        let (foreground, background, palette) = resolvedTerminalColors
        let sr = SwiftTermRenderer(font: font, foreground: foreground, background: background, colors: palette)
        renderer = sr
    }

    renderer.onInput = { [weak self] data in
        guard let self, let adapter = self.tmux as? TmuxAdapter else { return }
        let hex = data.map { String(format: "%02x", $0) }.joined(separator: " ")
        adapter.controlModeSend("send-keys -H -t \(paneId) \(hex)")
    }

    renderer.onResize = { [weak self] cols, rows in
        guard let self, let adapter = self.tmux as? TmuxAdapter else { return }
        adapter.controlModeSend("resize-pane -t \(paneId) -x \(cols) -y \(rows)")
    }

    outputRouter.register(paneId: paneId, renderer: renderer)
    return renderer
}
```

- [ ] **Step 4: Update activeRenderer type**

Change `var activeRenderer: SwiftTermRenderer?` to `var activeRenderer: (any TerminalRenderer)?` in WorkspaceController.

- [ ] **Step 5: Apply Forge theme to GhosttyApp**

In WorkspaceController or AppDelegate, after GhosttyApp is created:

```swift
if let ghosttyApp {
    let fontFamily = configStore.config.terminalFont?.family
    let fontSize = configStore.config.terminalFont?.size ?? configStore.config.terminal?.fontSize ?? 13
    // Convert theme colors to hex strings for ghostty config
    ghosttyApp.applyConfig(fontFamily: fontFamily, fontSize: fontSize, foreground: nil, background: nil)
}
```

- [ ] **Step 6: Build and test**

```bash
swift build && swift test 2>&1 | tail -5
```

- [ ] **Step 7: Commit**

```bash
git add Sources/ForgeApp.swift Sources/WorkspaceController.swift Sources/WorkspaceController+Rendering.swift
git commit -m "feat: wire GhosttyRenderer into rendering pipeline"
```

---

### Task 11: Handle resize via action callback

**Files:**
- Modify: `Sources/Infrastructure/Terminal/GhosttyApp.swift`
- Modify: `Sources/Infrastructure/Terminal/GhosttyRenderer.swift`

The `onResize` callback must fire when ghostty recalculates cols/rows from the pixel dimensions. This comes through the action callback.

- [ ] **Step 1: Add action callback routing in GhosttyApp**

Study the `ghostty_action_tag_e` enum in `ghostty.h` to find the cell size / resize action. The action callback receives a `ghostty_target_s` (which surface) and `ghostty_action_s` (what happened).

Wire the action callback to extract the surface's userdata, recover the `GhosttyCallbackContext`, and call `onResize` with the new cols/rows from `ghostty_surface_size()`.

This requires careful study of `ghostty.h` — the exact action tag name and how to extract the surface from the target. Reference cmux's action handler.

- [ ] **Step 2: Build and test**

```bash
swift build
```

- [ ] **Step 3: Commit**

```bash
git add Sources/Infrastructure/Terminal/GhosttyApp.swift Sources/Infrastructure/Terminal/GhosttyRenderer.swift
git commit -m "feat: handle resize via ghostty action callback"
```

---

### Task 12: Manual verification

- [ ] **Step 1: Ensure nativePaneRendering is enabled**

Verify `~/.config/forge/config.json` has `"nativePaneRendering": true`.

- [ ] **Step 2: Build and launch**

```bash
make dev
```

- [ ] **Step 3: Test basic output**

Open a project. Run:
- `echo hello` — text appears
- `ls --color` — colors render correctly
- Prompt is full-width (right-side prompt at far right)

- [ ] **Step 4: Test input**

- Type commands — keystrokes appear
- Arrow keys, tab completion, Ctrl+C work
- Backspace works

- [ ] **Step 5: Test resize**

Resize the window. Terminal reflows correctly. No wrapping artifacts.

- [ ] **Step 6: Test text selection**

Click and drag to select text. Selection wraps correctly within the terminal.

- [ ] **Step 7: Check rendering quality**

Compare against the old `tmux attach` path (set flag to false). The ghostty rendering should look equal or better — GPU-accelerated, crisp text, correct colors.

- [ ] **Step 8: Check logs**

```bash
tail -30 /tmp/forge.log | grep ghostty
```

Expected: "App initialized successfully", "Surface created successfully", no errors.

- [ ] **Step 9: Verify legacy path still works**

Set `nativePaneRendering: false`. Relaunch. The old `tmux attach` ForgeTerminalView renders correctly.

---

## Phase D: Cleanup

### Task 13: Remove SwiftTerm and legacy path

**Files:**
- Delete: `Sources/Infrastructure/Terminal/SwiftTermRenderer.swift`
- Delete: `Sources/Features/Terminal/ForgeTerminalView.swift`
- Delete: `Sources/Infrastructure/Terminal/GhosttyImportTest.swift`
- Modify: `Package.swift` (remove SwiftTerm dependency)
- Modify: `Sources/Infrastructure/Config/ForgeConfig.swift` (remove `nativePaneRendering`)
- Modify: `Sources/Infrastructure/Config/ForgeConfigStore.swift` (remove `isNativePaneRendering`)
- Modify: `Sources/Features/Terminal/TerminalArea.swift` (remove feature flag branch)
- Modify: `Sources/WorkspaceController+Rendering.swift` (remove SwiftTerm fallback)

- [ ] **Step 1: Remove SwiftTerm dependency from Package.swift**

Remove the `.package(url: "https://github.com/migueldeicaza/SwiftTerm.git", ...)` line and `"SwiftTerm"` from the Forge target dependencies.

- [ ] **Step 2: Delete SwiftTerm-specific files**

```bash
rm Sources/Infrastructure/Terminal/SwiftTermRenderer.swift
rm Sources/Features/Terminal/ForgeTerminalView.swift
rm Sources/Infrastructure/Terminal/GhosttyImportTest.swift
```

- [ ] **Step 3: Remove feature flag**

Remove `nativePaneRendering` from `ForgeConfig.GeneralSettings` and `isNativePaneRendering` from `ForgeConfigStore`.

- [ ] **Step 4: Simplify TerminalArea**

Remove the `if configStore.isNativePaneRendering` branch. Only the `PaneTerminalView` path remains.

- [ ] **Step 5: Remove SwiftTerm fallback in createRenderer**

Remove the `else` branch that creates `SwiftTermRenderer`.

- [ ] **Step 6: Build and test**

```bash
swift build && swift test 2>&1 | tail -5
```

- [ ] **Step 7: Final verification**

```bash
make dev
```

Verify everything works without the feature flag or SwiftTerm.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "chore: remove SwiftTerm dependency and legacy terminal path"
```
