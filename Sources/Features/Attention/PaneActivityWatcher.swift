import Foundation
import ForgeCore

/// Watches PTY output and foreground-process activity in native PTY mode and
/// emits AttentionEvents. The tmux equivalent of this lives in TmuxSyncEngine
/// (bell detection from control-mode events, content scanning during the
/// refresh cycle, silence/activity tracking). Native PTY has no refresh
/// cycle — output flows continuously through Ghostty surfaces — so detection
/// is event-driven instead.
///
/// Three sources:
/// - `processOutput(paneId:data:)`: PTY output bytes from GhosttyRenderer's
///   io_read_cb (EXEC) and read thread (EXTERNAL_FD). Scans for BEL bytes and
///   runs ContentDetector against a recent-output buffer.
/// - `start()` kicks off a 2s poll loop against PaneActivityPort. On an
///   active→inactive transition, emits a commandCompleted event (the user's
///   long-running command finished and the shell is back).
///
/// Mutates `pane.terminalState.hasBell` / `pane.terminalState.hasContentMatch` to mirror tmux behavior so
/// the sidebar dots show up; downstream wiring (AttentionManager,
/// notification dispatch) is the caller's responsibility via `onEvent`.
@MainActor
final class PaneActivityWatcher {
    private let workspace: Workspace
    private let activity: any PaneActivityPort
    private let config: ForgeConfigStore
    private let contentDetector = ContentDetector()
    private var outputBuffers: [String: Data] = [:]
    private var lastActiveState: [String: Bool] = [:]
    private var pollTask: Task<Void, Never>?
    /// Trailing-edge debounce — fires `silenceWaitingThreshold` seconds after
    /// the last output chunk from an AI-agent foreground process and flips the
    /// pane to `isSilentWaiting = true`. Cancelled on every new output chunk.
    private var silenceTimers: [String: DispatchWorkItem] = [:]

    /// Per-pane buffer cap. Holds roughly the last screen-ish of output —
    /// enough for ContentDetector to find prompts near the bottom without
    /// holding every byte the shell has ever printed.
    private let maxBufferSize = 8192

    /// Fired when detection produces an event. Callers route to AttentionManager
    /// + sendAttentionNotification.
    var onEvent: ((AttentionEvent) -> Void)?

    /// Fired when the foreground process transitions back to the pane's shell.
    /// The controller uses this to pop the Kitty keyboard stack so the shell
    /// doesn't keep seeing Kitty-encoded keypresses left over from a TUI
    /// (Claude Code etc.) that exited without resetting the terminal.
    var onShellResumed: ((_ paneId: String) -> Void)?

    init(workspace: Workspace, activity: any PaneActivityPort, config: ForgeConfigStore) {
        self.workspace = workspace
        self.activity = activity
        self.config = config
    }

