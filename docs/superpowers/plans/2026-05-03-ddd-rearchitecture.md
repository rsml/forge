# DDD Re-Architecture + UX Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-architect Forge into a clean domain-driven design with ports/adapters, fix sidebar chevron toggle UX, and fix horizontal tab switching.

**Architecture:** Hexagonal (ports & adapters). Domain layer defines protocols for tmux interaction. Adapters implement those protocols. UI layer consumes domain state. Each layer has a clear boundary and single responsibility per file.

**Tech Stack:** Swift 6, SwiftUI, @Observable, SwiftTerm (stopgap)

---

## Target File Structure

```
Sources/
  ForgeApp.swift                          # App entry point, wiring

  Domain/
    Models/
      Session.swift                       # TmuxSession model
      Window.swift                        # TmuxWindow model
      Pane.swift                          # TmuxPane model + PaneStatus enum
      Workspace.swift                     # Workspace state (all sessions, active IDs)
    Ports/
      TmuxPort.swift                      # Protocol: what the app needs from tmux

  Adapters/
    Tmux/
      TmuxAdapter.swift                   # Implements TmuxPort via real tmux CLI
      TmuxCommandRunner.swift             # Low-level Process execution
      TmuxControlMode.swift               # Control mode connection + event parsing
      TmuxStateParser.swift               # Parse tmux format strings into domain models
    Config/
      ForgeConfig.swift                    # ~/.config/forge/config.json persistence
    Logging/
      ForgeLog.swift                       # File-based logger

  App/
    WorkspaceController.swift             # @Observable — orchestrates domain + adapters, single source of UI state
    Views/
      MainView.swift                      # NavigationSplitView shell
      Sidebar/
        SidebarView.swift                 # Session list with chevron toggles
        SessionRow.swift                  # Single session row + expandable children
        StatusDot.swift                   # Colored status indicator
      Detail/
        SessionDetailView.swift           # Horizontal tab bar + terminal area
        WindowTabBar.swift                # Horizontal tabs (tmux windows)
        TerminalArea.swift                # Terminal rendering container
        ForgeTerminalView.swift           # SwiftTerm NSViewRepresentable wrapper
      Picker/
        ProjectPickerView.swift           # Cmd+O project picker
```

## What Changes

1. **Sidebar UX**: Replace hover-to-expand with click-chevron toggle (right chevron collapsed, down chevron expanded, animated rotation)
2. **Tab switching**: Fix horizontal tabs so clicking actually changes the displayed terminal/pane
3. **Architecture**: Split monolithic files into focused domain/adapter/UI layers
4. **No behavior changes** beyond the two UX fixes — pure restructure + fixes

---

### Task 1: Create Domain Layer

**Files:**
- Create: `Sources/Domain/Models/Session.swift`
- Create: `Sources/Domain/Models/Window.swift`
- Create: `Sources/Domain/Models/Pane.swift`
- Create: `Sources/Domain/Models/Workspace.swift`
- Create: `Sources/Domain/Ports/TmuxPort.swift`

- [ ] **Step 1: Create Session model**

```swift
// Sources/Domain/Models/Session.swift
import Foundation
import Observation

@Observable
@MainActor
final class Session: Identifiable {
    let id: String
    var name: String
    var windowCount: Int
    var attached: Bool
    var path: String?
    var windows: [Window] = []

    var aggregateStatus: PaneStatus {
        let all = windows.flatMap { $0.panes.map(\.status) }
        if all.contains(.needsAttention) { return .needsAttention }
        if all.contains(.error) { return .error }
        if all.contains(.running) { return .running }
        return .idle
    }

    init(id: String, name: String, windowCount: Int = 0, attached: Bool = false, path: String? = nil) {
        self.id = id
        self.name = name
        self.windowCount = windowCount
        self.attached = attached
        self.path = path
    }
}
```

- [ ] **Step 2: Create Window model**

```swift
// Sources/Domain/Models/Window.swift
import Foundation
import Observation

@Observable
@MainActor
final class Window: Identifiable {
    let id: String
    let sessionId: String
    var index: Int
    var name: String
    var active: Bool
    var panes: [Pane] = []

    init(id: String, sessionId: String, index: Int, name: String, active: Bool = false) {
        self.id = id
        self.sessionId = sessionId
        self.index = index
        self.name = name
        self.active = active
    }
}
```

- [ ] **Step 3: Create Pane model + PaneStatus**

