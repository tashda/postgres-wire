import XCTest
import Logging
@testable import PostgresKit

final class SimpleInsertTest: XCTestCase {

    private var client: PostgresDatabaseClient!
    private var testLogger: Logger!

    override func setUp() async throws {
        TestEnv.loadDotEnv()
        try await super.setUp()
        guard ProcessInfo.processInfo.environment["POSTGRES_HOST"] != nil else {
            throw XCTSkip("POSTGRES_HOST not set; skipping integration test")
        }
        testLogger = Logger(label: "simple-insert-test")

        let config = PostgresConfiguration(
            host: TestEnv.host,
            port: TestEnv.port,
            database: TestEnv.database,
            username: TestEnv.username,
            password: TestEnv.password,
            useTLS: TestEnv.useTLS,
            applicationName: "SimpleInsertTest"
        )

        client = try await PostgresDatabaseClient.connect(configuration: config, logger: testLogger)
    }

    override func tearDown() {
        client?.close()
        super.tearDown()
    }

    func testVerySimpleInsert() async throws {
        print("=== Testing Very Simple Insert ===")

        let result = try await client.withConnection { conn in
            // Create table without SERIAL to avoid complications
            _ = try await conn.simpleQuery("CREATE TEMPORARY TABLE simple_test (name TEXT, number INTEGER)")

            // First insert
            print("Inserting first row...")
            _ = try await conn.simpleQuery("INSERT INTO simple_test (name, number) VALUES ('first', 1)")
            print("First insert done")

            // Second insert
            print("Inserting second row...")
            _ = try await conn.simpleQuery("INSERT INTO simple_test (name, number) VALUES ('second', 2)")
            print("Second insert done")

            // Get all data
            print("Fetching all rows...")
            let allRows = try await conn.simpleQuery("SELECT name, number FROM simple_test ORDER BY number")
            var collectedData: [(String, Int)] = []

            for try await (name, number) in allRows.decode((String, Int).self) {
                collectedData.append((name, number))
                print("Found row: name='\(name)', number=\(number)")
            }

            print("Total rows found: \(collectedData.count)")
            return collectedData.count
        }

        print("Test completed with \(result) rows")
        XCTAssertEqual(result, 2, "Should have found exactly 2 rows")
    }

    func testSingleRowSelect() async throws {
        print("=== Testing Single Row Select ===")

        let result = try await client.withConnection { conn in
            // Create table
            _ = try await conn.simpleQuery("CREATE TEMPORARY TABLE single_test (name TEXT)")

            // Insert one row
            print("Inserting single row...")
            _ = try await conn.simpleQuery("INSERT INTO single_test (name) VALUES ('single')")
            print("Single insert done")

            // Select with COUNT
            print("Running COUNT query...")
            let countRows = try await conn.simpleQuery("SELECT COUNT(*)::text as count FROM single_test")
            var count = 0
            for try await countStr in countRows.decode(String.self) {
                print("COUNT query returned: '\(countStr)'")
                if let intVal = Int(countStr) {
                    count = intVal
                }
                break
            }

            // Select actual data
            print("Running SELECT query...")
            let dataRows = try await conn.simpleQuery("SELECT name FROM single_test")
            var actualCount = 0
            for try await name in dataRows.decode(String.self) {
                actualCount += 1
                print("Found name: '\(name)'")
            }

            print("COUNT result: \(count), Actual count: \(actualCount)")
            return count
        }

        print("Single row test completed with result: \(result)")
        XCTAssertEqual(result, 1, "Should have found exactly 1 row")
    }
}