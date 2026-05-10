import Testing
@testable import ForgeCore

/// Integration tests for the refresh pipeline: StateMerger produces events,
/// which are consumed by AttentionQueue. Tests the full event flow within Core.
@Suite("Refresh Pipeline")
struct RefreshPipelineTests {

    // MARK: - Helpers

    @MainActor
    private func makeTab(id: String = "@1", paneCommand: String = "zsh") -> (Project, Tab) {
        let project = Project(id: "s1", name: "test", tabCount: 1, attached: true, path: nil)
        let tab = Tab(id: id, projectId: "s1", index: 0, name: "tab", active: true)
        tab.panes = [
            Pane(id: "%0", tabId: id, index: 0, active: true,
                 currentCommand: paneCommand, currentPath: "/tmp",
                 width: 80, height: 24, pid: 100)
        ]
        project.tabs = [tab]
        return (project, tab)
    }

    private func paneInfo(id: String = "%0", tabId: String = "@1", command: String) -> PaneInfo {
        PaneInfo(id: id, tabId: tabId, index: 0, active: true,
                 currentCommand: command, currentPath: "/tmp",
                 width: 80, height: 24, pid: 100)
    }

    // MARK: - Event Production

    @Test("running to idle produces commandCompleted event")
    @MainActor func runningToIdleEvent() {
        let (_, tab) = makeTab(paneCommand: "npm test")
        let (_, events) = StateMerger.mergePanes(tab: tab, with: [paneInfo(command: "zsh")])
        #expect(events == [.commandCompleted(tabUUID: tab.uuid)])
    }

    @Test("idle to idle produces no event")
    @MainActor func idleToIdleNoEvent() {
        let (_, tab) = makeTab(paneCommand: "zsh")
        let (_, events) = StateMerger.mergePanes(tab: tab, with: [paneInfo(command: "zsh")])
        #expect(events.isEmpty)
    }

    @Test("idle to running produces no event")
    @MainActor func idleToRunningNoEvent() {
        let (_, tab) = makeTab(paneCommand: "zsh")
        let (_, events) = StateMerger.mergePanes(tab: tab, with: [paneInfo(command: "npm test")])
        #expect(events.isEmpty)
    }

    // MARK: - Event → Queue Pipeline

    @Test("commandCompleted event enqueues tab in AttentionQueue")
    @MainActor func eventEnqueuesTab() {
        let (_, tab) = makeTab(paneCommand: "npm test")
        let (_, events) = StateMerger.mergePanes(tab: tab, with: [paneInfo(command: "zsh")])

        var queue = AttentionQueue()
        for event in events {
            switch event {
            case .bell(let uuid), .silenceCleared(let uuid), .commandCompleted(let uuid), .contentMatch(let uuid):
                queue.enqueue(uuid)
            }
        }

        #expect(queue.contains(tab.uuid))
        #expect(queue.peek() == tab.uuid)
    }

    @Test("multiple panes completing enqueue multiple tabs")
    @MainActor func multiplePaneEvents() {
        let project = Project(id: "s1", name: "test", tabCount: 2, attached: true, path: nil)
        let tab1 = Tab(id: "@1", projectId: "s1", index: 0, name: "build", active: true)
        tab1.panes = [Pane(id: "%0", tabId: "@1", index: 0, active: true,
                           currentCommand: "make", currentPath: "/tmp",
                           width: 80, height: 24, pid: 100)]
        let tab2 = Tab(id: "@2", projectId: "s1", index: 1, name: "test", active: false)
        tab2.panes = [Pane(id: "%1", tabId: "@2", index: 0, active: true,
                           currentCommand: "npm test", currentPath: "/tmp",
                           width: 80, height: 24, pid: 101)]
        project.tabs = [tab1, tab2]

        // Both panes complete
        let (_, events1) = StateMerger.mergePanes(tab: tab1, with: [paneInfo(id: "%0", tabId: "@1", command: "zsh")])
        let (_, events2) = StateMerger.mergePanes(tab: tab2, with: [paneInfo(id: "%1", tabId: "@2", command: "zsh")])

        var queue = AttentionQueue()
        for event in events1 + events2 {
            switch event {
            case .bell(let uuid), .silenceCleared(let uuid), .commandCompleted(let uuid), .contentMatch(let uuid):
                queue.enqueue(uuid)
            }
        }

        #expect(queue.count == 2)
        #expect(queue.contains(tab1.uuid))
        #expect(queue.contains(tab2.uuid))
    }

    @Test("no events means queue stays empty")
    @MainActor func noEventsEmptyQueue() {
        let (_, tab) = makeTab(paneCommand: "zsh")
        let (_, events) = StateMerger.mergePanes(tab: tab, with: [paneInfo(command: "zsh")])

        var queue = AttentionQueue()
        for event in events {
            switch event {
            case .bell(let uuid), .silenceCleared(let uuid), .commandCompleted(let uuid), .contentMatch(let uuid):
                queue.enqueue(uuid)
            }
        }

        #expect(queue.count == 0)
    }

    @Test("sequential merges: running → idle → running → idle produces two events")
    @MainActor func sequentialTransitions() {
        let (_, tab) = makeTab(paneCommand: "make build")

        // First merge: running → idle
        let (_, events1) = StateMerger.mergePanes(tab: tab, with: [paneInfo(command: "zsh")])
        #expect(events1.count == 1)

        // Second merge: idle → running (user starts new command)
        let (_, events2) = StateMerger.mergePanes(tab: tab, with: [paneInfo(command: "make test")])
        #expect(events2.isEmpty)

        // Third merge: running → idle again
        let (_, events3) = StateMerger.mergePanes(tab: tab, with: [paneInfo(command: "zsh")])
        #expect(events3.count == 1)

        var queue = AttentionQueue()
        for event in events1 + events2 + events3 {
            switch event {
            case .bell(let uuid), .silenceCleared(let uuid), .commandCompleted(let uuid), .contentMatch(let uuid):
                queue.enqueue(uuid)
            }
        }
        // Enqueue is idempotent, so count stays 1
        #expect(queue.contains(tab.uuid))
    }

    @Test("new pane (no previous command) produces no event")
    @MainActor func newPaneNoEvent() {
        let project = Project(id: "s1", name: "test", tabCount: 1, attached: true, path: nil)
        let tab = Tab(id: "@1", projectId: "s1", index: 0, name: "tab", active: true)
        tab.panes = []  // No existing panes
        project.tabs = [tab]

        let (_, events) = StateMerger.mergePanes(tab: tab, with: [paneInfo(command: "zsh")])
        #expect(events.isEmpty)
    }
}
