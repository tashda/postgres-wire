import Foundation

/// Represents the state and data updates during PostgreSQL query streaming
public struct PostgresStreamUpdate: Sendable {

    // MARK: - Core Data

    /// Column information for the result set
    public let columns: [ColumnInfo]

    /// Newly formatted rows since last update
    public let appendedRows: [[String?]]

    /// Raw row payloads for deferred formatting
    public let rawRows: [ResultRowPayload]

    /// Total number of rows processed so far
    public let totalRowCount: Int

    // MARK: - Metadata

    /// Performance metrics for this update
    public let metrics: PostgresStreamMetrics

    /// Range of row indices included in this update
    public let rowRange: Range<Int>?

    /// Current state of the stream
    public let state: StreamState

    // MARK: - Initialization

    public init(
        columns: [ColumnInfo],
        appendedRows: [[String?]],
        rawRows: [ResultRowPayload],
        totalRowCount: Int,
        metrics: PostgresStreamMetrics,
        rowRange: Range<Int>?,
        state: StreamState = .streaming
    ) {
        self.columns = columns
        self.appendedRows = appendedRows
        self.rawRows = rawRows
        self.totalRowCount = totalRowCount
        self.metrics = metrics
        self.rowRange = rowRange
        self.state = state
    }

    /// Create a progress-only update (no new rows)
    public static func progress(
        columns: [ColumnInfo],
        totalRowCount: Int,
        metrics: PostgresStreamMetrics
    ) -> PostgresStreamUpdate {
        return PostgresStreamUpdate(
            columns: columns,
            appendedRows: [],
            rawRows: [],
            totalRowCount: totalRowCount,
            metrics: metrics,
            rowRange: nil,
            state: .streaming
        )
    }

    /// Create a completion update
    public static func completion(
        columns: [ColumnInfo],
        totalRowCount: Int,
        metrics: PostgresStreamMetrics,
        commandTag: String? = nil
    ) -> PostgresStreamUpdate {
        var completionMetrics = metrics
        completionMetrics.isComplete = true
        completionMetrics.commandTag = commandTag

        return PostgresStreamUpdate(
            columns: columns,
            appendedRows: [],
            rawRows: [],
            totalRowCount: totalRowCount,
            metrics: completionMetrics,
            rowRange: nil,
            state: .completed
        )
    }

    /// Create an error update
    public static func error(
        columns: [ColumnInfo],
        totalRowCount: Int,
        error: Error
    ) -> PostgresStreamUpdate {
        var errorMetrics = PostgresStreamMetrics(
            batchRowCount: 0,
            loopElapsed: 0,
            decodeDuration: 0,
            totalElapsed: 0,
            cumulativeRowCount: totalRowCount
        )
        errorMetrics.isError = true
        errorMetrics.error = error

        return PostgresStreamUpdate(
            columns: columns,
            appendedRows: [],
            rawRows: [],
            totalRowCount: totalRowCount,
            metrics: errorMetrics,
            rowRange: nil,
            state: .error
        )
    }
}

/// Current state of the streaming process
public enum StreamState: String, Sendable {
    case streaming = "streaming"
    case completed = "completed"
    case error = "error"
    case cancelled = "cancelled"
}

/// Performance metrics for streaming operations
public struct PostgresStreamMetrics: Sendable {

    // MARK: - Batch Metrics

    /// Number of rows in this batch
    public let batchRowCount: Int

    /// Time taken for this batch loop (seconds)
    public let loopElapsed: TimeInterval

    /// Time spent decoding data in this batch (seconds)
    public let decodeDuration: TimeInterval

    /// Time spent waiting for network in this batch (seconds)
    public let fetchWait: TimeInterval

    // MARK: - Cumulative Metrics

    /// Total time since operation started (seconds)
    public let totalElapsed: TimeInterval

    /// Total number of rows processed so far
    public let cumulativeRowCount: Int

    /// Rows per second average
    public var rowsPerSecond: Double {
        guard totalElapsed > 0 else { return 0 }
        return Double(cumulativeRowCount) / totalElapsed
    }

    // MARK: - State Flags

    /// True if the stream is complete
    public var isComplete: Bool = false

    /// True if an error occurred
    public var isError: Bool = false

    /// Command tag from PostgreSQL (e.g., "SELECT 100000")
    public var commandTag: String?

    /// Error information if isError is true
    public var error: Error?

    // MARK: - Optional Fetch Metrics (for cursor queries)

    /// Number of rows requested in this fetch
    public let fetchRequestRowCount: Int?

    /// Actual number of rows received in this fetch
    public let fetchRowCount: Int

    /// Time for this specific fetch operation (seconds)
    public let fetchDuration: TimeInterval

    // MARK: - Initialization

    public init(
        batchRowCount: Int,
        loopElapsed: TimeInterval,
        decodeDuration: TimeInterval,
        totalElapsed: TimeInterval,
        cumulativeRowCount: Int,
        fetchRequestRowCount: Int? = nil,
        fetchRowCount: Int = 0,
        fetchDuration: TimeInterval = 0,
        fetchWait: TimeInterval = 0
    ) {
        self.batchRowCount = batchRowCount
        self.loopElapsed = loopElapsed
        self.decodeDuration = decodeDuration
        self.fetchWait = fetchWait
        self.totalElapsed = totalElapsed
        self.cumulativeRowCount = cumulativeRowCount
        self.fetchRequestRowCount = fetchRequestRowCount
        self.fetchRowCount = fetchRowCount
        self.fetchDuration = fetchDuration
    }
}

/// Column information for result sets
public struct ColumnInfo: Sendable, Codable {
    public let name: String
    public let dataType: String
    public let isPrimaryKey: Bool
    public let isNullable: Bool
    public let maxLength: Int?

    public init(
        name: String,
        dataType: String,
        isPrimaryKey: Bool = false,
        isNullable: Bool = true,
        maxLength: Int? = nil
    ) {
        self.name = name
        self.dataType = dataType
        self.isPrimaryKey = isPrimaryKey
        self.isNullable = isNullable
        self.maxLength = maxLength
    }
}

/// Raw row payload for deferred formatting
public struct ResultRowPayload: Sendable {
    public let cells: [ResultCellPayload]
    public let rowIndex: Int

    public init(cells: [ResultCellPayload], rowIndex: Int) {
        self.cells = cells
        self.rowIndex = rowIndex
    }
}

/// Cell payload with raw PostgreSQL data
public struct ResultCellPayload: Sendable {
    public let dataTypeOID: UInt32
    public let format: Format
    public let bytes: Data?

    public enum Format: UInt8, Sendable {
        case text = 0
        case binary = 1
    }

    public init(dataTypeOID: UInt32, format: Format, bytes: Data?) {
        self.dataTypeOID = dataTypeOID
        self.format = format
        self.bytes = bytes
    }
}

/// Final result of a streaming query operation
public struct PostgresStreamResult: Sendable {
    public let columns: [ColumnInfo]
    public let totalRowCount: Int
    public let metrics: PostgresStreamMetrics
    public let commandTag: String?

    public init(
        columns: [ColumnInfo],
        totalRowCount: Int,
        metrics: PostgresStreamMetrics,
        commandTag: String? = nil
    ) {
        self.columns = columns
        self.totalRowCount = totalRowCount
        self.metrics = metrics
        self.commandTag = commandTag
    }
}

/// Handler for streaming query updates
public typealias PostgresStreamUpdateHandler = @Sendable (PostgresStreamUpdate) async -> Void