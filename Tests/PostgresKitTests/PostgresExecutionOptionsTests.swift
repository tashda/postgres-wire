import XCTest
@testable import PostgresWire
@testable import PostgresKit

final class PostgresExecutionOptionsTests: PostgresKitTestCase {
    private var client: PostgresKit.PostgresClient!

    override func setUp() async throws {
        try await super.setUp()
        guard TestEnv.isConfigured else { throw XCTSkip("Postgres environment not set") }
        let config = PostgresConfiguration(
            host: TestEnv.host, port: TestEnv.port,
            database: TestEnv.database, username: TestEnv.username,
            password: TestEnv.password, useTLS: TestEnv.useTLS,
            applicationName: "ExecutionOptionsTests"
        )
        client = try await PostgresKit.PostgresClient.connect(configuration: config)
    }

    override func tearDown() {
        client?.close()
        super.tearDown()
    }

    // MARK: - Default Options

    func testDefaultOptions() {
        let options = PostgresExecutionOptions()
        XCTAssertEqual(options.mode, .auto)
        XCTAssertNil(options.cursorThreshold)
        XCTAssertNil(options.fetchBaseline)
        XCTAssertNil(options.fetchRampMultiplier)
        XCTAssertNil(options.fetchRampMax)
        XCTAssertNil(options.progressThrottleMs)
    }

    func testCustomOptions() {
        let options = PostgresExecutionOptions(
            mode: .auto,
            cursorThreshold: 25_000,
            fetchBaseline: 4_096,
            fetchRampMultiplier: 24,
            fetchRampMax: 524_288,
            progressThrottleMs: 120
        )
        XCTAssertEqual(options.mode, .auto)
        XCTAssertEqual(options.cursorThreshold, 25_000)
        XCTAssertEqual(options.fetchBaseline, 4_096)
        XCTAssertEqual(options.fetchRampMultiplier, 24)
        XCTAssertEqual(options.fetchRampMax, 524_288)
        XCTAssertEqual(options.progressThrottleMs, 120)
    }

    func testOptionsEquatable() {
        let a = PostgresExecutionOptions(mode: .auto, cursorThreshold: 1000)
        let b = PostgresExecutionOptions(mode: .auto, cursorThreshold: 1000)
        let c = PostgresExecutionOptions(mode: .auto, cursorThreshold: 2000)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - Query with Auto Mode

    func testSimpleQueryWithAutoMode() async throws {
        let options = PostgresExecutionOptions(mode: .auto)
        let rows = try await client.simpleQuery("SELECT 1 AS val", options: options)
        var values: [Int] = []
        for try await val in rows.decode(Int.self) { values.append(val) }
        XCTAssertEqual(values, [1])
    }

    func testQueryWithCustomThresholds() async throws {
        let options = PostgresExecutionOptions(
            mode: .auto,
            cursorThreshold: 25_000,
            fetchBaseline: 4_096,
            fetchRampMultiplier: 24,
            fetchRampMax: 524_288,
            progressThrottleMs: 120
        )

        let rows = try await client.simpleQuery("SELECT generate_series(1, 10) AS n", options: options)
        var count = 0
        for try await _ in rows { count += 1 }
        XCTAssertEqual(count, 10)
    }

    // MARK: - Small vs Large Result Sets

    func testAutoModeSmallResultSet() async throws {
        let options = PostgresExecutionOptions(mode: .auto, cursorThreshold: 100)
        let rows = try await client.simpleQuery("SELECT generate_series(1, 5) AS n", options: options)
        var values: [Int] = []
        for try await val in rows.decode(Int.self) { values.append(val) }
        XCTAssertEqual(values, [1, 2, 3, 4, 5])
    }

    func testAutoModeLargerResultSet() async throws {
        let options = PostgresExecutionOptions(
            mode: .auto,
            cursorThreshold: 50,
            fetchBaseline: 10
        )
        let rows = try await client.simpleQuery("SELECT generate_series(1, 200) AS n", options: options)
        var count = 0
        for try await _ in rows { count += 1 }
        XCTAssertEqual(count, 200)
    }

    // MARK: - Options with Different Query Types

    func testOptionsWithSelectQuery() async throws {
        let options = PostgresExecutionOptions(mode: .auto)
        let rows = try await client.simpleQuery("SELECT 'hello'::text AS greeting, 42 AS number", options: options)
        var found = false
        for try await (greeting, number) in rows.decode((String, Int).self) {
            XCTAssertEqual(greeting, "hello")
            XCTAssertEqual(number, 42)
            found = true
        }
        XCTAssertTrue(found)
    }

    func testOptionsWithMultipleRows() async throws {
        let options = PostgresExecutionOptions(mode: .auto, fetchBaseline: 2)
        let rows = try await client.simpleQuery(
            "SELECT n, 'item_' || n::text AS name FROM generate_series(1, 20) AS n",
            options: options
        )
        var count = 0
        for try await _ in rows { count += 1 }
        XCTAssertEqual(count, 20)
    }
}
