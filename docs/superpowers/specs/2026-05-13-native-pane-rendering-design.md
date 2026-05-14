# Native Per-Pane Terminal Rendering

Replace the current single `tmux attach` terminal view with per-pane SwiftTerm instances fed by tmux control mode `%output` events. Tmux becomes an invisible process manager; Forge owns the entire visual experience.

## Motivation

Today `ForgeTerminalView` runs `tmux attach-session` inside a single `LocalProcessTerminalView`. Tmux renders everything — panes, borders, all of it. This inherits every tmux rendering limitation: text selection bleeds across panes, no per-pane scrollback, no pane click-to-focus, no native search, no clickable URLs.

Since Forge already uses tmux control mode (`-CC`) for push-based state updates, the `%output` data is flowing through the connection — it's just being discarded. Routing it to per-pane terminal views gives native UX while preserving tmux's process management.

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Migration strategy | Incremental with feature flag | Ship improvements without breaking current path |
| Input routing | `send-keys -H` (hex mode) | No key mapping table — raw bytes transmitted exactly |
| Tmux keybindings | Not supported | Forge owns all shortcuts |
| Process persistence | Sessions survive Forge quit | Killer feature — relaunch and everything is still running |
| Scrollback | Seed from tmux on connect | `capture-pane -p -S - -e` gives full history after restart |
| Terminal view | Swappable via infrastructure protocol | SwiftTerm now, libghostty later |

## Data Flow

### Output (tmux → screen)

```
TmuxControlMode
  → parses %output %<pane_id> <escaped_data>
  → onOutput callback
  → OutputRouter
  → TerminalRenderer.feed(data) for matching pane
```

`%output` data is percent-encoded by tmux. The router decodes it and dispatches raw bytes to the renderer.

### Input (keyboard → tmux)

```
SwiftTermRenderer captures keystroke
  → onInput callback with raw bytes
  → send-keys -H -t <pane_id> <hex_bytes>
  → tmux routes to pane's shell
```

`send-keys -H` sends hex-encoded bytes directly, bypassing tmux's key name parsing. No mapping table needed.

### Resize (layout change → tmux)

```
SwiftUI layout resizes PaneTerminalView
  → SwiftTermRenderer reports new cols/rows via onResize callback
  → resize-pane -t <pane_id> -x <cols> -y <rows>
```

### Scrollback Seeding (on connect)

When Forge connects to an existing tmux session (relaunch or reconnect):

1. For each pane: `capture-pane -p -S - -e -t <pane_id>` to get full scrollback with escape sequences
2. Feed to `renderer.seedScrollback(content)`
3. Then switch to live `%output` feed

This makes persistence feel complete — quit Forge, relaunch, scroll up, see previous output.

## Component Map

| Component | Layer | Purpose |
|-----------|-------|---------|
| `TerminalRenderer` protocol | `Infrastructure/Terminal/` | `feed(Data)`, `seedScrollback(String)`, `view: NSView`. Swappable abstraction — not a Core port because terminal rendering is infrastructure, not domain. |
| `SwiftTermRenderer` | `Infrastructure/Terminal/` | Implements `TerminalRenderer` using SwiftTerm. Reports keystrokes and resize via closures. |
| `OutputRouter` | `Infrastructure/Terminal/` | Maps pane IDs to `TerminalRenderer` instances. Receives parsed `%output` events from `TmuxControlMode`. |
| `TmuxControlMode` changes | `Infrastructure/Tmux/` | Stop filtering `%output`. Parse `%output %<pane_id> <data>` and call a new `onOutput: (String, Data) -> Void` callback. |
| `PaneTerminalView` | `Features/Terminal/` | SwiftUI view embedding a renderer's NSView via `NSViewRepresentable`. One per pane. |
| `PaneSplitView` | `Features/Terminal/` | Recursive SwiftUI view that lays out `PaneTerminalView`s according to the pane split topology. Draggable dividers between panes. |
| `TerminalArea` changes | `Features/Terminal/` | Checks feature flag. Old: `ForgeTerminalView`. New: `PaneSplitView`. |

Nothing in Core changes. The orchestrator (`WorkspaceController`) doesn't participate in rendering. It already manages pane state via `TmuxSyncEngine`, which continues working as-is. The `OutputRouter` operates alongside the orchestrator as a parallel infrastructure concern.

## Feature Flag

```json
{
  "general": {
    "nativePaneRendering": true
  }
}
```

`ForgeConfig.GeneralSettings.nativePaneRendering: Bool?` — defaults to `false` during migration, flipped to `true` when stable, removed when old path is deleted.

`TerminalArea` checks the flag at render time. Both paths coexist until Phase 5.

## Process Persistence

With native rendering, Forge no longer runs `tmux attach`. Quitting Forge doesn't detach from tmux — the sessions keep running because they were never "attached" in the traditional sense. Control mode disconnects, but the sessions and their processes remain.

On relaunch:
1. `TmuxSyncEngine` discovers existing sessions (as it does today)
2. `OutputRouter` creates renderers for each pane
3. Scrollback is seeded from tmux
4. `%output` resumes — the user sees their terminals exactly as they left them

The session snapshot feature (tab persistence) becomes the fallback for explicit project close (`Cmd+Shift+W`), where the tmux session is actually killed.

## Migration Phases

### Phase 1: Infrastructure Foundation
- `TerminalRenderer` protocol and `SwiftTermRenderer` implementation
- `OutputRouter` with pane ID → renderer mapping
- `TmuxControlMode` gains `onOutput` callback (stops filtering `%output`)
- Feature flag in `ForgeConfig`
- Nothing user-visible changes

### Phase 2: Single-Pane Rendering
- `PaneTerminalView` renders one pane via `%output`
- `TerminalArea` checks flag — new path renders active tab's first pane only, no splits
- Input via `send-keys -H`, resize via `resize-pane`
- Scrollback seeding on connect
- This proves the data flow end-to-end: output, input, resize, scrollback

### Phase 3: Multi-Pane Layout
- `PaneSplitView` reads pane topology from the domain model and lays out `PaneTerminalView`s
- Draggable SwiftUI dividers between panes
- Pane click-to-focus via NSView first responder
- Text selection works per-pane — the original motivation

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

## What's Not In Scope

- libghostty integration (the protocol is swappable, but only SwiftTerm is implemented)
- Per-pane zoom / independent font sizes (future enhancement)
- Image protocol support (Sixel, iTerm2 inline images — future enhancement)
- tmux copy-mode or tmux keybindings (Forge owns all shortcuts)
