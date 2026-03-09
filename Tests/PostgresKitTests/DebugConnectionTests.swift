import XCTest
import Logging
@testable import PostgresKit

final class DebugConnectionTests: XCTestCase {
    private var client: PostgresDatabaseClient!
    private var testLogger: Logger!

    override func setUp() async throws {
        try await super.setUp()
        testLogger = Logger(label: "debug-connection-tests")

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

        print("🔍 Debug Connection Info:")
        print("  Host: \(host)")
        print("  Port: \(port)")
        print("  Database: \(db)")
        print("  Username: \(user)")
        print("  Password: \(password != nil ? "***" : "nil")")
        print("  TLS: \(useTLS)")

        let config = PostgresConfiguration(
            host: host,
            port: port,
            database: db,
            username: user,
            password: password,
            useTLS: useTLS,
            applicationName: "DebugConnectionTests"
        )

        do {
            client = try await PostgresDatabaseClient.connect(configuration: config, logger: testLogger)
            print("✅ Database connection successful!")
        } catch {
            print("❌ Database connection failed!")
            print("Error: \(error)")
            print("Error reflection: \(String(reflecting: error))")
            throw error
        }
    }

    override func tearDown() {
        client?.close()
        super.tearDown()
    }

    func testBasicConnection() async throws {
        print("🧪 Testing basic connection...")

        do {
            let result = try await client.simpleQuery("SELECT 1 as test_value")
            print("✅ Basic query successful!")

            for try await (value,) in result.decode(Int.self) {
                print("Query result: \(value)")
                XCTAssertEqual(value, 1)
                break
            }
        } catch {
            print("❌ Basic query failed!")
            print("Error: \(error)")
            print("Error reflection: \(String(reflecting: error))")
            throw error
        }
    }

    func testCreateSimpleTable() async throws {
        print("🧪 Testing simple table creation...")

        do {
            // Clean up first
            try? await client.simpleQuery("DROP TABLE IF EXISTS debug_test_table")

            // Create table
            _ = try await client.simpleQuery("""
                CREATE TABLE debug_test_table (
                    id SERIAL PRIMARY KEY,
                    name TEXT NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            print("✅ Table creation successful!")

            // Insert data
            _ = try await client.simpleQuery("INSERT INTO debug_test_table (name) VALUES ('test')")
            print("✅ Insert successful!")

            // Query data
            let result = try await client.simpleQuery("SELECT COUNT(*)::text FROM debug_test_table")
            for try await (count,) in result.decode(String.self) {
                print("Record count: \(count)")
                XCTAssertEqual(count, "1")
                break
            }

            // Clean up
            _ = try await client.simpleQuery("DROP TABLE debug_test_table")
            print("✅ Cleanup successful!")

        } catch {
            print("❌ Table operation failed!")
            print("Error: \(error)")
            print("Error reflection: \(String(reflecting: error))")
            throw error
        }
    }

    func testPostgresClientAPI() async throws {
        print("🧪 Testing PostgresClient API...")

        do {
            // Clean up first
            _ = try await client.dropTable(name: "debug_api_test", ifExists: true)

            // Test createTable API
            _ = try await client.createTable(
                name: "debug_api_test",
                columns: [
                    .bigSerial(name: "id", primaryKey: true),
                    .text(name: "name", nullable: false),
                    .integer(name: "value", defaultValue: 42)
                ]
            )
            print("✅ createTable API successful!")

            // Test insert API
            _ = try await client.insert(
                into: "debug_api_test",
                columns: ["name"],
                values: [["API Test"]]
            )
            print("✅ insert API successful!")

            // Test query
            let result = try await client.simpleQuery("SELECT COUNT(*)::text FROM debug_api_test")
            for try await (count,) in result.decode(String.self) {
                print("API test record count: \(count)")
                XCTAssertEqual(count, "1")
                break
            }

            // Clean up
            _ = try await client.dropTable(name: "debug_api_test", ifExists: false)
            print("✅ API cleanup successful!")

        } catch {
            print("❌ PostgresClient API test failed!")
            print("Error: \(error)")
            print("Error reflection: \(String(reflecting: error))")
            throw error
        }
    }
}