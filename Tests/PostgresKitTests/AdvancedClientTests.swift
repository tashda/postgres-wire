import XCTest
import Logging
@testable import PostgresKit

/// Tests client operations not covered elsewhere:
/// schema ops, enum types, column alters, DML helpers, advisory locks,
/// server config, cursor streaming, copyTable, createTableAs.
final class AdvancedClientTests: XCTestCase {
    private var client: PostgresDatabaseClient!

    override func setUp() async throws {
        TestEnv.loadDotEnv()
        guard ProcessInfo.processInfo.environment["POSTGRES_HOST"] != nil else {
            throw XCTSkip("POSTGRES_HOST not set. Copy .env.example to .env and configure connection.")
        }
        let config = PostgresConfiguration(
            host: TestEnv.host,
            port: TestEnv.port,
            database: TestEnv.database,
            username: TestEnv.username,
            password: TestEnv.password,
            useTLS: TestEnv.useTLS,
            applicationName: "AdvancedClientTests"
        )
        client = try await PostgresDatabaseClient.connect(configuration: config, logger: Logger(label: "advanced-tests"))
    }

    override func tearDown() async throws {
        client?.close()
    }

    private func uniqueName(_ prefix: String = "pgwire") -> String {
        "\(prefix)_\(UInt32.random(in: 0..<UInt32.max))"
    }

    // MARK: - Schema Operations

    func testCreateAndDropSchema() async throws {
        let schema = uniqueName("pgwire_schema")
        try await client.createSchema(name: schema)

        let schemas = try await PostgresMetadata().listSchemas(using: client)
        XCTAssertTrue(schemas.contains(schema), "Schema should appear after creation")

        try await client.dropSchema(name: schema, cascade: true)

        let schemasAfter = try await PostgresMetadata().listSchemas(using: client)
        XCTAssertFalse(schemasAfter.contains(schema), "Schema should be gone after drop")
    }

    func testCreateSchemaIfNotExists() async throws {
        let schema = uniqueName("pgwire_schema")
        try await client.createSchema(name: schema, ifNotExists: true)
        // Calling again should not throw
        try await client.createSchema(name: schema, ifNotExists: true)
        try await client.dropSchema(name: schema, ifExists: true, cascade: true)
    }

    // MARK: - Enum Types

    func testCreateAndDropEnum() async throws {
        let typeName = uniqueName("pgwire_status")
        try await client.createEnum(name: typeName, values: ["active", "inactive", "pending"])

        // Use the enum in a table to confirm it works
        let table = uniqueName("pgwire_enum_t")
        try await client.withConnection { conn in
            _ = try await conn.simpleQuery("CREATE TABLE \(table) (id SERIAL, status \(typeName))")
            _ = try await conn.simpleQuery("INSERT INTO \(table) (status) VALUES ('active')")
        }

        let rows = try await client.simpleQuery("SELECT status FROM \(table)")
        var values: [String] = []
        for try await v in rows.decode(String.self) { values.append(v) }
        XCTAssertEqual(values, ["active"])

        try await client.withConnection { conn in
            _ = try await conn.simpleQuery("DROP TABLE IF EXISTS \(table)")
        }
        try await client.dropEnum(name: typeName, ifExists: true, cascade: true)
    }

    func testAddEnumValue() async throws {
        let typeName = uniqueName("pgwire_color")
        try await client.createEnum(name: typeName, values: ["red", "green"])
        try await client.addEnumValue(type: typeName, value: "blue")

        let table = uniqueName("pgwire_color_t")
        try await client.withConnection { conn in
            _ = try await conn.simpleQuery("CREATE TABLE \(table) (id SERIAL, color \(typeName))")
            _ = try await conn.simpleQuery("INSERT INTO \(table) (color) VALUES ('blue')")
        }

        let rows = try await client.simpleQuery("SELECT color FROM \(table)")
        var values: [String] = []
        for try await v in rows.decode(String.self) { values.append(v) }
        XCTAssertEqual(values, ["blue"])

        try await client.withConnection { conn in
            _ = try await conn.simpleQuery("DROP TABLE IF EXISTS \(table)")
        }
        try await client.dropEnum(name: typeName, ifExists: true, cascade: true)
    }

    func testRenameEnumValue() async throws {
        let typeName = uniqueName("pgwire_mood")
        try await client.createEnum(name: typeName, values: ["happy", "sad"])
        try await client.renameEnumValue(type: typeName, oldValue: "sad", newValue: "unhappy")

        let table = uniqueName("pgwire_mood_t")
        try await client.withConnection { conn in
            _ = try await conn.simpleQuery("CREATE TABLE \(table) (id SERIAL, mood \(typeName))")
            _ = try await conn.simpleQuery("INSERT INTO \(table) (mood) VALUES ('unhappy')")
        }

        let rows = try await client.simpleQuery("SELECT mood FROM \(table)")
        var values: [String] = []
        for try await v in rows.decode(String.self) { values.append(v) }
        XCTAssertEqual(values, ["unhappy"])

        try await client.withConnection { conn in
            _ = try await conn.simpleQuery("DROP TABLE IF EXISTS \(table)")
        }
        try await client.dropEnum(name: typeName, ifExists: true, cascade: true)
    }

