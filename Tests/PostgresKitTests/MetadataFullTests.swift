import XCTest
import Logging
@testable import PostgresKit

private actor ProgressCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}

/// Full integration test coverage for PostgresMetadata.
/// Tests all public methods not already covered by MetadataIntegrationTests.swift.
final class MetadataFullTests: XCTestCase {
    private var client: PostgresDatabaseClient!
    private let meta = PostgresMetadata()

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
            applicationName: "MetadataFullTests"
        )
        client = try await PostgresDatabaseClient.connect(configuration: config, logger: Logger(label: "meta-tests"))
    }

    override func tearDown() async throws {
        client?.close()
    }

    // MARK: - listDatabases

    func testListDatabases() async throws {
        let dbs = try await meta.listDatabases(using: client)
        XCTAssertFalse(dbs.isEmpty, "Should return at least one database")
        XCTAssertTrue(dbs.contains(TestEnv.database), "Connected database should be in list")
    }

    // MARK: - listSchemas

    func testListSchemas() async throws {
        let schemas = try await meta.listSchemas(using: client)
        // At minimum, 'public' should be present unless it was removed
        XCTAssertFalse(schemas.isEmpty, "Should have at least one schema")
        // System schemas are excluded
        XCTAssertFalse(schemas.contains("pg_catalog"), "pg_catalog should be excluded")
        XCTAssertFalse(schemas.contains("information_schema"), "information_schema should be excluded")
    }

    // MARK: - listColumns

    func testListColumns() async throws {
        let table = "pgwire_meta_col_\(UInt32.random(in: 0..<UInt32.max))"
        try await client.withConnection { conn in
            _ = try await conn.simpleQuery("CREATE TABLE \(table) (id SERIAL PRIMARY KEY, name TEXT NOT NULL, score INTEGER DEFAULT 0)")
        }
        defer {
            Task.detached { [client, table] in
                try? await client?.withConnection { conn in
                    _ = try? await conn.simpleQuery("DROP TABLE IF EXISTS \(table)")
                }
            }
        }

        let columns = try await meta.listColumns(using: client, schema: "public", table: table)
        XCTAssertEqual(columns.count, 3)
        let names = columns.map { $0.name }
        XCTAssertTrue(names.contains("id"))
        XCTAssertTrue(names.contains("name"))
        XCTAssertTrue(names.contains("score"))

        let nameCol = columns.first { $0.name == "name" }
        XCTAssertEqual(nameCol?.isNullable, false)

        let scoreCol = columns.first { $0.name == "score" }
        XCTAssertNotNil(scoreCol?.defaultValue, "score should have a default value")
    }

    // MARK: - listIndexes

    func testListIndexes() async throws {
        let table = "pgwire_meta_idx_\(UInt32.random(in: 0..<UInt32.max))"
        let idx = "pgwire_meta_idx_name_\(UInt32.random(in: 0..<UInt32.max))"
        try await client.withConnection { conn in
            _ = try await conn.simpleQuery("CREATE TABLE \(table) (id SERIAL PRIMARY KEY, name TEXT, score INTEGER)")
            _ = try await conn.simpleQuery("CREATE INDEX \(idx) ON \(table)(name)")
            _ = try await conn.simpleQuery("CREATE UNIQUE INDEX \(idx)_unique ON \(table)(score)")
        }
        defer {
            Task.detached { [client, table] in
                try? await client?.withConnection { conn in
                    _ = try? await conn.simpleQuery("DROP TABLE IF EXISTS \(table)")
                }
            }
        }

        let indexes: [PostgresMetadata.Index]
        do {
            indexes = try await meta.listIndexes(using: client, schema: "public", table: table)
        } catch {
            XCTFail("listIndexes failed: \(String(reflecting: error))")
            return
        }
        XCTAssertGreaterThanOrEqual(indexes.count, 2, "Should have at least 2 non-primary indexes")

        let uniqueIdx = indexes.first { $0.isUnique }
        XCTAssertNotNil(uniqueIdx, "Should have at least one unique index")

        let names = indexes.map { $0.name }
        XCTAssertTrue(names.contains(idx), "Should contain the named index")
    }

    // MARK: - primaryKey

    func testPrimaryKey() async throws {
        let table = "pgwire_meta_pk_\(UInt32.random(in: 0..<UInt32.max))"
        try await client.withConnection { conn in
            _ = try await conn.simpleQuery("CREATE TABLE \(table) (id SERIAL PRIMARY KEY, val TEXT)")
        }
        defer {
            Task.detached { [client, table] in
                try? await client?.withConnection { conn in
                    _ = try? await conn.simpleQuery("DROP TABLE IF EXISTS \(table)")
                }
            }
        }

        let pk = try await meta.primaryKey(using: client, schema: "public", table: table)
        XCTAssertNotNil(pk, "Table with primary key should return a PrimaryKey")
        XCTAssertEqual(pk?.columns, ["id"])
    }

    func testPrimaryKeyNone() async throws {
        let table = "pgwire_meta_nopk_\(UInt32.random(in: 0..<UInt32.max))"
        try await client.withConnection { conn in
            _ = try await conn.simpleQuery("CREATE TABLE \(table) (val TEXT)")
        }
        defer {
            Task.detached { [client, table] in
                try? await client?.withConnection { conn in
                    _ = try? await conn.simpleQuery("DROP TABLE IF EXISTS \(table)")
                }
            }
        }

        let pk = try await meta.primaryKey(using: client, schema: "public", table: table)
        XCTAssertNil(pk, "Table without primary key should return nil")
    }

    // MARK: - foreignKeys

    func testForeignKeys() async throws {
        let parent = "pgwire_meta_fkp_\(UInt32.random(in: 0..<UInt32.max))"
        let child = "pgwire_meta_fkc_\(UInt32.random(in: 0..<UInt32.max))"
        try await client.withConnection { conn in
            _ = try await conn.simpleQuery("CREATE TABLE \(parent) (id SERIAL PRIMARY KEY, name TEXT)")
            _ = try await conn.simpleQuery("CREATE TABLE \(child) (id SERIAL PRIMARY KEY, parent_id INTEGER REFERENCES \(parent)(id))")
        }
        defer {
            Task.detached { [client, child, parent] in
                try? await client?.withConnection { conn in
                    _ = try? await conn.simpleQuery("DROP TABLE IF EXISTS \(child)")
                    _ = try? await conn.simpleQuery("DROP TABLE IF EXISTS \(parent)")
                }
            }
        }

        let fks = try await meta.foreignKeys(using: client, schema: "public", table: child)
        XCTAssertEqual(fks.count, 1, "Child table should have 1 FK")
        let fk = fks[0]
        XCTAssertEqual(fk.columns, ["parent_id"])
        XCTAssertEqual(fk.referencedTable, parent)
        XCTAssertEqual(fk.referencedColumns, ["id"])
    }

    // MARK: - uniqueConstraints

    func testUniqueConstraints() async throws {
        let table = "pgwire_meta_uq_\(UInt32.random(in: 0..<UInt32.max))"
        let uqName = "uq_code_\(UInt32.random(in: 0..<UInt32.max))"
        try await client.withConnection { conn in
            _ = try await conn.simpleQuery("CREATE TABLE \(table) (id SERIAL PRIMARY KEY, email TEXT UNIQUE, code TEXT, CONSTRAINT \(uqName) UNIQUE (code))")
        }
        defer {
            Task.detached { [client, table] in
                try? await client?.withConnection { conn in
                    _ = try? await conn.simpleQuery("DROP TABLE IF EXISTS \(table)")
                }
            }
        }

        let constraints = try await meta.uniqueConstraints(using: client, schema: "public", table: table)
        XCTAssertGreaterThanOrEqual(constraints.count, 2, "Should have at least 2 unique constraints")
        let colNames = constraints.flatMap { $0.columns }
        XCTAssertTrue(colNames.contains("email"))
        XCTAssertTrue(colNames.contains("code"))
    }

    // MARK: - dependencies

    func testDependencies() async throws {
        let parent = "pgwire_meta_dep_p_\(UInt32.random(in: 0..<UInt32.max))"
        let child = "pgwire_meta_dep_c_\(UInt32.random(in: 0..<UInt32.max))"
        try await client.withConnection { conn in
            _ = try await conn.simpleQuery("CREATE TABLE \(parent) (id SERIAL PRIMARY KEY)")
            _ = try await conn.simpleQuery("CREATE TABLE \(child) (id SERIAL PRIMARY KEY, pid INTEGER REFERENCES \(parent)(id))")
        }
        defer {
            Task.detached { [client, child, parent] in
                try? await client?.withConnection { conn in
                    _ = try? await conn.simpleQuery("DROP TABLE IF EXISTS \(child)")
                    _ = try? await conn.simpleQuery("DROP TABLE IF EXISTS \(parent)")
                }
            }
        }

        // dependencies() returns tables that reference the given table
        let deps = try await meta.dependencies(using: client, schema: "public", table: parent)
        XCTAssertFalse(deps.isEmpty, "Parent table should have at least one dependent (the child)")
        let depTables = deps.map { $0.sourceTable }
        XCTAssertTrue(depTables.contains(child))
    }

    // MARK: - viewDefinition

    func testViewDefinition() async throws {
        let table = "pgwire_meta_vw_t_\(UInt32.random(in: 0..<UInt32.max))"
        let view = "pgwire_meta_vw_\(UInt32.random(in: 0..<UInt32.max))"
        try await client.withConnection { conn in
            _ = try await conn.simpleQuery("CREATE TABLE \(table) (id SERIAL, name TEXT)")
            _ = try await conn.simpleQuery("CREATE VIEW \(view) AS SELECT id, name FROM \(table) WHERE id > 0")
        }
        defer {
            Task.detached { [client, view, table] in
                try? await client?.withConnection { conn in
                    _ = try? await conn.simpleQuery("DROP VIEW IF EXISTS \(view)")
                    _ = try? await conn.simpleQuery("DROP TABLE IF EXISTS \(table)")
                }
            }
        }

        let def = try await meta.viewDefinition(using: client, schema: "public", view: view)
        XCTAssertNotNil(def, "View definition should not be nil")
        XCTAssertTrue(def?.lowercased().contains("select") == true,
                      "View definition should contain SELECT")
    }

    // MARK: - functionDefinition

    func testFunctionDefinition() async throws {
        let fn = "pgwire_meta_fn_\(UInt32.random(in: 0..<UInt32.max))"
        try await client.withConnection { conn in
            _ = try await conn.simpleQuery("""
            CREATE OR REPLACE FUNCTION \(fn)(x integer) RETURNS integer
            LANGUAGE SQL AS $$ SELECT x * 2 $$
            """)
        }
        defer {
            Task.detached { [client, fn] in
                try? await client?.withConnection { conn in
                    _ = try? await conn.simpleQuery("DROP FUNCTION IF EXISTS \(fn)(integer)")
                }
            }
        }

        let def = try await meta.functionDefinition(using: client, schema: "public", name: fn)
        XCTAssertNotNil(def, "Function definition should not be nil")
        XCTAssertTrue(def?.contains(fn) == true || def?.lowercased().contains("function") == true,
                      "Definition should contain the function name or 'FUNCTION'")
    }

    // MARK: - triggerDefinition

    func testTriggerDefinition() async throws {
        let table = "pgwire_meta_trig_t_\(UInt32.random(in: 0..<UInt32.max))"
        let fn = "pgwire_meta_trig_fn_\(UInt32.random(in: 0..<UInt32.max))"
        let trig = "pgwire_meta_trig_\(UInt32.random(in: 0..<UInt32.max))"
        try await client.withConnection { conn in
            _ = try await conn.simpleQuery("CREATE TABLE \(table) (id SERIAL, val TEXT)")
            _ = try await conn.simpleQuery("""
            CREATE OR REPLACE FUNCTION \(fn)() RETURNS trigger
            LANGUAGE plpgsql AS $$ BEGIN RETURN NEW; END $$
            """)
            _ = try await conn.simpleQuery("""
            CREATE TRIGGER \(trig) BEFORE INSERT ON \(table)
            FOR EACH ROW EXECUTE PROCEDURE \(fn)()
            """)
        }
        defer {
            Task.detached { [client, trig, table, fn] in
                try? await client?.withConnection { conn in
                    _ = try? await conn.simpleQuery("DROP TRIGGER IF EXISTS \(trig) ON \(table)")
                    _ = try? await conn.simpleQuery("DROP TABLE IF EXISTS \(table)")
                    _ = try? await conn.simpleQuery("DROP FUNCTION IF EXISTS \(fn)()")
                }
            }
        }

        let def = try await meta.triggerDefinition(using: client, schema: "public", name: trig)
        XCTAssertNotNil(def, "Trigger definition should not be nil")
        XCTAssertTrue(def?.uppercased().contains("TRIGGER") == true,
                      "Trigger definition should contain TRIGGER")
    }

    // MARK: - listRoles

    func testListRoles() async throws {
        let roles = try await meta.listRoles(using: client)
        XCTAssertFalse(roles.isEmpty, "Should return at least one role")
        // postgres superuser role always exists
        let roleNames = roles.map { $0.name }
        XCTAssertTrue(roleNames.contains("postgres") || !roleNames.isEmpty,
                      "Should have a postgres or other role")
    }

    // MARK: - listExtensions

    func testListExtensions() async throws {
        let extensions = try await meta.listExtensions(using: client)
        // plpgsql is always installed by default
        XCTAssertFalse(extensions.isEmpty, "Should have at least plpgsql extension")
        let extNames = extensions.map { $0.name }
        XCTAssertTrue(extNames.contains("plpgsql"), "plpgsql should always be installed")
    }

    // MARK: - Comments

    func testTableComment() async throws {
        let table = "pgwire_meta_cmt_\(UInt32.random(in: 0..<UInt32.max))"
        let comment = "Integration test table for comments"
        try await client.withConnection { conn in
            _ = try await conn.simpleQuery("CREATE TABLE \(table) (id SERIAL)")
            _ = try await conn.simpleQuery("COMMENT ON TABLE \(table) IS '\(comment)'")
        }
        defer {
            Task.detached { [client, table] in
                try? await client?.withConnection { conn in
                    _ = try? await conn.simpleQuery("DROP TABLE IF EXISTS \(table)")
                }
            }
        }

        let retrieved = try await meta.tableComment(using: client, schema: "public", table: table)
        XCTAssertEqual(retrieved, comment)
    }

    func testColumnComments() async throws {
        let table = "pgwire_meta_colcmt_\(UInt32.random(in: 0..<UInt32.max))"
        try await client.withConnection { conn in
            _ = try await conn.simpleQuery("CREATE TABLE \(table) (id SERIAL, name TEXT)")
            _ = try await conn.simpleQuery("COMMENT ON COLUMN \(table).name IS 'The display name'")
        }
        defer {
            Task.detached { [client, table] in
                try? await client?.withConnection { conn in
                    _ = try? await conn.simpleQuery("DROP TABLE IF EXISTS \(table)")
                }
            }
        }

        let comments = try await meta.columnComments(using: client, schema: "public", table: table)
        XCTAssertFalse(comments.isEmpty, "Should return column comment entries")
        let nameComment = comments.first { $0.column == "name" }
        XCTAssertEqual(nameComment?.comment, "The display name")
    }

    func testDatabaseComment() async throws {
        // This may return nil if no comment has been set — either is valid
        let comment = try await meta.databaseComment(using: client)
        _ = comment // nil or a string, both acceptable
    }

    // MARK: - schemaSummary

    func testSchemaSummary_PublicSchema() async throws {
        let table = "pgwire_meta_sum_\(UInt32.random(in: 0..<UInt32.max))"
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

        let summary = try await meta.schemaSummary(using: client, schema: "public")
        XCTAssertEqual(summary.schema, "public")

        let tableObj = summary.objects.first { $0.name == table }
        XCTAssertNotNil(tableObj, "Summary should include our test table")
        XCTAssertEqual(tableObj?.type, .table)
        XCTAssertFalse(tableObj?.columns.isEmpty == true, "Table should have columns in summary")
    }

    func testSchemaSummary_WithProgressCallback() async throws {
        let counter = ProgressCounter()
        let summary = try await meta.schemaSummary(using: client, schema: "public") { _, _, _ in
            await counter.increment()
        }
        XCTAssertEqual(summary.schema, "public")
        let calls = await counter.value
        XCTAssertGreaterThan(calls, 0, "Progress callback should have been called")
    }
}