```swift
// Sources/Domain/Models/Pane.swift
import Foundation
import Observation

enum PaneStatus: String {
    case idle, running, needsAttention, error

    static func from(command: String) -> PaneStatus {
        let lower = command.lowercased()
        if lower.isEmpty || lower == "zsh" || lower == "bash" || lower == "fish" {
            return .idle
        }
        return .running
    }
}

@Observable
@MainActor
final class Pane: Identifiable {
    let id: String
    let windowId: String
    var index: Int
    var active: Bool
    var currentCommand: String
    var currentPath: String
    var width: Int
    var height: Int
    var pid: Int
    var status: PaneStatus
    var hasBell: Bool = false

    init(id: String, windowId: String, index: Int, active: Bool = false,
         currentCommand: String = "", currentPath: String = "",
         width: Int = 80, height: Int = 24, pid: Int = 0) {
        self.id = id
        self.windowId = windowId
        self.index = index
        self.active = active
        self.currentCommand = currentCommand
        self.currentPath = currentPath
        self.width = width
        self.height = height
        self.pid = pid
        self.status = PaneStatus.from(command: currentCommand)
    }
}
```

- [ ] **Step 4: Create Workspace state container**

```swift
// Sources/Domain/Models/Workspace.swift
import Foundation
import Observation

@Observable
@MainActor
final class Workspace {
    var sessions: [Session] = []
    var activeSessionId: String?
    var activeWindowId: String?
    var activePaneId: String?
    var connected: Bool = false

    var activeSession: Session? {
        sessions.first { $0.id == activeSessionId }
    }

    func session(byId id: String) -> Session? {
        sessions.first { $0.id == id }
    }
}
```

- [ ] **Step 5: Create TmuxPort protocol**

```swift
// Sources/Domain/Ports/TmuxPort.swift
import Foundation

struct SessionInfo {
    let id: String
    let name: String
    let windowCount: Int
    let attached: Bool
    let path: String?
}

struct WindowInfo {
    let id: String
    let sessionId: String
    let index: Int
    let name: String
    let active: Bool
    let paneCount: Int
}

struct PaneInfo {
    let id: String
    let windowId: String
    let index: Int
    let active: Bool
    let currentCommand: String
    let currentPath: String
    let width: Int
    let height: Int
    let pid: Int
}

@MainActor
protocol TmuxPort {
    func listSessions() async -> [SessionInfo]
    func listWindows(session: String) async -> [WindowInfo]
    func listPanes(window: String) async -> [PaneInfo]

    func newSession(name: String, path: String) async
    func killSession(name: String) async
    func renameSession(target: String, newName: String) async

    func newWindow(session: String, path: String?) async
    func killWindow(id: String) async
    func selectWindow(id: String) async
    func renameWindow(id: String, newName: String) async

    func selectPane(id: String) async
    func switchClient(session: String) async

    func startControlMode(onEvent: @escaping (String) -> Void)
    func stopControlMode()
}
```

- [ ] **Step 6: Commit domain layer**

```bash
git add Sources/Domain/
git commit -m "feat: add domain layer — models, workspace, and TmuxPort protocol"
```

---

### Task 2: Create Adapters Layer

**Files:**
- Create: `Sources/Adapters/Tmux/TmuxCommandRunner.swift`
- Create: `Sources/Adapters/Tmux/TmuxStateParser.swift`
- Create: `Sources/Adapters/Tmux/TmuxControlMode.swift`
- Create: `Sources/Adapters/Tmux/TmuxAdapter.swift`
- Create: `Sources/Adapters/Logging/ForgeLog.swift`
- Create: `Sources/Adapters/Config/ForgeConfig.swift`

- [ ] **Step 1: Create TmuxCommandRunner** (extracted from TmuxController.run)

```swift
// Sources/Adapters/Tmux/TmuxCommandRunner.swift
import Foundation

/// Runs tmux CLI commands off the main thread
struct TmuxCommandRunner: Sendable {
    let tmuxPath: String

    init() {
        self.tmuxPath = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
            .first { FileManager.default.fileExists(atPath: $0) } ?? "tmux"
    }

    func run(_ args: [String]) async -> String? {
        let path = tmuxPath
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                let pipe = Pipe()
                let errPipe = Pipe()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = args
                process.standardOutput = pipe
                process.standardError = errPipe

                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    if process.terminationStatus != 0 {
                        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                        let errMsg = String(data: errData, encoding: .utf8) ?? ""
                        ForgeLog.log("[tmux] \(args.joined(separator: " ")) failed: \(errMsg)")
                    }

                    continuation.resume(returning: output)
                } catch {
                    ForgeLog.log("[tmux] exec error: \(error)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func run(_ args: String...) async -> String? {
        await run(args)
    }
}
```

