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
    private var maxConnections: Int?
    private var currentDatabase: String?

    public init(client: PostgresWireClient) {
        self.client = client
    }

    public func snapshot(options: PostgresActivityOptions = .init()) async throws -> PostgresActivitySnapshot {
        let now = Date()

        // Fetch one-time server info
        if maxConnections == nil {
            do {
                let rows = try await client.query(WireQuery(sql: "SHOW max_connections"))
                for try await row in rows {
                    let row = row.makeRandomAccess()
                    if let val = row[data: "max_connections"].int {
                        maxConnections = val
                    }
                    break
                }
            } catch {
                logger.error("Activity Monitor: Failed to fetch max_connections: \(error)")
            }
        }
        if currentDatabase == nil {
            do {
                let rows = try await client.query(WireQuery(sql: "SELECT current_database()"))
                for try await row in rows {
                    let row = row.makeRandomAccess()
                    currentDatabase = row[data: "current_database"].string
                    break
                }
            } catch {
                logger.error("Activity Monitor: Failed to fetch current_database: \(error)")
            }
        }

        // Check if pg_stat_statements exists
        let checkSql = "SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements'"
        var pgStatStatementsExists = false
        do {
            let checkRows = try await client.query(WireQuery(sql: checkSql))
            for try await _ in checkRows {
                pgStatStatementsExists = true
                break
            }
        } catch {
            // Ignore error
        }

        // Fetch all data in parallel with resilient error handling
        async let processes: [PostgresProcessInfo] = {
            do { return try await fetchProcesses(options: options, capturedAt: now) }
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
            guard pgStatStatementsExists else { return [] }
            do { return try await fetchExpensiveQueries(options: options) }
            catch { logger.error("Activity Monitor: Failed to fetch expensive queries: \(error)"); return [] }
        }()

        async let lockInfo: [PostgresLockInfo] = {
            do { return try await fetchLocks() }
            catch { logger.error("Activity Monitor: Failed to fetch locks: \(error)"); return [] }
        }()

        async let tableStatsResult: [PostgresTableStat] = {
            do { return try await fetchTableStats() }
            catch { logger.error("Activity Monitor: Failed to fetch table stats: \(error)"); return [] }
        }()

        async let replicationResult: [PostgresReplicationInfo] = {
            do { return try await fetchReplicationStats() }
            catch { logger.error("Activity Monitor: Failed to fetch replication: \(error)"); return [] }
        }()

        async let operationProgressResult: [PostgresOperationProgress] = {
            do { return try await fetchOperationProgress() }
            catch { logger.error("Activity Monitor: Failed to fetch operation progress: \(error)"); return [] }
        }()

        let (procs, dbStats, waits, expensiveQueries, locks, tblStats, replication, opProgress) =
            await (processes, databaseStats, waitStats, expensive, lockInfo, tableStatsResult, replicationResult, operationProgressResult)

        let waitsDelta = computeWaitDeltas(current: waits)
        let dbStatsDelta = computeDatabaseStatsDeltas(current: dbStats, now: now)

        // Overview calculation
        let totalConnections = dbStats.reduce(0) { $0 + $1.numbackends }
        let maxConn = maxConnections ?? 100

        // Cache hit ratio across all databases
        let totalHit = dbStatsDelta.reduce(Int64(0)) { $0 + $1.blks_hit_delta }
        let totalRead = dbStatsDelta.reduce(Int64(0)) { $0 + $1.blks_read_delta }
        let totalBlocks = totalHit + totalRead
        let cacheHitPercent = totalBlocks > 0 ? Double(totalHit) / Double(totalBlocks) * 100.0 : 100.0

        let totalXactDelta = dbStatsDelta.reduce(Int64(0)) { $0 + $1.xact_commit_delta + $1.xact_rollback_delta }
        let totalBlocksReadDelta = dbStatsDelta.reduce(Int64(0)) { $0 + $1.blks_read_delta }

        let elapsed = now.timeIntervalSince(lastSnapshotTime ?? now)
        let xactRate = elapsed > 0 ? Double(totalXactDelta) / elapsed : 0
        let ioRate = elapsed > 0 ? (Double(totalBlocksReadDelta) * 8192) / (1024 * 1024 * elapsed) : 0

        let totalDeadTuples = tblStats.reduce(Int64(0)) { $0 + $1.nDeadTup }

        let overview = PostgresActivityOverview(
            connectionsCount: totalConnections,
            maxConnections: maxConn,
            cacheHitPercent: cacheHitPercent,
            transactionsPerSec: xactRate,
            databaseIOMBPerSec: ioRate,
            totalDeadTuples: totalDeadTuples
        )

        self.baselineLock.withLock {
            self.lastSnapshotTime = now
        }

        return PostgresActivitySnapshot(
            capturedAt: now,
            connectedDatabase: currentDatabase ?? "postgres",
            overview: overview,
            processes: procs,
            waits: waits,
            waitsDelta: waitsDelta,
            databaseStats: dbStats,
            databaseStatsDelta: dbStatsDelta,
            expensiveQueries: expensiveQueries,
            pgStatStatementsAvailable: pgStatStatementsExists,
            locks: locks,
            tableStats: tblStats,
            replicationInfo: replication,
            operationProgress: opProgress
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

    /// Terminates a backend process by its PID.
    public func killSession(pid: Int32) async throws {
        let sql = "SELECT pg_terminate_backend(\(pid))"
        let rows = try await client.query(WireQuery(sql: sql))
        for try await _ in rows {
            break
        }
    }

    // MARK: - Internal Queries

    private func fetchProcesses(options: PostgresActivityOptions, capturedAt: Date) async throws -> [PostgresProcessInfo] {
        let sql = """
        SELECT pid, datname, usename, application_name, client_addr,
               backend_start, xact_start, query_start, state_change,
               wait_event_type, wait_event, state, query, backend_type
        FROM pg_stat_activity
        WHERE pid <> pg_backend_pid()
        ORDER BY pid
        """
        let rows = try await client.query(WireQuery(sql: sql))
        var results: [PostgresProcessInfo] = []
        for try await row in rows {
            let row = row.makeRandomAccess()
            results.append(PostgresProcessInfo(
                pid: row[data: "pid"].int32 ?? 0,
                databaseName: row[data: "datname"].string,
                userName: row[data: "usename"].string,
                applicationName: row[data: "application_name"].string,
                clientAddress: row[data: "client_addr"].string,
                backendStart: row[data: "backend_start"].date,
                xactStart: row[data: "xact_start"].date,
                queryStart: row[data: "query_start"].date,
                stateChange: row[data: "state_change"].date,
                waitEventType: row[data: "wait_event_type"].string,
                waitEvent: row[data: "wait_event"].string,
                state: row[data: "state"].string,
                query: options.includeSqlText ? row[data: "query"].string : nil,
                backendType: row[data: "backend_type"].string,
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
            let row = row.makeRandomAccess()
            guard let type = row[data: "wait_event_type"].string,
                  let event = row[data: "wait_event"].string
            else { continue }
            results.append(PostgresWaitStat(
                waitEventType: type,
                waitEvent: event,
                count: row[data: "count"].int ?? 0
            ))
        }
        return results
    }

    private func fetchDatabaseStats() async throws -> [PostgresDatabaseStat] {
        let sql = """
        SELECT datname, numbackends, xact_commit, xact_rollback,
               blks_read, blks_hit, tup_returned, tup_fetched,
               tup_inserted, tup_updated, tup_deleted,
               temp_files, deadlocks
        FROM pg_stat_database
        WHERE datname IS NOT NULL
        ORDER BY datname
        """
        let rows = try await client.query(WireQuery(sql: sql))
        var results: [PostgresDatabaseStat] = []
        for try await row in rows {
            let row = row.makeRandomAccess()
            guard let name = row[data: "datname"].string else { continue }
            results.append(PostgresDatabaseStat(
                datname: name,
                numbackends: row[data: "numbackends"].int ?? 0,
                xact_commit: row[data: "xact_commit"].int64 ?? 0,
                xact_rollback: row[data: "xact_rollback"].int64 ?? 0,
                blks_read: row[data: "blks_read"].int64 ?? 0,
                blks_hit: row[data: "blks_hit"].int64 ?? 0,
                tup_returned: row[data: "tup_returned"].int64 ?? 0,
                tup_fetched: row[data: "tup_fetched"].int64 ?? 0,
                tup_inserted: row[data: "tup_inserted"].int64 ?? 0,
                tup_updated: row[data: "tup_updated"].int64 ?? 0,
                tup_deleted: row[data: "tup_deleted"].int64 ?? 0,
                temp_files: row[data: "temp_files"].int64 ?? 0,
                deadlocks: row[data: "deadlocks"].int64 ?? 0
            ))
        }
        return results
    }

    private func fetchExpensiveQueries(options: PostgresActivityOptions) async throws -> [PostgresExpensiveQuery] {
        let sql = """
        SELECT queryid, query, calls, total_exec_time, min_exec_time,
               max_exec_time, mean_exec_time, rows
        FROM pg_stat_statements
        ORDER BY total_exec_time DESC
        LIMIT 20
        """
        let rows = try await client.query(WireQuery(sql: sql))
        var results: [PostgresExpensiveQuery] = []
        for try await row in rows {
            let row = row.makeRandomAccess()
            results.append(PostgresExpensiveQuery(
                queryid: row[data: "queryid"].int64,
                query: row[data: "query"].string ?? "",
                calls: row[data: "calls"].int64 ?? 0,
                total_exec_time: row[data: "total_exec_time"].double ?? 0,
                min_exec_time: row[data: "min_exec_time"].double ?? 0,
                max_exec_time: row[data: "max_exec_time"].double ?? 0,
                mean_exec_time: row[data: "mean_exec_time"].double ?? 0,
                rows: row[data: "rows"].int64 ?? 0
            ))
        }
        return results
    }

    private func fetchLocks() async throws -> [PostgresLockInfo] {
        // Filter out:
        // - Our own backend PID (the monitor's queries)
        // - AccessShareLock on system catalog objects (pg_*) — these are routine read locks
        //   taken by every SELECT and are not meaningful contention
        // Focus on: waiting locks, exclusive locks, locks on user relations
        let sql = """
        SELECT l.pid, a.datname, l.locktype,
               COALESCE(c.relname, l.locktype) AS relation,
               l.mode, l.granted,
               bl.pid AS blocking_pid,
               a.query, a.state,
               CASE WHEN NOT l.granted AND a.state_change IS NOT NULL
                    THEN EXTRACT(EPOCH FROM (now() - a.state_change))
                    ELSE NULL
               END AS wait_seconds
        FROM pg_locks l
        JOIN pg_stat_activity a ON l.pid = a.pid
        LEFT JOIN pg_class c ON l.relation = c.oid
        LEFT JOIN pg_locks bl ON bl.locktype = l.locktype
            AND bl.relation = l.relation
            AND bl.page = l.page
            AND bl.tuple = l.tuple
            AND bl.granted = true
            AND bl.pid <> l.pid
            AND NOT l.granted
        WHERE a.pid <> pg_backend_pid()
          AND NOT (l.mode = 'AccessShareLock' AND l.granted
                   AND c.relname IS NOT NULL AND c.relname LIKE 'pg_%')
        ORDER BY l.granted ASC, l.pid
        """
        let rows = try await client.query(WireQuery(sql: sql))
        var results: [PostgresLockInfo] = []
        for try await row in rows {
            let row = row.makeRandomAccess()
            results.append(PostgresLockInfo(
                pid: row[data: "pid"].int32 ?? 0,
                databaseName: row[data: "datname"].string,
                locktype: row[data: "locktype"].string ?? "",
                relation: row[data: "relation"].string,
                mode: row[data: "mode"].string ?? "",
                granted: row[data: "granted"].bool ?? true,
                blockingPid: row[data: "blocking_pid"].int32,
                query: row[data: "query"].string,
                state: row[data: "state"].string,
                waitDuration: row[data: "wait_seconds"].double
            ))
        }
        return results
    }

    private func fetchTableStats() async throws -> [PostgresTableStat] {
        let sql = """
        SELECT schemaname, relname,
               COALESCE(seq_scan, 0) AS seq_scan,
               COALESCE(seq_tup_read, 0) AS seq_tup_read,
               COALESCE(idx_scan, 0) AS idx_scan,
               COALESCE(idx_tup_fetch, 0) AS idx_tup_fetch,
               COALESCE(n_live_tup, 0) AS n_live_tup,
               COALESCE(n_dead_tup, 0) AS n_dead_tup,
               last_vacuum, last_autovacuum,
               last_analyze, last_autoanalyze
        FROM pg_stat_user_tables
        ORDER BY n_dead_tup DESC
        LIMIT 50
        """
        let rows = try await client.query(WireQuery(sql: sql))
        var results: [PostgresTableStat] = []
        for try await row in rows {
            let row = row.makeRandomAccess()
            guard let schema = row[data: "schemaname"].string,
                  let name = row[data: "relname"].string else { continue }
            results.append(PostgresTableStat(
                schemaName: schema,
                tableName: name,
                seqScan: row[data: "seq_scan"].int64 ?? 0,
                seqTupRead: row[data: "seq_tup_read"].int64 ?? 0,
                idxScan: row[data: "idx_scan"].int64 ?? 0,
                idxTupFetch: row[data: "idx_tup_fetch"].int64 ?? 0,
                nLiveTup: row[data: "n_live_tup"].int64 ?? 0,
                nDeadTup: row[data: "n_dead_tup"].int64 ?? 0,
                lastVacuum: row[data: "last_vacuum"].date,
                lastAutoVacuum: row[data: "last_autovacuum"].date,
                lastAnalyze: row[data: "last_analyze"].date,
                lastAutoAnalyze: row[data: "last_autoanalyze"].date
            ))
        }
        return results
    }

    private func fetchReplicationStats() async throws -> [PostgresReplicationInfo] {
        let sql = """
        SELECT pid, usename, application_name, client_addr,
               state, sent_lsn::text, write_lsn::text,
               flush_lsn::text, replay_lsn::text,
               write_lag::text, flush_lag::text, replay_lag::text
        FROM pg_stat_replication
        ORDER BY pid
        """
        let rows = try await client.query(WireQuery(sql: sql))
        var results: [PostgresReplicationInfo] = []
        for try await row in rows {
            let row = row.makeRandomAccess()
            results.append(PostgresReplicationInfo(
                pid: row[data: "pid"].int32 ?? 0,
                usename: row[data: "usename"].string ?? "",
                applicationName: row[data: "application_name"].string ?? "",
                clientAddr: row[data: "client_addr"].string,
                state: row[data: "state"].string ?? "",
                sentLsn: row[data: "sent_lsn"].string,
                writeLsn: row[data: "write_lsn"].string,
                flushLsn: row[data: "flush_lsn"].string,
                replayLsn: row[data: "replay_lsn"].string,
                writeLag: row[data: "write_lag"].string,
                flushLag: row[data: "flush_lag"].string,
                replayLag: row[data: "replay_lag"].string
            ))
        }
        return results
    }

    private func fetchOperationProgress() async throws -> [PostgresOperationProgress] {
        // UNION ALL across all pg_stat_progress_* views
        let sql = """
        SELECT v.pid, a.datname, v.operation, v.phase,
               COALESCE(c.relname, '') AS relation,
               v.progress_pct,
               a.backend_start
        FROM (
            SELECT pid, 'VACUUM' AS operation, phase,
                   relid,
                   CASE WHEN heap_blks_total > 0
                        THEN ROUND(100.0 * heap_blks_scanned / heap_blks_total)
                        ELSE NULL END AS progress_pct
            FROM pg_stat_progress_vacuum
            UNION ALL
            SELECT pid, 'ANALYZE' AS operation, phase,
                   relid,
                   CASE WHEN sample_blks_total > 0
                        THEN ROUND(100.0 * sample_blks_scanned / sample_blks_total)
                        ELSE NULL END AS progress_pct
            FROM pg_stat_progress_analyze
            UNION ALL
            SELECT pid, 'CREATE INDEX' AS operation, phase,
                   relid,
                   CASE WHEN blocks_total > 0
                        THEN ROUND(100.0 * blocks_done / blocks_total)
                        ELSE NULL END AS progress_pct
            FROM pg_stat_progress_create_index
            UNION ALL
            SELECT pid, 'CLUSTER' AS operation, phase,
                   relid,
                   CASE WHEN heap_blks_total > 0
                        THEN ROUND(100.0 * heap_blks_scanned / heap_blks_total)
                        ELSE NULL END AS progress_pct
            FROM pg_stat_progress_cluster
            UNION ALL
            SELECT pid, 'COPY' AS operation, phase,
                   relid,
                   CASE WHEN bytes_total > 0
                        THEN ROUND(100.0 * bytes_processed / bytes_total)
                        ELSE NULL END AS progress_pct
            FROM pg_stat_progress_copy
            UNION ALL
            SELECT pid, 'BASEBACKUP' AS operation, phase,
                   0 AS relid,
                   CASE WHEN backup_total > 0
                        THEN ROUND(100.0 * backup_streamed / backup_total)
                        ELSE NULL END AS progress_pct
            FROM pg_stat_progress_basebackup
        ) v
        JOIN pg_stat_activity a ON a.pid = v.pid
        LEFT JOIN pg_class c ON c.oid = v.relid AND v.relid > 0
        ORDER BY v.pid
        """
        let rows = try await client.query(WireQuery(sql: sql))
        var results: [PostgresOperationProgress] = []
        for try await row in rows {
            let row = row.makeRandomAccess()
            results.append(PostgresOperationProgress(
                pid: row[data: "pid"].int32 ?? 0,
                operation: row[data: "operation"].string ?? "",
                phase: row[data: "phase"].string ?? "",
                databaseName: row[data: "datname"].string,
                relation: row[data: "relation"].string,
                progressPercent: row[data: "progress_pct"].double,
                startedAt: row[data: "backend_start"].date
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
                    blks_hit_delta: max(0, s.blks_hit - prev.blks_hit),
                    tup_inserted_delta: max(0, s.tup_inserted - prev.tup_inserted),
                    tup_updated_delta: max(0, s.tup_updated - prev.tup_updated),
                    tup_deleted_delta: max(0, s.tup_deleted - prev.tup_deleted),
                    temp_files_delta: max(0, s.temp_files - prev.temp_files),
                    deadlocks_delta: max(0, s.deadlocks - prev.deadlocks)
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
