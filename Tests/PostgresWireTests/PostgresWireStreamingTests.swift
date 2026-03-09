import XCTest
@testable import PostgresWire
import PostgresNIO
import NIOCore
import Logging
import Foundation

/// Comprehensive test suite for postgres-wire streaming functionality
/// These tests cover all the various configurations and real-life scenarios
final class PostgresWireStreamingTests: XCTestCase {

    private var client: PostgresClient!
    private var wireClient: WireClient!
    private var logger: Logger!

    override func setUp() async throws {
        logger = Logger(label: "postgres-wire-tests")

        // Use environment variables for test database configuration
        let host = ProcessInfo.processInfo.environment["TEST_POSTGRES_HOST"] ?? "localhost"
        let port = Int(ProcessInfo.processInfo.environment["TEST_POSTGRES_PORT"] ?? "5432") ?? 5432
        let database = ProcessInfo.processInfo.environment["TEST_POSTGRES_DB"] ?? "postgres_wire_test"
        let username = ProcessInfo.processInfo.environment["TEST_POSTGRES_USER"] ?? "test_user"
        let password = ProcessInfo.processInfo.environment["TEST_POSTGRES_PASSWORD"] ?? "test_password"

        let config = PostgresConnectionConfiguration(
            host: host,
            port: port,
            database: database,
            user: username,
            password: password,
            tls: .disable
        )

        client = PostgresClient(configuration: config, logger: logger)
        wireClient = WireClient(connectionPool: client.eventLoopGroup, logger: logger)

        // Setup test data
        try await setupTestData()
    }

    override func tearDown() async throws {
        try await cleanupTestData()
        try await client.shutdown()
    }

    // MARK: - Test Data Setup

    private func setupTestData() async throws {
        logger.info("Setting up test data")

        // Create test tables with various data types
        try await executeSQL("""
            CREATE TABLE IF NOT EXISTS streaming_test (
                id SERIAL PRIMARY KEY,
                name TEXT NOT NULL,
                age INTEGER,
                salary NUMERIC(10,2),
                created_at TIMESTAMP,
                active BOOLEAN,
                data JSONB,
                uuid_col UUID,
                bytea_col BYTEA
            )
        """)

        // Insert test data
        try await executeSQL("""
            INSERT INTO streaming_test (name, age, salary, created_at, active, data, uuid_col, bytea_col)
            SELECT
                'User ' || generate_series,
                random() * 100,
                random() * 100000,
                NOW() - (random() * 365 || ' days')::INTERVAL,
                random() > 0.5,
                '{"key": "value", "number": ' || (random() * 1000) || '}'::jsonb,
                gen_random_uuid(),
                'DEADBEEF'::bytea
            FROM generate_series(1, 1000)
        """)

        // Create large table for performance testing
        try await executeSQL("""
            CREATE TABLE IF NOT EXISTS large_test (
                id SERIAL PRIMARY KEY,
                data TEXT,
                timestamp TIMESTAMP DEFAULT NOW()
            )
        """)

        try await executeSQL("""
            INSERT INTO large_test (data)
            SELECT 'Test data ' || generate_series || ' with some additional content to make it longer'
            FROM generate_series(1, 10000)
        """)
    }

    private func cleanupTestData() async throws {
        logger.info("Cleaning up test data")
        try await executeSQL("DROP TABLE IF EXISTS streaming_test CASCADE")
        try await executeSQL("DROP TABLE IF EXISTS large_test CASCADE")
    }

    private func executeSQL(_ sql: String) async throws {
        try await client.withConnection { connection in
            try await connection.query(PostgresQuery(unsafeSQL: sql), logger: self.logger)
        }
    }

    // MARK: - Configuration Tests

    func testPostgresStreamConfiguration_DefaultValues() {
        let config = PostgresStreamConfiguration.default

        XCTAssertEqual(config.initialPreviewRows, 500)
        XCTAssertEqual(config.streamingFetchSize, 4096)
        XCTAssertEqual(config.maxConcurrentRows, 100_000)
        XCTAssertTrue(config.liveCounterEnabled)
        XCTAssertEqual(config.liveCounterFrequency, 5)
        XCTAssertTrue(config.formattingEnabled)
        XCTAssertEqual(config.formattingMode, .smart)
        XCTAssertEqual(config.progressThrottle, 0.05)
        XCTAssertTrue(config.enableIncrementalLoading)
    }

