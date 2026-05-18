# Active-Process Close Confirmation

Prompt for confirmation when closing a pane, tab, or project that has a foreground process running (claude, vim, npm run dev — anything that grabbed the controlling terminal). Detection is universal — no per-program knowledge required — via `tcgetpgrp` on the PTY master.

## Behavior

Three close targets, three settings, one detection mechanism.

### Trigger matrix

| Setting | Effect when closing a tab |
|---------|---------------------------|
| `confirmCloseTab = .never` | Never prompts |
| `confirmCloseTab = .whenActive` *(default)* | Prompts iff any pane in the tab has a foreground process |
| `confirmCloseTab = .always` | Always prompts |

`confirmCloseProject` mirrors this with the same enum. `confirmClosePane` keeps the existing boolean semantics ("prompt iff active") — single-pane close is a small, frequent operation; an always-warn mode is not useful here.

### Dialog wording

Apple HIG: state the consequence, don't ask a question.

- **Pane (running)**: *"Closing this pane will terminate **\<command\>**."*
- **Pane (multiple actives, e.g. closing a tab with claude in pane 1 and vim in pane 2)**: *"Closing this pane will terminate **claude** (and 1 other process)."*
- **Tab (running)**: *"Closing this tab will terminate **\<command\>**."*
- **Tab (idle, always-warn)**: *"Closing this tab will close it permanently."*
- **Project (running)**: *"Closing "\<project\>" will terminate **\<command\>**."*
- **Project (idle, always-warn)**: *"Closing "\<project\>" will close all its tabs and remove it from Forge."*

Buttons:
- Affirmative (`Close Tab` / `Close Pane` / `Close Project`): `hasDestructiveAction = true` (red on macOS Tahoe).
- Cancel: **default button** (`keyEquivalent = "\r"`). Enter cancels.
- Presented as a window sheet via `NSAlert.beginSheetModal(for:)`, not free-floating.

`<command>` is the basename of the foreground process's binary path (e.g. `/usr/bin/vim` → `vim`). Falls back to `"a process"` if path lookup fails.

## Detection

### Core primitive

Each pane's PTY master fd is held by the `forged` daemon (already true today for persistence). The daemon adds an `is_active` op:

```
tcgetpgrp(fd) != getpgid(shellPid)  ⇒  foreground job is not the shell  ⇒  active
```

Works universally — every program started from an interactive shell joins its own process group via `tcsetpgrp` for job control. Backgrounded jobs (`claude &`) correctly report idle: the shell remains the foreground pgrp.

### Port

```swift
// Sources/Core/Ports/PaneActivityPort.swift
public struct PaneActivity: Sendable {
    public let paneId: String
    public let isActive: Bool
    public let command: String?  // nil iff isActive == false or lookup failed
}

public protocol PaneActivityPort: Sendable {
    func query(paneIds: [String]) async -> [PaneActivity]
}
```

Pure data, no framework imports. Lives in `Core/Ports/` next to the existing port protocols.

### Adapters

**`DaemonActivityAdapter`** (`Sources/Infrastructure/Process/`) — native PTY mode.

Sends a single batched `is_active` op to forged:

```json
{ "op": "is_active", "pane_ids": ["A", "B", "C"] }
```

Daemon response:

```json
{ "status": "ok", "panes": [
  { "pane_id": "A", "active": true, "command": "claude" },
  { "pane_id": "B", "active": false },
  { "pane_id": "C", "active": true, "command": "vim" }
]}
```

**`TmuxActivityAdapter`** (`Sources/Infrastructure/Tmux/`) — tmux mode.

Reads `pane.status == .running` from the existing `Workspace` model. Uses `pane.currentCommand` as `command`. No tmux round trip — the data is already cached from the refresh cycle.

Both adapters conform to `PaneActivityPort`. Composition root (`AppDelegate`) wires the right one based on `config.isNativePTY`.

### Daemon implementation

`Sources/Daemon/Forged.swift` changes:

