import XCTest
@testable import PostgresWire
import PostgresNIO
import NIOCore
import Logging
import Foundation

/// Performance benchmark tests specifically for the issues mentioned by the user
final class PostgresWirePerformanceBenchmarks: XCTestCase {

    private var client: PostgresClient!
    private var wireClient: WireClient!
    private var logger: Logger!

    override func setUp() async throws {
        logger = Logger(label: "postgres-wire-benchmarks")

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

        try await setupLargeTestTable()
    }

    override func tearDown() async throws {
        try await cleanupTestData()
        try await client.shutdown()
    }

    private func setupLargeTestTable() async throws {
        logger.info("Setting up large performance test table")

        // Create table with exactly 100,000 rows for the user's test case
        try await client.withConnection { connection in
            try await connection.query(PostgresQuery(unsafeSQL: """
                CREATE TABLE IF NOT EXISTS fixture (
                    id SERIAL PRIMARY KEY,
                    name TEXT NOT NULL,
                    value INTEGER,
                    created_at TIMESTAMP DEFAULT NOW(),
                    active BOOLEAN DEFAULT TRUE,
                    score NUMERIC(8,2),
                    description TEXT
                )
            """), logger: self.logger)

            // Clear existing data and insert exactly 100,000 rows
            try await connection.query(PostgresQuery(unsafeSQL: "TRUNCATE TABLE fixture"), logger: self.logger)

            try await connection.query(PostgresQuery(unsafeSQL: """
                INSERT INTO fixture (name, value, active, score, description)
                SELECT
                    'Name ' || generate_series,
                    (random() * 1000)::INTEGER,
                    generate_series % 2 = 0,
                    round(random() * 100, 2)::NUMERIC,
                    'This is a longer description text for row ' || generate_series ||
                    ' with some additional content to make it more realistic'
                FROM generate_series(1, 100000)
            """), logger: self.logger)
        }
    }

    private func cleanupTestData() async throws {
        try await client.withConnection { connection in
            try await connection.query(PostgresQuery(unsafeSQL: "DROP TABLE IF EXISTS fixture"), logger: self.logger)
        }
    }

    // MARK: - Performance Benchmark: 100k Row Query