    func start() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                await self?.pollActivity()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Feed PTY output bytes for detection. Safe to call from any thread —
    /// the caller (Ghostty's I/O thread or the EXTERNAL_FD read thread) hops
    /// to main via DispatchQueue before invoking the renderer's onOutput.
    func processOutput(paneId: String, data: Data) {
        // Attention signals — standalone BEL or OSC 777 notify. Claude Code
        // 2.1.141+ emits `ESC]777;notify;Claude Code;Claude is waiting for your
        // input BEL` when it wants the user back. Other modern TUIs use the
        // same OSC 777 protocol. OSC string-terminator BELs (e.g. OSC 133
        // semantic prompts emitted on every shell prompt redraw) are ignored.
        if BellDetector.containsAttentionSignal(data),
           let found = workspace.findTab(byPaneId: paneId) {
            for pane in found.tab.panes { pane.terminalState?.hasBell = true }
            onEvent?(.bell(tabUUID: found.tab.uuid))
        }

        // Append to buffer, trim to last N bytes, run content detector.
        var buf = outputBuffers[paneId] ?? Data()
        buf.append(data)
        if buf.count > maxBufferSize {
            buf = buf.suffix(maxBufferSize)
        }
        outputBuffers[paneId] = buf

        // Track when this pane last produced output. The poll loop reads this
        // to drive silence-based "AI agent waiting" detection.
        if let found = workspace.findPane(byId: paneId) {
            found.pane.terminalState?.lastOutputAt = Date()
            // Fresh output cancels the silent-waiting state; if the agent
            // goes quiet again, the poll loop will re-set it.
            found.pane.terminalState?.isSilentWaiting = false
        }

        // Trailing-edge debounce for snappier UI: fire ~silenceThreshold after
        // the last byte stops, independent of the 2s poll cadence. The poll
        // loop catches the cases this debounce misses (e.g. zero live output
        // on reconnect — claude is already idle from before Forge attached).
        silenceTimers[paneId]?.cancel()
        if let found = workspace.findPane(byId: paneId),
           AttentionPolicy.isAIAgent(found.pane.terminalState?.currentCommand ?? "") {
            let work = DispatchWorkItem { [weak self] in
                guard let self,
                      let found = self.workspace.findPane(byId: paneId),
                      AttentionPolicy.isAIAgent(found.pane.terminalState?.currentCommand ?? "")
                else { return }
                found.pane.terminalState?.isSilentWaiting = true
                self.onEvent?(.contentMatch(tabUUID: found.tab.uuid))
            }
            silenceTimers[paneId] = work
            DispatchQueue.main.asyncAfter(
                deadline: .now() + AttentionPolicy.silenceWaitingThreshold,
                execute: work
            )
        }

        guard let content = String(data: buf, encoding: .utf8) else { return }
        let patterns = ContentDetector.defaultPatterns
            + (config.config.stackView?.contentPatterns ?? [])
        let matched = contentDetector.scan(paneId: paneId, content: content, patterns: patterns)

        if matched {
            ForgeLog.log("[attention] Content match in pane \(paneId): \(content.suffix(80))")
            if let found = workspace.findPane(byId: paneId) {
                found.pane.terminalState?.hasContentMatch = true
                onEvent?(.contentMatch(tabUUID: found.tab.uuid))
            }
        } else if !contentDetector.isActive(paneId: paneId) {
            // Content no longer matches — clear the flag if it was set.
            if let found = workspace.findPane(byId: paneId), found.pane.terminalState?.hasContentMatch == true {
                found.pane.terminalState?.hasContentMatch = false
            }
        }
    }

    func paneRemoved(_ paneId: String) {
        outputBuffers.removeValue(forKey: paneId)
        lastActiveState.removeValue(forKey: paneId)
        contentDetector.paneRemoved(paneId)
    }

    private func pollActivity() async {
        let paneIds = workspace.projects.flatMap { $0.tabs.flatMap { $0.panes.map(\.id) } }
        guard !paneIds.isEmpty else { return }
        let results = await activity.query(paneIds: paneIds)
        for result in results {
            let wasActive = lastActiveState[result.paneId] ?? false
            lastActiveState[result.paneId] = result.isActive

            // Keep model in sync with daemon's view of the foreground process.
            // Without this, currentCommand stays "" forever → status stays .idle
            // → needsAttention stays true regardless of what's actually running.
            if let found = workspace.findPane(byId: result.paneId) {
                found.pane.apply(activity: result)

                // Silence-based "AI agent waiting" check. Independent of the
                // debounced timer in processOutput, this fires even when the
                // agent has been quiet since before we attached (no live
                // output to drive the debounce).
                if let ts = found.pane.terminalState,
                   AttentionPolicy.isAIAgent(ts.currentCommand) {
                    let silentLongEnough: Bool = {
                        guard let last = ts.lastOutputAt else { return true }
                        return Date().timeIntervalSince(last) >= AttentionPolicy.silenceWaitingThreshold
                    }()
                    if silentLongEnough, !ts.isSilentWaiting {
                        ts.isSilentWaiting = true
                        onEvent?(.contentMatch(tabUUID: found.tab.uuid))
                    }
                } else {
                    // Foreground is no longer an AI agent — make sure the
                    // flag doesn't stay sticky (e.g. user exited claude).
                    found.pane.terminalState?.isSilentWaiting = false
                }
            }

            // Transition active → inactive = user's long-running command finished.
            if wasActive && !result.isActive {
                onShellResumed?(result.paneId)
                if let found = workspace.findTab(byPaneId: result.paneId) {
                    onEvent?(.commandCompleted(tabUUID: found.tab.uuid))
                }
            }
        }
    }
}
