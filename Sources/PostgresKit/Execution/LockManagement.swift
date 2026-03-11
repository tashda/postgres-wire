import PostgresWire

/// Advisory and table lock management.
public extension PostgresDatabaseClient {
    /// Lock a table in the specified mode.
    @discardableResult
    func lock(table: String, mode: PostgresLockMode, nowait: Bool = false) async throws -> Int {
        var sql = "LOCK TABLE \(quoteIdentifier(table)) IN \(mode.rawValue)"
        if nowait { sql += " NOWAIT" }
        return try await executeDDL(sql)
    }

    /// Acquire a session-level advisory lock.
    func advisoryLock(key: Int64) async throws -> Bool {
        let rows = try await simpleQuery("SELECT pg_advisory_lock(\(key)) as locked")
        for try await locked in rows.decode(Bool.self) {
            return locked
        }
        throw PostgresKit.PostgresError.protocolError("Advisory lock query failed")
    }

    /// Attempt to acquire a session-level advisory lock without waiting.
    func tryAdvisoryLock(key: Int64) async throws -> Bool {
        let rows = try await simpleQuery("SELECT pg_try_advisory_lock(\(key)) as locked")
        for try await locked in rows.decode(Bool.self) {
            return locked
        }
        throw PostgresKit.PostgresError.protocolError("Advisory lock query failed")
    }

    /// Release a previously acquired session-level advisory lock.
    func advisoryUnlock(key: Int64) async throws -> Bool {
        let rows = try await simpleQuery("SELECT pg_advisory_unlock(\(key)) as unlocked")
        for try await unlocked in rows.decode(Bool.self) {
            return unlocked
        }
        throw PostgresKit.PostgresError.protocolError("Advisory unlock query failed")
    }
}
