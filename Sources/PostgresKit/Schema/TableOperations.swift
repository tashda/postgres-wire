import PostgresWire

/// High-level Table Data Definition Language (DDL) operations.
public extension PostgresDatabaseClient {
    /// Create a new table.
    @discardableResult
    func createTable(
        name: String,
        columns: [PostgresColumnDefinition],
        temporary: Bool = false,
        ifNotExists: Bool = false
    ) async throws -> Int {
        var parts: [String] = ["CREATE"]
        if temporary { parts.append("TEMPORARY") }
        parts.append("TABLE")
        if ifNotExists { parts.append("IF NOT EXISTS") }
        parts.append(quoteIdentifier(name))

        let columnDefinitions = columns.map { column in
            var columnDef = "\(quoteIdentifier(column.name)) \(column.dataType)"
            if let defaultValue = column.defaultValue { columnDef += " DEFAULT \(defaultValue)" }
            if column.nullable == false { columnDef += " NOT NULL" }
            if column.primaryKey { columnDef += " PRIMARY KEY" }
            if column.unique { columnDef += " UNIQUE" }
            return columnDef
        }.joined(separator: ", ")

        parts.append("(\(columnDefinitions))")
        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Drop an existing table.
    @discardableResult
    func dropTable(name: String, ifExists: Bool = false, cascade: Bool = false, schema: String? = nil) async throws -> Int {
        let qualifiedName = schema.map { "\(quoteIdentifier($0)).\(quoteIdentifier(name))" } ?? quoteIdentifier(name)
        var parts: [String] = ["DROP TABLE"]
        if ifExists { parts.append("IF EXISTS") }
        parts.append(qualifiedName)
        if cascade { parts.append("CASCADE") }
        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Add a column to an existing table.
    @discardableResult
    func addColumn(
        table: String,
        column: PostgresColumnDefinition,
        using: String? = nil
    ) async throws -> Int {
        var columnDef = "\(quoteIdentifier(column.name)) \(column.dataType)"
        if let defaultValue = column.defaultValue { columnDef += " DEFAULT \(defaultValue)" }
        if column.nullable == false { columnDef += " NOT NULL" }
        if column.primaryKey { columnDef += " PRIMARY KEY" }
        if column.unique { columnDef += " UNIQUE" }

        var parts: [String] = ["ALTER TABLE \(quoteIdentifier(table))", "ADD COLUMN \(columnDef)"]
        if let using { parts.append("USING \(using)") }
        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Remove a column from a table.
    @discardableResult
    func dropColumn(table: String, column: String) async throws -> Int {
        let sql = "ALTER TABLE \(quoteIdentifier(table)) DROP COLUMN \(quoteIdentifier(column))"
        return try await executeDDL(sql)
    }

    /// Rename an existing table.
    @discardableResult
    func renameTable(oldName: String, newName: String, schema: String? = nil) async throws -> Int {
        let qualifiedOldName = schema.map { "\(quoteIdentifier($0)).\(quoteIdentifier(oldName))" } ?? quoteIdentifier(oldName)
        let sql = "ALTER TABLE \(qualifiedOldName) RENAME TO \(quoteIdentifier(newName))"
        return try await executeDDL(sql)
    }

    /// Rename a column within a table.
    @discardableResult
    func renameColumn(table: String, oldName: String, newName: String) async throws -> Int {
        let sql = "ALTER TABLE \(quoteIdentifier(table)) RENAME COLUMN \(quoteIdentifier(oldName)) TO \(quoteIdentifier(newName))"
        return try await executeDDL(sql)
    }

    /// Change a column's data type.
    @discardableResult
    func alterColumnType(table: String, column: String, newType: String, using: String? = nil) async throws -> Int {
        var parts: [String] = [
            "ALTER TABLE \(quoteIdentifier(table))",
            "ALTER COLUMN \(quoteIdentifier(column))",
            "TYPE \(newType)"
        ]
        if let using { parts.append("USING \(using)") }
        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Set or remove a column's default value.
    @discardableResult
    func alterColumnDefault(table: String, column: String, defaultValue: String?) async throws -> Int {
        let sql: String
        if let defaultValue = defaultValue {
            sql = "ALTER TABLE \(quoteIdentifier(table)) ALTER COLUMN \(quoteIdentifier(column)) SET DEFAULT \(defaultValue)"
        } else {
            sql = "ALTER TABLE \(quoteIdentifier(table)) ALTER COLUMN \(quoteIdentifier(column)) DROP DEFAULT"
        }
        return try await executeDDL(sql)
    }

    /// Set or remove a column's NOT NULL constraint.
    @discardableResult
    func alterColumnNullability(table: String, column: String, nullable: Bool) async throws -> Int {
        let sql = "ALTER TABLE \(quoteIdentifier(table)) ALTER COLUMN \(quoteIdentifier(column)) \(nullable ? "DROP" : "SET") NOT NULL"
        return try await executeDDL(sql)
    }

    /// Copy data between tables.
    @discardableResult
    func copyTable(
        from sourceTable: String,
        to targetTable: String,
        columns: [String]? = nil
    ) async throws -> Int {
        let columnList = columns.map { "(\($0.map(quoteIdentifier).joined(separator: ", ")))" } ?? ""
        let sql = "INSERT INTO \(quoteIdentifier(targetTable))\(columnList) SELECT * FROM \(quoteIdentifier(sourceTable))"
        return try await executeDDL(sql)
    }

    /// Create a table from the results of a SELECT query.
    @discardableResult
    func createTableAs(
        name: String,
        selectQuery: String,
        temporary: Bool = false,
        ifNotExists: Bool = false
    ) async throws -> Int {
        var parts: [String] = ["CREATE"]
        if temporary { parts.append("TEMPORARY") }
        parts.append("TABLE")
        if ifNotExists { parts.append("IF NOT EXISTS") }
        parts.append(quoteIdentifier(name))
        parts.append("AS \(selectQuery)")
        return try await executeDDL(parts.joined(separator: " "))
    }
}