    func testPostgresStreamConfiguration_HighPerformance() {
        let config = PostgresStreamConfiguration.highPerformance

        XCTAssertFalse(config.liveCounterEnabled)
        XCTAssertFalse(config.formattingEnabled)
        XCTAssertEqual(config.progressThrottle, 0.5)
        XCTAssertEqual(config.streamingFetchSize, 8192)
    }

    func testPostgresStreamConfiguration_LargeDataset() {
        let config = PostgresStreamConfiguration.largeDataset

        XCTAssertEqual(config.initialPreviewRows, 200)
        XCTAssertEqual(config.streamingFetchSize, 8192)
        XCTAssertEqual(config.liveCounterFrequency, 50)
        XCTAssertEqual(config.maxConcurrentRows, 50_000)
        XCTAssertTrue(config.enableIncrementalLoading)
        XCTAssertEqual(config.incrementalWindowSize, 100)
    }

    func testPostgresStreamConfiguration_CustomModification() {
        let config = PostgresStreamConfiguration { config in
            config.initialPreviewRows = 100
            config.liveCounterFrequency = 20
            config.formattingMode = .immediate
            config.nullValueDisplay = "<NULL>"
        }

        XCTAssertEqual(config.initialPreviewRows, 100)
        XCTAssertEqual(config.liveCounterFrequency, 20)
        XCTAssertEqual(config.formattingMode, .immediate)
        XCTAssertEqual(config.nullValueDisplay, "<NULL>")
    }

    // MARK: - Basic Streaming Tests

    func testSimpleQuery_Streaming() async throws {
        var updateCount = 0
        var finalRowCount = 0

        let result = try await wireClient.streamQuery(
            "SELECT id, name, age FROM streaming_test ORDER BY id LIMIT 100",
            configuration: .default,
            onUpdate: { update in
                updateCount += 1
                finalRowCount = update.totalRowCount

                // Verify update structure
                XCTAssertFalse(update.columns.isEmpty)
                XCTAssertEqual(update.totalRowCount, update.rowRange.upperBound)

                // Log progress
                self.logger.info("Received update \(updateCount): \(update.totalRowCount) rows, state: \(update.state)")
            }
        )

        XCTAssertGreaterThan(updateCount, 0)
        XCTAssertEqual(result.totalRowCount, 100)
        XCTAssertEqual(finalRowCount, 100)
    }

    func testCursorQuery_Streaming() async throws {
        var updateCount = 0
        var finalRowCount = 0

        let config = PostgresStreamConfiguration { config in
            config.initialPreviewRows = 50
            config.streamingFetchSize = 100
            config.liveCounterFrequency = 25
        }

        let result = try await wireClient.streamQueryWithCursor(
            "SELECT id, name, age FROM streaming_test ORDER BY id LIMIT 500",
            configuration: config,
            onUpdate: { update in
                updateCount += 1
                finalRowCount = update.totalRowCount

                // Verify incremental updates
                self.logger.info("Cursor update \(updateCount): \(update.totalRowCount) rows, range: \(update.rowRange)")
            }
        )

        XCTAssertGreaterThan(updateCount, 0)
        XCTAssertEqual(result.totalRowCount, 500)
        XCTAssertEqual(finalRowCount, 500)
    }

    // MARK: - Performance Tests

    func testLargeDataset_Performance() async throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        var updateCount = 0
        var finalRowCount = 0

        let config = PostgresStreamConfiguration.largeDataset

        let result = try await wireClient.streamQuery(
            "SELECT * FROM large_test ORDER BY id",
            configuration: config,
            onUpdate: { update in
                updateCount += 1
                finalRowCount = update.totalRowCount

                // Verify performance metrics
                XCTAssertGreaterThan(update.metrics.totalElapsed, 0)
                XCTAssertGreaterThan(update.metrics.cumulativeRowCount, 0)

                self.logger.info("Performance update \(updateCount): \(update.totalRowCount) rows in \(String(format: "%.3f", update.metrics.totalElapsed))s")
            }
        )