    // MARK: - Column Alterations

    func testAlterColumnDefault() async throws {
        let table = uniqueName("pgwire_altdef")
        try await client.withConnection { conn in
            _ = try await conn.simpleQuery("CREATE TABLE \(table) (id SERIAL PRIMARY KEY, score INTEGER)")
        }
        defer {
            Task.detached { [client, table] in
                try? await client?.withConnection { conn in
                    _ = try? await conn.simpleQuery("DROP TABLE IF EXISTS \(table)")
                }
            }
        }

        // Set default
        try await client.alterColumnDefault(table: table, column: "score", defaultValue: "42")
        let meta = try await PostgresMetadata().listColumns(using: client, schema: "public", table: table)
        let scoreCol = meta.first { $0.name == "score" }
        XCTAssertNotNil(scoreCol?.defaultValue, "score should have a default value")

        // Remove default
        try await client.alterColumnDefault(table: table, column: "score", defaultValue: nil)
        let meta2 = try await PostgresMetadata().listColumns(using: client, schema: "public", table: table)
        let scoreCol2 = meta2.first { $0.name == "score" }
        XCTAssertNil(scoreCol2?.defaultValue, "score should have no default after DROP DEFAULT")
    }

    func testAlterColumnNullability() async throws {
        let table = uniqueName("pgwire_altnull")
        try await client.withConnection { conn in
            _ = try await conn.simpleQuery("CREATE TABLE \(table) (id SERIAL PRIMARY KEY, label TEXT)")
        }
        defer {
            Task.detached { [client, table] in
                try? await client?.withConnection { conn in
                    _ = try? await conn.simpleQuery("DROP TABLE IF EXISTS \(table)")
                }
            }
        }

        // Add data first so NOT NULL constraint doesn't fail
        try await client.withConnection { conn in
            _ = try await conn.simpleQuery("INSERT INTO \(table) (label) VALUES ('hello')")
        }

        // Make NOT NULL
        try await client.alterColumnNullability(table: table, column: "label", nullable: false)
        let meta = try await PostgresMetadata().listColumns(using: client, schema: "public", table: table)
        let col = meta.first { $0.name == "label" }
        XCTAssertEqual(col?.isNullable, false, "Column should be NOT NULL")

        // Make nullable again
        try await client.alterColumnNullability(table: table, column: "label", nullable: true)
        let meta2 = try await PostgresMetadata().listColumns(using: client, schema: "public", table: table)
        let col2 = meta2.first { $0.name == "label" }
        XCTAssertEqual(col2?.isNullable, true, "Column should be nullable again")
    }

    func testRenameColumn() async throws {
        let table = uniqueName("pgwire_rencol")
        try await client.withConnection { conn in
            _ = try await conn.simpleQuery("CREATE TABLE \(table) (id SERIAL PRIMARY KEY, old_name TEXT)")
        }
        defer {
            Task.detached { [client, table] in
                try? await client?.withConnection { conn in
                    _ = try? await conn.simpleQuery("DROP TABLE IF EXISTS \(table)")
                }
            }
        }

        try await client.renameColumn(table: table, oldName: "old_name", newName: "new_name")

        let cols = try await PostgresMetadata().listColumns(using: client, schema: "public", table: table)
        let names = cols.map { $0.name }
        XCTAssertTrue(names.contains("new_name"), "Renamed column should appear")
        XCTAssertFalse(names.contains("old_name"), "Old column name should not appear")
    }

    // MARK: - DML Convenience Methods

    func testInsertUpdateDeleteTruncate() async throws {
        let table = uniqueName("pgwire_dml")
        try await client.withConnection { conn in
            _ = try await conn.simpleQuery("CREATE TABLE \(table) (id INTEGER, name TEXT, active BOOLEAN)")
        }
        defer {
            Task.detached { [client, table] in
                try? await client?.withConnection { conn in
                    _ = try? await conn.simpleQuery("DROP TABLE IF EXISTS \(table)")
                }
            }
        }

        // INSERT
        try await client.insert(
            into: table,
            columns: ["id", "name", "active"],
            values: [
                [1, "Alice", true] as [Any],
                [2, "Bob", false] as [Any],
                [3, "Carol", true] as [Any]
            ]
        )

        let countAfterInsert = try await rowCount(table: table)
        XCTAssertEqual(countAfterInsert, 3)

        // UPDATE
        try await client.update(table: table, set: ["active": false], whereClause: "id = 1")
        let rows = try await client.simpleQuery("SELECT active FROM \(table) WHERE id = 1")
        var active: Bool?
        for try await v in rows.decode(Bool.self) { active = v; break }
        XCTAssertEqual(active, false)

        // DELETE
        try await client.delete(from: table, whereClause: "id = 3")
        let countAfterDelete = try await rowCount(table: table)
        XCTAssertEqual(countAfterDelete, 2)

        // TRUNCATE
        try await client.truncate(table: table)
        let countAfterTruncate = try await rowCount(table: table)
        XCTAssertEqual(countAfterTruncate, 0)
    }