- [ ] **Step 2: Create TmuxStateParser** (extracted parsing logic)

```swift
// Sources/Adapters/Tmux/TmuxStateParser.swift
import Foundation

/// Parses tmux format string output into domain info structs
enum TmuxStateParser {
    static func parseSessions(_ output: String) -> [SessionInfo] {
        output.split(separator: "\n").compactMap { line in
            let p = line.split(separator: "\t", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
            guard p.count >= 5 else { return nil }
            return SessionInfo(id: p[0], name: p[1], windowCount: Int(p[2]) ?? 0,
                             attached: p[3] != "0", path: p[4].isEmpty ? nil : p[4])
        }
    }

    static func parseWindows(_ output: String) -> [WindowInfo] {
        output.split(separator: "\n").compactMap { line in
            let p = line.split(separator: "\t", maxSplits: 5, omittingEmptySubsequences: false).map(String.init)
            guard p.count >= 6 else { return nil }
            return WindowInfo(id: p[0], sessionId: p[1], index: Int(p[2]) ?? 0,
                            name: p[3], active: p[4] != "0", paneCount: Int(p[5]) ?? 0)
        }
    }

    static func parsePanes(_ output: String) -> [PaneInfo] {
        output.split(separator: "\n").compactMap { line in
            let p = line.split(separator: "\t", maxSplits: 8, omittingEmptySubsequences: false).map(String.init)
            guard p.count >= 9 else { return nil }
            return PaneInfo(id: p[0], windowId: p[1], index: Int(p[2]) ?? 0,
                          active: p[3] != "0", currentCommand: p[4], currentPath: p[5],
                          width: Int(p[6]) ?? 80, height: Int(p[7]) ?? 24, pid: Int(p[8]) ?? 0)
        }
    }

    static let sessionFormat = "#{session_id}\t#{session_name}\t#{session_windows}\t#{session_attached}\t#{session_path}"
    static let windowFormat = "#{window_id}\t#{session_id}\t#{window_index}\t#{window_name}\t#{window_active}\t#{window_panes}"
    static let paneFormat = "#{pane_id}\t#{window_id}\t#{pane_index}\t#{pane_active}\t#{pane_current_command}\t#{pane_current_path}\t#{pane_width}\t#{pane_height}\t#{pane_pid}"
}
```

- [ ] **Step 3: Create TmuxControlMode** (extracted control mode logic)

```swift
// Sources/Adapters/Tmux/TmuxControlMode.swift
import Foundation

/// Manages a tmux control mode (-CC) connection for push-based state updates
final class TmuxControlMode: @unchecked Sendable {
    private var process: Process?
    private var stdin: FileHandle?
    private var buffer = ""
    private let tmuxPath: String
    private var onEvent: ((String) -> Void)?

    init(tmuxPath: String) {
        self.tmuxPath = tmuxPath
    }

    func start(onEvent: @escaping (String) -> Void) {
        self.onEvent = onEvent

        let process = Process()
        let stdoutPipe = Pipe()
        let stdinPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: tmuxPath)
        process.arguments = ["-C", "attach"]
        process.standardOutput = stdoutPipe
        process.standardInput = stdinPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            ForgeLog.log("[control] Started control mode")
        } catch {
            ForgeLog.log("[control] Failed to start: \(error)")
            return
        }

        self.process = process
        self.stdin = stdinPipe.fileHandleForWriting

        let handle = stdoutPipe.fileHandleForReading
        Thread.detachNewThread { [weak self] in
            while let self, self.process != nil {
                let data = handle.availableData
                if data.isEmpty { break }
                if let text = String(data: data, encoding: .utf8) {
                    self.handleOutput(text)
                }
            }
            ForgeLog.log("[control] Reader thread exited")
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        stdin = nil
    }

    func send(_ command: String) {
        guard let stdin else {
            ForgeLog.log("[control] No stdin for command: \(command)")
            return
        }
        if let data = (command + "\n").data(using: .utf8) {
            stdin.write(data)
        }
    }

    private func handleOutput(_ text: String) {
        buffer += text
        while let idx = buffer.firstIndex(of: "\n") {
            let line = String(buffer[buffer.startIndex..<idx])
            buffer = String(buffer[buffer.index(after: idx)...])
            if line.hasPrefix("%") {
                let event = line.split(separator: " ", maxSplits: 1).first.map(String.init) ?? line
                onEvent?(event)
            }
        }
    }
}
```