1. **Store pgid alongside pid** at `store` time:

   ```swift
   struct StoredPane {
       let fd: Int32
       let pid: Int32
       let pgid: pid_t      // NEW — getpgid(pid) at register time
       let cwd: String
       let createdAt: Date
   }
   ```

2. **New `is_active` op** in `handleClient`:

   ```swift
   case "is_active":
       guard let paneIds = json["pane_ids"] as? [String] else { return }
       var results: [[String: Any]] = []
       for id in paneIds {
           guard let pane = storedFDs[id] else {
               results.append(["pane_id": id, "active": false])
               continue
           }
           // Reap stale entries — shell exited
           if kill(pane.pid, 0) != 0 {
               results.append(["pane_id": id, "active": false])
               continue
           }
           let fg = tcgetpgrp(pane.fd)
           if fg <= 0 || fg == pane.pgid {
               results.append(["pane_id": id, "active": false])
           } else {
               let cmd = procCommandName(pid: fg)
               var entry: [String: Any] = ["pane_id": id, "active": true]
               if let cmd { entry["command"] = cmd }
               results.append(entry)
           }
       }
       // ...respond
   ```

3. **`procCommandName(pid:)` helper** — uses `proc_pidpath(pid, buf, PROC_PIDPATHINFO_MAXSIZE)` from `libproc.h`, returns the basename. Truncated comm field (`proc_name`) is *not* used — it caps at 15 chars and obscures binaries with longer names.

   Known limitation: Node-based / Python-based CLIs surface as `node` or `python3`. TODO comment notes future enhancement via `KERN_PROCARGS2` to extract `argv[1]`.

### Failure mode

**Fail-open.** If the daemon socket round-trip throws or returns garbage, `DaemonActivityAdapter.query` returns `[PaneActivity(paneId: x, isActive: false, command: nil) for each x]` and logs at `[daemon]`. Rationale: a flaky daemon must never block a close. The cost of a single missed warning during a daemon hiccup is lower than the cost of a phantom warning every time forged restarts.

## CloseConfirmation Changes

### Updated signature

`Sources/Core/CloseConfirmation.swift`:

```swift
public enum CloseConfirmation {
    public enum CloseTarget {
        case pane(id: String)
        case tab(Tab, in: Project)
        case project(Project)
    }

    public enum TabConfirmMode: String, Codable {
        case never, whenActive, always
    }

    public struct AlertInfo {
        public let message: String
        public let info: String          // may be empty
        public let action: String
    }

    public struct CloseDecision {
        public let target: CloseTarget
        public let alert: AlertInfo?
    }

    @MainActor public static func evaluate(
        project: Project,
        tab: Tab,
        activePane: Pane?,
        activities: [PaneActivity],          // all panes in the resolved target
        confirmCloseTab: TabConfirmMode,
        confirmCloseProject: TabConfirmMode  // same enum for symmetry
    ) -> CloseDecision
}
```

### Target picking (unchanged)

- `tab.panes.count > 1` and `activePane != nil` → `.pane`
- else `project.tabs.count > 1` → `.tab`
- else → `.project`

### Alert construction (new)

Find the first active pane in `activities` (sorted by pane index for determinism). Use its `command` for the message text.

For `confirmCloseTab = .always` (and no active pane), use the idle-but-always-warn message.

For `.whenActive`, return `alert = nil` when no pane is active.

For `.never`, return `alert = nil` always.

### Presentation

`Sources/Features/Shared/CloseConfirmation.swift` becomes async:

```swift
@MainActor
extension CloseConfirmation {
    static func present(_ info: AlertInfo, in window: NSWindow) async -> Bool {
        await withCheckedContinuation { cont in
            let alert = NSAlert()
            alert.messageText = info.message
            alert.informativeText = info.info
            alert.alertStyle = .warning

            let destructive = alert.addButton(withTitle: info.action)
            destructive.hasDestructiveAction = true
            destructive.keyEquivalent = ""

            let cancel = alert.addButton(withTitle: "Cancel")
            cancel.keyEquivalent = "\r"   // Enter cancels

            alert.beginSheetModal(for: window) { response in
                cont.resume(returning: response == .alertFirstButtonReturn)
            }
        }
    }
}
```

