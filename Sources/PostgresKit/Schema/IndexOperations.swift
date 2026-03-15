import PostgresWire

/// High-level Index Data Definition Language (DDL) operations.
public extension PostgresAdminClient {
    /// Create a standard index.
    @discardableResult
    func createIndex(
        name: String,
        table: String,
        columns: [String],
        unique: Bool = false,
        ifNotExists: Bool = false
    ) async throws -> Int {
        var parts: [String] = ["CREATE"]
        if unique { parts.append("UNIQUE") }
        parts.append("INDEX")
        if ifNotExists { parts.append("IF NOT EXISTS") }
        parts.append(client.quoteIdentifier(name))
        parts.append("ON \(client.quoteIdentifier(table))")

        let columnList = columns.map { client.quoteIdentifier($0) }.joined(separator: ", ")
        parts.append("(\(columnList))")

        return try await client.executeDDL(parts.joined(separator: " "))
    }

    /// Drop an existing index.
    @discardableResult
    func dropIndex(name: String, ifExists: Bool = false, cascade: Bool = false) async throws -> Int {
        var parts: [String] = ["DROP INDEX"]
        if ifExists { parts.append("IF EXISTS") }
        parts.append(client.quoteIdentifier(name))
        if cascade { parts.append("CASCADE") }
        return try await client.executeDDL(parts.joined(separator: " "))
    }

    /// Create an index with advanced configuration.
    @discardableResult
    func createAdvancedIndex(
        name: String,
        table: String,
        columns: [PostgresIndexColumn],
        indexType: PostgresIndexType = .btree,
        unique: Bool = false,
        ifNotExists: Bool = false,
        whereClause: String? = nil,
        tablespace: String? = nil,
        nullsDistinct: Bool = true
    ) async throws -> Int {
        var parts: [String] = ["CREATE"]
        if unique { parts.append("UNIQUE") }
        parts.append("INDEX")
        if ifNotExists { parts.append("IF NOT EXISTS") }
        parts.append(client.quoteIdentifier(name))
        parts.append("ON \(client.quoteIdentifier(table))")

        parts.append("USING \(indexType)")

        let columnList = columns.map { column in
            var colDef = client.quoteIdentifier(column.name)
            if let order = column.order { colDef += " " + order.rawValue }
            if let nullsOrder = column.nullsOrder { colDef += " NULLS " + nullsOrder.rawValue }
            return colDef
        }.joined(separator: ", ")
        parts.append("(\(columnList))")

        if let whereClause { parts.append("WHERE \(whereClause)") }
        if let tablespace { parts.append("TABLESPACE \(client.quoteIdentifier(tablespace))") }
        if !nullsDistinct { parts.append("NULLS NOT DISTINCT") }

        return try await client.executeDDL(parts.joined(separator: " "))
    }
}
