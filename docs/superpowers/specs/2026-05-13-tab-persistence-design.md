# Tab Persistence

Save and restore tab layout when reopening a project at the same folder path.

## Behavior

- **On close**: Before killing a tmux session, snapshot its tab/pane structure to disk.
- **On open**: When adding a project, check for a saved snapshot at that path. If found, restore the tab layout instead of creating a single default tab.
- **Always-on**: No config flag. Every close saves, every matching open restores.
- **One-shot restore**: Snapshot file is deleted after all restore commands are dispatched and `syncEngine.refresh()` completes. The next close captures fresh state.

## Data Model

Snapshots stored as individual JSON files at `~/.config/forge/sessions/<sha256-of-path>.json`. SHA256 via `CryptoKit.SHA256`. Paths are canonicalized (`URL.standardized.path`) at both save and restore time.

Snapshots are not capped. Files are ~200-500 bytes. Stale snapshots for long-gone projects are accepted — the storage cost is negligible.

```json
{
  "path": "/Users/ross/Personal/forge",
  "savedAt": "2026-05-13T10:00:00Z",
  "tabs": [
    {
      "name": "editor",
      "index": 0,
      "layout": "2a93,190x50,0,0{95x50,0,0,95x50,96,0}",
      "panes": [
        { "directory": "/Users/ross/Personal/forge", "index": 0 },
        { "directory": "/Users/ross/Personal/forge/Sources", "index": 1 }
      ]
    },
    {
      "name": "tests",
      "index": 1,
      "layout": null,
      "panes": [
        { "directory": "/Users/ross/Personal/forge", "index": 0 }
      ]
    }
  ]
}
```

- `layout`: Opaque tmux `window_layout` string captured verbatim from `#{window_layout}`. `null` for single-pane tabs (no splits to restore).
- `path`: Stored for human readability / debugging. The filename hash is the lookup key.

## Capture Flow

`removeProject` becomes `async`. Before `kill-session`:

1. Query tmux for the project's tab/pane state via `TmuxCommandRunner` (not control mode):
   - `list-windows -t <session> -F "#{window_index}\t#{window_name}\t#{window_layout}"`
   - `list-panes -t <session> -F "#{window_index}\t#{pane_index}\t#{pane_current_path}"`
2. Build `SessionSnapshot` struct from query results.
3. Write JSON to `~/.config/forge/sessions/<sha256>.json`.
4. Proceed with existing kill logic.

**Error handling**: If tmux queries fail or file write fails, log the error and continue with the kill. A failed snapshot is not worth blocking project removal.

## Restore Flow

In `addProject`, after `new-session` succeeds:

1. Compute `<sha256-of-canonicalized-path>` and check for snapshot file.
2. If no snapshot or snapshot is malformed JSON: current behavior (single tab, fresh shell). On malformed JSON, delete the bad file and log a warning.
3. If snapshot exists, replay tmux commands per tab:
   - **Tab 0** (already created by `new-session`): rename to saved name
   - **Tabs 1+**: `new-window -t <session>: -n <saved-name> -c <first-pane-dir>`
   - **Multi-pane restore** (see below): parse the layout tree, replay splits in correct order
   - `send-keys -t <pane> "cd <dir>" Enter` for each pane whose directory differs from the project root
4. Apply `select-layout <saved-layout>` per window to fine-tune dimensions.
5. Delete snapshot file after all commands are dispatched and `syncEngine.refresh()` completes.

### Multi-Pane Restore

The tmux `window_layout` string encodes a tree of nested splits:
- `{...}` = horizontal split (panes side by side)
- `[...]` = vertical split (panes stacked)
- Leaf nodes are individual panes

Example: `"2a93,190x50,0,0{95x50,0,0,1[47x25,0,0,2,47x24,0,26,3]}"` describes:
```
┌─────────┬──────────┐
│         │  pane 2  │
│ pane 1  ├──────────┤
│         │  pane 3  │
└─────────┴──────────┘
```
Horizontal split at the root → left leaf (pane 1), right branch is a vertical split → two leaves (panes 2, 3).

**Restore algorithm**: A pure function in Core (`LayoutParser`) parses the layout string into a tree of `SplitNode` values. The restore walk:

1. Start with the window's initial pane (pane 0).
2. Walk the tree depth-first. At each branch node:
   - `split-window -h` (horizontal) or `split-window -v` (vertical) targeting the current pane
   - The split creates a new pane. The original pane becomes the first child; the new pane becomes the second child.
   - Recurse into each child subtree.
3. Each leaf corresponds to a saved pane. `send-keys "cd <dir>"` to each leaf's pane in the order they appear in the tree (which matches the saved pane index order).
4. After all splits, `select-layout <saved-layout>` fine-tunes the proportions.

Because we control the creation order, the pane-to-directory mapping is deterministic — leaf N in the tree walk corresponds to saved pane N.

**Error handling**: If any tmux command fails mid-restore (e.g., `split-window` fails), log and continue with remaining tabs. Delete the snapshot regardless to avoid a retry loop. The user gets a partial restoration, which is better than a repeated failed attempt.

## Code Placement

| File | Layer | Purpose |
|------|-------|---------|
| `Core/Models/SessionSnapshot.swift` | Core | `SessionSnapshot`, `TabSnapshot`, `PaneSnapshot` — pure Codable structs |
| `Core/LayoutParser.swift` | Core | Parse `window_layout` string into `SplitNode` tree. Pure function, no framework imports. ~40 lines. |
| `Infrastructure/Config/SessionSnapshotStore.swift` | Infrastructure | Read/write/delete snapshot files. SHA256 via CryptoKit. Separate from `ForgeConfigStore` because snapshots are ephemeral per-path files, not app configuration. |
| `WorkspaceController+Actions.swift` | Orchestrator | `removeProject` captures snapshot (now `async`); `addProject` restores from snapshot |
| `TmuxAdapter.swift` | Infrastructure | Queries via `TmuxCommandRunner` for window layout + pane paths. Restore commands via `TmuxCommandRunner` (awaited, not fire-and-forget). |

No new views. No new config flags. No new ports — snapshot store is a simple file I/O utility used only by the orchestrator.

## What's Restored

- Tab count and order
- Tab names (custom renames preserved)
- Pane split layout (geometry proportions — tmux reflows to current window size)
- Working directory of each pane

## What's Not Restored

- Scrollback history
- Running processes / interactive state
- Terminal colors, cursor position
- Pane content
- Exact pane pixel dimensions (layout adapts to current terminal size)