## Close-Path Wiring

`WorkspaceController+Actions.swift` — every close method becomes `async` and consults the activity port before invoking the existing close logic. Call sites wrap in `Task { @MainActor in await ... }`.

Methods to convert (and their current line numbers):

| Method | Line | Notes |
|--------|------|-------|
| `closeCurrentPane` | 319 | tmux path — already uses `CloseConfirmation`, just gains activity query + async |
| `closeCurrentPaneNativePTY` | 352 | native PTY path — currently skips confirmation entirely |
| `removeTab(_ tab:)` | 237 | tab X button entry; currently skips confirmation |
| `removeTab(_ tab:in:)` | 249 | also skips |
| `removeTabNativePTY` | 269 | called by `removeTab` and by `closeCurrentPaneNativePTY` cascade |
| `removeProject` | (locate) | both tmux and native paths |
| `removeProjectNativePTY` | (locate) | called by last-tab cascade |

Cascading closes (last pane → close tab → close project) currently route through these methods recursively. Each level re-evaluates with its own `confirmClose*` setting, *not* the deepest target's setting. Closing a pane that triggers tab close that triggers project close fires at most one prompt — whichever level matches the mode.

Implementation pattern at each call site:

```swift
func closeCurrentPane() {
    Task { @MainActor in
        await closeCurrentPaneAsync()
    }
}

@MainActor
private func closeCurrentPaneAsync() async {
    // ...resolve project/tab/activePane as today...
    let activities = await activityPort.query(paneIds: tab.panes.map(\.id))
    let decision = CloseConfirmation.evaluate(
        project: project, tab: tab, activePane: activePane,
        activities: activities,
        confirmCloseTab: store.tabConfirmMode,
        confirmCloseProject: store.projectConfirmMode
    )
    if let alert = decision.alert,
       let window = NSApp.mainWindow,
       await !CloseConfirmation.present(alert, in: window) {
        return
    }
    // ...proceed with existing close logic...
}
```

## Settings

### Config schema

`Sources/Infrastructure/Config/ForgeConfig.swift`:

```swift
struct GeneralSettings: Codable {
    // ...existing...
    var warnOnCloseTab: Bool?           // LEGACY — migrated on load
    var warnOnCloseProject: Bool?       // LEGACY — migrated on load
    var confirmCloseTab: String?        // "never" | "whenActive" | "always"
    var confirmCloseProject: String?    // "never" | "whenActive" | "always"
}
```

Migration in `ForgeConfig.load()`, mirroring the existing `migrateNotificationSettings()` pattern:

```swift
mutating func migrateCloseConfirmSettings() {
    if general?.confirmCloseTab == nil {
        general?.confirmCloseTab = (general?.warnOnCloseTab == true) ? "always" : "whenActive"
        general?.warnOnCloseTab = nil
    }
    if general?.confirmCloseProject == nil {
        general?.confirmCloseProject = (general?.warnOnCloseProject == true) ? "always" : "whenActive"
        general?.warnOnCloseProject = nil
    }
}
```

### Settings UI

`Sources/Features/Settings/GeneralSettingsPane.swift` — replace the two boolean toggles in the Confirmations section with pickers:

```swift
Section("Confirmations") {
    Toggle("Warn before closing Forge", isOn: ...)
    Picker("Confirm project close", selection: bindingForProject) {
        Text("Never").tag("never")
        Text("When a process is running").tag("whenActive")
        Text("Always").tag("always")
    }
    Picker("Confirm tab close", selection: bindingForTab) {
        Text("Never").tag("never")
        Text("When a process is running").tag("whenActive")
        Text("Always").tag("always")
    }
}
```

No new UI for pane close — it always prompts when a process is active, never otherwise. (If users complain, add a third picker later.)

## Testing Strategy

### Core (TDD, Swift Testing in `ForgeTests`)

