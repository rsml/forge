# libghostty Integration

Replace SwiftTerm with libghostty (GhosttyKit) as Forge's terminal renderer. Use `GHOSTTY_SURFACE_IO_MANUAL` mode to feed tmux `%output` data into GPU-accelerated ghostty surfaces without child processes.

## Motivation

SwiftTerm's base `TerminalView` class has sizing and rendering issues when used without a process (the `feed()` path vs `LocalProcessTerminalView`). libghostty is a production-grade, GPU-accelerated terminal renderer used by Ghostty (a popular macOS terminal) and cmux. It provides Metal-based rendering, correct terminal sizing, proper text selection, URL detection, and image protocol support out of the box.

cmux's fork of Ghostty adds `GHOSTTY_SURFACE_IO_MANUAL` — a mode that creates terminal surfaces without child processes, accepting data via `ghostty_surface_process_output()` and routing keyboard input via an `io_write_cb` callback. This maps directly to Forge's `%output` → renderer → `send-keys` pipeline.

**Risk: MANUAL IO mode is untested in production.** cmux implements it in Zig but never activates it in their Swift layer (they use standard EXEC mode with their own child processes). Forge would be the first real consumer. Expect to discover bugs in this path during integration.

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Ghostty source | `rsml/ghostty` (forked from `manaflow-ai/ghostty`) | Control updates, cherry-pick from upstream as needed |
| Build system | SPM hybrid — proof-of-concept first (see below) | Preserves `swift build` if possible |
| Ghostty config | Ignored — Forge config is sole source of truth | One config file for users, simpler mental model |
| IO mode | `GHOSTTY_SURFACE_IO_MANUAL` | No child process — Forge feeds data from tmux |
| Data feed | `ghostty_surface_process_output(surface, ptr, len)` | Raw bytes from tmux `%output` → ghostty renderer |
| Input capture | `io_write_cb` callback → `controlMode.send("send-keys -H")` | Sub-ms latency via existing control mode pipe |
| Renderer protocol | Modified `TerminalRenderer` in `Infrastructure/Terminal/` | Resize becomes pixel-driven, add onInput/onResize to protocol |

## Sub-project 1: Build System

### Ghostty Submodule

Add `rsml/ghostty` as a git submodule at `vendor/ghostty`. The submodule is the full Ghostty source tree (required for `zig build`).

### Build Script

`scripts/build-ghosttykit.sh`:
1. Check for `zig` (error with install instructions if missing)
2. Compute a cache key from the ghostty submodule's git SHA
3. Check `~/.cache/forge/ghosttykit/<key>/GhosttyKit.xcframework` — skip build if cached
4. Build: `cd vendor/ghostty && zig build -Demit-xcframework=true -Dxcframework-target=universal -Doptimize=ReleaseFast`
5. Cache the result
6. Symlink `GhosttyKit.xcframework` at the project root

Based on cmux's `scripts/ensure-ghosttykit.sh` but simplified (no prebuilt download, no crash report subdirectory).

Note: GhosttyKit takes several minutes to build from scratch. The cache key avoids unnecessary rebuilds. `swift build` requires the xcframework to already exist — `make dev`/`make run` handle this automatically.

### SPM Integration — Proof of Concept Required

The xcframework structure emitted by `zig build` must be inspected before committing to an approach. Ghostty's own example at `ghostty/example/swift-vt-xcframework/Package.swift` shows the intended SPM integration pattern. Options ranked:

1. **`.binaryTarget`** pointing at the xcframework — works IF the xcframework contains headers and a module map internally. Inspect the built artifact to confirm.
2. **`.systemLibrary` with custom module map** — if the xcframework lacks internal headers, create a `GhosttyKit/module.modulemap` pointing to `vendor/ghostty/include/ghostty.h` and use `unsafeFlags(["-L..."])` for the library search path.
3. **Xcode project for the app target** — last resort if SPM integration proves too fragile. Keep `ForgeCore` as SPM, wrap the app in `.xcodeproj`.

**Phase A's first task is building the xcframework and verifying which approach works.** Don't commit to an SPM strategy until the artifact is inspected.

### Linker Requirements

