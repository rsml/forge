<p align="center">
  <img src="Assets/appicon-transparent.png" alt="Forge" width="192" height="192">
</p>

<h1 align="center">Forge</h1>

<p align="center">
  A native macOS terminal multiplexer built for parallel CLI agents and long-running tasks.<br>
  Powered by <a href="https://ghostty.org/"><code>libghostty</code></a>.
</p>

<p align="center">
  <a href="#about">About</a> ·
  <a href="#features">Features</a> ·
  <a href="#build">Build</a> ·
  <a href="#configuration">Configuration</a> ·
  <a href="#acknowledgments">Acknowledgments</a> ·
  <a href="#license">License</a>
</p>

---

## About

Forge is a terminal multiplexer for macOS that organizes your shells the way
you actually think about them: **Projects** (a directory you work in) hold
**Tabs** (an activity inside that project), which hold **Panes** (a single
terminal, optionally split). All of it is native SwiftUI on top of
[libghostty](https://github.com/ghostty-org/ghostty), so cells render at
GPU speed and key handling has no shim layer.

It is designed around two things modern terminal use has gotten harder
without:

- **Sessions that survive an app restart.** A sidecar daemon (`forged`)
  holds the PTY master file descriptors over a Unix-domain socket. Quitting
  Forge — or it crashing — does not SIGHUP your shells. Relaunch and pick
  back up exactly where you left off.

- **Knowing which terminal needs you.** With several long-running tasks or
  AI coding agents in flight, the hard problem is no longer "how do I see
  them all" but "which one is waiting on me right now." Forge watches every
  pane for terminal bells, command completion, and interactive prompts, and
  surfaces them through an attention queue and an optional **stack mode**
  that pops the most-recently-attention-grabbing tab to the front.

Forge embeds `libghostty` rather than shelling out to `tmux`. There is no
multiplexer process, no control-mode protocol, no escape-sequence
re-encoding — just PTYs that Forge owns directly through Ghostty's
embedding API.

## Features

**Workspace model**
- Projects with working directories, tabs, splits, and per-project sort
  order. Persisted to `~/.config/forge/workspace.json`.
- Arbitrary pane nesting — horizontal splits inside vertical splits inside
  horizontal splits, drag dividers to resize.
- Browser panes alongside terminal panes (WebKit), with full / slim /
  hidden chrome modes and a quick URL palette.

**Session persistence**
- `forged` daemon dups every PTY's master fd so shells survive a Forge
  quit, crash, or upgrade. On relaunch, surfaces reconnect to the existing
  fds in Ghostty's `EXTERNAL_FD` mode.
- Workspace structure (projects, tabs, splits, proportions) saves
  continuously and restores on launch.

**Attention system**
- Bell (`0x07`) detection per pane.
- Regex / exact-string content matches for common interactive prompts
  ("Allow once?", "(y/N)", Claude Code's tool-use prompts, etc.). Patterns
  are user-extensible.
- Command-completion detection: a pane's foreground process transitions
  from active → idle and you get notified the task is done.
- Native macOS notifications with configurable sound and badge color.
- A notification panel and per-tab badges in the sidebar.

**Stack mode**
- An alternative to the sidebar/tab UI: the frontmost queued tab is
  displayed full-screen with a Done / Hide / Move-to-Back toolbar.
- Designed for monitoring N agents at once — work with whichever is
  asking for input, dismiss it, get the next one.

**Themes and fonts**
- Bundles 31 themes (Catppuccin, Tokyo Night, Dracula, Gruvbox, Nord,
  Rose Pine, Solarized, GitHub, Ayu, Everforest, Monokai, and more)
  imported verbatim from
  [iTerm2-Color-Schemes](https://github.com/mbadolato/iTerm2-Color-Schemes).
- User themes drop into `~/.config/forge/themes/*.conf`. Format is
  Ghostty-compatible (`background=#hex`, `foreground=#hex`,
  `palette=N=#hex`, `cursor-color=#hex`) — see
  [ADR 0005](docs/adr/0005-ghostty-theme-format-compatibility.md).
- Font resolution: configured family → Ghostty config → Nerd Font
  fallbacks → system monospaced. Ligatures and line height configurable.

**Other niceties**
- Command palette (`⌘⇧P`) and tab switcher (`⌘P`).
- Customizable keyboard shortcuts (recorder UI in Settings → Shortcuts).
- Active-process close confirmation — closing a pane / tab / project that
  has a foreground process other than the shell prompts before terminating.
  Each level (`never` / `whenActive` / `always`) is configurable.
- Git branch in the title bar for the active project.
- Inline rename for projects and tabs.
- Sidebar reorderable by drag; tabs reorderable by drag.

## Build

Requirements:

- macOS 14 (Sonoma) or newer
- Xcode 16 or Swift 6.0+ toolchain
- [Zig](https://ziglang.org/) — required to build `libghostty` (`brew install zig`)

```sh
git clone https://github.com/rsml/forge.git
cd forge
git submodule update --init vendor/ghostty
make run          # release build + launch
# or
make dev          # debug build + launch
swift test        # run domain tests
```

`make` handles building `GhosttyKit.xcframework` from `vendor/ghostty` (cached
by SHA in `~/.cache/forge/ghosttykit/`) and copying the `forged` daemon into
the app bundle. Bare `swift build` compiles, but `make` is what produces a
working `.app`.

Logs land at `/tmp/forge.log`. Categories: `[app]`, `[ghostty]`, `[daemon]`,
`[attention]`, `[debug]`.

## Configuration

Forge keeps its config at `~/.config/forge/config.json`. Most settings are
editable through Settings (`⌘,`). Notable ones not in the UI:

- `nativePTY: true` — the only supported mode going forward.
- `shortcuts: { ... }` — override any default keybinding by id (see
  `Sources/Infrastructure/Config/KeyboardShortcuts.swift` for the list).

User themes go in `~/.config/forge/themes/*.conf`.

## Acknowledgments

Forge is not affiliated with or endorsed by any of the projects below. They
are named here to credit their authors and to make it clear what makes Forge
work.

### Powered by libghostty

Forge embeds [`libghostty`](https://ghostty.org/), the terminal library
extracted from [Ghostty](https://github.com/ghostty-org/ghostty), for
terminal surface rendering, PTY ownership in EXEC mode, and input encoding.
Ghostty is MIT-licensed; copyright Mitchell Hashimoto and Ghostty
contributors. The Ghostty name, ghost icon, and brand are not used as
Forge's branding.

### Color themes

Bundled themes are imported from
[mbadolato/iTerm2-Color-Schemes](https://github.com/mbadolato/iTerm2-Color-Schemes)
(MIT, copyright Mark Badolato 2011–Present). Each theme is the work of its
original author — Dracula Theme, Catppuccin, folke (Tokyo Night), Arctic
Ice Studio (Nord), Pavel Pertsev (Gruvbox), Rosé Pine, Ethan Schoonover
(Solarized), Sainnhe Park (Everforest), Wimer Hazenberg (Monokai), and many
others. See the upstream
[CREDITS.md](https://github.com/mbadolato/iTerm2-Color-Schemes/blob/master/CREDITS.md)
for full per-theme attribution.

### Kitty keyboard protocol

Forge implements the
[Kitty keyboard progressive enhancement protocol](https://sw.kovidgoyal.net/kitty/keyboard-protocol/)
designed by Kovid Goyal. Forge does not bundle or derive from the Kitty
terminal — only the public protocol specification.

### Full license texts

Verbatim license text for every third-party component bundled with Forge
lives in [`LICENSES/`](./LICENSES/).

## License

Forge is released under the [MIT License](./LICENSE). Copyright (c) 2026
Ross Miller.
