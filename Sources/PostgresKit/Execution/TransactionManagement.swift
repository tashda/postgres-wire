import PostgresWire

/// Transaction lifecycle management.
public extension PostgresConnectionClient {
    /// Begin a standard transaction.
    @discardableResult
    func beginTransaction() async throws -> Int {
        return try await client.executeDDL("BEGIN")
    }

    /// Begin a transaction with specific isolation level and options.
    @discardableResult
    func beginTransaction(
        isolation: PostgresIsolationLevel,
        readOnly: Bool = false,
        deferrable: Bool = false
    ) async throws -> Int {
        var parts: [String] = ["BEGIN TRANSACTION"]
        parts.append("ISOLATION LEVEL \(isolation.rawValue)")
        if readOnly { parts.append("READ ONLY") }
        if deferrable { parts.append("DEFERRABLE") }
        return try await client.executeDDL(parts.joined(separator: " "))
    }

    /// Commit the current transaction.
    @discardableResult
    func commit() async throws -> Int {
        return try await client.executeDDL("COMMIT")
    }

    /// Roll back the current transaction.
    @discardableResult
    func rollback() async throws -> Int {
        return try await client.executeDDL("ROLLBACK")
    }

    /// Create a named savepoint within the current transaction.
    @discardableResult
    func createSavepoint(_ name: String) async throws -> Int {
        return try await client.executeDDL("SAVEPOINT \(client.quoteIdentifier(name))")
    }

    /// Roll back to a previously created savepoint.
    @discardableResult
    func rollbackToSavepoint(_ name: String) async throws -> Int {
        return try await client.executeDDL("ROLLBACK TO SAVEPOINT \(client.quoteIdentifier(name))")
    }

    /// Release a named savepoint.
    @discardableResult
    func releaseSavepoint(_ name: String) async throws -> Int {
        return try await client.executeDDL("RELEASE SAVEPOINT \(client.quoteIdentifier(name))")
    }
}

