import Foundation
import Testing
@testable import ForgeCore

@Suite("StateMerger")
@MainActor
struct StateMergerTests {

    // MARK: - mergeProjects

    @Test("updates existing project properties in place")
    func mergeProjectsUpdatesExisting() {
        let ws = Workspace()
        ws.projects = [Project(id: "$1", name: "old-name", tabCount: 1)]
        ws.activeProjectId = "$1"

        StateMerger.mergeProjects(ws, with: [
            ProjectInfo(id: "$1", name: "new-name", tabCount: 3, attached: true, path: "/tmp")
        ])

        #expect(ws.projects.count == 1)
        #expect(ws.projects[0].name == "new-name")
        #expect(ws.projects[0].tabCount == 3)
        #expect(ws.projects[0].attached == true)
        #expect(ws.projects[0].path == "/tmp")
    }

    @Test("removes projects that no longer exist in tmux")
    func mergeProjectsRemovesDead() {
        let ws = Workspace()
        ws.projects = [
            Project(id: "$1", name: "alive"),
            Project(id: "$2", name: "dead"),
        ]
        ws.activeProjectId = "$1"

        StateMerger.mergeProjects(ws, with: [
            ProjectInfo(id: "$1", name: "alive", tabCount: 1, attached: false, path: nil)
        ])

        #expect(ws.projects.count == 1)
        #expect(ws.projects[0].id == "$1")
    }

    @Test("appends new projects from tmux")
    func mergeProjectsAppendsNew() {
        let ws = Workspace()
        ws.projects = [Project(id: "$1", name: "existing")]
        ws.activeProjectId = "$1"

        StateMerger.mergeProjects(ws, with: [
            ProjectInfo(id: "$1", name: "existing", tabCount: 1, attached: false, path: nil),
            ProjectInfo(id: "$2", name: "brand-new", tabCount: 1, attached: false, path: "/new"),
        ])

        #expect(ws.projects.count == 2)
        #expect(ws.projects[1].name == "brand-new")
    }

    @Test("selects neighbor when active project is removed")
    func mergeProjectsFallsBackOnRemoval() {
        let ws = Workspace()
        ws.projects = [
            Project(id: "$1", name: "a"),
            Project(id: "$2", name: "b"),
            Project(id: "$3", name: "c"),
        ]
        ws.activeProjectId = "$2"

        StateMerger.mergeProjects(ws, with: [
            ProjectInfo(id: "$1", name: "a", tabCount: 1, attached: false, path: nil),
            ProjectInfo(id: "$3", name: "c", tabCount: 1, attached: false, path: nil),
        ])

        #expect(ws.activeProjectId == "$1")
    }

    @Test("sets first project as active when none was selected")
    func mergeProjectsSetsFirstActive() {
        let ws = Workspace()

        StateMerger.mergeProjects(ws, with: [
            ProjectInfo(id: "$1", name: "first", tabCount: 1, attached: false, path: nil)
        ])

        #expect(ws.activeProjectId == "$1")
    }

    @Test("preserves local project order")
    func mergeProjectsPreservesOrder() {
        let ws = Workspace()
        ws.projects = [
            Project(id: "$2", name: "b"),
            Project(id: "$1", name: "a"),
        ]
        ws.activeProjectId = "$1"

        StateMerger.mergeProjects(ws, with: [
            ProjectInfo(id: "$1", name: "a", tabCount: 1, attached: false, path: nil),
            ProjectInfo(id: "$2", name: "b", tabCount: 1, attached: false, path: nil),
        ])

        #expect(ws.projects[0].id == "$2")
        #expect(ws.projects[1].id == "$1")
    }

    // MARK: - mergeTabs

    @Test("updates existing tab properties in place")
    func mergeTabsUpdatesExisting() {
        let project = Project(id: "$1", name: "p")
        project.tabs = [Tab(id: "@1", projectId: "$1", index: 0, name: "old")]

        _ = StateMerger.mergeTabs(project: project, with: [
            TabInfo(id: "@1", projectId: "$1", index: 1, name: "new", active: true, paneCount: 2)
        ], activeProjectId: "$1")

        #expect(project.tabs[0].name == "new")
        #expect(project.tabs[0].index == 1)
        #expect(project.tabs[0].active == true)
    }

    @Test("removes dead tabs and appends new ones")
    func mergeTabsRemovesAndAppends() {
        let project = Project(id: "$1", name: "p")
        project.tabs = [
            Tab(id: "@1", projectId: "$1", index: 0, name: "keep"),
            Tab(id: "@2", projectId: "$1", index: 1, name: "remove"),
        ]

        _ = StateMerger.mergeTabs(project: project, with: [
            TabInfo(id: "@1", projectId: "$1", index: 0, name: "keep", active: false, paneCount: 1),
            TabInfo(id: "@3", projectId: "$1", index: 1, name: "added", active: true, paneCount: 1),
        ], activeProjectId: "$1")

        #expect(project.tabs.count == 2)
        #expect(project.tabs.map(\.id) == ["@1", "@3"])
    }

