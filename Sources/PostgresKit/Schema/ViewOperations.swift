import PostgresWire

/// High-level View Data Definition Language (DDL) operations.
public extension PostgresDatabaseClient {
    /// Create a standard view.
    @discardableResult
    func createView(
        name: String,
        query: String,
        temporary: Bool = false,
        orReplace: Bool = false
    ) async throws -> Int {
        var parts: [String] = ["CREATE"]
        if orReplace { parts.append("OR REPLACE") }
        if temporary { parts.append("TEMPORARY") }
        parts.append("VIEW")
        parts.append(quoteIdentifier(name))
        parts.append("AS \(query)")
        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Drop an existing view.
    @discardableResult
    func dropView(name: String, ifExists: Bool = false, cascade: Bool = false) async throws -> Int {
        var parts: [String] = ["DROP VIEW"]
        if ifExists { parts.append("IF EXISTS") }
        parts.append(quoteIdentifier(name))
        if cascade { parts.append("CASCADE") }
        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Create a materialized view.
    @discardableResult
    func createMaterializedView(
        name: String,
        query: String,
        ifNotExists: Bool = false
    ) async throws -> Int {
        var parts: [String] = ["CREATE MATERIALIZED VIEW"]
        if ifNotExists { parts.append("IF NOT EXISTS") }
        parts.append(quoteIdentifier(name))
        parts.append("AS \(query)")
        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Refresh a materialized view's contents.
    @discardableResult
    func refreshMaterializedView(name: String, concurrently: Bool = false) async throws -> Int {
        var parts: [String] = ["REFRESH MATERIALIZED VIEW"]
        if concurrently { parts.append("CONCURRENTLY") }
        parts.append(quoteIdentifier(name))
        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Drop an existing materialized view.
    @discardableResult
    func dropMaterializedView(name: String, ifExists: Bool = false, cascade: Bool = false) async throws -> Int {
        var parts: [String] = ["DROP MATERIALIZED VIEW"]
        if ifExists { parts.append("IF EXISTS") }
        parts.append(quoteIdentifier(name))
        if cascade { parts.append("CASCADE") }
        return try await executeDDL(parts.joined(separator: " "))
    }
}
