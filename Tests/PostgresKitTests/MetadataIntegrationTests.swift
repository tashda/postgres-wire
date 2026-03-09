@testable import PostgresKit
import XCTest
import Logging

final class MetadataIntegrationTests: XCTestCase {
    var client: PostgresDatabaseClient!

    override func setUp() async throws {
        TestEnv.loadDotEnv()
        let logger = Logger(label: "postgres-kit-tests")
        let config = PostgresConfiguration(
            host: TestEnv.host,
            port: TestEnv.port,
            database: TestEnv.database,
            username: TestEnv.username,
            password: TestEnv.password,
            useTLS: TestEnv.useTLS,
            applicationName: "postgres-wire-tests"
        )
        self.client = try await PostgresDatabaseClient.connect(configuration: config, logger: logger)
    }

    override func tearDown() async throws {
        client?.close()
    }

    func testColumnsByTable() async throws {
        let schema = "public"
        // Use a fixed table name to ensure it exists for metadata queries
        let table = "kit_meta_test_table"
        let refTable = "kit_meta_ref_table"

        // Create tables - drop if exists first to handle test reruns
        try await client.withConnection { conn in
            _ = try await conn.simpleQuery("DROP TABLE IF EXISTS \(table) CASCADE")
            _ = try await conn.simpleQuery("DROP TABLE IF EXISTS \(refTable) CASCADE")
            _ = try await conn.simpleQuery("CREATE TABLE \(refTable) (id INT PRIMARY KEY, description TEXT)")
            _ = try await conn.simpleQuery("CREATE TABLE \(table) (id INT PRIMARY KEY, name TEXT, ref_id INT)")
            _ = try await conn.simpleQuery("ALTER TABLE \(table) ADD CONSTRAINT fk_ref FOREIGN KEY (ref_id) REFERENCES \(refTable)(id)")

            // Insert some test data to ensure tables are properly created
            _ = try await conn.simpleQuery("INSERT INTO \(refTable) (id, description) VALUES (1, 'test ref')")
            _ = try await conn.simpleQuery("INSERT INTO \(table) (id, name, ref_id) VALUES (1, 'test', 1)")
        }

        defer {
            Task.detached { [client] in
                try? await client?.withConnection { conn in
                    _ = try? await conn.simpleQuery("DROP TABLE IF EXISTS \(table) CASCADE")
                    _ = try? await conn.simpleQuery("DROP TABLE IF EXISTS \(refTable) CASCADE")
                }
            }
        }

        let meta = PostgresMetadata()
        let byTable = try await meta.columnsByTable(using: client, schema: schema)

        // Debug output
        print("Available tables in schema '\(schema)': \(byTable.keys.sorted())")
        print("Looking for table: '\(table)'")

        guard let details = byTable[table] else {
            // Try to get more debug info
            do {
                let availableTables = try await meta.listTablesAndViews(using: client, schema: schema)
                print("Tables from listTablesAndViews: \(availableTables.map { $0.name }.sorted())")
            } catch {
                print("Failed to list tables: \(error)")
            }
            return XCTFail("Expected details for table \(table)")
        }

        // Expect id, name, ref_id
        let names = Set(details.map { $0.name })
        XCTAssertTrue(names.contains("id"))
        XCTAssertTrue(names.contains("name"))
        XCTAssertTrue(names.contains("ref_id"))
        // Primary key on id
        XCTAssertTrue(details.first(where: { $0.name == "id" })?.isPrimaryKey == true)
        // Foreign key on ref_id
        XCTAssertNotNil(details.first(where: { $0.name == "ref_id" })?.foreignKey)
    }
}
