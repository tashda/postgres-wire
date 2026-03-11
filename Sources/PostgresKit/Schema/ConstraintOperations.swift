import PostgresWire

/// High-level Constraint Data Definition Language (DDL) operations.
public extension PostgresDatabaseClient {
    /// Add a primary key constraint to a table.
    @discardableResult
    func addPrimaryKey(table: String, column: String, constraintName: String? = nil) async throws -> Int {
        let name = constraintName ?? "pk_\(table)_\(column)"
        let sql = "ALTER TABLE \(quoteIdentifier(table)) ADD CONSTRAINT \(quoteIdentifier(name)) PRIMARY KEY (\(quoteIdentifier(column)))"
        return try await executeDDL(sql)
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
            "ALTER TABLE \(quoteIdentifier(table))",
            "ADD CONSTRAINT \(quoteIdentifier(name))",
            "FOREIGN KEY (\(quoteIdentifier(column)))",
            "REFERENCES \(quoteIdentifier(referencesTable))(\(quoteIdentifier(referencesColumn)))"
        ]
        if let onDelete { parts.append("ON DELETE \(onDelete.rawValue)") }
        if let onUpdate { parts.append("ON UPDATE \(onUpdate.rawValue)") }
        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Add a unique constraint to a table.
    @discardableResult
    func addUniqueConstraint(table: String, columns: [String], constraintName: String? = nil) async throws -> Int {
        let name = constraintName ?? "uq_\(table)_\(columns.joined(separator: "_"))"
        let columnList = columns.map { quoteIdentifier($0) }.joined(separator: ", ")
        let sql = "ALTER TABLE \(quoteIdentifier(table)) ADD CONSTRAINT \(quoteIdentifier(name)) UNIQUE (\(columnList))"
        return try await executeDDL(sql)
    }

    /// Add a check constraint to a table.
    @discardableResult
    func addCheckConstraint(table: String, condition: String, constraintName: String) async throws -> Int {
        let sql = "ALTER TABLE \(quoteIdentifier(table)) ADD CONSTRAINT \(quoteIdentifier(constraintName)) CHECK (\(condition))"
        return try await executeDDL(sql)
    }

    /// Drop a constraint from a table.
    @discardableResult
    func dropConstraint(table: String, constraintName: String, cascade: Bool = false) async throws -> Int {
        var parts: [String] = [
            "ALTER TABLE \(quoteIdentifier(table))",
            "DROP CONSTRAINT \(quoteIdentifier(constraintName))"
        ]
        if cascade { parts.append("CASCADE") }
        return try await executeDDL(parts.joined(separator: " "))
    }
}