    @Test("returns active tab ID for active project")
    func mergeTabsReturnsActiveTab() {
        let project = Project(id: "$1", name: "p")

        let activeTabId = StateMerger.mergeTabs(project: project, with: [
            TabInfo(id: "@1", projectId: "$1", index: 0, name: "a", active: false, paneCount: 1),
            TabInfo(id: "@2", projectId: "$1", index: 1, name: "b", active: true, paneCount: 1),
        ], activeProjectId: "$1")

        #expect(activeTabId == "@2")
    }

    @Test("returns nil for non-active project")
    func mergeTabsReturnsNilForInactive() {
        let project = Project(id: "$1", name: "p")

        let activeTabId = StateMerger.mergeTabs(project: project, with: [
            TabInfo(id: "@1", projectId: "$1", index: 0, name: "a", active: true, paneCount: 1),
        ], activeProjectId: "$2")

        #expect(activeTabId == nil)
    }

    // MARK: - mergePanes

    @Test("updates existing pane properties")
    func mergePanesUpdatesExisting() {
        let tab = Tab(id: "@1", projectId: "$1", index: 0, name: "t")
        tab.panes = [Pane(id: "%1", tabId: "@1", currentCommand: "zsh")]

        let (_, events) = StateMerger.mergePanes(tab: tab, with: [
            PaneInfo(id: "%1", tabId: "@1", index: 0, active: true,
                     currentCommand: "vim", currentPath: "/tmp",
                     width: 120, height: 40, pid: 999)
        ])

        #expect(tab.panes[0].currentCommand == "vim")
        #expect(tab.panes[0].width == 120)
        #expect(tab.panes[0].status == .running)
        #expect(events.isEmpty)
    }

    @Test("detects command completion (running to idle)")
    func mergePanesDetectsCompletion() {
        let uuid = UUID()
        let tab = Tab(id: "@1", projectId: "$1", index: 0, name: "t", uuid: uuid)
        tab.panes = [Pane(id: "%1", tabId: "@1", currentCommand: "make")]

        let (_, events) = StateMerger.mergePanes(tab: tab, with: [
            PaneInfo(id: "%1", tabId: "@1", index: 0, active: true,
                     currentCommand: "zsh", currentPath: "/tmp",
                     width: 80, height: 24, pid: 1)
        ])

        #expect(events == [.commandCompleted(tabUUID: uuid)])
    }

    @Test("clears bell on idle to running transition")
    func mergePanesClearsBellOnResume() {
        let tab = Tab(id: "@1", projectId: "$1", index: 0, name: "t")
        let pane = Pane(id: "%1", tabId: "@1", currentCommand: "zsh")
        pane.hasBell = true
        tab.panes = [pane]

        _ = StateMerger.mergePanes(tab: tab, with: [
            PaneInfo(id: "%1", tabId: "@1", index: 0, active: true,
                     currentCommand: "npm test", currentPath: "/tmp",
                     width: 80, height: 24, pid: 1)
        ])

        #expect(tab.panes[0].hasBell == false)
    }

    @Test("preserves bell status in needsAttention")
    func mergePanesPreservesBellStatus() {
        let tab = Tab(id: "@1", projectId: "$1", index: 0, name: "t")
        let pane = Pane(id: "%1", tabId: "@1", currentCommand: "zsh")
        pane.hasBell = true
        tab.panes = [pane]

        _ = StateMerger.mergePanes(tab: tab, with: [
            PaneInfo(id: "%1", tabId: "@1", index: 0, active: true,
                     currentCommand: "zsh", currentPath: "/tmp",
                     width: 80, height: 24, pid: 1)
        ])

        #expect(tab.panes[0].status == .needsAttention)
    }

    @Test("appends new panes not in existing list")
    func mergePanesAppendsNew() {
        let tab = Tab(id: "@1", projectId: "$1", index: 0, name: "t")

        let (activePaneId, _) = StateMerger.mergePanes(tab: tab, with: [
            PaneInfo(id: "%1", tabId: "@1", index: 0, active: false,
                     currentCommand: "zsh", currentPath: "/tmp",
                     width: 80, height: 24, pid: 1),
            PaneInfo(id: "%2", tabId: "@1", index: 1, active: true,
                     currentCommand: "vim", currentPath: "/tmp",
                     width: 80, height: 24, pid: 2),
        ])

        #expect(tab.panes.count == 2)
        #expect(activePaneId == "%2")
    }

    @Test("removes panes no longer in tmux output")
    func mergePanesRemovesDead() {
        let tab = Tab(id: "@1", projectId: "$1", index: 0, name: "t")
        tab.panes = [
            Pane(id: "%1", tabId: "@1"),
            Pane(id: "%2", tabId: "@1"),
        ]

        _ = StateMerger.mergePanes(tab: tab, with: [
            PaneInfo(id: "%1", tabId: "@1", index: 0, active: true,
                     currentCommand: "zsh", currentPath: "/tmp",
                     width: 80, height: 24, pid: 1)
        ])

        #expect(tab.panes.count == 1)
        #expect(tab.panes[0].id == "%1")
    }
}
