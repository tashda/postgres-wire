import Logging
import PostgresWire

/// High-level query execution entry points.
public extension PostgresDatabaseClient {
    /// Execute a simple query and return the resulting row sequence.
    func simpleQuery(_ sql: String) async throws -> WireRowSequence {
        // CALL WIRE DIRECTLY: PostgresClient.query returns a sequence that manages its own connection.
        // Using withConnection { ... } here is wrong because the connection is returned to the pool 
        // as soon as the block finishes, cancelling the sequence iteration.
        try await wire.query(WireQuery(sql: sql))
    }

    /// Execute a query with binds and return the row sequence.
    func simpleQuery(_ sql: String, options: PostgresExecutionOptions?) async throws -> WireRowSequence {
        try await wire.query(WireQuery(sql: sql), options: options)
    }

    /// Execute a query with streaming and formatting.
    func streamQuery(
        _ sql: String,
        configuration: PostgresStreamConfiguration = .default,
        onUpdate: @escaping @Sendable (PostgresStreamUpdate) async -> Void,
        logger: Logger? = nil
    ) async throws -> PostgresStreamResult {
        let effectiveLogger = logger ?? self.logger
        let result: Result<PostgresStreamResult, PostgresError> = await PostgresDatabaseClient.executeWithEnhancedError {
            try await wire.streamQuery(sql, configuration: configuration, onUpdate: onUpdate, logger: effectiveLogger)
        }
        switch result {
        case .success(let streamResult):
            return streamResult
        case .failure(let error):
            throw error
        }
    }

    /// Execute a streaming query with automatic cursor management for large result sets.
    func streamQueryWithCursor(
        _ sql: String,
        configuration: PostgresStreamConfiguration = .default,
        onUpdate: @escaping @Sendable (PostgresStreamUpdate) async -> Void,
        logger: Logger? = nil
    ) async throws -> PostgresStreamResult {
        let effectiveLogger = logger ?? self.logger
        let result: Result<PostgresStreamResult, PostgresError> = await PostgresDatabaseClient.executeWithEnhancedError {
            try await wire.streamQueryWithCursor(sql, configuration: configuration, onUpdate: onUpdate, logger: effectiveLogger)
        }
        switch result {
        case .success(let streamResult):
            return streamResult
        case .failure(let error):
            throw error
        }
    }

    /// Execute a DDL statement and return the number of affected rows.
    @discardableResult
    internal func executeDDL(_ sql: String) async throws -> Int {
        let rows = try await simpleQuery(sql)
        var count = 0
        for try await _ in rows.decode((String?).self) {
            count += 1
        }
        return count
    }
}
