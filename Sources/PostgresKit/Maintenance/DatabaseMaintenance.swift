import PostgresWire

/// Database maintenance operations.
public extension PostgresDatabaseClient {
    /// Perform a VACUUM operation.
    @discardableResult
    func vacuum(
        schema: String? = nil,
        table: String? = nil,
        analyze: Bool = false,
        full: Bool = false,
        verbose: Bool = false
    ) async throws -> Int {
        var parts: [String] = ["VACUUM"]
        if full { parts.append("FULL") }
        if analyze { parts.append("ANALYZE") }
        if verbose { parts.append("VERBOSE") }
        if let table {
            if let schema { parts.append("\(quoteIdentifier(schema)).\(quoteIdentifier(table))") }
            else { parts.append(quoteIdentifier(table)) }
        }
        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Perform an ANALYZE operation.
    @discardableResult
    func analyze(
        schema: String? = nil,
        table: String? = nil,
        verbose: Bool = false
    ) async throws -> Int {
        var parts: [String] = ["ANALYZE"]
        if verbose { parts.append("VERBOSE") }
        if let table {
            if let schema { parts.append("\(quoteIdentifier(schema)).\(quoteIdentifier(table))") }
            else { parts.append(quoteIdentifier(table)) }
        }
        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Perform a REINDEX operation.
    @discardableResult
    func reindex(
        database: String? = nil,
        schema: String? = nil,
        table: String? = nil,
        index: String? = nil,
        verbose: Bool = false
    ) async throws -> Int {
        var parts: [String] = ["REINDEX"]
        if verbose { parts.append("(VERBOSE)") }
        if let index { parts.append("INDEX \(quoteIdentifier(index))") }
        else if let table {
            if let schema { parts.append("TABLE \(quoteIdentifier(schema)).\(quoteIdentifier(table))") }
            else { parts.append("TABLE \(quoteIdentifier(table))") }
        } else if let schema { parts.append("SCHEMA \(quoteIdentifier(schema))") }
        else if let database { parts.append("DATABASE \(quoteIdentifier(database))") }
        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Install a PostgreSQL extension.
    @discardableResult
    func createExtension(
        _ name: String,
        ifNotExists: Bool = true,
        schema: String? = nil
    ) async throws -> Int {
        var parts: [String] = ["CREATE EXTENSION"]
        if ifNotExists { parts.append("IF NOT EXISTS") }
        parts.append(quoteIdentifier(name))
        if let schema { parts.append("WITH SCHEMA \(quoteIdentifier(schema))") }
        return try await executeDDL(parts.joined(separator: " "))
    }
}
