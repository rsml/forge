# Native Per-Pane Terminal Rendering

Replace the current single `tmux attach` terminal view with per-pane SwiftTerm instances fed by tmux control mode `%output` events. Tmux becomes an invisible process manager; Forge owns the entire visual experience.

## Motivation

Today `ForgeTerminalView` runs `tmux attach-session` inside a single `LocalProcessTerminalView`. Tmux renders everything — panes, borders, all of it. This inherits every tmux rendering limitation: text selection bleeds across panes, no per-pane scrollback, no pane click-to-focus, no native search, no clickable URLs.

Since Forge already uses tmux control mode (`-CC`) for push-based state updates, the `%output` data is flowing through the connection — it's just being discarded. Routing it to per-pane terminal views gives native UX while preserving tmux's process management.

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Migration strategy | Incremental with feature flag | Ship improvements without breaking current path |
| Input routing | `send-keys -H` via control mode stdin | No key mapping table — hex bytes via the existing control mode pipe (sub-ms latency) |
| Tmux keybindings | Not supported | Forge owns all shortcuts |
| Process persistence | Sessions survive Forge quit | Killer feature — relaunch and everything is still running |
| Scrollback | Seed from tmux on connect (bounded) | Full history after restart, capped to avoid startup stall |
| Terminal view | Swappable via infrastructure protocol | SwiftTerm now, libghostty later |

## Data Flow

### Output (tmux → screen)

```
TmuxControlMode reader thread
  → parses %output %<pane_id> <escaped_data>
  → decodes tmux escaping (not URL percent-encoding — see below)
  → dispatches to main thread
  → OutputRouter
  → TerminalRenderer.feed(data) for matching pane
```

**Tmux output escaping**: tmux control mode uses its own scheme — `\015` for CR, `\012` for LF, `\\` for backslash. This is NOT RFC 3986 percent-encoding. The parser must decode these octal escapes into raw bytes. Foundation's URL percent-decoding will not work.

**Threading**: `%output` events arrive on the reader thread. The `onOutput` callback must dispatch to the main thread before touching any renderer (SwiftTerm views are AppKit and must be manipulated on the main thread). The existing `onEvent` callback already uses `Task { @MainActor in ... }` — `onOutput` follows the same pattern.

**Line buffering**: The existing `TmuxControlMode.handleOutput` buffers by newline. `%output` payloads are single logical lines in the tmux protocol. Large payloads (e.g., `cat` of a big file) may arrive across multiple `availableData` reads, but the newline-based buffer accumulation handles this correctly — it won't emit a partial `%output` line.

### Input (keyboard → tmux)

```
SwiftTermRenderer captures keystroke
  → onInput callback with raw bytes
  → controlMode.send("send-keys -H -t <pane_id> <hex_bytes>")
  → tmux routes to pane's shell
```

Input MUST go through `controlMode.send()` (writes to the existing control mode process stdin, sub-millisecond). NOT through `TmuxCommandRunner.run()` (spawns a new process per call, 20-50ms latency — unusable for typing).

### Resize (layout change → tmux)

```
SwiftUI layout resizes PaneTerminalView
  → SwiftTermRenderer reports new cols/rows via onResize callback
  → controlMode.send("resize-pane -t <pane_id> -x <cols> -y <rows>")
```

**Control mode client size**: Today `TmuxControlMode` sends `refresh-client -C 1,1` on connect to keep the control mode client small. With native rendering, this must change to match the largest pane dimensions (or use tmux `window-size manual` policy). When the feature flag is on, skip the `refresh-client -C 1,1` init command. Add `set-option -g window-size manual` to `forge-tmux.conf` to prevent tmux from auto-constraining pane dimensions.

### Scrollback Seeding (on connect)

When Forge connects to an existing tmux session (relaunch or reconnect):

