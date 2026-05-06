import Foundation
import Testing
@testable import ForgeCore

@Suite("AttentionQueue")
struct AttentionQueueTests {

    // MARK: - enqueue

    @Test("enqueue adds to back")
    func testEnqueueAddsToBack() {
        var q = AttentionQueue()
        let a = UUID(), b = UUID()
        q.enqueue(a)
        q.enqueue(b)
        #expect(q.peek() == a)
        #expect(q.count == 2)
    }

    @Test("enqueue is idempotent — same id twice is a no-op")
    func testEnqueueIdempotent() {
        var q = AttentionQueue()
        let id = UUID()
        q.enqueue(id)
        q.enqueue(id)
        #expect(q.count == 1)
    }

    // MARK: - dequeue

    @Test("dequeue removes and returns the front item")
    func testDequeueRemovesFront() {
        var q = AttentionQueue()
        let a = UUID(), b = UUID()
        q.enqueue(a)
        q.enqueue(b)
        let result = q.dequeue()
        #expect(result == a)
        #expect(q.count == 1)
        #expect(q.peek() == b)
    }

    @Test("dequeue from empty queue returns nil")
    func testDequeueEmptyReturnsNil() {
        var q = AttentionQueue()
        #expect(q.dequeue() == nil)
    }

    // MARK: - insertAtFront

    @Test("insertAtFront adds to front")
    func testInsertAtFront() {
        var q = AttentionQueue()
        let a = UUID(), b = UUID()
        q.enqueue(a)
        q.insertAtFront(b)
        #expect(q.peek() == b)
        #expect(q.count == 2)
    }

    @Test("insertAtFront is idempotent — existing id is a no-op")
    func testInsertAtFrontIdempotent() {
        var q = AttentionQueue()
        let a = UUID(), b = UUID()
        q.enqueue(a)
        q.enqueue(b)
        q.insertAtFront(b)          // b is already in the queue
        #expect(q.count == 2)
        #expect(q.peek() == a)      // order unchanged
    }

    // MARK: - moveToBack

    @Test("moveToBack moves item from current position to back")
    func testMoveToBack() {
        var q = AttentionQueue()
        let a = UUID(), b = UUID(), c = UUID()
        q.enqueue(a)
        q.enqueue(b)
        q.enqueue(c)
        q.moveToBack(a)
        // Order should now be b, c, a
        #expect(q.dequeue() == b)
        #expect(q.dequeue() == c)
        #expect(q.dequeue() == a)
    }

    @Test("moveToBack on non-existent item is safe")
    func testMoveToBackNonExistent() {
        var q = AttentionQueue()
        let a = UUID()
        q.enqueue(a)
        q.moveToBack(UUID())        // random unknown id — should not crash
        #expect(q.count == 1)
        #expect(q.peek() == a)
    }

    // MARK: - remove

    @Test("remove removes the item entirely")
    func testRemove() {
        var q = AttentionQueue()
        let a = UUID(), b = UUID()
        q.enqueue(a)
        q.enqueue(b)
        q.remove(a)
        #expect(q.count == 1)
        #expect(q.peek() == b)
        #expect(!q.contains(a))
    }

    @Test("remove on non-existent item is safe")
    func testRemoveNonExistent() {
        var q = AttentionQueue()
        let a = UUID()
        q.enqueue(a)
        q.remove(UUID())            // unknown id — should not crash
        #expect(q.count == 1)
    }

    // MARK: - peek

    @Test("peek returns front without removing it")
    func testPeek() {
        var q = AttentionQueue()
        let a = UUID()
        q.enqueue(a)
        let first = q.peek()
        #expect(first == a)
        #expect(q.count == 1)       // not removed
    }

    @Test("peek on empty queue returns nil")
    func testPeekEmpty() {
        let q = AttentionQueue()
        #expect(q.peek() == nil)
    }

    // MARK: - contains

    @Test("contains returns true for present item")
    func testContainsTrue() {
        var q = AttentionQueue()
        let a = UUID()
        q.enqueue(a)
        #expect(q.contains(a))
    }

    @Test("contains returns false for absent item")
    func testContainsFalse() {
        var q = AttentionQueue()
        q.enqueue(UUID())
        #expect(!q.contains(UUID()))
    }

    // MARK: - isEmpty / count

    @Test("isEmpty is true for a new queue")
    func testIsEmptyInitial() {
        let q = AttentionQueue()
        #expect(q.isEmpty)
        #expect(q.count == 0)
    }

    @Test("isEmpty is false after enqueue, true after all dequeued")
    func testIsEmptyAfterOperations() {
        var q = AttentionQueue()
        let id = UUID()
        q.enqueue(id)
        #expect(!q.isEmpty)
        _ = q.dequeue()
        #expect(q.isEmpty)
    }

    @Test("count reflects number of distinct items")
    func testCount() {
        var q = AttentionQueue()
        #expect(q.count == 0)
        q.enqueue(UUID())
        #expect(q.count == 1)
        q.enqueue(UUID())
        #expect(q.count == 2)
        _ = q.dequeue()
        #expect(q.count == 1)
    }
}