`CloseConfirmationTests`:

- **Mode = .never** → `alert == nil` regardless of activity.
- **Mode = .whenActive, no activity** → `alert == nil`.
- **Mode = .whenActive, one active pane** → alert message contains the command basename.
- **Mode = .whenActive, multiple actives** → alert message contains first command + "(and N other process[es])".
- **Mode = .always, no activity** → alert with idle-but-always-warn copy.
- **Mode = .always, with activity** → alert with active copy (active wins over idle).
- **Target picking** (multi-pane vs multi-tab vs project) — preserved from existing tests.

### Integration

`PaneActivityPortTests`:

- **TmuxActivityAdapter**: synthesise a `Workspace` with one running and one idle pane, assert correct `PaneActivity` shape.
- **DaemonActivityAdapter**: requires a running forged. Spawn a known-running command via Ghostty surface, query, assert `isActive == true` and `command` matches. Then send the command SIGTERM, re-query, assert `isActive == false`. Marked `.serialized` since they share the daemon.

### Manual / verification

`make dev`, then:

1. Open a tab, run `claude`. `cmd+w` → sheet appears with "Closing this tab will terminate **claude**." Cancel default. ✓
2. At a shell prompt. `cmd+w` → no prompt. ✓
3. Toggle `confirmCloseTab` to `.always` in settings. `cmd+w` at shell prompt → always-warn copy. ✓
4. Run `claude &` (backgrounded). `cmd+w` → no prompt (foreground = shell). ✓
5. Tab with two panes; one runs `vim`, other at prompt. Close the tab → sheet names `vim`. ✓
6. Tab with two panes both running (claude + vim). Close the tab → "Closing this tab will terminate **claude** (and 1 other process)." ✓
7. Kill `forged` while Forge is running; `cmd+w` on a tab running claude → no prompt (fail-open), `[daemon]` error in `/tmp/forge.log`. ✓ (Recover by restarting Forge.)
8. Toggle to `.never`. All closes proceed without prompt. ✓

## Out of Scope

- **Tab-level visual indicator** for "process running" (a new attention-dot variant). Would reduce confirmation friction long-term. File as follow-up.
- **`KERN_PROCARGS2` argv extraction** to show `node script.js` instead of bare `node`. TODO comment in `procCommandName`.
- **Upgrading tmux mode's command detection** from string-match-against-shell-list to a proper `tcgetpgrp`-based check. The string heuristic is good enough and lives entirely in `PaneStatus.from(command:)`.
- **`confirmClosePane` 3-state picker.** Pane close always prompts when active, never otherwise. Add later if users ask.
- **Undo-toast pattern** instead of modal sheet. Worth a future UX exploration but inconsistent with current modal-based confirmations elsewhere in Forge.

## File-by-File Changes

```
Sources/Core/Ports/PaneActivityPort.swift         NEW
Sources/Core/CloseConfirmation.swift              EDIT  (signature + alert construction)
Sources/Features/Shared/CloseConfirmation.swift   EDIT  (async sheet presentation)
Sources/Infrastructure/Process/DaemonActivityAdapter.swift   NEW
Sources/Infrastructure/Tmux/TmuxActivityAdapter.swift        NEW
Sources/Daemon/Forged.swift                       EDIT  (pgid storage, is_active op, procCommandName)
Sources/Infrastructure/Process/DaemonAdapter.swift           EDIT  (extend protocol or add adjacent struct)
Sources/Infrastructure/Config/ForgeConfig.swift   EDIT  (new fields + migration)
Sources/Features/Settings/GeneralSettingsPane.swift          EDIT  (pickers)
Sources/WorkspaceController+Actions.swift         EDIT  (~7 close methods → async; wire activity port)
Sources/ForgeApp.swift                            EDIT  (composition root: wire correct adapter)
Tests/ForgeTests/CloseConfirmationTests.swift     EDIT  (new cases for activities/modes)
Tests/ForgeTests/PaneActivityPortTests.swift      NEW
```

All under the 300-line file limit.