1. For each pane: `capture-pane -p -S -<N> -e -t <pane_id>` where N is bounded (e.g., 5000 lines) to avoid startup stall
2. Feed to `renderer.seedScrollback(content)` asynchronously (don't block the main thread)
3. Then switch to live `%output` feed

**Alternate screen limitation**: Programs using the alternate screen (vim, less, htop) store their display on the alternate screen buffer, not in scrollback. After a Forge restart, `capture-pane` returns the main screen content — the user sees their shell prompt, not the TUI. The running program will redraw when it receives input. This is an inherent limitation of tmux session reconnection, not specific to this architecture.

## Component Map

| Component | Layer | Purpose |
|-----------|-------|---------|
| `TerminalRenderer` protocol | `Infrastructure/Terminal/` | `feed(Data)`, `seedScrollback(String)`, `view: NSView`. Swappable abstraction — not a Core port because terminal rendering is infrastructure, not domain. `OutputRouter` depends only on the protocol, never imports SwiftTerm. |
| `SwiftTermRenderer` | `Infrastructure/Terminal/` | Implements `TerminalRenderer` using SwiftTerm. Reports keystrokes and resize via closures. |
| `OutputRouter` | `Infrastructure/Terminal/` | Maps pane IDs to `TerminalRenderer` instances. Receives parsed `%output` events from `TmuxControlMode`. Pane lifecycle managed via post-refresh hook (same pattern as `AttentionManager`). |
| `TmuxControlMode` changes | `Infrastructure/Tmux/` | Stop filtering `%output`. Parse `%output %<pane_id> <data>`, decode tmux escaping, and call `onOutput: @Sendable (String, Data) -> Void`. |
| `TmuxControlPort` changes | `Core/Ports/` | `startControlMode` gains an `onOutput` parameter alongside existing `onEvent`, `onDisconnect`, `onReconnect`. |
| `PaneTerminalView` | `Features/Terminal/` | SwiftUI view embedding a renderer's NSView via `NSViewRepresentable`. One per pane. |
| `PaneSplitView` | `Features/Terminal/` | Recursive SwiftUI view that lays out `PaneTerminalView`s according to the pane split topology. Draggable dividers between panes. |
| `TerminalArea` changes | `Features/Terminal/` | Checks feature flag. Old: `ForgeTerminalView`. New: `PaneSplitView`. |

Nothing else in Core changes. The orchestrator (`WorkspaceController`) doesn't participate in rendering. It already manages pane state via `TmuxSyncEngine`, which continues working as-is. The `OutputRouter` is wired at the composition root and operates alongside the orchestrator as a parallel infrastructure concern.

## Feature Flag

```json
{
  "general": {
    "nativePaneRendering": true
  }
}
```

`ForgeConfig.GeneralSettings.nativePaneRendering: Bool?` — defaults to `false` during migration, flipped to `true` when stable, removed when old path is deleted.

`TerminalArea` checks the flag at render time. Both paths coexist until Phase 5. The flag also gates Stack mode — `StackView`'s terminal snapshot capture (`findTerminalView` by class name) must be updated in Phase 3 to work with the new view hierarchy.

## Process Persistence

With native rendering, Forge no longer runs `tmux attach`. Quitting Forge doesn't detach from tmux — the sessions keep running because they were never "attached" in the traditional sense. Control mode disconnects, but the sessions and their processes remain.

On relaunch:
1. `TmuxSyncEngine` discovers existing sessions (as it does today)
2. `OutputRouter` creates renderers for each pane
3. Scrollback is seeded from tmux (bounded, async)
4. `%output` resumes — the user sees their terminals with scrollback history

The session snapshot feature (tab persistence) becomes the fallback for explicit project close (`Cmd+Shift+W`), where the tmux session is actually killed.

## Migration Phases

### Phase 1: Infrastructure Foundation
- `TerminalRenderer` protocol and `SwiftTermRenderer` implementation
- `OutputRouter` with pane ID → renderer mapping, lifecycle via post-refresh hook
- `TmuxControlMode` gains `onOutput` callback (stops filtering `%output`), tmux escape decoding
- `TmuxControlPort` protocol updated with `onOutput` parameter
- Feature flag in `ForgeConfig`
- `forge-tmux.conf`: add `set-option -g window-size manual`
- Nothing user-visible changes

### Phase 2: Single-Pane Rendering
- `PaneTerminalView` renders one pane via `%output`
- `TerminalArea` checks flag — new path renders active tab's first pane only (test with single-pane tabs only in this phase)
- Input via `controlMode.send("send-keys -H ...")`, resize via `controlMode.send("resize-pane ...")`
- Scrollback seeding on connect
- Skip `refresh-client -C 1,1` when flag is on
- This proves the data flow end-to-end: output, input, resize, scrollback

### Phase 3: Multi-Pane Layout
- `PaneSplitView` reads pane topology from the domain model and lays out `PaneTerminalView`s
- Draggable SwiftUI dividers between panes
- Pane click-to-focus via NSView first responder
- Text selection works per-pane — the original motivation
- Fix `StackView.findTerminalView` to work with new view hierarchy

### Phase 4: Persistence Polish
- Sessions survive Forge quit (no `tmux attach` to disconnect)
- On relaunch: reconnect to running sessions, seed scrollback, resume `%output`
- Tab snapshot feature serves explicit close only

### Phase 5: Remove Old Path
- Delete `ForgeTerminalView`
- Remove feature flag
- Clean up any dual-path conditionals

Each phase is independently shippable and testable. Phase 2 is the riskiest — if the data flow works there, everything else follows.

## What Users Get

| Feature | Today | After |
|---------|-------|-------|
| Text selection | Bleeds across panes | Native per-pane, proper line wrapping |
| Pane click to focus | Doesn't work | NSView hit testing |
| Scrollback | Tmux copy-mode only | Native trackpad scroll per pane |
| Search (Cmd+F) | Not possible | Search SwiftTerm buffer per pane |
| Clickable URLs | Not possible | SwiftTerm URL detection per pane |
| Pane resize | Tmux redraw flicker | Smooth SwiftUI drag dividers |
| Right-click menu | None | Copy/Paste/Select All per pane |
| Process persistence | Processes die on quit | Processes survive, resume on relaunch |
| Session restore | Snapshot-based | Automatic — sessions still running |
| Accessibility | One opaque view | VoiceOver per pane |

## Limitations

- **Alternate screen**: TUI programs (vim, htop) use the alternate screen buffer. After Forge restart, `capture-pane` can't recover TUI display — the program redraws on first input.
- **Scrollback seeding is bounded**: Only the most recent N lines (e.g., 5000) are seeded on reconnect to avoid startup delay.

## What's Not In Scope

- libghostty integration (the protocol is swappable, but only SwiftTerm is implemented)
- Per-pane zoom / independent font sizes (future enhancement)
- Image protocol support (Sixel, iTerm2 inline images — future enhancement)
- tmux copy-mode or tmux keybindings (Forge owns all shortcuts)
