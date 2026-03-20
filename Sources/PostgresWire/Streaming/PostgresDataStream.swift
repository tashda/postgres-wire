import Foundation
import Logging
import PostgresNIO

/// Actor managing PostgreSQL data streaming with integrated formatting.
/// Prefer `PostgresRowExtractor` and `PostgresCellFormatter` for lower per-row overhead in new code.
public actor PostgresDataStream {

    // MARK: - Configuration

    private let configuration: PostgresStreamConfiguration
    private let logger: Logger
    private let operationStart: TimeInterval

    // MARK: - Data Storage

    /// Column information for the result set
    public private(set) var columns: [ColumnInfo] = []

    /// Raw row payloads for deferred formatting
    private(set) public var rawRows: [ResultRowPayload] = []

    /// Formatted rows for immediate display
    private(set) public var formattedRows: [[String?]] = []

    /// Total number of rows processed
    private(set) public var totalRowCount: Int = 0

    // MARK: - State Management

    /// Current streaming state
    private(set) public var state: StreamState = .streaming

    /// Command tag from PostgreSQL when query completes
    private(set) public var commandTag: String?

    /// Progress tracking
    private var lastProgressUpdate: TimeInterval = 0
    private var lastProgressRowCount: Int = 0

    // MARK: - Formatting Engine

    private let formatterEngine: PostgresFormatterEngine

    // MARK: - Memory Management

    /// Maximum rows to keep in memory
    private var maxConcurrentRows: Int { configuration.maxConcurrentRows }

    // MARK: - Initialization

    public init(
        configuration: PostgresStreamConfiguration,
        logger: Logger,
        operationStart: TimeInterval = Date().timeIntervalSinceReferenceDate
    ) {
        self.configuration = configuration
        self.logger = logger
        self.operationStart = operationStart
        self.formatterEngine = PostgresFormatterEngine(configuration: configuration)
        self.lastProgressUpdate = operationStart
    }

    // MARK: - Column Management

    /// Set column information (called once when first row is processed)
    public func setColumns(_ newColumns: [ColumnInfo]) {
        guard columns.isEmpty else { return }
        columns = newColumns
        Task {
            await formatterEngine.setColumns(newColumns)
        }
    }

    // MARK: - Row Processing

    /// Process a single PostgreSQL row
    public func appendRow(_ row: PostgresRow) async {
        guard state == .streaming else { return }

        let rowIndex = totalRowCount

        // Extract column information if this is the first row
        if columns.isEmpty {
            let newColumns = row.map { cell in
                ColumnInfo(
                    name: cell.columnName,
                    dataType: "\(cell.dataType)",
                    isPrimaryKey: false, // TODO: Extract from metadata if available
                    isNullable: true // TODO: Extract from metadata if available
                )
            }
            setColumns(newColumns)
        }

        // Convert row to raw payload
        let payload = convertRowToPayload(row, rowIndex: rowIndex)
        rawRows.append(payload)

        // Decide formatting strategy based on configuration and row index
        let shouldFormatImmediately = shouldFormatRowImmediately(rowIndex: rowIndex)
        var formattedRow: [String?] = []

        if shouldFormatImmediately {
            formattedRow = await formatterEngine.formatRow(payload)
            formattedRows.append(formattedRow)
        } else if configuration.formattingEnabled {
            // For deferred formatting, add placeholder efficiently
            if formattedRows.count <= rowIndex {
                formattedRows.append(Array(repeating: nil, count: columns.count))
            } else {
                // Row already exists as placeholder, nothing to do
            }
        }

        totalRowCount += 1

        // Enforce memory limits
        await enforceMemoryLimits()

        // Update progress if needed
        await maybeUpdateProgress()
    }

    /// Get formatted rows in a specific range (for incremental loading)
    public func getFormattedRows(in range: Range<Int>) async -> [[String?]] {
        let startIndex = max(0, range.lowerBound)
        let endIndex = min(totalRowCount, range.upperBound)

        var result: [[String?]] = []

        for i in startIndex..<endIndex {
            if i < formattedRows.count {
                let row = formattedRows[i]
                if row.contains(nil) && configuration.formattingEnabled {
                    // Need to format this row on-demand
                    if i < rawRows.count {
                        let formattedRow = await formatterEngine.formatRow(rawRows[i])
                        // Store formatted row for future use
                        if i < formattedRows.count {
                            formattedRows[i] = formattedRow
                        }
                        result.append(formattedRow)
                    } else {
                        result.append(row)
                    }
                } else {
                    result.append(row)
                }
            } else {
                // Row not yet available
                result.append(Array(repeating: nil, count: columns.count))
            }
        }

        return result
    }

    /// Get raw rows in a specific range (for deferred formatting)
    public func getRawRows(in range: Range<Int>) async -> [ResultRowPayload] {
        let startIndex = max(0, range.lowerBound)
        let endIndex = min(totalRowCount, range.upperBound)

        guard startIndex < rawRows.count else { return [] }

        let endIndexClamped = min(endIndex, rawRows.count)
        return Array(rawRows[startIndex..<endIndexClamped])
    }

    /// Get current row count for live counter
    public func getLiveRowCount() async -> Int {
        return totalRowCount
    }

    /// Get current metrics
    public func getMetrics() async -> PostgresStreamMetrics {
        let now = Date().timeIntervalSinceReferenceDate
        return PostgresStreamMetrics(
            batchRowCount: 0, // This would be set in batch operations
            loopElapsed: now - operationStart,
            decodeDuration: 0, // This would be tracked in batch operations
            totalElapsed: now - operationStart,
            cumulativeRowCount: totalRowCount,
            fetchRowCount: totalRowCount
        )
    }

    /// Mark streaming as completed
    public func complete(with commandTag: String? = nil) async {
        state = .completed
        self.commandTag = commandTag

        // Format any remaining unformatted rows if configured to do so
        if configuration.formattingEnabled && configuration.formattingMode != .deferred {
            await formatAllRemainingRows()
        }
    }

    /// Mark streaming as failed
    public func fail(with error: Error) async {
        state = .error
        logger.error("PostgreSQL streaming failed: \(error)")
    }

    /// Cancel streaming
    public func cancel() async {
        state = .cancelled
        logger.info("PostgreSQL streaming cancelled")
    }

    // MARK: - Private Helper Methods

    /// Convert PostgreSQL row to raw payload
    private func convertRowToPayload(_ row: PostgresRow, rowIndex: Int) -> ResultRowPayload {
        let cells = row.map { cell in
            let formatRaw = UInt8(clamping: cell.format.rawValue)
            let format = ResultCellPayload.Format(rawValue: formatRaw) ?? .text

            let data: Data?
            if var buffer = cell.bytes {
                let readable = buffer.readableBytes
                if readable > 0 {
                    if let extracted = buffer.readData(length: readable) {
                        data = extracted
                    } else if let bytes = buffer.readBytes(length: readable) {
                        data = Data(bytes)
                    } else {
                        data = Data()
                    }
                } else {
                    data = Data()
                }
            } else {
                data = nil
            }

            return ResultCellPayload(dataTypeOID: cell.dataType.rawValue, format: format, bytes: data)
        }

        return ResultRowPayload(cells: cells, rowIndex: rowIndex)
    }

    /// Determine if a row should be formatted immediately based on configuration
    private func shouldFormatRowImmediately(rowIndex: Int) -> Bool {
        guard configuration.formattingEnabled else { return false }

        switch configuration.formattingMode {
        case .immediate:
            return true
        case .deferred:
            return false
        case .smart:
            return rowIndex < configuration.initialPreviewRows
        }
    }

    /// Enforce memory limits by removing old data
    private func enforceMemoryLimits() async {
        guard totalRowCount > maxConcurrentRows else { return }

        let rowsToRemove = totalRowCount - maxConcurrentRows

        // Remove oldest raw rows
        if rowsToRemove < rawRows.count {
            rawRows.removeFirst(rowsToRemove)
        }

        // Remove oldest formatted rows
        if rowsToRemove < formattedRows.count {
            formattedRows.removeFirst(rowsToRemove)
        }

        logger.debug("Enforced memory limits: removed \(rowsToRemove) rows")
    }

    /// Update progress if throttling allows
    private func maybeUpdateProgress() async {
        guard configuration.liveCounterEnabled else { return }

        let now = Date().timeIntervalSinceReferenceDate
        let timeSinceLastUpdate = now - lastProgressUpdate
        let rowsSinceLastUpdate = totalRowCount - lastProgressRowCount

        // Update if either condition is met (more responsive)
        let shouldUpdateByTime = timeSinceLastUpdate >= configuration.progressThrottle
        let shouldUpdateByCount = rowsSinceLastUpdate >= configuration.liveCounterFrequency

        if shouldUpdateByTime || shouldUpdateByCount {
            lastProgressUpdate = now
            lastProgressRowCount = totalRowCount
        }
    }

    /// Format all remaining unformatted rows (used on completion)
    private func formatAllRemainingRows() async {
        for i in 0..<rawRows.count {
            if i >= formattedRows.count || formattedRows[i].contains(nil) {
                let formattedRow = await formatterEngine.formatRow(rawRows[i])
                if i < formattedRows.count {
                    formattedRows[i] = formattedRow
                } else {
                    formattedRows.append(formattedRow)
                }
            }
        }
    }
}
