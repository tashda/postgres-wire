import PostgresWire

/// High-level Database and Schema Data Definition Language (DDL) operations.
public extension PostgresDatabaseClient {
    /// Create a new database.
    @discardableResult
    func createDatabase(
        name: String,
        ifNotExists: Bool = false,
        owner: String? = nil,
        template: String = "template1",
        encoding: String? = nil
    ) async throws -> Int {
        var parts: [String] = ["CREATE DATABASE"]
        if ifNotExists { parts.append("IF NOT EXISTS") }
        parts.append(quoteIdentifier(name))
        parts.append("WITH TEMPLATE \(quoteIdentifier(template))")
        if let owner { parts.append("OWNER \(quoteIdentifier(owner))") }
        if let encoding { parts.append("ENCODING '\(encoding)'") }
        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Drop an existing database.
    @discardableResult
    func dropDatabase(name: String, ifExists: Bool = false, withForce: Bool = false) async throws -> Int {
        var parts: [String] = ["DROP DATABASE"]
        if ifExists { parts.append("IF EXISTS") }
        parts.append(quoteIdentifier(name))
        if withForce { parts.append("WITH (FORCE)") }
        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Change the default search path to the specified database/schema.
    @discardableResult
    func useDatabase(_ name: String) async throws -> Int {
        return try await executeDDL("SET search_path TO \(quoteIdentifier(name))")
    }

    /// Create a new schema.
    @discardableResult
    func createSchema(name: String, ifNotExists: Bool = false, authorization: String? = nil) async throws -> Int {
        var parts: [String] = ["CREATE SCHEMA"]
        if ifNotExists { parts.append("IF NOT EXISTS") }
        parts.append(quoteIdentifier(name))
        if let authorization { parts.append("AUTHORIZATION \(quoteIdentifier(authorization))") }
        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Drop an existing schema.
    @discardableResult
    func dropSchema(name: String, ifExists: Bool = false, cascade: Bool = false) async throws -> Int {
        var parts: [String] = ["DROP SCHEMA"]
        if ifExists { parts.append("IF EXISTS") }
        parts.append(quoteIdentifier(name))
        if cascade { parts.append("CASCADE") }
        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Change database owner.
    func alterDatabaseOwner(name: String, newOwner: String) async throws {
        let sql = "ALTER DATABASE \(quoteIdentifier(name)) OWNER TO \(quoteIdentifier(newOwner))"
        _ = try await executeDDL(sql)
    }

    /// Alter database connection limit.
    func alterDatabaseConnectionLimit(name: String, limit: Int) async throws {
        let sql = "ALTER DATABASE \(quoteIdentifier(name)) CONNECTION LIMIT \(limit)"
        _ = try await executeDDL(sql)
    }

    /// Alter database is_template flag.
    func alterDatabaseIsTemplate(name: String, isTemplate: Bool) async throws {
        let sql = "ALTER DATABASE \(quoteIdentifier(name)) IS_TEMPLATE \(isTemplate)"
        _ = try await executeDDL(sql)
    }

    /// Alter database allow_connections flag.
    func alterDatabaseAllowConnections(name: String, allow: Bool) async throws {
        let sql = "ALTER DATABASE \(quoteIdentifier(name)) ALLOW_CONNECTIONS \(allow)"
        _ = try await executeDDL(sql)
    }

    /// Alter database tablespace.
    func alterDatabaseTablespace(name: String, tablespace: String) async throws {
        let sql = "ALTER DATABASE \(quoteIdentifier(name)) SET TABLESPACE \(quoteIdentifier(tablespace))"
        _ = try await executeDDL(sql)
    }

    /// Set a database-level configuration parameter.
    func alterDatabaseSet(name: String, parameter: String, value: String) async throws {
        let sql = "ALTER DATABASE \(quoteIdentifier(name)) SET \(quoteIdentifier(parameter)) TO \(quoteLiteral(value))"
        _ = try await executeDDL(sql)
    }

    /// Reset a database-level configuration parameter.
    func alterDatabaseReset(name: String, parameter: String) async throws {
        let sql = "ALTER DATABASE \(quoteIdentifier(name)) RESET \(quoteIdentifier(parameter))"
        _ = try await executeDDL(sql)
    }

    /// Update the database comment/description.
    func commentOnDatabase(name: String, comment: String?) async throws {
        let sql: String
        if let comment {
            sql = "COMMENT ON DATABASE \(quoteIdentifier(name)) IS \(quoteLiteral(comment))"
        } else {
            sql = "COMMENT ON DATABASE \(quoteIdentifier(name)) IS NULL"
        }
        _ = try await executeDDL(sql)
    }
}
