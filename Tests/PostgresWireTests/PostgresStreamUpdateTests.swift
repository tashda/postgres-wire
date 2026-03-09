import XCTest
@testable import PostgresWire

final class PostgresStreamUpdateTests: XCTestCase {

    // MARK: - Helpers

    private func makeColumn(name: String = "id", type: String = "int4") -> ColumnInfo {
        ColumnInfo(name: name, dataType: type)
    }

    private func makeMetrics(
        batchRows: Int = 0,
        totalElapsed: TimeInterval = 1.0,
        cumulativeRows: Int = 10
    ) -> PostgresStreamMetrics {
        PostgresStreamMetrics(
            batchRowCount: batchRows,
            loopElapsed: 0.1,
            decodeDuration: 0.01,
            totalElapsed: totalElapsed,
            cumulativeRowCount: cumulativeRows
        )
    }

    // MARK: - Direct Initialization

    func testDirectInitialization() {
        let columns = [makeColumn()]
        let rows: [[String?]] = [["42", "Alice"]]
        let metrics = makeMetrics()

        let update = PostgresStreamUpdate(
            columns: columns,
            appendedRows: rows,
            rawRows: [],
            totalRowCount: 1,
            metrics: metrics,
            rowRange: 0..<1,
            state: .streaming
        )

        XCTAssertEqual(update.columns.count, 1)
        XCTAssertEqual(update.appendedRows.count, 1)
        XCTAssertEqual(update.totalRowCount, 1)
        XCTAssertEqual(update.rowRange, 0..<1)
        XCTAssertEqual(update.state, .streaming)
    }

    // MARK: - .progress() factory

    func testProgressFactory() {
        let columns = [makeColumn()]
        let metrics = makeMetrics(cumulativeRows: 50)

        let update = PostgresStreamUpdate.progress(
            columns: columns,
            totalRowCount: 50,
            metrics: metrics
        )

        XCTAssertEqual(update.totalRowCount, 50)
        XCTAssertTrue(update.appendedRows.isEmpty)
        XCTAssertTrue(update.rawRows.isEmpty)
        XCTAssertNil(update.rowRange)
        XCTAssertEqual(update.state, .streaming)
    }

    // MARK: - .completion() factory

    func testCompletionFactory() {
        let columns = [makeColumn()]
        let metrics = makeMetrics(cumulativeRows: 100)

        let update = PostgresStreamUpdate.completion(
            columns: columns,
            totalRowCount: 100,
            metrics: metrics,
            commandTag: "SELECT 100"
        )

        XCTAssertEqual(update.totalRowCount, 100)
        XCTAssertTrue(update.appendedRows.isEmpty)
        XCTAssertNil(update.rowRange)
        XCTAssertEqual(update.state, .completed)
        XCTAssertTrue(update.metrics.isComplete)
        XCTAssertEqual(update.metrics.commandTag, "SELECT 100")
    }

    func testCompletionFactory_NoCommandTag() {
        let columns = [makeColumn()]
        let metrics = makeMetrics()

        let update = PostgresStreamUpdate.completion(
            columns: columns,
            totalRowCount: 0,
            metrics: metrics
        )

        XCTAssertEqual(update.state, .completed)
        XCTAssertNil(update.metrics.commandTag)
    }

    // MARK: - .error() factory

    func testErrorFactory() {
        let columns = [makeColumn()]
        let testError = NSError(domain: "TestDomain", code: 42, userInfo: [NSLocalizedDescriptionKey: "Test error"])

        let update = PostgresStreamUpdate.error(
            columns: columns,
            totalRowCount: 5,
            error: testError
        )

        XCTAssertEqual(update.totalRowCount, 5)
        XCTAssertTrue(update.appendedRows.isEmpty)
        XCTAssertNil(update.rowRange)
        XCTAssertEqual(update.state, .error)
        XCTAssertTrue(update.metrics.isError)
        XCTAssertNotNil(update.metrics.error)
    }

    // MARK: - StreamState

    func testStreamStateRawValues() {
        XCTAssertEqual(StreamState.streaming.rawValue, "streaming")
        XCTAssertEqual(StreamState.completed.rawValue, "completed")
        XCTAssertEqual(StreamState.error.rawValue, "error")
        XCTAssertEqual(StreamState.cancelled.rawValue, "cancelled")
    }

    // MARK: - PostgresStreamMetrics

    func testRowsPerSecond() {
        let metrics = makeMetrics(totalElapsed: 2.0, cumulativeRows: 1000)
        XCTAssertEqual(metrics.rowsPerSecond, 500.0, accuracy: 0.001)
    }

