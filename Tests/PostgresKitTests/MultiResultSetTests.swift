import XCTest
import Logging
@testable import PostgresKit

final class MultiResultSetTests: PostgresKitTestCase {

    private var client: PostgresKit.PostgresClient!
    private var testLogger: Logger!

    override func setUp() async throws {
        try await super.setUp()
        testLogger = Logger(label: "multi-result-set-tests")

        guard TestEnv.isConfigured else { throw XCTSkip("Postgres environment not set") }

        let config = PostgresConfiguration(
            host: TestEnv.host,
            port: TestEnv.port,
            database: TestEnv.database,
            username: TestEnv.username,
            password: TestEnv.password,
            useTLS: TestEnv.useTLS,
            applicationName: "MultiResultSetTests"
        )

        client = try await PostgresKit.PostgresClient.connect(configuration: config, logger: testLogger)
    }

    override func tearDown() {
        client?.close()
        super.tearDown()
    }

    // MARK: - Single Statement Baseline

    func testSingleStatementBaseline() async throws {
        let rows = try await client.connection.simpleQuery("SELECT 1 AS value")
        var values: [Int] = []
        for try await value in rows.decode(Int.self) {
            values.append(value)
        }
        XCTAssertEqual(values, [1], "Single SELECT should return exactly one row with value 1")
    }

    // MARK: - Multiple Statements via Simple Query

    func testSimpleQueryMultipleStatements() async throws {
        // PostgreSQL simple query protocol allows multiple statements separated by semicolons.
        // The wire protocol returns multiple result sets; the client should yield at least
        // the first result set's rows.
        let rows = try await client.connection.simpleQuery("SELECT 1 AS a; SELECT 2 AS b")

        var values: [Int] = []
        for try await value in rows.decode(Int.self) {
            values.append(value)
        }

        // At minimum, the first result set (value 1) must be present.
        // If the driver merges both result sets, we also accept [1, 2].
        XCTAssertFalse(values.isEmpty, "Should return at least one row from multi-statement query")
        XCTAssertTrue(values.contains(1), "First result set value (1) should be present")
    }

    func testSimpleQueryMultipleStatementsRowCounts() async throws {
        // Create a temp table, insert rows, then run two SELECTs in one simple query.
        try await client.connection.withConnection { conn in
            _ = try await conn.simpleQuery("""
                CREATE TEMPORARY TABLE multi_rs_test (id SERIAL PRIMARY KEY, name TEXT);
                INSERT INTO multi_rs_test (name) VALUES ('alpha'), ('beta'), ('gamma');
                """)
        }

        // Execute two queries in a single simple-query message:
        // 1) SELECT all rows  2) SELECT COUNT(*)
        let rows = try await client.connection.simpleQuery(
            "SELECT name FROM multi_rs_test ORDER BY id; SELECT COUNT(*)::int FROM multi_rs_test"
        )

        var allValues: [String] = []
        for try await value in rows.decode(String.self) {
            allValues.append(value)
        }

        // The first result set should contain 3 name values.
        // Depending on driver behavior, the second result set's count ("3") may also appear.
        XCTAssertGreaterThanOrEqual(allValues.count, 3,
            "Should have at least 3 rows from the first result set")
        XCTAssertTrue(allValues.contains("alpha"), "Should contain 'alpha'")
        XCTAssertTrue(allValues.contains("beta"), "Should contain 'beta'")
        XCTAssertTrue(allValues.contains("gamma"), "Should contain 'gamma'")
    }

    // MARK: - Streaming Multiple Statements

    func testStreamingMultipleStatements() async throws {
        // Execute two generate_series queries via the streaming API.
        // Verify that streaming delivers rows progressively.
        let counter = StreamUpdateCounter()

        let result = try await client.connection.streamQuery(
            "SELECT generate_series(1, 5) AS val; SELECT generate_series(1, 3) AS val"
        ) { update in
            await counter.record(update)
        }

        let updateCount = await counter.count

        // The stream result should report at least 5 rows (from the first series).
        // If the driver processes both result sets, we may see up to 8.
        XCTAssertGreaterThanOrEqual(result.totalRowCount, 5,
            "Stream should deliver at least 5 rows from generate_series(1,5)")
        XCTAssertGreaterThanOrEqual(updateCount, 1,
            "Should have received at least one streaming update")
    }

    // MARK: - Mixed DML and SELECT

    func testMixedDMLAndSelect() async throws {
        // Create a temp table, then in a single simple-query batch: INSERT + SELECT.
        try await client.connection.withConnection { conn in
            _ = try await conn.simpleQuery(
                "CREATE TEMPORARY TABLE mixed_dml_test (id SERIAL PRIMARY KEY, label TEXT)"
            )
        }

        // Execute INSERT followed by SELECT in a single simple query.
        // The INSERT produces a command completion (not a row set),
        // the SELECT produces a row set.
        let rows = try await client.connection.simpleQuery("""
            INSERT INTO mixed_dml_test (label) VALUES ('one'), ('two'), ('three');
            SELECT label FROM mixed_dml_test ORDER BY id
            """)

        var labels: [String] = []
        for try await label in rows.decode(String.self) {
            labels.append(label)
        }

        // We expect the SELECT result set to contain the 3 inserted rows.
        XCTAssertTrue(labels.contains("one"), "Should contain 'one'")
        XCTAssertTrue(labels.contains("two"), "Should contain 'two'")
        XCTAssertTrue(labels.contains("three"), "Should contain 'three'")
    }
}

// MARK: - Helpers

/// Thread-safe counter for streaming update callbacks.
private actor StreamUpdateCounter {
    private(set) var count: Int = 0
    private(set) var lastTotalRowCount: Int = 0

    func record(_ update: PostgresStreamUpdate) {
        count += 1
        lastTotalRowCount = update.totalRowCount
    }
}
