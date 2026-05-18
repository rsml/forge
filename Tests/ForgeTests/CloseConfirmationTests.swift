import Testing
import Foundation
@testable import ForgeCore

@Suite("CloseConfirmation")
@MainActor
struct CloseConfirmationTests {

    // MARK: - Fixtures

    /// Build a project with `tabs` tabs; tab `i` gets `panesPerTab[i]` panes.
    /// Pane IDs are `"<projectId>-t<i>-p<j>"`, pane indexes are `j`.
    private func makeProject(
        id: String = "proj",
        name: String = "demo",
        panesPerTab: [Int]
    ) -> Project {
        let project = Project(id: id, name: name, attached: true)
        for (i, paneCount) in panesPerTab.enumerated() {
            let tab = Tab(id: "\(id)-t\(i)", projectId: id, index: i, name: "tab-\(i)", active: i == 0)
            for j in 0..<paneCount {
                let pane = Pane(id: "\(id)-t\(i)-p\(j)", tabId: tab.id, index: j, active: j == 0)
                tab.panes.append(pane)
            }
            project.tabs.append(tab)
        }
        return project
    }

    private func makeActivity(paneId: String, cmd: String? = "claude") -> PaneActivity {
        PaneActivity(paneId: paneId, isActive: true, command: cmd)
    }

    private func idleActivity(paneId: String) -> PaneActivity {
        PaneActivity(paneId: paneId, isActive: false, command: nil)
    }

    // MARK: - Mode .never

    @Test("mode .never returns no alert regardless of activity")
    func neverNeverPrompts() {
        let project = makeProject(panesPerTab: [1, 1])  // multi-tab, single-pane each
        let tab = project.tabs[0]
        let activities = [makeActivity(paneId: tab.panes[0].id, cmd: "claude")]
        let decision = CloseConfirmation.evaluate(
            project: project, tab: tab, activePane: tab.panes[0],
            activities: activities,
            confirmCloseTab: .never, confirmCloseProject: .never
        )
        // multi-tab + single-pane → target is .tab
        if case .tab = decision.target {} else {
            Issue.record("expected .tab target, got \(decision.target)")
        }
        #expect(decision.alert == nil)
    }

    // MARK: - Mode .whenActive

    @Test("mode .whenActive with no activity returns no alert")
    func whenActiveIdleNoAlert() {
        let project = makeProject(panesPerTab: [1, 1])
        let tab = project.tabs[0]
        let activities = [idleActivity(paneId: tab.panes[0].id)]
        let decision = CloseConfirmation.evaluate(
            project: project, tab: tab, activePane: tab.panes[0],
            activities: activities,
            confirmCloseTab: .whenActive, confirmCloseProject: .whenActive
        )
        #expect(decision.alert == nil)
    }

    @Test("mode .whenActive with one active pane names that command")
    func whenActiveOneActiveNamesCommand() {
        let project = makeProject(panesPerTab: [1, 1])
        let tab = project.tabs[0]
        let activities = [makeActivity(paneId: tab.panes[0].id, cmd: "vim")]
        let decision = CloseConfirmation.evaluate(
            project: project, tab: tab, activePane: tab.panes[0],
            activities: activities,
            confirmCloseTab: .whenActive, confirmCloseProject: .whenActive
        )
        #expect(decision.alert?.message == "Closing this tab will terminate \"vim\".")
        #expect(decision.alert?.action == "Close Tab")
        #expect(decision.alert?.info == "")
    }

    @Test("mode .whenActive with two actives names first + other-process suffix")
    func whenActiveTwoActivesIncludesSuffix() {
        // Multi-tab so we close as .tab; the closed tab has two active panes.
        let project = makeProject(panesPerTab: [2, 1])
        let tab = project.tabs[0]
        let activities = [
            makeActivity(paneId: tab.panes[0].id, cmd: "claude"),
            makeActivity(paneId: tab.panes[1].id, cmd: "vim")
        ]
        // tab has 2 panes → resolveTarget yields .pane, not .tab.
        // For a tab-level multi-active test we need to force .tab by passing
        // activePane = nil so the multi-pane branch is skipped.
        let decision = CloseConfirmation.evaluate(
            project: project, tab: tab, activePane: nil,
            activities: activities,
            confirmCloseTab: .whenActive, confirmCloseProject: .whenActive
        )
        if case .tab = decision.target {} else {
            Issue.record("expected .tab target, got \(decision.target)")
        }
        #expect(decision.alert?.message == "Closing this tab will terminate \"claude\" (and 1 other process).")
    }

    @Test("three actives use plural \"processes\"")
    func threeActivesPlural() {
        let project = makeProject(panesPerTab: [3, 1])
        let tab = project.tabs[0]
        let activities = [
            makeActivity(paneId: tab.panes[0].id, cmd: "claude"),
            makeActivity(paneId: tab.panes[1].id, cmd: "vim"),
            makeActivity(paneId: tab.panes[2].id, cmd: "npm")
        ]
        let decision = CloseConfirmation.evaluate(
            project: project, tab: tab, activePane: nil,
            activities: activities,
            confirmCloseTab: .whenActive, confirmCloseProject: .whenActive
        )
        #expect(decision.alert?.message == "Closing this tab will terminate \"claude\" (and 2 other processes).")
    }

    // MARK: - Mode .always

