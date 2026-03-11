import Logging

/// A legacy compatibility wrapper for database administrative operations.
/// 
/// New code should prefer calling methods directly on `PostgresDatabaseClient`.
public struct PostgresAdmin: Sendable {
    private let client: PostgresDatabaseClient
    private let logger: Logger

    public init(client: PostgresDatabaseClient, logger: Logger) {
        self.client = client
        self.logger = logger
    }

    @discardableResult
    public func vacuum(
        schema: String? = nil,
        table: String? = nil,
        analyze: Bool = false,
        full: Bool = false,
        verbose: Bool = false
    ) async throws -> Int {
        try await client.vacuum(schema: schema, table: table, analyze: analyze, full: full, verbose: verbose)
    }

    @discardableResult
    public func analyze(
        schema: String? = nil,
        table: String? = nil,
        verbose: Bool = false
    ) async throws -> Int {
        try await client.analyze(schema: schema, table: table, verbose: verbose)
    }

    @discardableResult
    public func reindex(
        database: String? = nil,
        schema: String? = nil,
        table: String? = nil,
        index: String? = nil,
        verbose: Bool = false
    ) async throws -> Int {
        try await client.reindex(database: database, schema: schema, table: table, index: index, verbose: verbose)
    }

    public func show(_ parameter: String) async throws -> String? {
        let rows = try await client.simpleQuery("SHOW \(client.quoteIdentifier(parameter))")
        for try await row in rows.decode(String.self) { return row }
        return nil
    }

    public func set(_ parameter: String, value: String, local: Bool = false) async throws {
        _ = try await client.setConfiguration(parameter: parameter, value: value, local: local)
    }
}