- [ ] **Step 4: Create TmuxAdapter** (implements TmuxPort)

```swift
// Sources/Adapters/Tmux/TmuxAdapter.swift
import Foundation

/// Concrete implementation of TmuxPort using the tmux CLI + control mode
@MainActor
final class TmuxAdapter: TmuxPort {
    private let runner = TmuxCommandRunner()
    private lazy var controlMode = TmuxControlMode(tmuxPath: runner.tmuxPath)

    func listSessions() async -> [SessionInfo] {
        guard let output = await runner.run("list-sessions", "-F", TmuxStateParser.sessionFormat),
              !output.isEmpty else { return [] }
        return TmuxStateParser.parseSessions(output)
    }

    func listWindows(session: String) async -> [WindowInfo] {
        guard let output = await runner.run("list-windows", "-t", session, "-F", TmuxStateParser.windowFormat),
              !output.isEmpty else { return [] }
        return TmuxStateParser.parseWindows(output)
    }

    func listPanes(window: String) async -> [PaneInfo] {
        guard let output = await runner.run("list-panes", "-t", window, "-F", TmuxStateParser.paneFormat),
              !output.isEmpty else { return [] }
        return TmuxStateParser.parsePanes(output)
    }

    func newSession(name: String, path: String) async {
        _ = await runner.run("new-session", "-d", "-s", name, "-c", path)
    }

    func killSession(name: String) async {
        controlMode.send("kill-session -t \(name)")
    }

    func renameSession(target: String, newName: String) async {
        controlMode.send("rename-session -t \(target) \(newName)")
    }

    func newWindow(session: String, path: String?) async {
        var cmd = "new-window -t \(session)"
        if let path { cmd += " -c \(path)" }
        controlMode.send(cmd)
    }

    func killWindow(id: String) async {
        controlMode.send("kill-window -t \(id)")
    }

    func selectWindow(id: String) async {
        controlMode.send("select-window -t \(id)")
    }

    func renameWindow(id: String, newName: String) async {
        controlMode.send("rename-window -t \(id) \(newName)")
    }

    func selectPane(id: String) async {
        controlMode.send("select-pane -t \(id)")
    }

    func switchClient(session: String) async {
        controlMode.send("switch-client -t \(session)")
    }

    func startControlMode(onEvent: @escaping (String) -> Void) {
        controlMode.start(onEvent: onEvent)
    }

    func stopControlMode() {
        controlMode.stop()
    }
}
```

- [ ] **Step 5: Move ForgeLog and ForgeConfig to Adapters**

Extract `ForgeLog` from TmuxController.swift into `Sources/Adapters/Logging/ForgeLog.swift`.
Extract `ForgeConfig` from ProjectPickerView.swift into `Sources/Adapters/Config/ForgeConfig.swift`.

- [ ] **Step 6: Commit adapters layer**

```bash
git add Sources/Adapters/
git commit -m "feat: add adapters layer — TmuxAdapter, command runner, control mode, parser"
```

---

### Task 3: Create WorkspaceController + Rewire App

**Files:**
- Create: `Sources/App/WorkspaceController.swift`
- Modify: `Sources/ForgeApp.swift`

- [ ] **Step 1: Create WorkspaceController** (replaces TmuxController as the single UI-facing observable)

