import Foundation

public struct PostgresActivityOptions: Sendable, Equatable {
    public var includeSqlText: Bool
    public var includeQueryPlan: Bool

    public init(includeSqlText: Bool = true, includeQueryPlan: Bool = false) {
        self.includeSqlText = includeSqlText
        self.includeQueryPlan = includeQueryPlan
    }
}

public struct PostgresActivityOverview: Sendable {
    public let processorTimePercent: Double
    public let waitingTasksCount: Int
    public let databaseIOMBPerSec: Double
    public let transactionsPerSec: Double

    public init(
        processorTimePercent: Double,
        waitingTasksCount: Int,
        databaseIOMBPerSec: Double,
        transactionsPerSec: Double
    ) {
        self.processorTimePercent = processorTimePercent
        self.waitingTasksCount = waitingTasksCount
        self.databaseIOMBPerSec = databaseIOMBPerSec
        self.transactionsPerSec = transactionsPerSec
    }
}

public struct PostgresActivitySnapshot: Sendable {
    public let capturedAt: Date
    public let overview: PostgresActivityOverview?
    public let processes: [PostgresProcessInfo]
    public let waits: [PostgresWaitStat]
    public let waitsDelta: [PostgresWaitStatDelta]?
    public let databaseStats: [PostgresDatabaseStat]
    public let databaseStatsDelta: [PostgresDatabaseStatDelta]?
    public let expensiveQueries: [PostgresExpensiveQuery]
    public let pgStatStatementsAvailable: Bool

    public init(
        capturedAt: Date = Date(),
        overview: PostgresActivityOverview? = nil,
        processes: [PostgresProcessInfo],
        waits: [PostgresWaitStat],
        waitsDelta: [PostgresWaitStatDelta]? = nil,
        databaseStats: [PostgresDatabaseStat],
        databaseStatsDelta: [PostgresDatabaseStatDelta]? = nil,
        expensiveQueries: [PostgresExpensiveQuery],
        pgStatStatementsAvailable: Bool = true
    ) {
        self.capturedAt = capturedAt
        self.overview = overview
        self.processes = processes
        self.waits = waits
        self.waitsDelta = waitsDelta
        self.databaseStats = databaseStats
        self.databaseStatsDelta = databaseStatsDelta
        self.expensiveQueries = expensiveQueries
        self.pgStatStatementsAvailable = pgStatStatementsAvailable
    }
}

public struct PostgresProcessInfo: Sendable, Identifiable {
    public var id: Int32 { pid }
    
    public let pid: Int32
    public let databaseName: String?
    public let userName: String?
    public let applicationName: String?
    public let clientAddress: String?
    public let backendStart: Date?
    public let xactStart: Date?
    public let queryStart: Date?
    public let stateChange: Date?
    public let waitEventType: String?
    public let waitEvent: String?
    public let state: String?
    public let query: String?
    public let isBlocked: Bool
}

public struct PostgresWaitStat: Sendable {
    public let waitEventType: String
    public let waitEvent: String
    public let count: Int
}

public struct PostgresWaitStatDelta: Sendable, Identifiable {
    public var id: String { "\(waitEventType):\(waitEvent)" }
    
    public let waitEventType: String
    public let waitEvent: String
    public let countDelta: Int
}

public struct PostgresDatabaseStat: Sendable {
    public let datname: String
    public let numbackends: Int
    public let xact_commit: Int64
    public let xact_rollback: Int64
    public let blks_read: Int64
    public let blks_hit: Int64
    public let tup_returned: Int64
    public let tup_fetched: Int64
    public let tup_inserted: Int64
    public let tup_updated: Int64
    public let tup_deleted: Int64
}

public struct PostgresDatabaseStatDelta: Sendable, Identifiable {
    public var id: String { datname }
    
    public let datname: String
    public let xact_commit_delta: Int64
    public let xact_rollback_delta: Int64
    public let blks_read_delta: Int64
    public let blks_hit_delta: Int64
}

public struct PostgresExpensiveQuery: Sendable, Identifiable {
    public var id: String { "\(queryid ?? 0):\(query)" }
    
    public let queryid: Int64?
    public let query: String
    public let calls: Int64
    public let total_exec_time: Double
    public let min_exec_time: Double
    public let max_exec_time: Double
    public let mean_exec_time: Double
    public let rows: Int64
}
