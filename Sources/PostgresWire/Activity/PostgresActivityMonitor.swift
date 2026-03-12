import Foundation
import NIOConcurrencyHelpers
import Logging

public final class PostgresActivityMonitor: @unchecked Sendable {
    private let client: PostgresWireClient
    private let baselineLock = NIOLock()
    private let logger = Logger(label: "dk.tippr.postgres-wire.activity-monitor")

    private var lastWaits: [String: PostgresWaitStat] = [:]
    private var lastDatabaseStats: [String: PostgresDatabaseStat] = [:]
    private var lastSnapshotTime: Date?

    public init(client: PostgresWireClient) {
        self.client = client
    }

    public func snapshot(options: PostgresActivityOptions = .init()) async throws -> PostgresActivitySnapshot {
        let now = Date()
        
        // Use task groups or async let with catch blocks for resilience
        async let processes: [PostgresProcessInfo] = {
            do { return try await fetchProcesses(options: options) }
            catch { logger.error("Activity Monitor: Failed to fetch processes: \(error)"); return [] }
        }()
        
        async let databaseStats: [PostgresDatabaseStat] = {
            do { return try await fetchDatabaseStats() }
            catch { logger.error("Activity Monitor: Failed to fetch DB stats: \(error)"); return [] }
        }()
        
        async let waitStats: [PostgresWaitStat] = {
            do { return try await fetchWaits() }
            catch { logger.error("Activity Monitor: Failed to fetch waits: \(error)"); return [] }
        }()
        
        async let expensive: [PostgresExpensiveQuery] = {
            do { return try await fetchExpensiveQueries(options: options) }
            catch { logger.error("Activity Monitor: Failed to fetch expensive queries: \(error)"); return [] }
        }()
        
        let (procs, dbStats, waits, expensiveQueries) = try await (processes, databaseStats, waitStats, expensive)
        
        let waitsDelta = computeWaitDeltas(current: waits)
        let dbStatsDelta = computeDatabaseStatsDeltas(current: dbStats, now: now)
        
        // Overview calculation
        let waitingTasks = procs.filter { $0.waitEvent != nil }.count
        let totalXactDelta = dbStatsDelta.reduce(0) { $0 + $1.xact_commit_delta + $1.xact_rollback_delta }
        let totalBlocksReadDelta = dbStatsDelta.reduce(0) { $0 + $1.blks_read_delta }
        
        let elapsed = now.timeIntervalSince(lastSnapshotTime ?? now)
        let xactRate = elapsed > 0 ? Double(totalXactDelta) / elapsed : 0
        let ioRate = elapsed > 0 ? (Double(totalBlocksReadDelta) * 8192) / (1024 * 1024 * elapsed) : 0
        
        let overview = PostgresActivityOverview(
            processorTimePercent: 0, 
            waitingTasksCount: waitingTasks,
            databaseIOMBPerSec: ioRate,
            transactionsPerSec: xactRate
        )
        
        self.baselineLock.withLock {
            self.lastSnapshotTime = now
        }
        
        return PostgresActivitySnapshot(
            capturedAt: now,
            overview: overview,
            processes: procs,
            waits: waits,
            waitsDelta: waitsDelta,
            databaseStats: dbStats,
            databaseStatsDelta: dbStatsDelta,
            expensiveQueries: expensiveQueries
        )
    }

    public func streamSnapshots(every seconds: TimeInterval = 5.0, options: PostgresActivityOptions = .init()) -> AsyncThrowingStream<PostgresActivitySnapshot, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    do {
                        let snap = try await self.snapshot(options: options)
                        continuation.yield(snap)
                    } catch {
                        logger.error("Activity Monitor: Stream snapshot error: \(error)")
                    }
                    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Internal Queries

    private func fetchProcesses(options: PostgresActivityOptions) async throws -> [PostgresProcessInfo] {
        let sql = """
        SELECT pid, datname, usename, application_name, client_addr, backend_start, xact_start, query_start, state_change, wait_event_type, wait_event, state, query
        FROM pg_stat_activity
        WHERE pid <> pg_backend_pid()
        ORDER BY pid
        """
        let rows = try await client.query(WireQuery(sql: sql))
        var results: [PostgresProcessInfo] = []
        for try await row in rows {
            results.append(PostgresProcessInfo(
                pid: row.column("pid")?.int32 ?? 0,
                databaseName: row.column("datname")?.string,
                userName: row.column("usename")?.string,
                applicationName: row.column("application_name")?.string,
                clientAddress: row.column("client_addr")?.string,
                backendStart: row.column("backend_start")?.date,
                xactStart: row.column("xact_start")?.date,
                queryStart: row.column("query_start")?.date,
                stateChange: row.column("state_change")?.date,
                waitEventType: row.column("wait_event_type")?.string,
                waitEvent: row.column("wait_event")?.string,
                state: row.column("state")?.string,
                query: options.includeSqlText ? row.column("query")?.string : nil,
                isBlocked: false
            ))
        }
        return results
    }