```swift
// Sources/App/WorkspaceController.swift
import Foundation
import Observation

@Observable
@MainActor
final class WorkspaceController {
    let workspace = Workspace()
    private let tmux: TmuxPort
    private var refreshTask: Task<Void, Never>?

    init(tmux: TmuxPort) {
        self.tmux = tmux
    }

    func connect() {
        Task {
            ForgeLog.log("[app] Connecting...")
            await ensureServer()
            await refresh()

            tmux.startControlMode { [weak self] event in
                Task { @MainActor in
                    self?.handleEvent(event)
                }
            }

            startPeriodicRefresh()
            workspace.connected = true
            ForgeLog.log("[app] Connected. \(workspace.sessions.count) sessions found.")
        }
    }

    func disconnect() {
        refreshTask?.cancel()
        tmux.stopControlMode()
    }

    // MARK: - State Refresh

    func refresh() async {
        let sessionInfos = await tmux.listSessions()
        mergeSessionState(sessionInfos)

        for session in workspace.sessions {
            let windowInfos = await tmux.listWindows(session: session.name)
            mergeWindowState(session: session, windowInfos)

            for window in session.windows {
                let paneInfos = await tmux.listPanes(window: window.id)
                mergePaneState(window: window, paneInfos)
            }
        }
    }

    // MARK: - Actions

    func selectSession(_ session: Session) {
        workspace.activeSessionId = session.id
        if let window = session.windows.first(where: { $0.active }) ?? session.windows.first {
            workspace.activeWindowId = window.id
        }
        Task { await tmux.switchClient(session: session.name) }
    }

    func selectWindow(_ window: Window) {
        workspace.activeWindowId = window.id
        Task { await tmux.selectWindow(id: window.id) }
    }

    func addSession(name: String, path: String) async {
        await tmux.newSession(name: name, path: path)
        await refresh()
        if let session = workspace.sessions.first(where: { $0.name == name }) {
            selectSession(session)
        }
    }

    func removeSession(_ session: Session) {
        Task { await tmux.killSession(name: session.name) }
    }

    func addWindow(in session: Session) {
        Task { await tmux.newWindow(session: session.name, path: session.path) }
    }

    func removeWindow(_ window: Window) {
        Task { await tmux.killWindow(id: window.id) }
    }

    func renameSession(_ session: Session, to name: String) {
        Task { await tmux.renameSession(target: session.name, newName: name) }
    }

    func renameWindow(_ window: Window, to name: String) {
        Task { await tmux.renameWindow(id: window.id, newName: name) }
    }

    // MARK: - Private

    private func ensureServer() async {
        let sessions = await tmux.listSessions()
        if sessions.isEmpty {
            await tmux.newSession(name: "forge-default", path: NSHomeDirectory())
        }
    }

    private func handleEvent(_ event: String) {
        ForgeLog.log("[control] \(event)")
        Task { await refresh() }
    }

    private func startPeriodicRefresh() {
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await refresh()
            }
        }
    }

    private func mergeSessionState(_ infos: [SessionInfo]) {
        var updated: [Session] = []
        for info in infos {
            if let existing = workspace.session(byId: info.id) {
                existing.name = info.name
                existing.windowCount = info.windowCount
                existing.attached = info.attached
                existing.path = info.path
                updated.append(existing)
            } else {
                updated.append(Session(id: info.id, name: info.name, windowCount: info.windowCount,
                                      attached: info.attached, path: info.path))
            }
        }
        workspace.sessions = updated
        if workspace.activeSessionId == nil, let first = workspace.sessions.first {
            workspace.activeSessionId = first.id
        }
    }

    private func mergeWindowState(session: Session, _ infos: [WindowInfo]) {
        var updated: [Window] = []
        for info in infos {
            if let existing = session.windows.first(where: { $0.id == info.id }) {
                existing.index = info.index
                existing.name = info.name
                existing.active = info.active
                updated.append(existing)
            } else {
                updated.append(Window(id: info.id, sessionId: info.sessionId,
                                     index: info.index, name: info.name, active: info.active))
            }
        }
        session.windows = updated
        if let active = infos.first(where: { $0.active }) {
            if session.id == workspace.activeSessionId {
                workspace.activeWindowId = active.id
            }
        }
    }

    private func mergePaneState(window: Window, _ infos: [PaneInfo]) {
        var updated: [Pane] = []
        for info in infos {
            if let existing = window.panes.first(where: { $0.id == info.id }) {
                existing.index = info.index
                existing.active = info.active
                existing.currentCommand = info.currentCommand
                existing.currentPath = info.currentPath
                existing.width = info.width
                existing.height = info.height
                existing.pid = info.pid
                existing.status = existing.hasBell ? .needsAttention : PaneStatus.from(command: info.currentCommand)
                updated.append(existing)
            } else {
                updated.append(Pane(id: info.id, windowId: info.windowId, index: info.index,
                                   active: info.active, currentCommand: info.currentCommand,
                                   currentPath: info.currentPath, width: info.width,
                                   height: info.height, pid: info.pid))
            }
        }
        window.panes = updated
        if let active = infos.first(where: { $0.active }) {
            workspace.activePaneId = active.id
        }
    }
}
```

- [ ] **Step 2: Update ForgeApp.swift** to wire WorkspaceController with TmuxAdapter

