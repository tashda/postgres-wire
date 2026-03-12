import Logging
import PostgresWire

/// High-level query execution entry points.
public extension PostgresConnectionClient {
    /// Execute a simple query and return the resulting row sequence.
    func simpleQuery(_ sql: String) async throws -> WireRowSequence {
        try await client.wire.query(WireQuery(sql: sql))
    }

    /// Execute a query with binds and return the row sequence.
    func simpleQuery(_ sql: String, options: PostgresExecutionOptions?) async throws -> WireRowSequence {
        try await client.wire.query(WireQuery(sql: sql), options: options)
    }

    /// Execute a query with streaming and formatting.
    func streamQuery(
        _ sql: String,
        configuration: PostgresStreamConfiguration = .default,
        onUpdate: @escaping @Sendable (PostgresStreamUpdate) async -> Void,
        logger: Logger? = nil
    ) async throws -> PostgresStreamResult {
        let effectiveLogger = logger ?? client.logger
        let result: Result<PostgresStreamResult, PostgresError> = await PostgresClient.executeWithEnhancedError {
            try await client.wire.streamQuery(sql, configuration: configuration, onUpdate: onUpdate, logger: effectiveLogger)
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
        let effectiveLogger = logger ?? client.logger
        let result: Result<PostgresStreamResult, PostgresError> = await PostgresClient.executeWithEnhancedError {
            try await client.wire.streamQueryWithCursor(sql, configuration: configuration, onUpdate: onUpdate, logger: effectiveLogger)
        }
        switch result {
        case .success(let streamResult):
            return streamResult
        case .failure(let error):
            throw error
        }
    }
}

public extension PostgresClient {
    func simpleQuery(_ sql: String) async throws -> WireRowSequence {
        try await connection.simpleQuery(sql)
    }
    
    func simpleQuery(_ sql: String, options: PostgresExecutionOptions?) async throws -> WireRowSequence {
        try await connection.simpleQuery(sql, options: options)
    }
}
