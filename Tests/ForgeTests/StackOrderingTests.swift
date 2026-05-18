import Foundation
import Testing
@testable import ForgeCore

@Suite("StackOrdering")
@MainActor
struct StackOrderingTests {

    private func attentionTab(uuid: UUID, projectId: String, index: Int) -> Tab {
        let tab = Tab(id: UUID().uuidString, projectId: projectId, index: index, name: "tab-\(index)", uuid: uuid)
        let pane = Pane(id: UUID().uuidString, tabId: tab.id, currentPath: "/tmp")
        pane.hasBell = true
        tab.panes.append(pane)
        return tab
    }

    @Test("simple mode: sidebar order — projects then tabs")
    func testSimpleOrdering() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let p1 = Project(id: "p1", name: "alpha", path: "/a")
        p1.tabs.append(attentionTab(uuid: a, projectId: "p1", index: 0))
        p1.tabs.append(attentionTab(uuid: b, projectId: "p1", index: 1))
        let p2 = Project(id: "p2", name: "beta", path: "/b")
        p2.tabs.append(attentionTab(uuid: c, projectId: "p2", index: 0))
        p2.tabs.append(attentionTab(uuid: d, projectId: "p2", index: 1))

        let result = StackOrdering.order(
            projects: [p1, p2], frontUUID: a, mode: .simple,
            timestamps: AttentionTimestamps(), isHidden: { _ in false }
        )
        #expect(result == [a, b, c, d])
    }

    @Test("grouped mode: active project first, then others in sidebar order")
    func testGroupedOrdering() {
        let a = UUID(), b = UUID(), c = UUID()
        let p1 = Project(id: "p1", name: "alpha", path: "/a")
        p1.tabs.append(attentionTab(uuid: a, projectId: "p1", index: 0))
        let p2 = Project(id: "p2", name: "beta", path: "/b")
        p2.tabs.append(attentionTab(uuid: b, projectId: "p2", index: 0))
        p2.tabs.append(attentionTab(uuid: c, projectId: "p2", index: 1))

        let result = StackOrdering.order(
            projects: [p1, p2], frontUUID: b, mode: .grouped,
            timestamps: AttentionTimestamps(), isHidden: { _ in false }
        )
        #expect(result == [b, c, a])
    }

    @Test("chronological mode: earliest attention timestamp first")
    func testChronologicalOrdering() {
        let a = UUID(), b = UUID(), c = UUID()
        let p1 = Project(id: "p1", name: "alpha", path: "/a")
        p1.tabs.append(attentionTab(uuid: a, projectId: "p1", index: 0))
        p1.tabs.append(attentionTab(uuid: b, projectId: "p1", index: 1))
        let p2 = Project(id: "p2", name: "beta", path: "/b")
        p2.tabs.append(attentionTab(uuid: c, projectId: "p2", index: 0))

        var ts = AttentionTimestamps()
        ts.record(a, at: Date(timeIntervalSince1970: 300))
        ts.record(b, at: Date(timeIntervalSince1970: 100))
        ts.record(c, at: Date(timeIntervalSince1970: 200))

        let result = StackOrdering.order(
            projects: [p1, p2], frontUUID: a, mode: .chronological,
            timestamps: ts, isHidden: { _ in false }
        )
        #expect(result == [a, b, c])
    }

    @Test("frontUUID is always first regardless of mode")
    func testFrontAlwaysFirst() {
        let a = UUID(), b = UUID()
        let p1 = Project(id: "p1", name: "alpha", path: "/a")
        p1.tabs.append(attentionTab(uuid: a, projectId: "p1", index: 0))
        p1.tabs.append(attentionTab(uuid: b, projectId: "p1", index: 1))

        let result = StackOrdering.order(
            projects: [p1], frontUUID: b, mode: .simple,
            timestamps: AttentionTimestamps(), isHidden: { _ in false }
        )
        #expect(result.first == b)
    }

    @Test("hidden tabs are excluded from ordering")
    func testHiddenExcluded() {
        let a = UUID(), b = UUID(), c = UUID()
        let p1 = Project(id: "p1", name: "alpha", path: "/a")
        p1.tabs.append(attentionTab(uuid: a, projectId: "p1", index: 0))
        p1.tabs.append(attentionTab(uuid: b, projectId: "p1", index: 1))
        p1.tabs.append(attentionTab(uuid: c, projectId: "p1", index: 2))

        let result = StackOrdering.order(
            projects: [p1], frontUUID: a, mode: .simple,
            timestamps: AttentionTimestamps(), isHidden: { $0 == b }
        )
        #expect(result == [a, c])
    }

    @Test("tabs without needsAttention are excluded (except frontUUID)")
    func testNonAttentionExcluded() {
        let a = UUID(), b = UUID()
        let p1 = Project(id: "p1", name: "alpha", path: "/a")
        p1.tabs.append(attentionTab(uuid: a, projectId: "p1", index: 0))
        // b has no attention — pane must have running command so status != .idle
        let noAttentionTab = Tab(id: UUID().uuidString, projectId: "p1", index: 1, name: "busy", uuid: b)
        let busyPane = Pane(id: UUID().uuidString, tabId: noAttentionTab.id, currentCommand: "vim", currentPath: "/tmp")
        busyPane.status = .running
        noAttentionTab.panes.append(busyPane)
        p1.tabs.append(noAttentionTab)

        let result = StackOrdering.order(
            projects: [p1], frontUUID: a, mode: .simple,
            timestamps: AttentionTimestamps(), isHidden: { _ in false }
        )
        #expect(result == [a])
    }
}
