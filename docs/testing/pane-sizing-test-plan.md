# Pane Sizing Test Plan

Goal: prove that every pane's terminal content fills its full visual area, with no cut-off, no scrollback bleed, no blank screens, and no proportion drift — under all scenarios.

## The Invariants (what must ALWAYS be true)

1. **Grid match**: For every pane, ghostty's grid (cols x rows) == tmux's pane dimensions (width x height). Zero tolerance.
2. **Content visible**: Every pane shows its terminal content immediately after app launch, project switch, tab switch, and split creation.
3. **Proportions stable**: Split divider positions don't move unless the user drags them.
4. **Full-screen TUI apps work**: vim, htop, Claude Code render correctly with no cut-off at top/bottom/sides, and the input area is always visible.

## How to verify invariant 1 (grid match)

Test command: `curl localhost:7654/pane-sizes | python3 -m json.tool`

Check: every pane has `"mismatch": false`.

### Scenarios to test:

- [ ] **Single pane, app launch** — open app with 1 project, 1 tab, 1 pane
- [ ] **Single pane, new project** — add a new project, check its pane
- [ ] **Horizontal split** — split horizontally, check both panes
- [ ] **Vertical split** — split vertically, check both panes
- [ ] **Nested split** — horizontal split, then split one side vertically. Check all 3 panes.
- [ ] **After window resize** — drag the app window edge to resize. Re-check all panes.
- [ ] **After divider drag** — drag a split divider. Re-check all panes.
- [ ] **After app restart** — close and reopen app. Check all panes immediately.
- [ ] **After project switch** — switch to a different project and back. Check panes.
- [ ] **After tab switch** — switch tabs within a project. Check panes.
- [ ] **After closing a pane** — close one pane in a split. Check remaining pane.

## How to verify invariant 2 (content visible)

Test command: `curl localhost:7654/screenshot > /tmp/forge.png` + visual inspection

### Scenarios to test:

- [ ] **App launch with idle shell** — all panes show prompts (not blank)
- [ ] **App launch with Claude Code running** — Claude Code pane shows full UI including input area
- [ ] **Project switch** — switching projects shows content immediately (no blank flash)
- [ ] **New split creation** — new pane shows prompt immediately
- [ ] **After closing a split** — remaining pane still shows content (not blank)

### What "blank" means and how to diagnose:

If a pane is blank (just a cursor), check:
1. Is the OutputRouter buffering working? (check logs for "replaying X buffered bytes")
2. Did resize-window trigger a redraw? (check logs for resize commands)
3. Is the control mode client attached to the right session? (check `tmux list-clients`)
4. Is %output arriving? (check logs for output routing)

## How to verify invariant 3 (proportions stable)

### Scenarios to test:

- [ ] **App restart preserves splits** — set up a 30/70 horizontal split. Restart app. Divider should be at same position.
- [ ] **Window resize preserves ratios** — set up splits, resize app window. Divider should stay at same relative position.
- [ ] **Divider stays after release** — drag divider, release. Divider should not move at all after release. No bouncing, no snapping.
- [ ] **No drift over time** — leave app running for 5 minutes with splits. Divider should not move.
- [ ] **Project switch and back** — switch away, switch back. Splits should be exactly where left.

### How to measure:

Take screenshot before and after. The divider pixel position should not change (within 1px tolerance for cell rounding).

## How to verify invariant 4 (TUI apps)

### Scenarios to test:

- [ ] **Claude Code in single pane** — launch claude, full UI visible including input line at bottom
- [ ] **Claude Code in horizontal split** — launch claude in one side. Resize the split. Claude should redraw cleanly.
- [ ] **Claude Code in nested split** — claude in bottom-right of a 3-pane layout. Full UI visible.
- [ ] **vim in a split** — open vim, check it fills the pane. `:set lines? columns?` should match the pane dimensions.
- [ ] **htop in a split** — htop should fill the pane with no truncation
- [ ] **After divider drag** — drag a split divider while Claude Code is running. After release, Claude should redraw cleanly with correct dimensions.

## Timing and sequencing (where things go wrong)

These are the critical timing windows where mismatches occur:

### T1: App startup sequence

1. detachAllClients — are all stale clients gone?
2. startControlMode — is the new client attached?
3. switchClient — is it on the right session BEFORE renderers are created?
4. updateRenderers — are renderers created?
5. Cell size computed — is terminalCellSize set before the first flush?
6. Dividers rendered — are they using cell size (not 8px fallback)?
7. Flush fires — does it send correct total dimensions?
8. tmux redraws — does %output arrive for all panes?

**Test**: Add timestamped logging for each step. Verify order and timing.

### T2: Divider drag sequence

1. Drag starts — is suppressPaneResize set?
2. During drag — are resize commands suppressed? (no tmux commands)
3. Drag ends — is suppressPaneResize cleared?
4. Flush fires — does it send resize-pane with correct dimensions?
5. tmux processes — does it accept all resize-pane commands?
6. Panes redraw — does %output arrive with correct content?

**Test**: Drag divider, then immediately check `curl localhost:7654/pane-sizes`.

### T3: Control mode reconnection

1. If control mode disconnects (e.g., after killing a session), does it reconnect?
2. After reconnect, does refresh-client -C get sent with correct format (XxY not X,Y)?
3. After reconnect, do panes get redrawn?

**Test**: Kill a tmux session, wait for reconnect, check pane-sizes.

## Data to collect for every failing scenario

When something doesn't look right, collect ALL of these:

```bash
# 1. Pane sizing diagnostic
curl localhost:7654/pane-sizes | python3 -m json.tool

# 2. tmux state
tmux -L forge list-clients -F '#{client_name} w=#{client_width} h=#{client_height} s=#{client_session}'
tmux -L forge list-panes -a -F '#{session_name} #{pane_id} #{pane_width}x#{pane_height}'
tmux -L forge list-windows -a -F '#{session_name} #{window_id} #{window_width}x#{window_height} #{window_layout}'

# 3. Screenshot
curl localhost:7654/screenshot > /tmp/forge-debug.png

# 4. Recent logs
tail -50 /tmp/forge.log
```

## Root causes we've identified (regression checklist)

These are bugs we've already fixed. Each must be tested on every change:

1. **refresh-client -C format**: must be `WxH` not `W,H` — verify client height is set
2. **Stale clients**: detachAllClients must run before control mode start
3. **switchClient before updateRenderers**: resize commands need correct session context
4. **Divider width must match cell size**: 8px fallback causes pixel allocation mismatch
5. **No onChange from tmux proportions**: local @State is authoritative for divider positions
6. **DragGesture uses .global coordinates**: prevents oscillation from view movement
7. **OutputRouter buffers unregistered panes**: prevents dropped output on split creation
8. **resize-window toggle (+1/-1)**: forces tmux to redraw idle panes on startup

## Definition of done

ALL of the following are true simultaneously:
- `curl localhost:7654/pane-sizes` shows `"mismatch": false` for every pane
- Screenshot shows all panes with visible content (no blank screens)
- Claude Code in a nested split shows full UI including input line
- Close and reopen app: divider positions preserved, all content visible
- Drag a divider: stays exactly where released, all panes redraw correctly