    func testBenchmark_100kRowQuery_Performance() async throws {
        logger.info("Starting 100k row performance benchmark")

        var updateCount = 0
        var liveCounterUpdates = 0
        var lastRowCount = 0
        var updateIntervals: [TimeInterval] = []
        var lastUpdateTime: CFAbsoluteTime = 0

        let config = PostgresStreamConfiguration { config in
            config.initialPreviewRows = 500  // Preview size
            config.streamingFetchSize = 4096  // Background fetch size
            config.liveCounterEnabled = true
            config.liveCounterFrequency = 10  // Update every 10 rows
            config.formattingEnabled = true
            config.formattingMode = .smart  // Immediate for preview, deferred for rest
            config.progressThrottle = 0.05  // 50ms max throttle
            config.maxConcurrentRows = 100_000
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        let result = try await wireClient.streamQuery(
            "SELECT * FROM public.fixture ORDER BY id",
            configuration: config,
            onUpdate: { update in
                let currentTime = CFAbsoluteTimeGetCurrent()
                updateCount += 1

                // Track live counter updates
                if update.totalRowCount > lastRowCount {
                    liveCounterUpdates += 1
                    lastRowCount = update.totalRowCount

                    if lastUpdateTime > 0 {
                        updateIntervals.append(currentTime - lastUpdateTime)
                    }
                    lastUpdateTime = currentTime

                    self.logger.info("Live counter update #\(liveCounterUpdates): \(update.totalRowCount) rows")
                }

                // Log progress every 10,000 rows
                if update.totalRowCount % 10000 == 0 {
                    let elapsed = currentTime - startTime
                    self.logger.info("Progress: \(update.totalRowCount) rows in \(String(format: "%.3f", elapsed))s")
                }

                // Verify data integrity for sample rows
                if update.appendedRows.count > 0 {
                    let sampleRow = update.appendedRows[0]
                    XCTAssertGreaterThanOrEqual(sampleRow.count, 7, "Should have all columns")
                }
            }
        )

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime

        // Performance assertions
        XCTAssertEqual(result.totalRowCount, 100_000, "Should load all 100,000 rows")
        XCTAssertGreaterThan(updateCount, 0, "Should receive updates")

        // Performance target: should be under 25 seconds (user reported it took 25s before)
        XCTAssertLessThan(totalTime, 25.0, "100k row query should complete in under 25 seconds")

        // Live counter should update frequently (not every 4000 rows as reported)
        XCTAssertGreaterThan(liveCounterUpdates, 20, "Live counter should update frequently")
        XCTAssertEqual(lastRowCount, 100_000, "Should count all rows")

        // Update intervals should be reasonable
        if updateIntervals.count > 0 {
            let avgInterval = updateIntervals.reduce(0, +) / Double(updateIntervals.count)
            XCTAssertLessThan(avgInterval, 1.0, "Average update interval should be under 1 second")
        }

        logger.info("🎯 100k Row Performance Benchmark Results:")
        logger.info("   Total time: \(String(format: "%.3f", totalTime))s")
        logger.info("   Total updates: \(updateCount)")
        logger.info("   Live counter updates: \(liveCounterUpdates)")
        logger.info("   Average rows per update: \(100_000 / max(updateCount, 1))")
        logger.info("   Performance target achieved: \(totalTime < 25.0)")
    }

    // MARK: - Live Counter Responsiveness Test

    func testLiveCounter_Responsiveness_100kRows() async throws {
        logger.info("Testing live counter responsiveness with 100k rows")

        var liveUpdateTimestamps: [(rowCount: Int, timestamp: TimeInterval)] = []
        var totalUpdates = 0

        let config = PostgresStreamConfiguration { config in
            config.liveCounterEnabled = true
            config.liveCounterFrequency = 5  // Very frequent updates
            config.progressThrottle = 0.02   // 20ms throttle
            config.formattingMode = .deferred // Focus on performance
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        let result = try await wireClient.streamQuery(
            "SELECT id, name FROM public.fixture ORDER BY id",
            configuration: config,
            onUpdate: { update in
                let currentTime = CFAbsoluteTimeGetCurrent() - startTime
                totalUpdates += 1

                if update.totalRowCount > (liveUpdateTimestamps.last?.rowCount ?? 0) {
                    liveUpdateTimestamps.append((rowCount: update.totalRowCount, timestamp: currentTime))
                }
            }
        )

        // Analyze live counter performance
        XCTAssertGreaterThan(liveUpdateTimestamps.count, 10, "Should receive multiple live counter updates")
        XCTAssertEqual(liveUpdateTimestamps.last?.rowCount, 100_000, "Should reach final row count")

        // Calculate update frequency
        if liveUpdateTimestamps.count > 1 {
            var intervals: [TimeInterval] = []
            for i in 1..<liveUpdateTimestamps.count {
                let interval = liveUpdateTimestamps[i].timestamp - liveUpdateTimestamps[i-1].timestamp
                intervals.append(interval)
            }

            let avgInterval = intervals.reduce(0, +) / Double(intervals.count)
            let maxInterval = intervals.max() ?? 0

            logger.info("🎯 Live Counter Responsiveness Results:")
            logger.info("   Total live updates: \(liveUpdateTimestamps.count)")
            logger.info("   Average interval: \(String(format: "%.3f", avgInterval))s")
            logger.info("   Maximum interval: \(String(format: "%.3f", maxInterval))s")

            // Should not have long gaps (user reported updates every 4000 rows)
            XCTAssertLessThan(maxInterval, 0.5, "Should not have gaps longer than 500ms")
            XCTAssertLessThan(avgInterval, 0.1, "Average interval should be under 100ms")
        }
    }

    // MARK: - Data Formatting Accuracy Test

    func testDataFormatting_Accuracy_100kRows() async throws {
        logger.info("Testing data formatting accuracy with 100k rows")

        var formattingErrors: [String] = []
        var sampleData: [(id: Int, name: String?, value: String?, active: String?, score: String?)] = []

        let config = PostgresStreamConfiguration { config in
            config.formattingEnabled = true
            config.formattingMode = .smart
            config.initialPreviewRows = 1000  // Larger sample
        }

        let result = try await wireClient.streamQuery(
            """
            SELECT id, name, value, active, score, created_at, description
            FROM public.fixture
            ORDER BY id
            """,
            configuration: config,
            onUpdate: { update in
                // Sample every 1000th row for accuracy checking
                for (index, row) in update.appendedRows.enumerated() {
                    let globalRowIndex = update.rowRange.lowerBound + index

                    if globalRowIndex % 1000 == 0 && globalRowIndex < 100_000 {
                        guard row.count >= 5 else {
                            formattingErrors.append("Row \(globalRowIndex): insufficient columns")
                            continue
                        }

                        let idString = row[0]
                        let name = row[1]
                        let value = row[2]
                        let active = row[3]
                        let score = row[4]

                        // Verify ID formatting
                        if let id = Int(idString ?? "") {
                            // Verify name formatting
                            if name == nil || name!.isEmpty {
                                formattingErrors.append("Row \(globalRowIndex): name is null/empty")
                            } else if !name!.hasPrefix("Name ") {
                                formattingErrors.append("Row \(globalRowIndex): name format incorrect: \(name!)")
                            }

                            // Verify value formatting
                            if value != nil {
                                if Int(value!) == nil {
                                    formattingErrors.append("Row \(globalRowIndex): value not integer: \(value!)")
                                }
                            }

                            // Verify boolean formatting
                            if active != nil && active != "true" && active != "false" {
                                formattingErrors.append("Row \(globalRowIndex): active not true/false: \(active!)")
                            }

                            // Verify score formatting
                            if score != nil {
                                if Double(score!) == nil {
                                    formattingErrors.append("Row \(globalRowIndex): score not numeric: \(score!)")
                                }
                            }

                            sampleData.append((
                                id: id,
                                name: name,
                                value: value,
                                active: active,
                                score: score
                            ))
                        } else {
                            formattingErrors.append("Row \(globalRowIndex): ID not integer: \(idString ?? "nil")")
                        }
                    }
                }
            }
        )

        logger.info("🎯 Data Formatting Accuracy Results:")
        logger.info("   Total rows processed: \(result.totalRowCount)")
        logger.info("   Sample rows checked: \(sampleData.count)")
        logger.info("   Formatting errors: \(formattingErrors.count)")

        if !formattingErrors.isEmpty {
            logger.error("Formatting errors found:")
            for error in formattingErrors.prefix(10) {
                logger.error("  \(error)")
            }
        }

        XCTAssertEqual(result.totalRowCount, 100_000, "Should process all rows")
        XCTAssertEqual(sampleData.count, 100, "Should sample approximately 100 rows")
        XCTAssertEqual(formattingErrors.count, 0, "Should have no formatting errors")

        // Verify specific data types
        for sample in sampleData {
            XCTAssertNotNil(sample.name, "Name should not be nil")
            XCTAssertTrue(sample.name!.hasPrefix("Name "), "Name should have correct format")

            if sample.value != nil {
                XCTAssertNotNil(Int(sample.value!), "Value should be convertible to Int")
            }

            XCTAssertTrue(sample.active == "true" || sample.active == "false", "Active should be true/false")

            if sample.score != nil {
                XCTAssertNotNil(Double(sample.score!), "Score should be convertible to Double")
            }
        }
    }

    // MARK: - Date Formatting Test

    func testDateFormatting_Accuracy() async throws {
        logger.info("Testing date formatting accuracy")

        var dateSamples: [(id: Int, dateString: String?)] = []
        var dateErrors: [String] = []

        let result = try await wireClient.streamQuery(
            "SELECT id, created_at FROM public.fixture WHERE id <= 1000 ORDER BY id",
            configuration: .default,
            onUpdate: { update in
                for row in update.appendedRows {
                    guard row.count >= 2 else { continue }

                    if let idString = row[0], let id = Int(idString) {
                        let dateString = row[1]
                        dateSamples.append((id: id, dateString: dateString))

                        // Verify date format
                        if dateString != nil && !dateString!.isEmpty {
                            // Should be in readable format, not binary or encoded
                            if dateString!.contains("AAAP7g==") || dateString!.contains("-") == false {
                                dateErrors.append("Row \(id): Invalid date format: \(dateString!)")
                            }

                            // Should be reasonable length (not encoded binary)
                            if dateString!.count > 50 {
                                dateErrors.append("Row \(id): Date string too long: \(dateString!)")
                            }
                        }
                    }
                }
            }
        )

        logger.info("🎯 Date Formatting Results:")
        logger.info("   Date samples checked: \(dateSamples.count)")
        logger.info("   Date errors: \(dateErrors.count)")

        if !dateErrors.isEmpty {
            logger.error("Date formatting errors:")
            for error in dateErrors.prefix(5) {
                logger.error("  \(error)")
            }
        }

        XCTAssertEqual(dateSamples.count, 1000, "Should sample all 1000 rows")
        XCTAssertEqual(dateErrors.count, 0, "Should have no date formatting errors")

        // Verify specific date format requirements
        for sample in dateSamples {
            if let dateString = sample.dateString {
                // Should not be encoded binary data
                XCTAssertFalse(dateString.contains("AAAP7g=="), "Date should not be encoded: \(dateString)")

                // Should be readable format (contains year-month-day pattern)
                XCTAssertTrue(dateString.contains("-") || dateString.contains("/") || dateString.count < 30,
                              "Date should be in readable format: \(dateString)")
            }
        }
    }

    // MARK: - Integer Formatting Test

    func testIntegerFormatting_Accuracy() async throws {
        logger.info("Testing integer formatting accuracy")

        var integerSamples: [(id: Int, valueString: String?)] = []
        var integerErrors: [String] = []

        let result = try await wireClient.streamQuery(
            "SELECT id, value FROM public.fixture WHERE id <= 5000 ORDER BY id",
            configuration: .default,
            onUpdate: { update in
                for row in update.appendedRows {
                    guard row.count >= 2 else { continue }

                    if let idString = row[0], let id = Int(idString) {
                        let valueString = row[1]
                        integerSamples.append((id: id, valueString: valueString))

                        // Verify integer formatting
                        if valueString != nil && !valueString!.isEmpty {
                            if let value = Int(valueString!) {
                                // Value should be in reasonable range (0-1000 based on our test data)
                                if value < 0 || value > 1000 {
                                    integerErrors.append("Row \(id): Integer value out of range: \(value)")
                                }
                            } else {
                                integerErrors.append("Row \(id): Not convertible to integer: \(valueString!)")
                            }
                        }
                    }
                }
            }
        )

        logger.info("🎯 Integer Formatting Results:")
        logger.info("   Integer samples checked: \(integerSamples.count)")
        logger.info("   Integer errors: \(integerErrors.count)")

        if !integerErrors.isEmpty {
            logger.error("Integer formatting errors:")
            for error in integerErrors.prefix(5) {
                logger.error("  \(error)")
            }
        }

        XCTAssertEqual(integerSamples.count, 5000, "Should sample all 5000 rows")
        XCTAssertEqual(integerErrors.count, 0, "Should have no integer formatting errors")

        // Verify integer conversion accuracy
        for sample in integerSamples {
            if let valueString = sample.valueString {
                XCTAssertNotNil(Int(valueString), "Should be convertible to integer: \(valueString)")

                if let value = Int(valueString) {
                    XCTAssertGreaterThanOrEqual(value, 0, "Value should be non-negative")
                    XCTAssertLessThanOrEqual(value, 1000, "Value should be <= 1000")
                }
            }
        }
    }

    // MARK: - Null Value Handling Test

    func testNullValueHandling_Accuracy() async throws {
        logger.info("Testing null value handling accuracy")

        // Create a table with explicit NULL values for testing
        try await client.withConnection { connection in
            try await connection.query(PostgresQuery(unsafeSQL: """
                CREATE TABLE IF NOT EXISTS null_test (
                    id INTEGER PRIMARY KEY,
                    text_value TEXT,
                    int_value INTEGER,
                    numeric_value NUMERIC,
                    timestamp_value TIMESTAMP,
                    boolean_value BOOLEAN
                )
            """), logger: self.logger)

            try await connection.query(PostgresQuery(unsafeSQL: "TRUNCATE TABLE null_test"), logger: self.logger)

            try await connection.query(PostgresQuery(unsafeSQL: """
                INSERT INTO null_test (id, text_value, int_value, numeric_value, timestamp_value, boolean_value)
                VALUES
                    (1, 'not null', 42, 123.45, NOW(), TRUE),
                    (2, NULL, NULL, NULL, NULL, NULL),
                    (3, 'also not null', 0, 0.00, '1970-01-01', FALSE),
                    (4, NULL, 100, NULL, NOW(), NULL)
            """), logger: self.logger)
        }

        defer {
            Task {
                try? await client.withConnection { connection in
                    try await connection.query(PostgresQuery(unsafeSQL: "DROP TABLE IF EXISTS null_test"), logger: self.logger)
                }
            }
        }

        var nullResults: [(id: Int, text: String?, int: String?, numeric: String?, timestamp: String?, boolean: String?)] = []
        var nullErrors: [String] = []

        let config = PostgresStreamConfiguration { config in
            config.nullValueDisplay = "NULL"
        }

        let result = try await wireClient.streamQuery(
            "SELECT id, text_value, int_value, numeric_value, timestamp_value, boolean_value FROM null_test ORDER BY id",
            configuration: config,
            onUpdate: { update in
                for row in update.appendedRows {
                    guard row.count >= 6 else { continue }

                    if let idString = row[0], let id = Int(idString) {
                        nullResults.append((
                            id: id,
                            text: row[1],
                            int: row[2],
                            numeric: row[3],
                            timestamp: row[4],
                            boolean: row[5]
                        ))
                    }
                }
            }
        )

        logger.info("🎯 Null Value Handling Results:")
        logger.info("   Null test rows processed: \(nullResults.count)")

        // Verify null handling accuracy
        for result in nullResults {
            switch result.id {
            case 1: // All non-null
                XCTAssertNotNil(result.text, "Row 1 text should not be null")
                XCTAssertNotNil(result.int, "Row 1 int should not be null")
                XCTAssertNotNil(result.numeric, "Row 1 numeric should not be null")
                XCTAssertNotNil(result.timestamp, "Row 1 timestamp should not be null")
                XCTAssertNotNil(result.boolean, "Row 1 boolean should not be null")

                XCTAssertEqual(result.boolean, "true", "Row 1 boolean should be true")

            case 2: // All null
                XCTAssertEqual(result.text, "NULL", "Row 2 text should be NULL")
                XCTAssertEqual(result.int, "NULL", "Row 2 int should be NULL")
                XCTAssertEqual(result.numeric, "NULL", "Row 2 numeric should be NULL")
                XCTAssertEqual(result.timestamp, "NULL", "Row 2 timestamp should be NULL")
                XCTAssertEqual(result.boolean, "NULL", "Row 2 boolean should be NULL")

            case 3: // All non-null (zero values)
                XCTAssertNotNil(result.text, "Row 3 text should not be null")
                XCTAssertNotNil(result.int, "Row 3 int should not be null")
                XCTAssertNotNil(result.numeric, "Row 3 numeric should not be null")
                XCTAssertNotNil(result.timestamp, "Row 3 timestamp should not be null")
                XCTAssertNotNil(result.boolean, "Row 3 boolean should not be null")

                XCTAssertEqual(result.int, "0", "Row 3 int should be 0")
                XCTAssertEqual(result.boolean, "false", "Row 3 boolean should be false")

            case 4: // Mixed null/non-null
                XCTAssertEqual(result.text, "NULL", "Row 4 text should be NULL")
                XCTAssertNotNil(result.int, "Row 4 int should not be null")
                XCTAssertEqual(result.numeric, "NULL", "Row 4 numeric should be NULL")
                XCTAssertNotNil(result.timestamp, "Row 4 timestamp should not be null")
                XCTAssertEqual(result.boolean, "NULL", "Row 4 boolean should be NULL")

            default:
                break
            }
        }

        XCTAssertEqual(nullResults.count, 4, "Should process all 4 test rows")
        logger.info("   Null handling verification: PASSED")
    }
}