Regardless of SPM approach, these frameworks must be linked:
- Metal
- QuartzCore
- IOSurface
- Carbon
- Also link `libc++`

### Makefile Changes

- `make ghosttykit` — runs `scripts/build-ghosttykit.sh`
- `make dev` / `make run` — depend on `ghosttykit` target

### Zig Dependency

Zig is required to build GhosttyKit. Install via `brew install zig`. The build script checks for this and errors with instructions if missing. Zig is NOT required to run Forge — only to build from source.

## Sub-project 2: GhosttyRenderer

### Ghostty App Initialization

A singleton `GhosttyApp` class in `Infrastructure/Terminal/` manages the ghostty app lifecycle:

1. `ghostty_init()` — called once at app launch
2. `ghostty_config_new()` — create an empty config (we don't load user's Ghostty config)
3. Apply Forge's settings programmatically via `ghostty_config_load_string()`:
   - Font family and size from `ForgeConfigStore`
   - Disable all Ghostty keybindings (Forge owns shortcuts)
   - Disable window chrome, tabs, splits (Forge owns UI)
   - Set background/foreground colors from Forge's theme
4. `ghostty_config_finalize(config)`
5. Create `ghostty_runtime_config_s` with ALL required callbacks:
   - `wakeup_cb`: schedule `ghostty_app_tick()` on main thread (coalesce via NSLock like cmux)
   - `action_cb`: handle title changes, bell, cell size changes, color changes (dispatch to main thread)
   - `read_clipboard_cb`: read from `NSPasteboard`
   - `confirm_read_clipboard_cb`: confirm clipboard access
   - `write_clipboard_cb`: write to `NSPasteboard`
   - `close_surface_cb`: handle surface close (defensive — MANUAL mode shouldn't trigger this, but set it anyway)
6. `ghostty_app_new(&runtimeConfig, config)` — creates the app singleton
7. Subscribe to `NSApplication.didBecomeActive/didResignActive` → call `ghostty_app_set_focus(app, focused)`

The `GhosttyApp` singleton is created at Forge's composition root (`AppDelegate`) and injected where needed.

### GhosttyNSView

A minimal `NSView` subclass that:
- Overrides `wantsLayer` → `true` and `makeBackingLayer()` → `CAMetalLayer` with:
  - `pixelFormat = .bgra8Unorm`
  - `isOpaque = false`
  - `framebufferOnly = false`
- Forwards keyboard events to `ghostty_surface_key()` / `ghostty_surface_text()`
- Forwards mouse events to `ghostty_surface_mouse_*()`
- On `setFrameSize`: calls `ghostty_surface_set_size(surface, pixelWidth, pixelHeight)`
- On `viewDidMoveToWindow` / `backingProperties` change: calls `ghostty_surface_set_content_scale(surface, scaleX, scaleY)` for Retina
- On display change: calls `ghostty_surface_set_display_id(surface, displayID)` for correct vsync
- On focus change: calls `ghostty_surface_set_focus(surface, focused)`
- On occlusion change: calls `ghostty_surface_set_occlusion(surface, occluded)` to pause rendering for hidden surfaces

Based on cmux's `GhosttyNSView` (~200 lines of essential code, stripped of cmux-specific features).

### TerminalRenderer Protocol Changes

The protocol needs modification for ghostty's pixel-driven resize model:

```swift
@MainActor
protocol TerminalRenderer: AnyObject {
    var view: NSView { get }
    func feed(_ data: Data)
    func feedScrollback(_ content: String)

    /// Callbacks wired by the owner (WorkspaceController)
    var onInput: ((Data) -> Void)? { get set }
    var onResize: ((Int, Int) -> Void)? { get set }
}
```

Changes from current:
- `resize(cols:rows:)` removed — ghostty handles resize internally via `setFrameSize`, not via caller-driven resize. SwiftTerm also does this (via `processSizeChange`). The method was never the right abstraction.
- `onInput` and `onResize` promoted to protocol — both renderers need these callbacks.

### GhosttyRenderer

```swift
@MainActor
final class GhosttyRenderer: TerminalRenderer {
    private var surface: ghostty_surface_t?
    private let nsView: GhosttyNSView
    private var callbackContext: Unmanaged<GhosttyCallbackContext>?
    var onInput: ((Data) -> Void)?
    var onResize: ((Int, Int) -> Void)?

    var view: NSView { nsView }

    func feed(_ data: Data) {
        guard let surface else { return }
        data.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            ghostty_surface_process_output(surface, base.assumingMemoryBound(to: CChar.self), ptr.count)
        }
    }

    func feedScrollback(_ content: String) {
        // Feed as terminal output — ghostty processes escape sequences
        feed(Data(content.utf8))
    }

    deinit {
        if let surface { ghostty_surface_free(surface) }
        callbackContext?.release()  // balance passRetained at creation
    }
}
```

### Surface Creation

```swift
let context = GhosttyCallbackContext(renderer: self)
let retained = Unmanaged.passRetained(context)  // prevent deallocation while ghostty holds pointer
self.callbackContext = retained

var config = ghostty_surface_config_new()
config.io_mode = GHOSTTY_SURFACE_IO_MANUAL
config.io_write_cb = { userdata, data, len in
    // Fires from I/O thread — extract data, dispatch to main
    guard let userdata, let data else { return }
    let bytes = Data(bytes: data, count: len)
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
surface = ghostty_surface_new(GhosttyApp.shared.app, &config)

// Critical post-creation calls
ghostty_surface_set_content_scale(surface, scaleX, scaleY)
ghostty_surface_set_display_id(surface, displayID)
ghostty_surface_set_size(surface, pixelWidth, pixelHeight)
ghostty_surface_set_focus(surface, true)
```

`GhosttyCallbackContext` is a class holding a weak reference to the renderer, preventing use-after-free while ghostty holds the raw pointer. Pattern matches cmux's `GhosttySurfaceCallbackContext`.

### Threading

- `ghostty_surface_process_output()` — any thread (takes internal lock). For large scrollback payloads, call from a background thread to avoid main thread hitches.
- `io_write_cb` — fires from ghostty's I/O thread. Extract `Data`, dispatch to main thread, then call `onInput`.
- `wakeup_cb` — fires from I/O thread. Schedule `ghostty_app_tick()` on main run loop (coalesce with NSLock to avoid flooding).
- `action_cb` — fires from I/O thread. Dispatch to main thread. Handle `GHOSTTY_ACTION_CELL_SIZE` to extract cols/rows and fire `onResize`.

### Resize Flow

Driven by the view frame, not by the caller:
1. SwiftUI layout changes → `GhosttyNSView.setFrameSize()` fires
2. `ghostty_surface_set_size(surface, pixelWidth, pixelHeight)` — ghostty recalculates cols/rows
3. Ghostty fires `GHOSTTY_ACTION_CELL_SIZE` action callback
4. Action handler calls `ghostty_surface_size(surface)` to get computed cols/rows
5. Fires `onResize(cols, rows)` → sends `resize-pane -t <pane_id> -x <cols> -y <rows>` to tmux

## Sub-project 3: Integration & Polish

### Swap Renderer

In `WorkspaceController+Rendering.swift`, `createRenderer()` creates a `GhosttyRenderer` instead of `SwiftTermRenderer`. The `OutputRouter`, `onOutput` pipeline, and `PaneTerminalView` remain unchanged — they depend on the `TerminalRenderer` protocol, not the implementation.

### PaneTerminalView Changes

Change from `SwiftTermRenderer` to `TerminalRenderer` (the protocol). The view embeds `renderer.view` (an NSView) regardless of implementation.

### Theme Sync

On config change or theme switch, update the ghostty config:
- `ghostty_config_load_string(config, "font-family = Dank Mono\nfont-size = 16\n...", len, nil)`
- `ghostty_app_update_config(app, config)` — hot-reloads all surfaces

### Scrollback Seeding

Same as before: `capture-pane -p -S -<N> -e -t <pane_id>` → `renderer.feedScrollback(content)` → `ghostty_surface_process_output()`. Ghostty processes the escape sequences and renders the content. For large payloads, feed from a background thread.

### Surface Occlusion Management

When tabs switch or panes become invisible:
- `ghostty_surface_set_occlusion(surface, true)` — pauses GPU rendering
- `ghostty_surface_set_occlusion(surface, false)` — resumes

Critical for multi-tab/multi-pane: without this, every pane burns GPU cycles even when hidden.

### Remove SwiftTerm

After GhosttyRenderer is working:
1. Delete `SwiftTermRenderer.swift`
2. Remove SwiftTerm from `Package.swift` dependencies
3. Delete `ForgeTerminalView.swift` (the legacy `tmux attach` path)
4. Remove the `nativePaneRendering` feature flag — native is the only path
5. `PaneTerminalView` becomes the sole terminal view

### Feature Flag

During migration, the existing `nativePaneRendering` flag gates between:
- `false` → legacy `ForgeTerminalView` (tmux attach)
- `true` → `PaneTerminalView` with `GhosttyRenderer`

## Component Map

| Component | Layer | Purpose |
|-----------|-------|---------|
| `vendor/ghostty/` | Submodule | Ghostty source (rsml/ghostty fork) |
| `GhosttyKit/` | Build | Module map or binary target for SPM |
| `scripts/build-ghosttykit.sh` | Build | Builds GhosttyKit.xcframework from source |
| `GhosttyApp` | `Infrastructure/Terminal/` | Singleton managing ghostty app lifecycle, config, callbacks |
| `GhosttyNSView` | `Infrastructure/Terminal/` | NSView subclass with CAMetalLayer, input forwarding, display/scale tracking |
| `GhosttyCallbackContext` | `Infrastructure/Terminal/` | Class bridging Swift objects through ghostty's C void* userdata |
| `GhosttyRenderer` | `Infrastructure/Terminal/` | Implements `TerminalRenderer` using libghostty |
| `OutputRouter` | `Infrastructure/Terminal/` | Unchanged — routes `%output` to any `TerminalRenderer` |
| `PaneTerminalView` | `Features/Terminal/` | Changed to accept `TerminalRenderer` protocol (not concrete type) |

## Migration Phases

### Phase A: Build System (Sub-project 1)
- Add ghostty submodule
- Build GhosttyKit.xcframework
- Inspect artifact structure, determine SPM integration approach
- Verify `import GhosttyKit` compiles and `ghostty_init()` links
- Nothing user-visible changes

### Phase B: GhosttyRenderer (Sub-project 2)
- GhosttyApp singleton with all callbacks
- GhosttyNSView with Metal layer, input forwarding, display/scale/focus tracking
- GhosttyCallbackContext for safe C↔Swift bridging
- GhosttyRenderer conforming to modified TerminalRenderer protocol
- Verify surface creates, renders a blank terminal, accepts input
- Update SwiftTermRenderer to conform to modified protocol

### Phase C: Integration (Sub-project 3)
- Swap renderer in createRenderer()
- Wire theme/font from Forge config → ghostty config
- Verify %output → render → input → tmux round-trip
- Scrollback seeding
- Surface occlusion management for hidden tabs/panes
- Manual verification

### Phase D: Cleanup
- Remove SwiftTerm dependency
- Remove ForgeTerminalView (legacy tmux attach)
- Remove feature flag
- Remove SwiftTermRenderer

## What Users Get

Everything from the native pane rendering spec, plus:
- GPU-accelerated Metal rendering (same quality as Ghostty terminal)
- Correct terminal sizing (no SwiftTerm quirks)
- Proper text selection per pane
- Ligature support
- True color
- URL detection and clickable links
- Image protocol support (Sixel, iTerm2 inline images)

## Limitations

- MANUAL IO mode is untested in production — expect to discover and fix bugs in the Zig backend
- GhosttyKit build requires Zig toolchain (brew install zig)
- Build from scratch takes several minutes (cached afterward)
- Metal rendering is opaque — cannot overlay SwiftUI content inside the terminal view

## What's Not In Scope

- Loading user's Ghostty config (Forge config is sole source of truth)
- Ghostty keybindings (Forge owns all shortcuts)
- Ghostty's window/tab/split management (Forge owns UI)
- Multi-pane split layout (Phase 3 of native pane rendering — separate spec)
