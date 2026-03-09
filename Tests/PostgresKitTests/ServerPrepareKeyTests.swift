import XCTest
import PostgresNIO
@testable import PostgresKit

final class ServerPrepareKeyTests: XCTestCase {

    // MARK: - Key format

    func testMakeKey_NoTypes_ProducesSQLPlusDelimiter() {
        let key = ServerPrepareKey.make(sql: "SELECT 1", types: [])
        XCTAssertEqual(key, "SELECT 1|#")
    }

    func testMakeKey_SingleType_IncludesOIDInKey() {
        let key = ServerPrepareKey.make(sql: "SELECT $1", types: [PostgresDataType(23)])
        XCTAssertEqual(key, "SELECT $1|#23")
    }

    func testMakeKey_MultipleTypes_JoinedByComma() {
        let key = ServerPrepareKey.make(
            sql: "INSERT INTO t VALUES ($1, $2)",
            types: [PostgresDataType(25), PostgresDataType(23)]
        )
        XCTAssertEqual(key, "INSERT INTO t VALUES ($1, $2)|#25,23")
    }

    func testMakeKey_ThreeTypes_NoTrailingComma() {
        let key = ServerPrepareKey.make(
            sql: "SELECT $1, $2, $3",
            types: [
                PostgresDataType(23),
                PostgresDataType(25),
                PostgresDataType(16)
            ]
        )
        XCTAssertEqual(key, "SELECT $1, $2, $3|#23,25,16")
        XCTAssertFalse(key.hasSuffix(","))
    }

    // MARK: - Uniqueness

    func testMakeKey_DifferentSQL_ProducesDifferentKeys() {
        let key1 = ServerPrepareKey.make(sql: "SELECT 1", types: [])
        let key2 = ServerPrepareKey.make(sql: "SELECT 2", types: [])
        XCTAssertNotEqual(key1, key2)
    }

    func testMakeKey_DifferentTypes_ProducesDifferentKeys() {
        let key1 = ServerPrepareKey.make(sql: "SELECT $1", types: [PostgresDataType(23)])
        let key2 = ServerPrepareKey.make(sql: "SELECT $1", types: [PostgresDataType(25)])
        XCTAssertNotEqual(key1, key2)
    }

    func testMakeKey_SameSQLAndTypes_ProducesSameKey() {
        let key1 = ServerPrepareKey.make(sql: "SELECT $1", types: [PostgresDataType(23)])
        let key2 = ServerPrepareKey.make(sql: "SELECT $1", types: [PostgresDataType(23)])
        XCTAssertEqual(key1, key2)
    }

    func testMakeKey_TypeOrderMatters() {
        let key1 = ServerPrepareKey.make(
            sql: "SELECT $1, $2",
            types: [PostgresDataType(23), PostgresDataType(25)]
        )
        let key2 = ServerPrepareKey.make(
            sql: "SELECT $1, $2",
            types: [PostgresDataType(25), PostgresDataType(23)]
        )
        XCTAssertNotEqual(key1, key2)
    }
}
