import Testing
@testable import ForgeCore

@Suite("TabReordering")
struct TabReorderingTests {

    private let ids = ["A", "B", "C", "D", "E"]

    // MARK: - Forward moves

    @Test("move forward by one position")
    func forwardByOne() {
        let targets = TabReordering.swapTargets(fromIndex: 1, toIndex: 3, ids: ids)
        #expect(targets == ["C"])
    }

    @Test("move forward by multiple positions")
    func forwardByMultiple() {
        let targets = TabReordering.swapTargets(fromIndex: 0, toIndex: 4, ids: ids)
        #expect(targets == ["B", "C", "D"])
    }

    @Test("move to end")
    func moveToEnd() {
        let targets = TabReordering.swapTargets(fromIndex: 0, toIndex: 5, ids: ids)
        #expect(targets == ["B", "C", "D", "E"])
    }

    // MARK: - Backward moves

    @Test("move backward by one position")
    func backwardByOne() {
        let targets = TabReordering.swapTargets(fromIndex: 2, toIndex: 1, ids: ids)
        #expect(targets == ["B"])
    }

    @Test("move backward by multiple positions")
    func backwardByMultiple() {
        let targets = TabReordering.swapTargets(fromIndex: 4, toIndex: 1, ids: ids)
        #expect(targets == ["D", "C", "B"])
    }

    @Test("move to start")
    func moveToStart() {
        let targets = TabReordering.swapTargets(fromIndex: 4, toIndex: 0, ids: ids)
        #expect(targets == ["D", "C", "B", "A"])
    }

    // MARK: - No-op cases

    @Test("same position returns empty")
    func samePosition() {
        let targets = TabReordering.swapTargets(fromIndex: 2, toIndex: 2, ids: ids)
        #expect(targets.isEmpty)
    }

    @Test("adjacent insertion point returns empty")
    func adjacentForwardNoOp() {
        let targets = TabReordering.swapTargets(fromIndex: 2, toIndex: 3, ids: ids)
        #expect(targets.isEmpty)
    }

    // MARK: - Edge cases

    @Test("negative fromIndex returns empty")
    func negativeFrom() {
        let targets = TabReordering.swapTargets(fromIndex: -1, toIndex: 2, ids: ids)
        #expect(targets.isEmpty)
    }

    @Test("fromIndex out of bounds returns empty")
    func fromOutOfBounds() {
        let targets = TabReordering.swapTargets(fromIndex: 5, toIndex: 2, ids: ids)
        #expect(targets.isEmpty)
    }

    @Test("single element list returns empty")
    func singleElement() {
        let targets = TabReordering.swapTargets(fromIndex: 0, toIndex: 0, ids: ["X"])
        #expect(targets.isEmpty)
    }

    @Test("two element swap")
    func twoElements() {
        let targets = TabReordering.swapTargets(fromIndex: 0, toIndex: 2, ids: ["A", "B"])
        #expect(targets == ["B"])
    }
}