    private func fetchWaits() async throws -> [PostgresWaitStat] {
        let sql = """
        SELECT wait_event_type, wait_event, count(*)
        FROM pg_stat_activity
        WHERE wait_event IS NOT NULL
        GROUP BY 1, 2
        ORDER BY 3 DESC
        """
        let rows = try await client.query(WireQuery(sql: sql))
        var results: [PostgresWaitStat] = []
        for try await row in rows {
            guard let type = row.column("wait_event_type")?.string,
                  let event = row.column("wait_event")?.string
            else { continue }
            results.append(PostgresWaitStat(
                waitEventType: type,
                waitEvent: event,
                count: row.column("count")?.int ?? 0
            ))
        }
        return results
    }

    private func fetchDatabaseStats() async throws -> [PostgresDatabaseStat] {
        let sql = """
        SELECT datname, numbackends, xact_commit, xact_rollback, blks_read, blks_hit, tup_returned, tup_fetched, tup_inserted, tup_updated, tup_deleted
        FROM pg_stat_database
        WHERE datname IS NOT NULL
        ORDER BY datname
        """
        let rows = try await client.query(WireQuery(sql: sql))
        var results: [PostgresDatabaseStat] = []
        for try await row in rows {
            guard let name = row.column("datname")?.string else { continue }
            results.append(PostgresDatabaseStat(
                datname: name,
                numbackends: row.column("numbackends")?.int ?? 0,
                xact_commit: row.column("xact_commit")?.int64 ?? 0,
                xact_rollback: row.column("xact_rollback")?.int64 ?? 0,
                blks_read: row.column("blks_read")?.int64 ?? 0,
                blks_hit: row.column("blks_hit")?.int64 ?? 0,
                tup_returned: row.column("tup_returned")?.int64 ?? 0,
                tup_fetched: row.column("tup_fetched")?.int64 ?? 0,
                tup_inserted: row.column("tup_inserted")?.int64 ?? 0,
                tup_updated: row.column("tup_updated")?.int64 ?? 0,
                tup_deleted: row.column("tup_deleted")?.int64 ?? 0
            ))
        }
        return results
    }

    private func fetchExpensiveQueries(options: PostgresActivityOptions) async throws -> [PostgresExpensiveQuery] {
        // First check if pg_stat_statements exists
        let checkSql = "SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements'"
        let checkRows = try await client.query(WireQuery(sql: checkSql))
        var exists = false
        for try await _ in checkRows {
            exists = true
            break
        }
        
        if !exists { return [] }
        
        let sql = """
        SELECT queryid, query, calls, total_exec_time, min_exec_time, max_exec_time, mean_exec_time, rows
        FROM pg_stat_statements
        ORDER BY total_exec_time DESC
        LIMIT 20
        """
        let rows = try await client.query(WireQuery(sql: sql))
        var results: [PostgresExpensiveQuery] = []
        for try await row in rows {
            results.append(PostgresExpensiveQuery(
                queryid: row.column("queryid")?.int64,
                query: row.column("query")?.string ?? "",
                calls: row.column("calls")?.int64 ?? 0,
                total_exec_time: row.column("total_exec_time")?.double ?? 0,
                min_exec_time: row.column("min_exec_time")?.double ?? 0,
                max_exec_time: row.column("max_exec_time")?.double ?? 0,
                mean_exec_time: row.column("mean_exec_time")?.double ?? 0,
                rows: row.column("rows")?.int64 ?? 0
            ))
        }
        return results
    }

    // MARK: - Delta helpers

    private func computeWaitDeltas(current: [PostgresWaitStat]) -> [PostgresWaitStatDelta] {
        var deltas: [PostgresWaitStatDelta] = []
        let previous = baselineLock.withLock { lastWaits }
        for w in current {
            let key = "\(w.waitEventType):\(w.waitEvent)"
            if let prev = previous[key] {
                let d = PostgresWaitStatDelta(
                    waitEventType: w.waitEventType,
                    waitEvent: w.waitEvent,
                    countDelta: max(0, w.count - prev.count)
                )
                if d.countDelta > 0 {
                    deltas.append(d)
                }
            }
        }
        // update baseline
        baselineLock.withLock {
            lastWaits = Dictionary(uniqueKeysWithValues: current.map { ("\($0.waitEventType):\($0.waitEvent)", $0) })
        }
        return deltas.sorted { $0.countDelta > $1.countDelta }
    }

    private func computeDatabaseStatsDeltas(current: [PostgresDatabaseStat], now: Date) -> [PostgresDatabaseStatDelta] {
        var deltas: [PostgresDatabaseStatDelta] = []
        let previous = baselineLock.withLock { lastDatabaseStats }
        for s in current {
            if let prev = previous[s.datname] {
                let d = PostgresDatabaseStatDelta(
                    datname: s.datname,
                    xact_commit_delta: max(0, s.xact_commit - prev.xact_commit),
                    xact_rollback_delta: max(0, s.xact_rollback - prev.xact_rollback),
                    blks_read_delta: max(0, s.blks_read - prev.blks_read),
                    blks_hit_delta: max(0, s.blks_hit - prev.blks_hit)
                )
                deltas.append(d)
            }
        }
        // update baseline
        baselineLock.withLock {
            lastDatabaseStats = Dictionary(uniqueKeysWithValues: current.map { ($0.datname, $0) })
        }
        return deltas
    }
}