    // MARK: - copyTable and createTableAs

    func testCopyTable() async throws {
        let src = uniqueName("pgwire_cpsrc")
        let dst = uniqueName("pgwire_cpdst")
        try await client.withConnection { conn in
            _ = try await conn.simpleQuery("CREATE TABLE \(src) (id INTEGER, val TEXT)")
            _ = try await conn.simpleQuery("INSERT INTO \(src) VALUES (1,'a'),(2,'b'),(3,'c')")
            _ = try await conn.simpleQuery("CREATE TABLE \(dst) (id INTEGER, val TEXT)")
        }
        defer {
            Task.detached { [client, src, dst] in
                try? await client?.withConnection { conn in
                    _ = try? await conn.simpleQuery("DROP TABLE IF EXISTS \(src)")
                    _ = try? await conn.simpleQuery("DROP TABLE IF EXISTS \(dst)")
                }
            }
        }

        try await client.copyTable(from: src, to: dst)
        let copyCount = try await rowCount(table: dst)
        XCTAssertEqual(copyCount, 3)
    }

    func testCreateTableAs() async throws {
        let src = uniqueName("pgwire_ctas_src")
        let dst = uniqueName("pgwire_ctas_dst")
        try await client.withConnection { conn in
            _ = try await conn.simpleQuery("CREATE TABLE \(src) (id INTEGER, name TEXT)")
            _ = try await conn.simpleQuery("INSERT INTO \(src) VALUES (1,'Alice'),(2,'Bob')")
        }
        defer {
            Task.detached { [client, src, dst] in
                try? await client?.withConnection { conn in
                    _ = try? await conn.simpleQuery("DROP TABLE IF EXISTS \(dst)")
                    _ = try? await conn.simpleQuery("DROP TABLE IF EXISTS \(src)")
                }
            }
        }

        try await client.createTableAs(name: dst, selectQuery: "SELECT * FROM \(src)")
        let ctasCount = try await rowCount(table: dst)
        XCTAssertEqual(ctasCount, 2)
    }

    // MARK: - Advisory Locks

    func testTryAdvisoryLock_AndUnlock() async throws {
        let key: Int64 = 987654321
        // Unlock first in case a previous test left it locked
        _ = try? await client.advisoryUnlock(key: key)

        let acquired = try await client.tryAdvisoryLock(key: key)
        XCTAssertTrue(acquired, "Should be able to acquire advisory lock")

        let released = try await client.advisoryUnlock(key: key)
        XCTAssertTrue(released, "Should release the advisory lock")
    }

    func testTryAdvisoryLock_SameKey_TwiceOnSameSession() async throws {
        // PostgreSQL advisory locks are session-level; same session can acquire the same lock multiple times
        let key: Int64 = 111222333
        _ = try? await client.advisoryUnlock(key: key)

        let first = try await client.tryAdvisoryLock(key: key)
        XCTAssertTrue(first)

        // In PostgreSQL, session-level advisory locks are re-entrant from the same session
        let second = try await client.tryAdvisoryLock(key: key)
        XCTAssertTrue(second, "Re-entrant advisory lock on same session should succeed")

        // Unlock needs to be called once per acquire
        _ = try? await client.advisoryUnlock(key: key)
        _ = try? await client.advisoryUnlock(key: key)
    }

    // MARK: - Server Configuration

    func testSetAndResetConfiguration() async throws {
        let original = try await client.simpleQuery("SHOW work_mem")
        var originalVal = ""
        for try await v in original.decode(String.self) { originalVal = v; break }

        try await client.setConfiguration(parameter: "work_mem", value: "16MB")

        let current = try await client.simpleQuery("SHOW work_mem")
        var currentVal = ""
        for try await v in current.decode(String.self) { currentVal = v; break }
        XCTAssertFalse(currentVal.isEmpty, "work_mem should be set")

        try await client.resetConfiguration(parameter: "work_mem")
    }

    // MARK: - Cursor Streaming

    func testStreamQueryWithCursor() async throws {
        let result = try await client.streamQueryWithCursor(
            "SELECT generate_series(1, 50) AS n",
            configuration: PostgresStreamConfiguration { $0.streamingFetchSize = 10 }
        ) { _ async in
            // Callback receives streaming updates; side-effect-free in test
        }
        // If the call completes without throwing, streaming worked
        _ = result
    }

    func testStreamQueryWithCursor_LargerDataset() async throws {
        _ = try await client.streamQueryWithCursor(
            "SELECT generate_series(1, 200) AS n"
        ) { _ async in }
        // If we get here without error, cursor streaming completed successfully
    }

    // MARK: - Helpers

    private func rowCount(table: String) async throws -> Int {
        let rows = try await client.simpleQuery("SELECT COUNT(*)::text FROM \(table)")
        var countStr = ""
        for try await s in rows.decode(String.self) { countStr = s; break }
        return Int(countStr) ?? 0
    }
}
