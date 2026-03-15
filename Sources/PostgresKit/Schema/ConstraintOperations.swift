import PostgresWire

/// High-level Constraint Data Definition Language (DDL) operations.
public extension PostgresAdminClient {
    /// Add a primary key constraint to a table.
    @discardableResult
    func addPrimaryKey(table: String, column: String, constraintName: String? = nil) async throws -> Int {
        let name = constraintName ?? "pk_\(table)_\(column)"
        let sql = "ALTER TABLE \(client.quoteIdentifier(table)) ADD CONSTRAINT \(client.quoteIdentifier(name)) PRIMARY KEY (\(client.quoteIdentifier(column)))"
        return try await client.executeDDL(sql)
    }

    /// Add a foreign key constraint to a table.
    @discardableResult
    func addForeignKey(
        table: String,
        column: String,
        referencesTable: String,
        referencesColumn: String,
        constraintName: String? = nil,
        onDelete: PostgresForeignKeyAction? = nil,
        onUpdate: PostgresForeignKeyAction? = nil
    ) async throws -> Int {
        let name = constraintName ?? "fk_\(table)_\(column)_\(referencesTable)_\(referencesColumn)"
        var parts: [String] = [
            "ALTER TABLE \(client.quoteIdentifier(table))",
            "ADD CONSTRAINT \(client.quoteIdentifier(name))",
            "FOREIGN KEY (\(client.quoteIdentifier(column)))",
            "REFERENCES \(client.quoteIdentifier(referencesTable))(\(client.quoteIdentifier(referencesColumn)))"
        ]
        if let onDelete { parts.append("ON DELETE \(onDelete.rawValue)") }
        if let onUpdate { parts.append("ON UPDATE \(onUpdate.rawValue)") }
        return try await client.executeDDL(parts.joined(separator: " "))
    }

    /// Add a unique constraint to a table.
    @discardableResult
    func addUniqueConstraint(table: String, columns: [String], constraintName: String? = nil) async throws -> Int {
        let name = constraintName ?? "uq_\(table)_\(columns.joined(separator: "_"))"
        let columnList = columns.map { client.quoteIdentifier($0) }.joined(separator: ", ")
        let sql = "ALTER TABLE \(client.quoteIdentifier(table)) ADD CONSTRAINT \(client.quoteIdentifier(name)) UNIQUE (\(columnList))"
        return try await client.executeDDL(sql)
    }

    /// Add a check constraint to a table.
    @discardableResult
    func addCheckConstraint(table: String, condition: String, constraintName: String) async throws -> Int {
        let sql = "ALTER TABLE \(client.quoteIdentifier(table)) ADD CONSTRAINT \(client.quoteIdentifier(constraintName)) CHECK (\(condition))"
        return try await client.executeDDL(sql)
    }

    /// Drop a constraint from a table.
    @discardableResult
    func dropConstraint(table: String, constraintName: String, cascade: Bool = false) async throws -> Int {
        var parts: [String] = [
            "ALTER TABLE \(client.quoteIdentifier(table))",
            "DROP CONSTRAINT \(client.quoteIdentifier(constraintName))"
        ]
        if cascade { parts.append("CASCADE") }
        return try await client.executeDDL(parts.joined(separator: " "))
    }
}
