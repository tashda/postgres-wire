import PostgresWire

/// Collation DDL operations.
public extension PostgresAdminClient {

    /// Create a collation.
    @discardableResult
    func createCollation(
        name: String,
        locale: String? = nil,
        lcCollate: String? = nil,
        lcCtype: String? = nil,
        provider: String? = nil,
        schema: String? = nil,
        ifNotExists: Bool = false
    ) async throws -> Int {
        let qualifiedName = schema.map { "\(client.quoteIdentifier($0)).\(client.quoteIdentifier(name))" } ?? client.quoteIdentifier(name)
        var parts: [String] = ["CREATE COLLATION"]
        if ifNotExists { parts.append("IF NOT EXISTS") }
        parts.append(qualifiedName)

        var clauses: [String] = []
        if let provider { clauses.append("provider = \(client.quoteLiteral(provider))") }
        if let locale { clauses.append("locale = \(client.quoteLiteral(locale))") }
        if let lcCollate { clauses.append("lc_collate = \(client.quoteLiteral(lcCollate))") }
        if let lcCtype { clauses.append("lc_ctype = \(client.quoteLiteral(lcCtype))") }

        parts.append("(\(clauses.joined(separator: ", ")))")
        return try await client.executeDDL(parts.joined(separator: " "))
    }

    /// Drop a collation.
    @discardableResult
    func dropCollation(name: String, ifExists: Bool = false, cascade: Bool = false, schema: String? = nil) async throws -> Int {
        let qualifiedName = schema.map { "\(client.quoteIdentifier($0)).\(client.quoteIdentifier(name))" } ?? client.quoteIdentifier(name)
        var parts: [String] = ["DROP COLLATION"]
        if ifExists { parts.append("IF EXISTS") }
        parts.append(qualifiedName)
        if cascade { parts.append("CASCADE") }
        return try await client.executeDDL(parts.joined(separator: " "))
    }
}
