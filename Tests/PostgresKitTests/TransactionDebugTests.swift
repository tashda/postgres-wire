import XCTest
import Logging
@testable import PostgresKit

final class TransactionDebugTests: PostgresKitTestCase {

    private var client: PostgresDatabaseClient!
    private var testLogger: Logger!

    override func setUp() async throws {
        TestEnv.loadDotEnv()
        try await super.setUp()
        guard TestEnv.isConfigured else {
            throw XCTSkip("POSTGRES_HOST not set; skipping integration test")
        }
        testLogger = Logger(label: "transaction-debug-tests")

        let config = PostgresConfiguration(
            host: TestEnv.host,
            port: TestEnv.port,
            database: TestEnv.database,
            username: TestEnv.username,
            password: TestEnv.password,
            useTLS: TestEnv.useTLS,
            applicationName: "TransactionDebugTests"
        )

        client = try await PostgresDatabaseClient.connect(configuration: config, logger: testLogger)
    }

    override func tearDown() {
        client?.close()
        super.tearDown()
    }

    // Test to understand the behavior of temporary tables
    func testTemporaryTableBehavior() async throws {
        print("=== Testing Temporary Table Behavior ===")

        let result = try await client.withConnection { conn in
            // Create temporary table and test its behavior
            _ = try await conn.simpleQuery("CREATE TEMPORARY TABLE debug_tx (id SERIAL PRIMARY KEY, value TEXT)")

            // Insert a row and check immediate result
            print("About to insert first row...")
            _ = try await conn.simpleQuery("INSERT INTO debug_tx (value) VALUES ('test1')")
            print("First insert completed")

            // Count immediately
            let countRows1 = try await conn.simpleQuery("SELECT COUNT(*)::text FROM debug_tx")
            var count1 = 0
            for try await countStr in countRows1.decode(String.self) {
                if let intVal = Int(countStr) {
                    count1 = intVal
                }
                break
            }
            print("After 1 insert: COUNT = \(count1)")

            // Verify the actual data exists
            let dataRows1 = try await conn.simpleQuery("SELECT id, value FROM debug_tx")
            var rowCount1 = 0
            for try await (id, value) in dataRows1.decode((Int32, String).self) {
                rowCount1 += 1
                print("Found row: id=\(id), value='\(value)'")
            }
            print("Actual rows found: \(rowCount1)")

            // Insert another row
            print("About to insert second row...")
            _ = try await conn.simpleQuery("INSERT INTO debug_tx (value) VALUES ('test2')")
            print("Second insert completed")

            // Count again
            let countRows2 = try await conn.simpleQuery("SELECT COUNT(*)::text FROM debug_tx")
            var count2 = 0
            for try await countStr in countRows2.decode(String.self) {
                if let intVal = Int(countStr) {
                    count2 = intVal
                }
                break
            }
            print("After 2 inserts: COUNT = \(count2)")

            // Verify the actual data exists again
            let dataRows2 = try await conn.simpleQuery("SELECT id, value FROM debug_tx")
            var rowCount2 = 0
            for try await (id, value) in dataRows2.decode((Int32, String).self) {
                rowCount2 += 1
                print("Found row: id=\(id), value='\(value)'")
            }
            print("Actual rows found after second insert: \(rowCount2)")

            return Int32(count2)
        }

        XCTAssertEqual(result, 2)
        print("Test completed successfully. Temporary table behavior seems normal.")
    }

    func testTransactionIsolation() async throws {
        print("=== Testing Transaction Isolation ===")

        let result = try await client.withConnection { conn in
            // Start transaction
            _ = try await conn.simpleQuery("BEGIN")

            // Create table inside transaction
            _ = try await conn.simpleQuery("CREATE TEMPORARY TABLE iso_tx (id SERIAL PRIMARY KEY, value TEXT)")

            // Insert rows inside transaction
            _ = try await conn.simpleQuery("INSERT INTO iso_tx (value) VALUES ('iso1')")
            _ = try await conn.simpleQuery("INSERT INTO iso_tx (value) VALUES ('iso2')")

            // Count inside transaction (before commit)
            let countBefore = try await conn.simpleQuery("SELECT COUNT(*)::text FROM iso_tx")
            var beforeCount = 0
            for try await countStr in countBefore.decode(String.self) {
                if let intVal = Int(countStr) {
                    beforeCount = intVal
                }
                break
            }
            print("Before COMMIT: COUNT = \(beforeCount)")

            // Commit transaction
            _ = try await conn.simpleQuery("COMMIT")

            // Count after commit
            let countAfter = try await conn.simpleQuery("SELECT COUNT(*)::text FROM iso_tx")
            var afterCount = 0
            for try await countStr in countAfter.decode(String.self) {
                if let intVal = Int(countStr) {
                    afterCount = intVal
                }
                break
            }
            print("After COMMIT: COUNT = \(afterCount)")

            return Int32(afterCount)
        }

        XCTAssertEqual(result, 2)
        print("Transaction isolation test completed successfully.")
    }

    func testRollbackBehavior() async throws {
        print("=== Testing Rollback Behavior ===")

        let result = try await client.withConnection { conn in
            // Create table outside transaction so it persists after rollback
            _ = try await conn.simpleQuery("CREATE TEMPORARY TABLE rollback_tx (id SERIAL PRIMARY KEY, value TEXT)")

            // Start transaction
            _ = try await conn.simpleQuery("BEGIN")

            // Insert row inside transaction
            _ = try await conn.simpleQuery("INSERT INTO rollback_tx (value) VALUES ('rollback_test')")

            // Count inside transaction (before rollback)
            let countBefore = try await conn.simpleQuery("SELECT COUNT(*)::text FROM rollback_tx")
            var beforeCount = 0
            for try await countStr in countBefore.decode(String.self) {
                if let intVal = Int(countStr) {
                    beforeCount = intVal
                }
                break
            }
            print("Before ROLLBACK: COUNT = \(beforeCount)")

            // Rollback transaction
            _ = try await conn.simpleQuery("ROLLBACK")

            // Count after rollback (table should still exist but be empty)
            let countAfter = try await conn.simpleQuery("SELECT COUNT(*)::text FROM rollback_tx")
            var afterCount = 0
            for try await countStr in countAfter.decode(String.self) {
                if let intVal = Int(countStr) {
                    afterCount = intVal
                }
                break
            }
            print("After ROLLBACK: COUNT = \(afterCount)")

            return Int32(afterCount)
        }

        XCTAssertEqual(result, 0)
        print("Rollback test completed successfully.")
    }
}