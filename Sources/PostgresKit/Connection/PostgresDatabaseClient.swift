import Foundation
import Logging
import Metrics
import PostgresWire
import PostgresNIO

/// Primary high-level client for PostgreSQL interaction.
///
/// Use this client to manage connections, execute queries, and perform database administration.
public final class PostgresDatabaseClient: @unchecked Sendable {
    internal let wire: PostgresWireClient
    internal let logger: Logger
    private let registry = PreparedRegistry()

    private init(wire: PostgresWireClient, logger: Logger) {
        self.wire = wire
        var logger = logger
        logger[metadataKey: "component"] = "PostgresDatabaseClient"
        self.logger = logger
    }

    deinit { wire.close() }

    /// Establish a connection to the database.
    public static func connect(
        configuration: PostgresConfiguration,
        logger: Logger = .init(label: "postgres-kit")
    ) async throws -> PostgresDatabaseClient {
        let result: Result<PostgresDatabaseClient, PostgresError> = await PostgresDatabaseClient.executeWithEnhancedError {
            let wire = try await PostgresWireClient.connect(configuration: configuration.makeWireConfiguration(), logger: logger)
            return PostgresDatabaseClient(wire: wire, logger: logger)
        }
        switch result {
        case .success(let client):
            return client
        case .failure(let error):
            throw error
        }
    }

    /// Explicitly close all connections.
    public func close() { wire.close() }

    /// Borrow a single connection for multi-step operations (e.g., transactions).
    public func withConnection<T>(
        _ body: @Sendable (PostgresDatabaseConnection) async throws -> T
    ) async throws -> T {
        do {
            return try await wire.withConnection { connection in
                let cache = await registry.statementCache(for: connection.id)
                let serverCache = await registry.serverPreparedCache(for: connection.id)
                return try await body(PostgresDatabaseConnection(wireConnection: connection, logger: logger, cache: cache, serverCache: serverCache))
            }
        } catch {
            throw PostgresKit.PostgresError.from(error)
        }
    }

    /// Internal helper to convert values to wire format.
    internal func toPGData(value: Any) throws -> PGData {
        if let encodable = value as? PostgresEncodable {
            var data = PGData(type: encodable.pgDataType)
            try encodable.encode(into: &data)
            return data
        } else {
            throw PostgresError.encodingError(type: type(of: value))
        }
    }
}

// MARK: - Internal Registry

/// Registry associates a per-connection StatementCache via connection identity.
private actor PreparedRegistry {
    private var stmtCaches: [ObjectIdentifier: StatementCache] = [:]
    private var serverCaches: [ObjectIdentifier: PreparedServerCache] = [:]

    func statementCache(for id: ObjectIdentifier) -> StatementCache {
        if let cache = stmtCaches[id] { return cache }
        let new = StatementCache(capacity: 256)
        stmtCaches[id] = new
        return new
    }

    func serverPreparedCache(for id: ObjectIdentifier) -> PreparedServerCache {
        if let cache = serverCaches[id] { return cache }
        let new = PreparedServerCache(capacity: 128)
        serverCaches[id] = new
        return new
    }
}
