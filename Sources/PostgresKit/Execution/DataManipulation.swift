import Foundation
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
        let converted = try values.map { row in
            try row.map(PostgresInsertValue.fromAny)
        }
        return try await insert(into: table, columns: columns, values: converted)
    }

    /// Insert rows using structured values that can mix binds and SQL expressions.
    @discardableResult
    func insert(
        into table: String,
        columns: [String] = [],
        values: [[PostgresInsertValue]]
    ) async throws -> Int {
        try await withConnection { conn in
            try await conn.insert(into: table, columns: columns, values: values)
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
        restartIdentity: Bool = false,
        schema: String? = nil
    ) async throws -> Int {
        let qualifiedName = schema.map { "\(quoteIdentifier($0)).\(quoteIdentifier(table))" } ?? quoteIdentifier(table)
        var parts: [String] = ["TRUNCATE TABLE"]
        parts.append(qualifiedName)
        if cascade { parts.append("CASCADE") }
        if restartIdentity { parts.append("RESTART IDENTITY") } else { parts.append("CONTINUE IDENTITY") }
        return try await executeDDL(parts.joined(separator: " "))
    }
}

public extension PostgresDatabaseConnection {
    /// Insert rows using structured values that can mix binds and SQL expressions.
    @discardableResult
    func insert(
        into table: String,
        columns: [String] = [],
        values: [[PostgresInsertValue]]
    ) async throws -> Int {
        if values.isEmpty { return 0 }

        let columnList = columns.isEmpty ? "" : "(\(columns.map(quoteIdentifier).joined(separator: ", ")))"

        var allBinds: [PGData] = []
        var bindIndex = 1
        let valuePlaceholders = try values.map { row in
            let fragments = try row.map { value in
                switch value {
                case .bind(let encodable):
                    defer { bindIndex += 1 }
                    allBinds.append(try toPGData(value: encodable))
                    return "$\(bindIndex)"
                case .sql(let sql):
                    return sql
                }
            }
            return "(\(fragments.joined(separator: ", ")))"
        }.joined(separator: ", ")

        let sql = "INSERT INTO \(quoteIdentifier(table))\(columnList) VALUES \(valuePlaceholders)"
        let rows = try await query(sql, binds: allBinds)
        var count = 0
        for try await _ in rows.decode((String?).self) {
            count += 1
        }
        return count
    }
}

private extension PostgresInsertValue {
    static func fromAny(_ value: Any) throws -> PostgresInsertValue {
        if let value = value as? PostgresInsertValue {
            return value
        }
        if let encodable = value as? any PostgresEncodable {
            return .bind(encodable)
        }
        if value is NSNull {
            return .null
        }
        throw PostgresError.encodingError(type: type(of: value))
    }
}
