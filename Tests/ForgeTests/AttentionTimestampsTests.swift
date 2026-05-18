import Foundation
import Testing
@testable import ForgeCore

@Suite("AttentionTimestamps")
struct AttentionTimestampsTests {

    @Test("record stores timestamp for UUID")
    func testRecord() {
        var ts = AttentionTimestamps()
        let id = UUID()
        let now = Date()
        ts.record(id, at: now)
        #expect(ts.timestamp(for: id) == now)
    }

    @Test("record does not overwrite existing timestamp")
    func testRecordIdempotent() {
        var ts = AttentionTimestamps()
        let id = UUID()
        let first = Date(timeIntervalSince1970: 100)
        let second = Date(timeIntervalSince1970: 200)
        ts.record(id, at: first)
        ts.record(id, at: second)
        #expect(ts.timestamp(for: id) == first)
    }

    @Test("remove deletes timestamp")
    func testRemove() {
        var ts = AttentionTimestamps()
        let id = UUID()
        ts.record(id, at: Date())
        ts.remove(id)
        #expect(ts.timestamp(for: id) == nil)
    }

    @Test("prune removes UUIDs not in valid set")
    func testPrune() {
        var ts = AttentionTimestamps()
        let a = UUID(), b = UUID(), c = UUID()
        ts.record(a, at: Date())
        ts.record(b, at: Date())
        ts.record(c, at: Date())
        ts.prune(validUUIDs: [a, c])
        #expect(ts.timestamp(for: a) != nil)
        #expect(ts.timestamp(for: b) == nil)
        #expect(ts.timestamp(for: c) != nil)
    }

    @Test("toDictionary and init(from:) round-trip")
    func testPersistence() {
        var ts = AttentionTimestamps()
        let a = UUID(), b = UUID()
        let d1 = Date(timeIntervalSince1970: 1000)
        let d2 = Date(timeIntervalSince1970: 2000)
        ts.record(a, at: d1)
        ts.record(b, at: d2)
        let dict = ts.toDictionary()
        let restored = AttentionTimestamps(from: dict)
        #expect(restored.timestamp(for: a) == d1)
        #expect(restored.timestamp(for: b) == d2)
    }
}