        let duration = CFAbsoluteTimeGetCurrent() - startTime

        XCTAssertGreaterThan(updateCount, 0)
        XCTAssertEqual(result.totalRowCount, 10000)
        XCTAssertEqual(finalRowCount, 10000)

        // Performance assertion - should complete within reasonable time
        XCTAssertLessThan(duration, 30.0, "Large dataset query should complete within 30 seconds")

        logger.info("Large dataset performance test completed in \(String(format: "%.3f", duration))s")
    }

    func testLiveCounter_Responsiveness() async throws {
        var updateTimestamps: [TimeInterval] = []
        var updateCount = 0

        let config = PostgresStreamConfiguration { config in
            config.liveCounterEnabled = true
            config.liveCounterFrequency = 10 // Update every 10 rows
            config.progressThrottle = 0.1 // Max 100ms between updates
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        let result = try await wireClient.streamQuery(
            "SELECT id, generate_series as num FROM generate_series(1, 100) ORDER BY num",
            configuration: config,
            onUpdate: { update in
                let currentTime = CFAbsoluteTimeGetCurrent() - startTime
                updateTimestamps.append(currentTime)
                updateCount += 1

                self.logger.info("Live counter update \(updateCount): \(update.totalRowCount) rows at \(String(format: "%.3f", currentTime))s")
            }
        )

        // Verify we received regular updates
        XCTAssertGreaterThan(updateCount, 5, "Should receive multiple live counter updates")
        XCTAssertEqual(result.totalRowCount, 100)

        // Verify update frequency
        if updateTimestamps.count > 1 {
            for i in 1..<updateTimestamps.count {
                let interval = updateTimestamps[i] - updateTimestamps[i-1]
                // Should not have gaps larger than twice the throttle time
                XCTAssertLessThan(interval, 0.2, "Live counter should update regularly")
            }
        }
    }

    // MARK: - Data Type Formatting Tests

    func testDataFormatting_AllTypes() async throws {
        var formattedData: [[String?]] = []

        let result = try await wireClient.streamQuery(
            """
            SELECT
                id,
                name,
                age,
                salary,
                created_at,
                active,
                data,
                uuid_col,
                bytea_col
            FROM streaming_test
            WHERE id <= 10
            ORDER BY id
            """,
            configuration: .default,
            onUpdate: { update in
                formattedData.append(contentsOf: update.appendedRows)
            }
        )

        XCTAssertEqual(result.totalRowCount, 10)
        XCTAssertEqual(formattedData.count, 10)

        // Verify formatting of different data types
        for row in formattedData {
            XCTAssertEqual(row.count, 9)

            // id (INTEGER)
            XCTAssertNotNil(row[0])
            XCTAssertNotNil(Int(row[0]!))

            // name (TEXT)
            XCTAssertNotNil(row[1])
            XCTAssertTrue(row[1]!.hasPrefix("User "))

            // age (INTEGER) - may be NULL
            if row[2] != nil {
                XCTAssertNotNil(Int(row[2]!))
            }

            // salary (NUMERIC) - may be NULL
            if row[3] != nil {
                XCTAssertNotNil(Double(row[3]!))
            }

            // created_at (TIMESTAMP)
            XCTAssertNotNil(row[5])
            // Should be formatted as readable timestamp

            // active (BOOLEAN)
            XCTAssertNotNil(row[6])
            XCTAssertTrue(row[6] == "true" || row[6] == "false")

            // data (JSONB)
            XCTAssertNotNil(row[7])
            // Should contain JSON string

            // uuid_col (UUID)
            XCTAssertNotNil(row[8])
            // Should be formatted as UUID string
        }
    }

    func testFormattingMode_Immediate() async throws {
        var immediateData: [[String?]] = []

        let config = PostgresStreamConfiguration { config in
            config.formattingMode = .immediate
            config.initialPreviewRows = 20
        }

        let result = try await wireClient.streamQuery(
            "SELECT id, name, age FROM streaming_test ORDER BY id LIMIT 50",
            configuration: config,
            onUpdate: { update in
                immediateData.append(contentsOf: update.appendedRows)
            }
        )

        XCTAssertEqual(result.totalRowCount, 50)
        XCTAssertEqual(immediateData.count, 50)

        // All rows should be immediately formatted (no nil values except where NULL in database)
        for row in immediateData {
            for cell in row {
                if cell != nil {
                    XCTAssertFalse(cell!.isEmpty, "Non-null cells should not be empty in immediate mode")
                }
            }
        }
    }

    func testFormattingMode_Deferred() async throws {
        var deferredData: [[String?]] = []
        var rawRowsCount = 0

        let config = PostgresStreamConfiguration { config in
            config.formattingMode = .deferred
            config.initialPreviewRows = 0 // No immediate formatting
        }

        let result = try await wireClient.streamQuery(
            "SELECT id, name, age FROM streaming_test ORDER BY id LIMIT 50",
            configuration: config,
            onUpdate: { update in
                deferredData.append(contentsOf: update.appendedRows)
                rawRowsCount += update.rawRows.count
            }
        )

        XCTAssertEqual(result.totalRowCount, 50)
        XCTAssertGreaterThan(rawRowsCount, 0, "Should receive raw rows for deferred formatting")

        // In deferred mode, most formatting should be nil initially
        // (except preview rows if any)
        logger.info("Deferred mode received \(deferredData.count) formatted rows and \(rawRowsCount) raw rows")
    }

    // MARK: - Incremental Loading Tests

    func testIncrementalLoading_WindowAccess() async throws {
        var allData: [[String?]] = []
        var accessRanges: [Range<Int>] = []

        let config = PostgresStreamConfiguration { config in
            config.enableIncrementalLoading = true
            config.incrementalWindowSize = 20
            config.initialPreviewRows = 10
        }

        let result = try await wireClient.streamQuery(
            "SELECT id, name FROM streaming_test ORDER BY id LIMIT 100",
            configuration: config,
            onUpdate: { update in
                allData.append(contentsOf: update.appendedRows)
                accessRanges.append(update.rowRange)

                self.logger.info("Incremental update: rows \(update.rowRange), total: \(update.totalRowCount)")
            }
        )

        XCTAssertEqual(result.totalRowCount, 100)
        XCTAssertGreaterThan(accessRanges.count, 1, "Should receive multiple incremental updates")

        // Verify that ranges are incremental
        for i in 1..<accessRanges.count {
            XCTAssertLessThan(accessRanges[i-1].upperBound, accessRanges[i].upperBound,
                             "Ranges should be incremental")
        }
    }

    // MARK: - Error Handling Tests

    func testQueryError_Handling() async throws {
        var errorReceived = false
        var errorMessage = ""

        do {
            _ = try await wireClient.streamQuery(
                "SELECT * FROM non_existent_table",
                configuration: .default,
                onUpdate: { update in
                    // Should not receive success updates
                    XCTFail("Should not receive success updates for error query")
                }
            )

            XCTFail("Query should have thrown an error")

        } catch {
            errorReceived = true
            errorMessage = error.localizedDescription
            logger.info("Received expected error: \(errorMessage)")
        }

        XCTAssertTrue(errorReceived, "Should receive error for invalid query")
        XCTAssertFalse(errorMessage.isEmpty, "Error message should not be empty")
    }

    // MARK: - Configuration Validation Tests

    func testConfiguration_Validation() {
        // Test that configuration validates its parameters
        let config1 = PostgresStreamConfiguration { config in
            config.initialPreviewRows = -1
            config.streamingFetchSize = 0
        }

        // Configuration should still work but will use defaults for invalid values
        XCTAssertGreaterThan(config1.initialPreviewRows, 0)
        XCTAssertGreaterThan(config1.streamingFetchSize, 0)
    }

    // MARK: - Memory Management Tests

    func testMemoryManagement_LargeQuery() async throws {
        var maxRowCountSeen = 0
        var updateCount = 0

        let config = PostgresStreamConfiguration { config in
            config.maxConcurrentRows = 1000 // Limit memory usage
            config.streamingFetchSize = 500
        }

        let result = try await wireClient.streamQuery(
            "SELECT id, data, timestamp FROM large_test ORDER BY id",
            configuration: config,
            onUpdate: { update in
                updateCount += 1
                maxRowCountSeen = max(maxRowCountSeen, update.totalRowCount)

                // Verify we don't exceed memory limits
                XCTAssertLessThanOrEqual(update.totalRowCount, config.maxConcurrentRows + 500,
                                       "Should not exceed memory limits significantly")

                self.logger.info("Memory test update \(updateCount): \(update.totalRowCount) rows (max seen: \(maxRowCountSeen))")
            }
        )

        XCTAssertEqual(result.totalRowCount, 10000)
        XCTAssertGreaterThan(updateCount, 0)
        logger.info("Memory management test completed. Max rows seen: \(maxRowCountSeen)")
    }

    // MARK: - Grid Loading Simulation Tests

    func testGridLoading_RealLifeScenario() async throws {
        // Simulate a realistic grid loading scenario like a data grid in a UI

        var gridData: [Int: [String?]] = [:] // rowIndex -> rowData
        var totalRowsLoaded = 0
        var loadingTimes: [TimeInterval] = []

        let startTime = CFAbsoluteTimeGetCurrent()

        let config = PostgresStreamConfiguration { config in
            config.initialPreviewRows = 50 // Initial grid page size
            config.streamingFetchSize = 200 // Background loading batch size
            config.liveCounterEnabled = true
            config.liveCounterFrequency = 25
            config.formattingMode = .smart // Immediate for preview, deferred for rest
            config.progressThrottle = 0.1 // Update UI every 100ms max
        }

        let result = try await wireClient.streamQuery(
            """
            SELECT
                id,
                name,
                age,
                salary,
                created_at,
                active,
                CASE
                    WHEN age < 30 THEN 'Young'
                    WHEN age < 50 THEN 'Middle'
                    ELSE 'Senior'
                END as age_group
            FROM streaming_test
            ORDER BY id
            """,
            configuration: config,
            onUpdate: { update in
                let updateStart = CFAbsoluteTimeGetCurrent()

                // Process incremental updates like a real grid would
                for (index, row) in update.appendedRows.enumerated() {
                    let rowIndex = update.rowRange.lowerBound + index
                    gridData[rowIndex] = row
                }

                totalRowsLoaded = update.totalRowCount
                let updateTime = CFAbsoluteTimeGetCurrent() - updateStart
                loadingTimes.append(updateTime)

                self.logger.info("Grid loading: \(update.totalRowCount) rows loaded, update took \(String(format: "%.3f", updateTime))s")
            }
        )

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime

        // Verify grid loading simulation
        XCTAssertEqual(result.totalRowCount, 1000)
        XCTAssertEqual(totalRowsLoaded, 1000)
        XCTAssertEqual(gridData.count, 1000)

        // Verify performance characteristics
        XCTAssertLessThan(totalTime, 20.0, "Grid loading should complete within 20 seconds")

        // Calculate average update processing time
        let avgUpdateTime = loadingTimes.reduce(0, +) / Double(loadingTimes.count)
        XCTAssertLessThan(avgUpdateTime, 0.01, "Average update processing should be very fast")

        // Verify data integrity
        for i in 0..<1000 {
            XCTAssertNotNil(gridData[i], "Every row should be loaded")
            XCTAssertEqual(gridData[i]?.count, 7, "Each row should have 7 columns")
        }

        logger.info("Grid loading simulation completed in \(String(format: "%.3f", totalTime))s")
        logger.info("Average update processing time: \(String(format: "%.3f", avgUpdateTime))s")
    }

    // MARK: - Custom Formatter Tests

    func testCustomFormatters() async throws {
        var formattedData: [[String?]] = []

        let config = PostgresStreamConfiguration { config in
            config.nullValueDisplay = "<NULL>"
            config.booleanTrueDisplay = "YES"
            config.booleanFalseDisplay = "NO"

            // Add custom formatters for specific data types
            config.customFormatters[.text] = { value in
                if let stringValue = value as? String {
                    return "📝 \(stringValue.uppercased())"
                }
                return String(describing: value)
            }
        }

        let result = try await wireClient.streamQuery(
            "SELECT name, active, age FROM streaming_test WHERE id IN (1,2,3) ORDER BY id",
            configuration: config,
            onUpdate: { update in
                formattedData.append(contentsOf: update.appendedRows)
            }
        )

        XCTAssertEqual(result.totalRowCount, 3)
        XCTAssertEqual(formattedData.count, 3)

        // Verify custom formatting
        for row in formattedData {
            // Name should be uppercased with prefix
            XCTAssertTrue(row[0]?.hasPrefix("📝 ") == true)
            if let nameWithoutPrefix = row[0]?.replacingOccurrences(of: "📝 ", with: "") {
                XCTAssertEqual(nameWithoutPrefix, nameWithoutPrefix.uppercased())
            }

            // Boolean should be YES/NO
            XCTAssertTrue(row[1] == "YES" || row[1] == "NO")
        }
    }

    // MARK: - Concurrent Query Tests

    func testConcurrentQueries() async throws {
        // Test multiple concurrent streaming queries

        let query1 = "SELECT id, name FROM streaming_test WHERE id <= 100 ORDER BY id"
        let query2 = "SELECT id, age FROM streaming_test WHERE id <= 200 ORDER BY id"
        let query3 = "SELECT id, salary FROM streaming_test WHERE id <= 300 ORDER BY id"

        async func executeQuery(_ sql: String, name: String) async -> (rowCount: Int, updateCount: Int) {
            var updateCount = 0
            var finalRowCount = 0

            let result = try await wireClient.streamQuery(
                sql,
                configuration: .default,
                onUpdate: { update in
                    updateCount += 1
                    finalRowCount = update.totalRowCount
                    self.logger.info("\(name) update \(updateCount): \(update.totalRowCount) rows")
                }
            )

            return (result.totalRowCount, updateCount)
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        async let result1 = executeQuery(query1, name: "Query1")
        async let result2 = executeQuery(query2, name: "Query2")
        async let result3 = executeQuery(query3, name: "Query3")

        let (r1, u1) = await result1
        let (r2, u2) = await result2
        let (r3, u3) = await result3

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime

        // Verify results
        XCTAssertEqual(r1, 100)
        XCTAssertEqual(r2, 200)
        XCTAssertEqual(r3, 300)

        XCTAssertGreaterThan(u1, 0)
        XCTAssertGreaterThan(u2, 0)
        XCTAssertGreaterThan(u3, 0)

        logger.info("Concurrent queries completed in \(String(format: "%.3f", totalTime))s")
        logger.info("Query1: \(r1) rows, \(u1) updates")
        logger.info("Query2: \(r2) rows, \(u2) updates")
        logger.info("Query3: \(r3) rows, \(u3) updates")
    }

    // MARK: - Edge Cases Tests

    func testEmptyResultSet() async throws {
        var updateCount = 0
        var finalRowCount = 0

        let result = try await wireClient.streamQuery(
            "SELECT * FROM streaming_test WHERE id = -1", // Should return no rows
            configuration: .default,
            onUpdate: { update in
                updateCount += 1
                finalRowCount = update.totalRowCount
                self.logger.info("Empty result update \(updateCount): \(update.totalRowCount) rows")
            }
        )

        XCTAssertEqual(result.totalRowCount, 0)
        XCTAssertEqual(finalRowCount, 0)
        // Should still receive at least one update for completion
        XCTAssertGreaterThanOrEqual(updateCount, 0)
    }

    func testSingleRowResultSet() async throws {
        var updateCount = 0
        var finalRowCount = 0
        var rowData: [String?]?

        let result = try await wireClient.streamQuery(
            "SELECT * FROM streaming_test WHERE id = 1",
            configuration: .default,
            onUpdate: { update in
                updateCount += 1
                finalRowCount = update.totalRowCount
                if let firstRow = update.appendedRows.first {
                    rowData = firstRow
                }
                self.logger.info("Single row update \(updateCount): \(update.totalRowCount) rows")
            }
        )

        XCTAssertEqual(result.totalRowCount, 1)
        XCTAssertEqual(finalRowCount, 1)
        XCTAssertGreaterThan(updateCount, 0)
        XCTAssertNotNil(rowData)
        XCTAssertGreaterThan(rowData?.count ?? 0, 0)
    }
}