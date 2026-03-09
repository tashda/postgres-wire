import XCTest
import Logging
@testable import PostgresKit

final class AdminTests: XCTestCase {
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
            applicationName: "AdminTests"
        )
        client = try await PostgresDatabaseClient.connect(configuration: config, logger: Logger(label: "admin-tests"))
    }

    override func tearDown() async throws {
        client?.close()
    }

    private var admin: PostgresAdmin {
        PostgresAdmin(client: client, logger: Logger(label: "admin"))
    }

    // MARK: - VACUUM

    func testVacuumDatabase() async throws {
        // VACUUM the whole database — should complete without error
        try await admin.vacuum()
    }

    func testVacuumWithAnalyze() async throws {
        try await admin.vacuum(analyze: true)
    }

    func testVacuumSpecificTable() async throws {
        // Create a temp table, vacuum it, drop it
        _ = try await client.simpleQuery("CREATE TEMPORARY TABLE admin_vacuum_tmp (id INT)")
        _ = try await client.simpleQuery("INSERT INTO admin_vacuum_tmp VALUES (1),(2),(3)")
        _ = try await client.simpleQuery("DELETE FROM admin_vacuum_tmp")
        // VACUUM on a temp table is a no-op but must not throw
        try await admin.vacuum(table: "admin_vacuum_tmp")
    }

    // MARK: - ANALYZE

    func testAnalyzeDatabase() async throws {
        try await admin.analyze()
    }

    func testAnalyzeSpecificTable() async throws {
        _ = try await client.simpleQuery("CREATE TEMPORARY TABLE admin_analyze_tmp (id INT, name TEXT)")
        _ = try await client.simpleQuery("INSERT INTO admin_analyze_tmp VALUES (1,'a'),(2,'b')")
        try await admin.analyze(table: "admin_analyze_tmp")
    }

    // MARK: - REINDEX

    func testReindexDatabase() async throws {
        let db = TestEnv.database
        try await admin.reindex(database: db)
    }

    // MARK: - SHOW / SET

    func testShowWorkMem() async throws {
        let value = try await admin.show("work_mem")
        XCTAssertNotNil(value, "SHOW work_mem should return a value")
    }

    func testShowStatementTimeout() async throws {
        let value = try await admin.show("statement_timeout")
        XCTAssertNotNil(value)
    }

    func testSetAndRestoreWorkMem() async throws {
        let original = try await admin.show("work_mem")
        let testValue = "32MB"

        try await admin.set("work_mem", value: testValue)
        let updated = try await admin.show("work_mem")
        XCTAssertNotNil(updated)
        // The value may be normalised by Postgres (e.g. "32768kB") so just check it's non-nil

        // Restore
        if let original {
            try await admin.set("work_mem", value: original)
        }
        let restored = try await admin.show("work_mem")
        XCTAssertEqual(restored, original)
    }

    func testSetEnableSeqScan() async throws {
        try await admin.set("enable_seqscan", value: "off")
        let v = try await admin.show("enable_seqscan")
        XCTAssertEqual(v?.lowercased(), "off")
        try await admin.set("enable_seqscan", value: "on")
    }
}
