import Testing
import Foundation
@testable import ForgeCore

@Suite("CloseConfirmation")
@MainActor
struct CloseConfirmationTests {

    // MARK: - Fixtures

    private func makeProject(
        id: String = "proj", name: String = "demo", panesPerTab: [Int]
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

    private func active(_ id: String, _ cmd: String? = "claude") -> PaneActivity {
        PaneActivity(paneId: id, isActive: true, command: cmd)
    }
    private func idle(_ id: String) -> PaneActivity {
        PaneActivity(paneId: id, isActive: false, command: nil)
    }

    // MARK: - Mode .never

    @Test("mode .never returns no alert regardless of activity")
    func neverNeverPrompts() {
        let project = makeProject(panesPerTab: [1, 1])
        let tab = project.tabs[0]
        let decision = CloseConfirmation.evaluate(
            target: .tab(tab, in: project),
            activities: [active(tab.panes[0].id, "claude")],
            confirmClosePane: .never, confirmCloseTab: .never, confirmCloseProject: .never
        )
        #expect(decision.alert == nil)
    }

    // MARK: - Mode .whenActive

    @Test("mode .whenActive with no activity returns no alert")
    func whenActiveIdleNoAlert() {
        let project = makeProject(panesPerTab: [1, 1])
        let tab = project.tabs[0]
        let decision = CloseConfirmation.evaluate(
            target: .tab(tab, in: project),
            activities: [idle(tab.panes[0].id)],
            confirmClosePane: .whenActive, confirmCloseTab: .whenActive, confirmCloseProject: .whenActive
        )
        #expect(decision.alert == nil)
    }

    @Test("mode .whenActive with one active pane names that command")
    func whenActiveOneActiveNamesCommand() {
        let project = makeProject(panesPerTab: [1, 1])
        let tab = project.tabs[0]
        let decision = CloseConfirmation.evaluate(
            target: .tab(tab, in: project),
            activities: [active(tab.panes[0].id, "vim")],
            confirmClosePane: .whenActive, confirmCloseTab: .whenActive, confirmCloseProject: .whenActive
        )
        #expect(decision.alert?.message == "Closing this tab will terminate \"vim\".")
        #expect(decision.alert?.action == "Close Tab")
        #expect(decision.alert?.info == "")
    }

    // MARK: - Multi-active

    @Test("two actives use count-in-message + names-in-info form")
    func twoActives() {
        let project = makeProject(panesPerTab: [2])
        let tab = project.tabs[0]
        let decision = CloseConfirmation.evaluate(
            target: .tab(tab, in: project),
            activities: [
                active(tab.panes[0].id, "claude"),
                active(tab.panes[1].id, "vim")
            ],
            confirmClosePane: .whenActive, confirmCloseTab: .whenActive, confirmCloseProject: .whenActive
        )
        #expect(decision.alert?.message == "Closing this tab will terminate 2 running processes.")
        #expect(decision.alert?.info == "claude, vim")
        #expect(decision.alert?.action == "Close Tab")
    }

    @Test("three actives list all in info")
    func threeActives() {
        let project = makeProject(panesPerTab: [3])
        let tab = project.tabs[0]
        let decision = CloseConfirmation.evaluate(
            target: .tab(tab, in: project),
            activities: [
                active(tab.panes[0].id, "claude"),
                active(tab.panes[1].id, "vim"),
                active(tab.panes[2].id, "npm")
            ],
            confirmClosePane: .whenActive, confirmCloseTab: .whenActive, confirmCloseProject: .whenActive
        )
        #expect(decision.alert?.message == "Closing this tab will terminate 3 running processes.")
        #expect(decision.alert?.info == "claude, vim, npm")
    }

    @Test("five actives still fit fully in info")
    func fiveActives() {
        let project = makeProject(panesPerTab: [5])
        let tab = project.tabs[0]
        let activities = (0..<5).map { i in
            active(tab.panes[i].id, ["claude", "vim", "npm", "top", "psql"][i])
        }
        let decision = CloseConfirmation.evaluate(
            target: .tab(tab, in: project),
            activities: activities,
            confirmClosePane: .whenActive, confirmCloseTab: .whenActive, confirmCloseProject: .whenActive
        )
        #expect(decision.alert?.message == "Closing this tab will terminate 5 running processes.")
        #expect(decision.alert?.info == "claude, vim, npm, top, psql")
    }

    @Test("six actives roll over into \"and N more\"")
    func sixActives() {
        let project = makeProject(panesPerTab: [6])
        let tab = project.tabs[0]
        let activities = (0..<6).map { i in
            active(tab.panes[i].id, ["claude", "vim", "npm", "top", "psql", "redis"][i])
        }
        let decision = CloseConfirmation.evaluate(
            target: .tab(tab, in: project),
            activities: activities,
            confirmClosePane: .whenActive, confirmCloseTab: .whenActive, confirmCloseProject: .whenActive
        )
        #expect(decision.alert?.message == "Closing this tab will terminate 6 running processes.")
        #expect(decision.alert?.info == "claude, vim, npm, top, psql, and 1 more")
    }

    @Test("eight actives show first five + \"and 3 more\"")
    func eightActives() {
        let project = makeProject(panesPerTab: [8])
        let tab = project.tabs[0]
        let names = ["a", "b", "c", "d", "e", "f", "g", "h"]
        let activities = (0..<8).map { active(tab.panes[$0].id, names[$0]) }
        let decision = CloseConfirmation.evaluate(
            target: .tab(tab, in: project),
            activities: activities,
            confirmClosePane: .whenActive, confirmCloseTab: .whenActive, confirmCloseProject: .whenActive
        )
        #expect(decision.alert?.info == "a, b, c, d, e, and 3 more")
    }

    // MARK: - Mode .always

    @Test("mode .always with idle tab uses always-warn copy")
    func alwaysIdleUsesIdleCopy() {
        let project = makeProject(panesPerTab: [1])
        let tab = project.tabs[0]
        let decision = CloseConfirmation.evaluate(
            target: .tab(tab, in: project),
            activities: [idle(tab.panes[0].id)],
            confirmClosePane: .always, confirmCloseTab: .always, confirmCloseProject: .always
        )
        #expect(decision.alert?.message == "Closing this tab will close it permanently.")
        #expect(decision.alert?.info == "")
    }

    @Test("mode .always with active tab uses active copy (active wins)")
    func alwaysActiveWinsOverIdle() {
        let project = makeProject(panesPerTab: [1])
        let tab = project.tabs[0]
        let decision = CloseConfirmation.evaluate(
            target: .tab(tab, in: project),
            activities: [active(tab.panes[0].id, "vim")],
            confirmClosePane: .always, confirmCloseTab: .always, confirmCloseProject: .always
        )
        #expect(decision.alert?.message == "Closing this tab will terminate \"vim\".")
    }

    @Test("mode .always for project uses idle project copy")
    func alwaysIdleProject() {
        let project = makeProject(id: "proj", name: "Awesome", panesPerTab: [1])
        let decision = CloseConfirmation.evaluate(
            target: .project(project),
            activities: [idle(project.tabs[0].panes[0].id)],
            confirmClosePane: .always, confirmCloseTab: .always, confirmCloseProject: .always
        )
        #expect(decision.alert?.message == "Closing \"Awesome\" will close all tabs and remove the project from Forge.")
    }

    @Test("project active copy uses project name + multi-active list")
    func projectActiveMulti() {
        let project = makeProject(id: "proj", name: "Awesome", panesPerTab: [1, 2])
        let activities = [
            active(project.tabs[0].panes[0].id, "claude"),
            active(project.tabs[1].panes[0].id, "vim"),
            active(project.tabs[1].panes[1].id, "npm")
        ]
        let decision = CloseConfirmation.evaluate(
            target: .project(project),
            activities: activities,
            confirmClosePane: .whenActive, confirmCloseTab: .whenActive, confirmCloseProject: .whenActive
        )
        #expect(decision.alert?.message == "Closing \"Awesome\" will terminate 3 running processes.")
        #expect(decision.alert?.info == "claude, vim, npm")
    }

    // MARK: - Pane target

    @Test("pane target with active process names the command")
    func paneTargetSingleActive() {
        let project = makeProject(panesPerTab: [2])
        let tab = project.tabs[0]
        let decision = CloseConfirmation.evaluate(
            target: .pane(id: tab.panes[0].id),
            activities: [
                active(tab.panes[0].id, "claude"),
                idle(tab.panes[1].id)
            ],
            confirmClosePane: .whenActive, confirmCloseTab: .never, confirmCloseProject: .never
        )
        #expect(decision.alert?.message == "Closing this pane will terminate \"claude\".")
        #expect(decision.alert?.action == "Close Pane")
    }

    @Test("pane target idle + mode .whenActive → no alert")
    func paneTargetIdleNoAlert() {
        let project = makeProject(panesPerTab: [2])
        let tab = project.tabs[0]
        let decision = CloseConfirmation.evaluate(
            target: .pane(id: tab.panes[0].id),
            activities: [idle(tab.panes[0].id), idle(tab.panes[1].id)],
            confirmClosePane: .whenActive, confirmCloseTab: .never, confirmCloseProject: .never
        )
        #expect(decision.alert == nil)
    }

    @Test("pane target ignores activities of sibling panes")
    func paneTargetScopedToPane() {
        // Two panes, the *other* one is active. Closing the inactive pane should
        // not prompt — activity is per-pane.
        let project = makeProject(panesPerTab: [2])
        let tab = project.tabs[0]
        let decision = CloseConfirmation.evaluate(
            target: .pane(id: tab.panes[0].id),
            activities: [idle(tab.panes[0].id), active(tab.panes[1].id, "claude")],
            confirmClosePane: .whenActive, confirmCloseTab: .never, confirmCloseProject: .never
        )
        #expect(decision.alert == nil)
    }

    // MARK: - Mode selection by target

    @Test("pane target consults confirmClosePane, ignores tab/project modes")
    func paneTargetUsesPaneMode() {
        let project = makeProject(panesPerTab: [1])
        let tab = project.tabs[0]
        let decision = CloseConfirmation.evaluate(
            target: .pane(id: tab.panes[0].id),
            activities: [active(tab.panes[0].id, "claude")],
            confirmClosePane: .never,             // pane mode wins
            confirmCloseTab: .whenActive,
            confirmCloseProject: .whenActive
        )
        #expect(decision.alert == nil)
    }

    @Test("tab target consults confirmCloseTab")
    func tabTargetUsesTabMode() {
        let project = makeProject(panesPerTab: [1])
        let tab = project.tabs[0]
        let decision = CloseConfirmation.evaluate(
            target: .tab(tab, in: project),
            activities: [active(tab.panes[0].id, "claude")],
            confirmClosePane: .whenActive,
            confirmCloseTab: .never,              // tab mode wins
            confirmCloseProject: .whenActive
        )
        #expect(decision.alert == nil)
    }

    @Test("project target consults confirmCloseProject")
    func projectTargetUsesProjectMode() {
        let project = makeProject(panesPerTab: [1])
        let decision = CloseConfirmation.evaluate(
            target: .project(project),
            activities: [active(project.tabs[0].panes[0].id, "claude")],
            confirmClosePane: .whenActive,
            confirmCloseTab: .whenActive,
            confirmCloseProject: .never           // project mode wins
        )
        #expect(decision.alert == nil)
    }

    // MARK: - Command-nil fallback

    @Test("command nil substitutes \"a process\" in single-active copy")
    func nilCommandFallbackSingle() {
        let project = makeProject(panesPerTab: [1])
        let tab = project.tabs[0]
        let decision = CloseConfirmation.evaluate(
            target: .tab(tab, in: project),
            activities: [PaneActivity(paneId: tab.panes[0].id, isActive: true, command: nil)],
            confirmClosePane: .whenActive, confirmCloseTab: .whenActive, confirmCloseProject: .whenActive
        )
        #expect(decision.alert?.message == "Closing this tab will terminate \"a process\".")
    }

    @Test("command nil substitutes \"a process\" in multi-active info list")
    func nilCommandFallbackMulti() {
        let project = makeProject(panesPerTab: [2])
        let tab = project.tabs[0]
        let decision = CloseConfirmation.evaluate(
            target: .tab(tab, in: project),
            activities: [
                active(tab.panes[0].id, "claude"),
                PaneActivity(paneId: tab.panes[1].id, isActive: true, command: nil)
            ],
            confirmClosePane: .whenActive, confirmCloseTab: .whenActive, confirmCloseProject: .whenActive
        )
        #expect(decision.alert?.info == "claude, a process")
    }
}