```swift
// Sources/ForgeApp.swift — replace TmuxController with WorkspaceController
@State private var controller = WorkspaceController(tmux: TmuxAdapter())
// Pass into environment: .environment(controller)
```

- [ ] **Step 3: Commit**

```bash
git add Sources/App/WorkspaceController.swift Sources/ForgeApp.swift
git commit -m "feat: add WorkspaceController, wire domain to adapters"
```

---

### Task 4: Rewrite Sidebar with Chevron Toggle

**Files:**
- Create: `Sources/App/Views/Sidebar/SidebarView.swift`
- Create: `Sources/App/Views/Sidebar/SessionRow.swift`
- Create: `Sources/App/Views/Sidebar/StatusDot.swift`

- [ ] **Step 1: Create SessionRow with chevron toggle**

Click-to-toggle chevron: right chevron (collapsed) rotates 90deg clockwise to become down chevron (expanded). Click again to rotate back.

```swift
// Sources/App/Views/Sidebar/SessionRow.swift
struct SessionRow: View {
    var session: Session
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                // Chevron toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .buttonStyle(.plain)
                .frame(width: 16)

                StatusDot(status: session.aggregateStatus)

                Text(session.name)
                    .font(.system(.body, weight: .medium))
                    .lineLimit(1)

                Spacer()

                if session.windowCount > 1 {
                    Text("\(session.windowCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(session.windows) { window in
                        // ... window/pane rows (same as before)
                    }
                }
                .padding(.leading, 28)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 2)
    }
}
```

- [ ] **Step 2: Create SidebarView with expansion state dictionary**

```swift
// Sources/App/Views/Sidebar/SidebarView.swift
@State private var expandedSessions: Set<String> = []

// In ForEach:
SessionRow(
    session: session,
    isExpanded: Binding(
        get: { expandedSessions.contains(session.id) },
        set: { if $0 { expandedSessions.insert(session.id) } else { expandedSessions.remove(session.id) } }
    )
)
```

- [ ] **Step 3: Create StatusDot** (extract to own file)

- [ ] **Step 4: Commit**

```bash
git add Sources/App/Views/Sidebar/
git commit -m "feat: sidebar with click-to-expand chevron toggle"
```

---

### Task 5: Fix Horizontal Tab Switching

**Files:**
- Create: `Sources/App/Views/Detail/SessionDetailView.swift`
- Create: `Sources/App/Views/Detail/WindowTabBar.swift`
- Create: `Sources/App/Views/Detail/TerminalArea.swift`
- Create: `Sources/App/Views/Detail/ForgeTerminalView.swift`

The current bug: clicking a horizontal tab calls `tmux.selectWindow()` which sends a tmux command, but the terminal view is keyed on `sessionName` not `windowId`. When the active window changes, the terminal view doesn't re-create because the session hasn't changed.

- [ ] **Step 1: Fix TerminalArea to key on window ID**

The `ForgeTerminalView` must be keyed on the active window so SwiftUI recreates it when tabs switch:

```swift
// In SessionDetailView, use .id() to force recreation:
ForgeTerminalView(sessionName: session.name)
    .id(controller.workspace.activeWindowId) // forces new terminal on tab switch
```

- [ ] **Step 2: Update ForgeTerminalView** to attach to specific window

Instead of `tmux attach-session -t sessionName`, use the session name (tmux will show the active window). The `.id()` modifier handles recreation.

- [ ] **Step 3: Commit**

```bash
git add Sources/App/Views/Detail/
git commit -m "fix: horizontal tab switching recreates terminal view"
```

---

### Task 6: Delete Old Files + Update Package.swift

**Files:**
- Delete: `Sources/Models/TmuxController.swift`
- Delete: `Sources/Models/TmuxState.swift`
- Delete: `Sources/Views/` (all old view files)

- [ ] **Step 1: Delete old files**

```bash
rm -rf Sources/Models/ Sources/Views/
```

- [ ] **Step 2: Update Package.swift** path if needed (should still work with `path: "Sources"`)

- [ ] **Step 3: Build and verify**

```bash
swift build
```

- [ ] **Step 4: Run and test**

Open Forge, verify:
- Sidebar shows sessions with chevron toggles
- Clicking chevron expands/collapses (no hover)
- Clicking horizontal tabs switches the terminal view
- Control mode events update UI

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "refactor: complete DDD re-architecture, remove old files"
```
