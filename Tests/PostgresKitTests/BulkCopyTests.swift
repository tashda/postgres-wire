import XCTest
import Logging
import Foundation
@testable import PostgresKit

final class BulkCopyTests: PostgresKitTestCase {
    private var client: PostgresDatabaseClient!

    override func setUp() async throws {
        try await super.setUp()
        guard TestEnv.isConfigured else { throw XCTSkip("Postgres environment not set") }
        let config = PostgresConfiguration(
            host: TestEnv.host, port: TestEnv.port,
            database: TestEnv.database, username: TestEnv.username,
            password: TestEnv.password, useTLS: TestEnv.useTLS,
            applicationName: "BulkCopyTests"
        )
        client = try await PostgresDatabaseClient.connect(configuration: config, logger: Logger(label: "bulk-copy-tests"))
    }

    override func tearDown() {
        client?.close()
        super.tearDown()
    }

    private func uniqueName(_ prefix: String = "bulk") -> String {
        "\(prefix)_\(UInt32.random(in: 0..<UInt32.max))"
    }

    private var bulkCopy: PostgresBulkCopy {
        PostgresBulkCopy(client: client, logger: Logger(label: "bulk-copy"))
    }

    // MARK: - copyOut

    func testCopyOutBasicCSV() async throws {
        let table = uniqueName()
        defer { Task { _ = try? await client.simpleQuery("DROP TABLE IF EXISTS \(table)") } }

        _ = try await client.simpleQuery("CREATE TABLE \(table) (id INTEGER, name TEXT, score INTEGER)")
        _ = try await client.simpleQuery("INSERT INTO \(table) VALUES (1, 'Alice', 95), (2, 'Bob', 87), (3, 'Carol', 92)")

        let stream = try await bulkCopy.copyOut(sql: "COPY \(table) TO STDOUT WITH (FORMAT csv, HEADER true)")
        var allData = Data()
        for try await chunk in stream {
            allData.append(chunk)
        }

        let csv = String(data: allData, encoding: .utf8) ?? ""
        XCTAssertTrue(csv.contains("id,name,score"), "Should have CSV header")
        XCTAssertTrue(csv.contains("Alice"), "Should contain Alice")
        XCTAssertTrue(csv.contains("Bob"), "Should contain Bob")
        XCTAssertTrue(csv.contains("Carol"), "Should contain Carol")

        // Count data lines (excluding header)
        let lines = csv.split(separator: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 4, "Should have 1 header + 3 data lines")
    }

    func testCopyOutEmptyTable() async throws {
        let table = uniqueName()
        defer { Task { _ = try? await client.simpleQuery("DROP TABLE IF EXISTS \(table)") } }

        _ = try await client.simpleQuery("CREATE TABLE \(table) (id INTEGER, name TEXT)")

        let stream = try await bulkCopy.copyOut(sql: "COPY \(table) TO STDOUT WITH (FORMAT csv, HEADER true)")
        var allData = Data()
        for try await chunk in stream {
            allData.append(chunk)
        }

        let csv = String(data: allData, encoding: .utf8) ?? ""
        // Should have header only (or be empty if no header data rows)
        let lines = csv.split(separator: "\n").filter { !$0.isEmpty }
        XCTAssertLessThanOrEqual(lines.count, 1, "Empty table should have at most header line")
    }

    func testCopyOutWithNulls() async throws {
        let table = uniqueName()
        defer { Task { _ = try? await client.simpleQuery("DROP TABLE IF EXISTS \(table)") } }

        _ = try await client.simpleQuery("CREATE TABLE \(table) (id INTEGER, name TEXT, notes TEXT)")
        _ = try await client.simpleQuery("INSERT INTO \(table) VALUES (1, 'Alice', NULL), (2, NULL, 'has notes')")

        let stream = try await bulkCopy.copyOut(sql: "COPY \(table) TO STDOUT WITH (FORMAT csv, HEADER true)")
        var allData = Data()
        for try await chunk in stream {
            allData.append(chunk)
        }

        let csv = String(data: allData, encoding: .utf8) ?? ""
        XCTAssertFalse(csv.isEmpty, "Should produce CSV output even with NULLs")
    }

    func testCopyOutWithSpecialCharacters() async throws {
        let table = uniqueName()
        defer { Task { _ = try? await client.simpleQuery("DROP TABLE IF EXISTS \(table)") } }

        _ = try await client.simpleQuery("CREATE TABLE \(table) (id INTEGER, name TEXT)")
        _ = try await client.simpleQuery("INSERT INTO \(table) VALUES (1, 'O''Brien'), (2, 'Hello, World'), (3, 'Line1')")

        let stream = try await bulkCopy.copyOut(sql: "COPY \(table) TO STDOUT WITH (FORMAT csv, HEADER true)")
        var allData = Data()
        for try await chunk in stream {
            allData.append(chunk)
        }

        let csv = String(data: allData, encoding: .utf8) ?? ""
        XCTAssertFalse(csv.isEmpty)
        // CSV should properly escape commas and quotes
        let lines = csv.split(separator: "\n").filter { !$0.isEmpty }
        XCTAssertGreaterThanOrEqual(lines.count, 4, "Should have header + 3 data lines")
    }

