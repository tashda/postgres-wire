import PostgresWire
import PostgresNIO

/// High-level Data Manipulation Language (DML) operations.
public extension PostgresDatabaseClient {
    /// Insert rows into a table.
    @discardableResult
    func insert(
        into table: String,
        columns: [String] = [],
        values: [[Any]]
    ) async throws -> Int {
        let isEmpty = values.isEmpty
        let processedValues = try values.map { row in
            try row.map { value in
                try toPGData(value: value)
            }
        }

        return try await withConnection { conn in
            if isEmpty { return 0 }

            let columnList = columns.isEmpty ? "" : "(\(columns.map(quoteIdentifier).joined(separator: ", ")))"

            var allBinds: [PGData] = []
            var bindIndex = 1
            let valuePlaceholders = processedValues.enumerated().map { _, processedRow in
                let placeholders = processedRow.enumerated().map { _, _ in
                    defer { bindIndex += 1 }
                    return "$\(bindIndex)"
                }
                allBinds.append(contentsOf: processedRow)
                return "(" + placeholders.joined(separator: ", ") + ")"
            }.joined(separator: ", ")

            let sql = "INSERT INTO \(quoteIdentifier(table))\(columnList) VALUES \(valuePlaceholders)"

            let rows = try await conn.query(sql, binds: allBinds)
            var count = 0
            for try await _ in rows.decode((String?).self) {
                count += 1
            }
            return count
        }
    }

    /// Update existing rows in a table.
    @discardableResult
    func update(
        table: String,
        set: [String: Any],
        whereClause: String? = nil
    ) async throws -> Int {
        let setClause = set.map { (column, value) in
            let quotedColumn = quoteIdentifier(column)
            if let stringValue = value as? String {
                return "\(quotedColumn) = '\(stringValue.replacingOccurrences(of: "'", with: "''"))'"
            } else {
                return "\(quotedColumn) = \(value)"
            }
        }.joined(separator: ", ")

        var sql = "UPDATE \(quoteIdentifier(table)) SET \(setClause)"

        if let whereClause {
            sql += " WHERE \(whereClause)"
        }

        return try await executeDDL(sql)
    }

    /// Delete rows from a table.
    @discardableResult
    func delete(
        from table: String,
        whereClause: String? = nil
    ) async throws -> Int {
        var sql = "DELETE FROM \(quoteIdentifier(table))"
        if let whereClause {
            sql += " WHERE \(whereClause)"
        }
        return try await executeDDL(sql)
    }

    /// Efficiently remove all rows from a table.
    @discardableResult
    func truncate(
        table: String,
        cascade: Bool = false,
        restartIdentity: Bool = false
    ) async throws -> Int {
        var parts: [String] = ["TRUNCATE TABLE"]
        parts.append(quoteIdentifier(table))
        if cascade { parts.append("CASCADE") }
        if restartIdentity { parts.append("RESTART IDENTITY") } else { parts.append("CONTINUE IDENTITY") }
        return try await executeDDL(parts.joined(separator: " "))
    }
}
