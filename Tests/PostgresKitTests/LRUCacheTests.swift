import XCTest
@testable import PostgresKit

final class LRUCacheTests: PostgresKitTestCase {

    // MARK: - Basic operations

    func testGetReturnsNilForMissingKey() {
        let cache = LRUCache<String, Int>(capacity: 5)
        XCTAssertNil(cache.get("missing"))
    }

    func testSetAndGet() {
        let cache = LRUCache<String, Int>(capacity: 5)
        cache.set("key", value: 42)
        XCTAssertEqual(cache.get("key"), 42)
    }

    func testSetUpdatesExistingKey() {
        let cache = LRUCache<String, Int>(capacity: 5)
        cache.set("key", value: 1)
        cache.set("key", value: 2)
        XCTAssertEqual(cache.get("key"), 2)
    }

    func testMultipleKeys() {
        let cache = LRUCache<String, Int>(capacity: 5)
        cache.set("a", value: 1)
        cache.set("b", value: 2)
        cache.set("c", value: 3)
        XCTAssertEqual(cache.get("a"), 1)
        XCTAssertEqual(cache.get("b"), 2)
        XCTAssertEqual(cache.get("c"), 3)
    }

    // MARK: - LRU eviction

    func testLRUEviction_AtCapacity_EvictsLeastRecentlyUsed() {
        let cache = LRUCache<String, Int>(capacity: 2)
        cache.set("a", value: 1)
        cache.set("b", value: 2)
        cache.set("c", value: 3) // "a" should be evicted (LRU)

        XCTAssertNil(cache.get("a"))
        XCTAssertEqual(cache.get("b"), 2)
        XCTAssertEqual(cache.get("c"), 3)
    }

    func testGet_TouchesKey_ProtectsFromEviction() {
        let cache = LRUCache<String, Int>(capacity: 2)
        cache.set("a", value: 1)
        cache.set("b", value: 2)
        _ = cache.get("a") // touch "a", making "b" the LRU
        cache.set("c", value: 3) // "b" should be evicted

        XCTAssertEqual(cache.get("a"), 1)
        XCTAssertNil(cache.get("b"))
        XCTAssertEqual(cache.get("c"), 3)
    }

    func testCapacityOne() {
        let cache = LRUCache<String, Int>(capacity: 1)
        cache.set("a", value: 1)
        cache.set("b", value: 2) // "a" evicted

        XCTAssertNil(cache.get("a"))
        XCTAssertEqual(cache.get("b"), 2)
    }

    func testMultipleEvictions() {
        let cache = LRUCache<Int, String>(capacity: 3)
        cache.set(1, value: "one")
        cache.set(2, value: "two")
        cache.set(3, value: "three")
        cache.set(4, value: "four")   // 1 evicted
        cache.set(5, value: "five")   // 2 evicted

        XCTAssertNil(cache.get(1))
        XCTAssertNil(cache.get(2))
        XCTAssertEqual(cache.get(3), "three")
        XCTAssertEqual(cache.get(4), "four")
        XCTAssertEqual(cache.get(5), "five")
    }

    func testUpdateExistingKey_DoesNotEvict() {
        let cache = LRUCache<String, Int>(capacity: 2)
        cache.set("a", value: 1)
        cache.set("b", value: 2)
        cache.set("a", value: 99) // update "a", should not evict anything
        XCTAssertEqual(cache.get("a"), 99)
        XCTAssertEqual(cache.get("b"), 2)
    }

    // MARK: - Remove

    func testRemoveExistingKey() {
        let cache = LRUCache<String, Int>(capacity: 5)
        cache.set("key", value: 42)
        cache.remove("key")
        XCTAssertNil(cache.get("key"))
    }

    func testRemoveMissingKey_DoesNotCrash() {
        let cache = LRUCache<String, Int>(capacity: 5)
        cache.remove("nonexistent") // should not crash
    }

    func testRemoveFreesCapacity() {
        let cache = LRUCache<String, Int>(capacity: 2)
        cache.set("a", value: 1)
        cache.set("b", value: 2)
        cache.remove("a")
        cache.set("c", value: 3) // should not evict "b"

        XCTAssertNil(cache.get("a"))
        XCTAssertEqual(cache.get("b"), 2)
        XCTAssertEqual(cache.get("c"), 3)
    }

    // MARK: - Integer key type

    func testIntegerKeys() {
        let cache = LRUCache<Int, String>(capacity: 3)
        cache.set(1, value: "one")
        cache.set(2, value: "two")
        XCTAssertEqual(cache.get(1), "one")
        XCTAssertEqual(cache.get(2), "two")
        XCTAssertNil(cache.get(3))
    }

    // MARK: - StatementCache Integration

    func testStatementCacheLRUEviction() throws {
        let cache = StatementCache(capacity: 2)
        cache.insert(.init(sql: "a", parameterCount: 1, handle: WireConnection.WirePreparedStatement(sql: "a")))
        cache.insert(.init(sql: "b", parameterCount: 2, handle: WireConnection.WirePreparedStatement(sql: "b")))
        XCTAssertNotNil(cache.lookup(sql: "a", parameterCount: 1))
        cache.insert(.init(sql: "c", parameterCount: 3, handle: WireConnection.WirePreparedStatement(sql: "c")))
        // "b" should be evicted since "a" was touched
        XCTAssertNil(cache.lookup(sql: "b", parameterCount: 2))
        XCTAssertNotNil(cache.lookup(sql: "a", parameterCount: 1))
        XCTAssertNotNil(cache.lookup(sql: "c", parameterCount: 3))
    }
}
