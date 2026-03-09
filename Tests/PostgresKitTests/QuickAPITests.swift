import XCTest
import Logging
@testable import PostgresKit

final class QuickAPITests: XCTestCase {
    private var client: PostgresDatabaseClient!
    private var testLogger: Logger!

    override func setUp() async throws {
        try await super.setUp()
        testLogger = Logger(label: "quick-api-tests")

                guard let host = ProcessInfo.processInfo.environment["POSTGRES_HOST"],

                      let user = ProcessInfo.processInfo.environment["POSTGRES_USERNAME"],

                      let db = ProcessInfo.processInfo.environment["POSTGRES_DATABASE"],

                      let portStr = ProcessInfo.processInfo.environment["POSTGRES_PORT"],

                      let port = Int(portStr)

                else {

                    throw XCTSkip("POSTGRES_* environment not set; skipping integration test")

                }

        

                let password = ProcessInfo.processInfo.environment["POSTGRES_PASSWORD"]

                let useTLS = (ProcessInfo.processInfo.environment["POSTGRES_TLS"] ?? "false").lowercased() == "true"

        let config = PostgresConfiguration(
            host: host,
            port: port,
            database: db,
            username: user,
            password: password,
            useTLS: useTLS,
            applicationName: "QuickAPITests"
        )

        client = try await PostgresDatabaseClient.connect(configuration: config, logger: testLogger)
    }

    override func tearDown() {
        client?.close()
        super.tearDown()
    }

    func testBasicCreateTableAPI() async throws {
        print("🧪 Testing createTable API...")

        do {
            // Clean up first
            _ = try await client.dropTable(name: "quick_test", ifExists: true)

            // Test createTable API
            _ = try await client.createTable(
                name: "quick_test",
                columns: [
                    .bigSerial(name: "id", primaryKey: true),
                    .text(name: "name", nullable: false),
                    .integer(name: "value", defaultValue: 0)
                ]
            )
            print("✅ createTable API successful!")

            // Test insert API
            _ = try await client.insert(
                into: "quick_test",
                columns: ["name"],
                values: [["Test Record"]]
            )
            print("✅ insert API successful!")

            // Verify data exists
            let result = try await client.simpleQuery("SELECT COUNT(*)::text FROM quick_test")
            for try await (count,) in result.decode(String.self) {
                print("Record count: \(count)")
                XCTAssertEqual(count, "1")
                break
            }

            // Clean up
            _ = try await client.dropTable(name: "quick_test", ifExists: false)
            print("✅ dropTable API successful!")

        } catch {
            print("❌ Quick API test failed!")
            print("Error details: \(String(reflecting: error))")
            throw error
        }
    }

    func testBasicSequenceAPI() async throws {
        print("🧪 Testing sequence API...")

        do {
            // Clean up first
            _ = try await client.dropSequence(name: "quick_test_seq", ifExists: true)

            // Test createSequence API
            _ = try await client.createSequence(name: "quick_test_seq")
            print("✅ createSequence API successful!")

            // Test nextval API
            let next1 = try await client.nextval("quick_test_seq")
            print("✅ nextval API successful! First value: \(next1)")

            let next2 = try await client.nextval("quick_test_seq")
            print("✅ nextval API successful! Second value: \(next2)")

            // Verify sequence increments
            XCTAssertEqual(next2, next1 + 1)

            // Clean up
            _ = try await client.dropSequence(name: "quick_test_seq", ifExists: false)
            print("✅ dropSequence API successful!")

        } catch {
            print("❌ Sequence API test failed!")
            print("Error details: \(String(reflecting: error))")
            throw error
        }
    }
}