    @Test("mode .always with idle tab uses always-warn copy")
    func alwaysIdleUsesIdleCopy() {
        let project = makeProject(panesPerTab: [1, 1])
        let tab = project.tabs[0]
        let activities = [idleActivity(paneId: tab.panes[0].id)]
        let decision = CloseConfirmation.evaluate(
            project: project, tab: tab, activePane: tab.panes[0],
            activities: activities,
            confirmCloseTab: .always, confirmCloseProject: .always
        )
        #expect(decision.alert?.message == "Closing this tab will close it permanently.")
        #expect(decision.alert?.info == "")
    }

    @Test("mode .always with active tab uses active copy (active wins)")
    func alwaysActiveWinsOverIdle() {
        let project = makeProject(panesPerTab: [1, 1])
        let tab = project.tabs[0]
        let activities = [makeActivity(paneId: tab.panes[0].id, cmd: "vim")]
        let decision = CloseConfirmation.evaluate(
            project: project, tab: tab, activePane: tab.panes[0],
            activities: activities,
            confirmCloseTab: .always, confirmCloseProject: .always
        )
        #expect(decision.alert?.message == "Closing this tab will terminate \"vim\".")
    }

    @Test("mode .always for project uses idle project copy")
    func alwaysIdleProject() {
        let project = makeProject(id: "proj", name: "Awesome", panesPerTab: [1])
        let tab = project.tabs[0]
        let activities = [idleActivity(paneId: tab.panes[0].id)]
        let decision = CloseConfirmation.evaluate(
            project: project, tab: tab, activePane: tab.panes[0],
            activities: activities,
            confirmCloseTab: .always, confirmCloseProject: .always
        )
        if case .project = decision.target {} else {
            Issue.record("expected .project target, got \(decision.target)")
        }
        #expect(decision.alert?.message == "Closing \"Awesome\" will close all tabs and remove the project from Forge.")
    }

    // MARK: - Pane target

    @Test("pane target with single active names the command")
    func paneTargetSingleActive() {
        // Multi-pane tab → resolveTarget gives .pane.
        let project = makeProject(panesPerTab: [2])
        let tab = project.tabs[0]
        let activePane = tab.panes[0]
        let activities = [
            makeActivity(paneId: activePane.id, cmd: "claude"),
            idleActivity(paneId: tab.panes[1].id)
        ]
        let decision = CloseConfirmation.evaluate(
            project: project, tab: tab, activePane: activePane,
            activities: activities,
            // Pane close uses implicit .whenActive — these settings are ignored.
            confirmCloseTab: .never, confirmCloseProject: .never
        )
        if case .pane(let id) = decision.target {
            #expect(id == activePane.id)
        } else {
            Issue.record("expected .pane target, got \(decision.target)")
        }
        #expect(decision.alert?.message == "Closing this pane will terminate \"claude\".")
        #expect(decision.alert?.action == "Close Pane")
    }

    @Test("pane target with no activity returns no alert regardless of tab/project modes")
    func paneTargetIdleNoAlert() {
        let project = makeProject(panesPerTab: [2])
        let tab = project.tabs[0]
        let activePane = tab.panes[0]
        let activities = [
            idleActivity(paneId: activePane.id),
            idleActivity(paneId: tab.panes[1].id)
        ]
        let decision = CloseConfirmation.evaluate(
            project: project, tab: tab, activePane: activePane,
            activities: activities,
            confirmCloseTab: .always, confirmCloseProject: .always
        )
        if case .pane = decision.target {} else {
            Issue.record("expected .pane target, got \(decision.target)")
        }
        #expect(decision.alert == nil)
    }

    // MARK: - Target picking

    @Test("target picking: multi-pane tab → .pane")
    func targetPickingPane() {
        let project = makeProject(panesPerTab: [2, 1])
        let tab = project.tabs[0]
        let decision = CloseConfirmation.evaluate(
            project: project, tab: tab, activePane: tab.panes[0],
            activities: [],
            confirmCloseTab: .whenActive, confirmCloseProject: .whenActive
        )
        if case .pane = decision.target {} else {
            Issue.record("expected .pane, got \(decision.target)")
        }
    }

    @Test("target picking: single-pane multi-tab → .tab")
    func targetPickingTab() {
        let project = makeProject(panesPerTab: [1, 1])
        let tab = project.tabs[0]
        let decision = CloseConfirmation.evaluate(
            project: project, tab: tab, activePane: tab.panes[0],
            activities: [],
            confirmCloseTab: .whenActive, confirmCloseProject: .whenActive
        )
        if case .tab = decision.target {} else {
            Issue.record("expected .tab, got \(decision.target)")
        }
    }

    @Test("target picking: last tab → .project")
    func targetPickingProject() {
        let project = makeProject(panesPerTab: [1])
        let tab = project.tabs[0]
        let decision = CloseConfirmation.evaluate(
            project: project, tab: tab, activePane: tab.panes[0],
            activities: [],
            confirmCloseTab: .whenActive, confirmCloseProject: .whenActive
        )
        if case .project = decision.target {} else {
            Issue.record("expected .project, got \(decision.target)")
        }
    }

    // MARK: - Command-nil fallback

    @Test("command nil in PaneActivity substitutes \"a process\"")
    func nilCommandFallback() {
        let project = makeProject(panesPerTab: [1, 1])
        let tab = project.tabs[0]
        let activities = [PaneActivity(paneId: tab.panes[0].id, isActive: true, command: nil)]
        let decision = CloseConfirmation.evaluate(
            project: project, tab: tab, activePane: tab.panes[0],
            activities: activities,
            confirmCloseTab: .whenActive, confirmCloseProject: .whenActive
        )
        #expect(decision.alert?.message == "Closing this tab will terminate \"a process\".")
    }
}