    func testRowsPerSecond_ZeroElapsed_ReturnsZero() {
        let metrics = makeMetrics(totalElapsed: 0.0, cumulativeRows: 100)
        XCTAssertEqual(metrics.rowsPerSecond, 0.0)
    }

    func testRowsPerSecond_ZeroRows() {
        let metrics = makeMetrics(totalElapsed: 5.0, cumulativeRows: 0)
        XCTAssertEqual(metrics.rowsPerSecond, 0.0)
    }

    func testMetricsDefaultFlags() {
        let metrics = makeMetrics()
        XCTAssertFalse(metrics.isComplete)
        XCTAssertFalse(metrics.isError)
        XCTAssertNil(metrics.commandTag)
        XCTAssertNil(metrics.error)
    }

    // MARK: - ColumnInfo

    func testColumnInfoDefaults() {
        let col = ColumnInfo(name: "username", dataType: "text")
        XCTAssertEqual(col.name, "username")
        XCTAssertEqual(col.dataType, "text")
        XCTAssertFalse(col.isPrimaryKey)
        XCTAssertTrue(col.isNullable)
        XCTAssertNil(col.maxLength)
    }

    func testColumnInfoAllFields() {
        let col = ColumnInfo(name: "id", dataType: "int4", isPrimaryKey: true, isNullable: false, maxLength: 4)
        XCTAssertEqual(col.name, "id")
        XCTAssertEqual(col.dataType, "int4")
        XCTAssertTrue(col.isPrimaryKey)
        XCTAssertFalse(col.isNullable)
        XCTAssertEqual(col.maxLength, 4)
    }

    func testColumnInfoCodable() throws {
        let col = ColumnInfo(name: "email", dataType: "text", isPrimaryKey: false, isNullable: true)
        let encoded = try JSONEncoder().encode(col)
        let decoded = try JSONDecoder().decode(ColumnInfo.self, from: encoded)
        XCTAssertEqual(decoded.name, col.name)
        XCTAssertEqual(decoded.dataType, col.dataType)
        XCTAssertEqual(decoded.isPrimaryKey, col.isPrimaryKey)
        XCTAssertEqual(decoded.isNullable, col.isNullable)
    }

    // MARK: - ResultCellPayload

    func testResultCellPayload_WithData() {
        let data = "hello".data(using: .utf8)!
        let cell = ResultCellPayload(dataTypeOID: 25, format: .text, bytes: data)
        XCTAssertEqual(cell.dataTypeOID, 25)
        XCTAssertEqual(cell.format, .text)
        XCTAssertEqual(cell.bytes, data)
    }

    func testResultCellPayload_NilBytes() {
        let cell = ResultCellPayload(dataTypeOID: 25, format: .binary, bytes: nil)
        XCTAssertNil(cell.bytes)
        XCTAssertEqual(cell.format, .binary)
    }

    func testResultCellPayload_Format() {
        XCTAssertEqual(ResultCellPayload.Format.text.rawValue, 0)
        XCTAssertEqual(ResultCellPayload.Format.binary.rawValue, 1)
    }

    // MARK: - ResultRowPayload

    func testResultRowPayload() {
        let cells = [ResultCellPayload(dataTypeOID: 23, format: .binary, bytes: Data([0, 0, 0, 42]))]
        let payload = ResultRowPayload(cells: cells, rowIndex: 5)

        XCTAssertEqual(payload.cells.count, 1)
        XCTAssertEqual(payload.rowIndex, 5)
    }

    func testResultRowPayload_EmptyCells() {
        let payload = ResultRowPayload(cells: [], rowIndex: 0)
        XCTAssertTrue(payload.cells.isEmpty)
        XCTAssertEqual(payload.rowIndex, 0)
    }

    // MARK: - PostgresStreamResult

    func testStreamResult() {
        let columns = [makeColumn()]
        let metrics = makeMetrics()

        let result = PostgresStreamResult(
            columns: columns,
            totalRowCount: 100,
            metrics: metrics,
            commandTag: "SELECT 100"
        )

        XCTAssertEqual(result.columns.count, 1)
        XCTAssertEqual(result.totalRowCount, 100)
        XCTAssertEqual(result.commandTag, "SELECT 100")
    }

    func testStreamResult_NoCommandTag() {
        let result = PostgresStreamResult(
            columns: [],
            totalRowCount: 0,
            metrics: makeMetrics()
        )
        XCTAssertNil(result.commandTag)
    }
}
