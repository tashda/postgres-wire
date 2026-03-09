import XCTest
import Logging
import Foundation
@testable import PostgresKit

final class BulkCopyTests: XCTestCase {
    private var client: PostgresDatabaseClient!
    private let tableName = "pgwire_bulk_copy_\(UInt32.random(in: 0..<UInt32.max))"

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
            applicationName: "BulkCopyTests"
        )
        client = try await PostgresDatabaseClient.connect(configuration: config, logger: Logger(label: "bulk-tests"))
        let t = tableName
        try await client.withConnection { conn in
            _ = try await conn.simpleQuery("CREATE TABLE IF NOT EXISTS \(t) (id INTEGER, name TEXT, score INTEGER)")
        }
    }

    override func tearDown() async throws {
        let t = tableName
        try? await client.withConnection { conn in
            _ = try? await conn.simpleQuery("DROP TABLE IF EXISTS \(t)")
        }
        client?.close()
    }

    private var bulkCopy: PostgresBulkCopy {
        PostgresBulkCopy(client: client, logger: Logger(label: "bulk-copy"))
    }

    // MARK: - copyOut via SELECT subquery

    func testCopyOutWithSelectSubquery() async throws {
        let t = tableName
        try await client.withConnection { conn in
            _ = try await conn.simpleQuery("INSERT INTO \(t) VALUES (1,'Alice',95),(2,'Bob',80),(3,'Carol',88)")
        }

        let sql = "COPY (SELECT id, name, score FROM \(tableName) ORDER BY id) TO STDOUT WITH (FORMAT csv)"
        let stream = try await bulkCopy.copyOut(sql: sql)

        var csvData = Data()
        for try await chunk in stream {
            csvData.append(chunk)
        }

        let csv = String(data: csvData, encoding: .utf8) ?? ""
        XCTAssertTrue(csv.contains("Alice"), "CSV should contain Alice")
        XCTAssertTrue(csv.contains("Bob"), "CSV should contain Bob")
        XCTAssertTrue(csv.contains("Carol"), "CSV should contain Carol")

        let lines = csv.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 3, "Should have 3 data rows")
    }

    func testCopyOutWithHeader() async throws {
        let t = tableName
        try await client.withConnection { conn in
            _ = try await conn.simpleQuery("INSERT INTO \(t) VALUES (10,'Dave',70)")
        }

        let sql = "COPY (SELECT id, name FROM \(tableName) WHERE id=10) TO STDOUT WITH (FORMAT csv, HEADER)"
        let stream = try await bulkCopy.copyOut(sql: sql)

        var csvData = Data()
        for try await chunk in stream { csvData.append(chunk) }

        let csv = String(data: csvData, encoding: .utf8) ?? ""
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: true)
        // First line is header (id,name), second is data
        XCTAssertGreaterThanOrEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("id") || lines[0].contains("name"),
                      "First line should be header but got: \(lines[0])")
        XCTAssertTrue(lines.last?.contains("Dave") == true, "Last line should contain Dave")
    }

    func testCopyOutEmptyTable() async throws {
        // No rows inserted — stream should complete with no data
        let sql = "COPY (SELECT id, name FROM \(tableName) WHERE false) TO STDOUT WITH (FORMAT csv)"
        let stream = try await bulkCopy.copyOut(sql: sql)

        var total = 0
        for try await chunk in stream { total += chunk.count }
        XCTAssertEqual(total, 0, "Empty result set should produce no bytes")
    }

    // MARK: - copyIn round-trip

    func testCopyInRoundTrip() async throws {
        let csvLines = ["1,Alice,95", "2,Bob,80", "3,Carol,88"].joined(separator: "\n") + "\n"
        let csvData = Data(csvLines.utf8)

        let inSQL = "COPY \(tableName) FROM STDIN WITH (FORMAT csv)"
        let source = AsyncStream<Data> { continuation in
            continuation.yield(csvData)
            continuation.finish()
        }
        try await bulkCopy.copyIn(sql: inSQL, source: source)

        // Verify rows were inserted
        let rows = try await client.simpleQuery("SELECT COUNT(*)::text FROM \(tableName)")
        var countStr = ""
        for try await s in rows.decode(String.self) { countStr = s; break }
        XCTAssertEqual(Int(countStr), 3, "3 rows should have been inserted via copyIn")
    }

    func testCopyInChunkedData() async throws {
        let row1 = Data("1,Alice,95\n".utf8)
        let row2 = Data("2,Bob,80\n".utf8)

        let inSQL = "COPY \(tableName) FROM STDIN WITH (FORMAT csv)"
        let source = AsyncStream<Data> { continuation in
            continuation.yield(row1)
            continuation.yield(row2)
            continuation.finish()
        }
        try await bulkCopy.copyIn(sql: inSQL, source: source)

        let rows = try await client.simpleQuery("SELECT COUNT(*)::text FROM \(tableName)")
        var countStr = ""
        for try await s in rows.decode(String.self) { countStr = s; break }
        XCTAssertEqual(Int(countStr), 2)
    }

    func testCopyInWithHeaderSkipped() async throws {
        let csv = Data("id,name,score\n1,Alice,95\n2,Bob,80\n".utf8)

        let inSQL = "COPY \(tableName) FROM STDIN WITH (FORMAT csv, HEADER)"
        let source = AsyncStream<Data> { continuation in
            continuation.yield(csv)
            continuation.finish()
        }
        try await bulkCopy.copyIn(sql: inSQL, source: source)

        let rows = try await client.simpleQuery("SELECT COUNT(*)::text FROM \(tableName)")
        var countStr = ""
        for try await s in rows.decode(String.self) { countStr = s; break }
        XCTAssertEqual(Int(countStr), 2, "Header row should not be inserted as data")
    }

    // MARK: - Error handling

    func testCopyOutInvalidDirection_Throws() async throws {
        let sql = "COPY \(tableName) FROM STDIN WITH (FORMAT csv)"
        do {
            _ = try await bulkCopy.copyOut(sql: sql)
            XCTFail("Expected notSupported error for FROM STDIN in copyOut")
        } catch let error as PostgresKit.PostgresKitError {
            if case .notSupported = error {} else {
                XCTFail("Expected .notSupported, got \(error)")
            }
        }
    }

    func testCopyInInvalidDirection_Throws() async throws {
        let sql = "COPY (SELECT 1) TO STDOUT WITH (FORMAT csv)"
        let source = AsyncStream<Data> { $0.finish() }
        do {
            try await bulkCopy.copyIn(sql: sql, source: source)
            XCTFail("Expected notSupported error for TO STDOUT in copyIn")
        } catch let error as PostgresKit.PostgresKitError {
            if case .notSupported = error {} else {
                XCTFail("Expected .notSupported, got \(error)")
            }
        }
    }
}
