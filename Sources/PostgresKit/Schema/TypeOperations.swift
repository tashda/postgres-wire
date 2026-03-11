import PostgresWire

/// High-level Type Data Definition Language (DDL) operations.
public extension PostgresDatabaseClient {
    /// Create a new enum type.
    @discardableResult
    func createEnum(name: String, values: [String], ifNotExists: Bool = false) async throws -> Int {
        var parts: [String] = ["CREATE TYPE"]
        if ifNotExists { parts.append("IF NOT EXISTS") }
        parts.append(quoteIdentifier(name))
        parts.append("AS ENUM")
        let valueList = values.map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" }.joined(separator: ", ")
        parts.append("(\(valueList))")
        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Drop an existing enum type.
    @discardableResult
    func dropEnum(name: String, ifExists: Bool = false, cascade: Bool = false) async throws -> Int {
        var parts: [String] = ["DROP TYPE"]
        if ifExists { parts.append("IF EXISTS") }
        parts.append(quoteIdentifier(name))
        if cascade { parts.append("CASCADE") }
        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Add a value to an existing enum type.
    @discardableResult
    func addEnumValue(type: String, value: String, before: String? = nil, after: String? = nil) async throws -> Int {
        var parts: [String] = ["ALTER TYPE"]
        parts.append(quoteIdentifier(type))
        parts.append("ADD VALUE '\(value.replacingOccurrences(of: "'", with: "''"))'")
        if let before {
            parts.append("BEFORE '\(before.replacingOccurrences(of: "'", with: "''"))'")
        } else if let after {
            parts.append("AFTER '\(after.replacingOccurrences(of: "'", with: "''"))'")
        }
        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Rename an existing value in an enum type.
    @discardableResult
    func renameEnumValue(type: String, oldValue: String, newValue: String) async throws -> Int {
        let sql = "ALTER TYPE \(quoteIdentifier(type)) RENAME VALUE '\(oldValue.replacingOccurrences(of: "'", with: "''"))' TO '\(newValue.replacingOccurrences(of: "'", with: "''"))'"
        return try await executeDDL(sql)
    }
}