    // MARK: - copyIn

    func testCopyInBasicCSV() async throws {
        let table = uniqueName()
        defer { Task { _ = try? await client.simpleQuery("DROP TABLE IF EXISTS \(table)") } }

        _ = try await client.simpleQuery("CREATE TABLE \(table) (id INTEGER, name TEXT, score INTEGER)")

        let csvData = "id,name,score\n1,Alice,95\n2,Bob,87\n3,Carol,92\n"
        let source = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(Data(csvData.utf8))
            continuation.finish()
        }

        try await bulkCopy.copyIn(
            sql: "COPY \(table) FROM STDIN WITH (FORMAT csv, HEADER true)",
            source: source
        )

        // Verify data was inserted
        let rows = try await client.simpleQuery("SELECT count(*) FROM \(table)")
        var count: Int64 = 0
        for try await c in rows.decode(Int64.self) { count = c }
        XCTAssertEqual(count, 3, "Should have inserted 3 rows")
    }

    func testCopyInLargeDataset() async throws {
        let table = uniqueName()
        defer { Task { _ = try? await client.simpleQuery("DROP TABLE IF EXISTS \(table)") } }

        _ = try await client.simpleQuery("CREATE TABLE \(table) (id INTEGER, value TEXT)")

        // Generate 1000 rows
        var csv = "id,value\n"
        for i in 1...1000 {
            csv += "\(i),item_\(i)\n"
        }

        let source = AsyncThrowingStream<Data, Error> { continuation in
            // Send in chunks to simulate streaming
            let data = Data(csv.utf8)
            let chunkSize = 4096
            var offset = 0
            while offset < data.count {
                let end = min(offset + chunkSize, data.count)
                continuation.yield(data[offset..<end])
                offset = end
            }
            continuation.finish()
        }

        try await bulkCopy.copyIn(
            sql: "COPY \(table) FROM STDIN WITH (FORMAT csv, HEADER true)",
            source: source
        )

        let rows = try await client.simpleQuery("SELECT count(*) FROM \(table)")
        var count: Int64 = 0
        for try await c in rows.decode(Int64.self) { count = c }
        XCTAssertEqual(count, 1000, "Should have inserted 1000 rows")
    }

    // MARK: - Round-trip

    func testCopyOutThenCopyIn() async throws {
        let sourceTable = uniqueName("src")
        let destTable = uniqueName("dst")
        defer { Task {
            _ = try? await client.simpleQuery("DROP TABLE IF EXISTS \(sourceTable)")
            _ = try? await client.simpleQuery("DROP TABLE IF EXISTS \(destTable)")
        }}

        _ = try await client.simpleQuery("CREATE TABLE \(sourceTable) (id INTEGER, name TEXT)")
        _ = try await client.simpleQuery("INSERT INTO \(sourceTable) VALUES (1, 'Alice'), (2, 'Bob'), (3, 'Carol')")
        _ = try await client.simpleQuery("CREATE TABLE \(destTable) (id INTEGER, name TEXT)")

        // Copy out from source
        let outStream = try await bulkCopy.copyOut(sql: "COPY \(sourceTable) TO STDOUT WITH (FORMAT csv, HEADER true)")
        var exportedData = Data()
        for try await chunk in outStream {
            exportedData.append(chunk)
        }

        // Copy in to destination
        let inSource = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(exportedData)
            continuation.finish()
        }
        try await bulkCopy.copyIn(
            sql: "COPY \(destTable) FROM STDIN WITH (FORMAT csv, HEADER true)",
            source: inSource
        )

        // Verify destination has same data
        let rows = try await client.simpleQuery("SELECT count(*) FROM \(destTable)")
        var count: Int64 = 0
        for try await c in rows.decode(Int64.self) { count = c }
        XCTAssertEqual(count, 3, "Destination should have same 3 rows")
    }

    // MARK: - Options

    func testBulkCopyWithCustomOptions() async throws {
        let table = uniqueName()
        defer { Task { _ = try? await client.simpleQuery("DROP TABLE IF EXISTS \(table)") } }

        _ = try await client.simpleQuery("CREATE TABLE \(table) (id INTEGER, name TEXT)")

        let customBulk = PostgresBulkCopy(
            client: client,
            logger: Logger(label: "bulk-custom"),
            options: .init(chunkSizeBytes: 1024, insertBatchSize: 10)
        )

        let csvData = "id,name\n1,Alice\n2,Bob\n"
        let source = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(Data(csvData.utf8))
            continuation.finish()
        }

        try await customBulk.copyIn(
            sql: "COPY \(table) FROM STDIN WITH (FORMAT csv, HEADER true)",
            source: source
        )

        let rows = try await client.simpleQuery("SELECT count(*) FROM \(table)")
        var count: Int64 = 0
        for try await c in rows.decode(Int64.self) { count = c }
        XCTAssertEqual(count, 2)
    }
}
