import Foundation
import Logging

public struct PostgresAdmin: Sendable {
    private let client: PostgresDatabaseClient
    private let logger: Logger

    public init(client: PostgresDatabaseClient, logger: Logger) {
        self.client = client
        self.logger = logger
    }

    @discardableResult
    public func vacuum(schema: String? = nil, table: String? = nil, analyze: Bool = false, full: Bool = false, verbose: Bool = false) async throws -> Int {
        var parts: [String] = ["VACUUM"]
        if full { parts.append("FULL") }
        if analyze { parts.append("ANALYZE") }
        if verbose { parts.append("VERBOSE") }
        if let table {
            if let schema {
                parts.append("\"\(schema)\".\"\(table)\"")
            } else {
                parts.append("\"\(table)\"")
            }
        }
        let sql = parts.joined(separator: " ")
        return try await execUpdate(sql)
    }

    @discardableResult
    public func analyze(schema: String? = nil, table: String? = nil, verbose: Bool = false) async throws -> Int {
        var parts: [String] = ["ANALYZE"]
        if verbose { parts.append("VERBOSE") }
        if let table {
            if let schema {
                parts.append("\"\(schema)\".\"\(table)\"")
            } else {
                parts.append("\"\(table)\"")
            }
        }
        let sql = parts.joined(separator: " ")
        return try await execUpdate(sql)
    }

    @discardableResult
    public func reindex(database: String? = nil, schema: String? = nil, table: String? = nil, index: String? = nil, verbose: Bool = false) async throws -> Int {
        var parts: [String] = ["REINDEX"]
        if verbose { parts.append("(VERBOSE)") }
        if let index { parts.append("INDEX \(quoteIdent(index))") }
        else if let table {
            if let schema { parts.append("TABLE \(quoteIdent(schema)).\(quoteIdent(table))") }
            else { parts.append("TABLE \(quoteIdent(table))") }
        } else if let schema { parts.append("SCHEMA \(quoteIdent(schema))") }
        else if let database { parts.append("DATABASE \(quoteIdent(database))") }
        let sql = parts.joined(separator: " ")
        return try await execUpdate(sql)
    }

    @discardableResult
    public func createExtension(_ name: String, ifNotExists: Bool = true, schema: String? = nil) async throws -> Int {
        var parts: [String] = ["CREATE EXTENSION"]
        if ifNotExists { parts.append("IF NOT EXISTS") }
        parts.append(quoteIdent(name))
        if let schema { parts.append("WITH SCHEMA \(quoteIdent(schema))") }
        let sql = parts.joined(separator: " ")
        return try await execUpdate(sql)
    }

    public func set(_ parameter: String, value: String) async throws {
        let sql = "SET \(quoteIdent(parameter)) TO \(quoteLiteral(value))"
        _ = try await execUpdate(sql)
    }

    public func show(_ parameter: String) async throws -> String? {
        let sql = "SHOW \(quoteIdent(parameter))"
        let rows = try await client.simpleQuery(sql)
        for try await value in rows.decode(String?.self) { return value }
        return nil
    }

    // MARK: - Database Properties

    /// Comprehensive database properties compatible with all PostgreSQL versions.
    public func fetchDatabaseProperties(name: String, using client: PostgresDatabaseClient) async throws -> PostgresDatabaseProperties {
        let sql = """
            SELECT
                d.oid::text,
                d.datname,
                pg_catalog.pg_get_userbyid(d.datdba) AS owner,
                pg_catalog.pg_encoding_to_char(d.encoding) AS encoding,
                d.datcollate AS collation,
                d.datctype AS ctype,
                COALESCE(d.daticulocale, '') AS icu_locale,
                d.datconnlimit::text AS connection_limit,
                d.datistemplate::text AS is_template,
                d.datallowconn::text AS allow_connections,
                COALESCE(t.spcname, 'pg_default') AS tablespace,
                pg_catalog.pg_database_size(d.datname)::text AS size_bytes,
                (SELECT count(*)::text FROM pg_catalog.pg_stat_activity WHERE datname = d.datname) AS active_connections,
                COALESCE(pg_catalog.shobj_description(d.oid, 'pg_database'), '') AS description,
                COALESCE(d.datacl::text, '') AS acl
            FROM pg_catalog.pg_database d
            LEFT JOIN pg_catalog.pg_tablespace t ON t.oid = d.dattablespace
            WHERE d.datname = '\(name.replacingOccurrences(of: "'", with: "''"))'
            """

        let rows = try await client.simpleQuery(sql)
        var props: PostgresDatabaseProperties?
        for try await values in rows.decode((String, String, String, String, String, String, String, String, String, String, String, String, String, String, String).self) {
            props = PostgresDatabaseProperties(
                oid: values.0,
                name: values.1,
                owner: values.2,
                encoding: values.3,
                collation: values.4,
                ctype: values.5,
                icuLocale: values.6.isEmpty ? nil : values.6,
                connectionLimit: Int(values.7) ?? -1,
                isTemplate: values.8 == "t" || values.8 == "true",
                allowConnections: values.9 == "t" || values.9 == "true",
                tablespace: values.10,
                sizeBytes: Int64(values.11) ?? 0,
                activeConnections: Int(values.12) ?? 0,
                description: values.13.isEmpty ? nil : values.13,
                acl: values.14.isEmpty ? nil : values.14
            )
        }

        guard let result = props else {
            throw PostgresAdminError.notFound("Database '\(name)' not found")
        }
        return result
    }

    /// Fetch database-level configuration parameters from pg_db_role_setting.
    public func fetchDatabaseParameters(databaseOid: String, using client: PostgresDatabaseClient) async throws -> [PostgresDatabaseParameter] {
        let sql = """
            SELECT unnest(setconfig)::text AS setting
            FROM pg_catalog.pg_db_role_setting
            WHERE setdatabase = \(databaseOid)::oid AND setrole = 0
            """
        var params: [PostgresDatabaseParameter] = []
        let rows = try await client.simpleQuery(sql)
        for try await setting in rows.decode(String.self) {
            let parts = setting.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                params.append(PostgresDatabaseParameter(name: String(parts[0]), value: String(parts[1])))
            }
        }
        return params
    }

    /// Alter a database owner.
    public func alterDatabaseOwner(name: String, newOwner: String) async throws {
        let sql = "ALTER DATABASE \(quoteIdent(name)) OWNER TO \(quoteIdent(newOwner))"
        _ = try await execUpdate(sql)
    }

    /// Alter database connection limit.
    public func alterDatabaseConnectionLimit(name: String, limit: Int) async throws {
        let sql = "ALTER DATABASE \(quoteIdent(name)) CONNECTION LIMIT \(limit)"
        _ = try await execUpdate(sql)
    }

    /// Alter database is_template flag.
    public func alterDatabaseIsTemplate(name: String, isTemplate: Bool) async throws {
        let sql = "ALTER DATABASE \(quoteIdent(name)) IS_TEMPLATE \(isTemplate)"
        _ = try await execUpdate(sql)
    }

    /// Alter database allow_connections flag.
    public func alterDatabaseAllowConnections(name: String, allow: Bool) async throws {
        let sql = "ALTER DATABASE \(quoteIdent(name)) ALLOW_CONNECTIONS \(allow)"
        _ = try await execUpdate(sql)
    }

    /// Alter database tablespace.
    public func alterDatabaseTablespace(name: String, tablespace: String) async throws {
        let sql = "ALTER DATABASE \(quoteIdent(name)) SET TABLESPACE \(quoteIdent(tablespace))"
        _ = try await execUpdate(sql)
    }

    /// Set a database-level configuration parameter.
    public func alterDatabaseSet(name: String, parameter: String, value: String) async throws {
        let sql = "ALTER DATABASE \(quoteIdent(name)) SET \(quoteIdent(parameter)) TO \(quoteLiteral(value))"
        _ = try await execUpdate(sql)
    }

    /// Reset a database-level configuration parameter.
    public func alterDatabaseReset(name: String, parameter: String) async throws {
        let sql = "ALTER DATABASE \(quoteIdent(name)) RESET \(quoteIdent(parameter))"
        _ = try await execUpdate(sql)
    }

    /// Update the database comment/description.
    public func commentOnDatabase(name: String, comment: String?) async throws {
        let sql: String
        if let comment {
            sql = "COMMENT ON DATABASE \(quoteIdent(name)) IS \(quoteLiteral(comment))"
        } else {
            sql = "COMMENT ON DATABASE \(quoteIdent(name)) IS NULL"
        }
        _ = try await execUpdate(sql)
    }

    /// List available tablespaces.
    public func listTablespaces(using client: PostgresDatabaseClient) async throws -> [String] {
        var names: [String] = []
        let rows = try await client.simpleQuery("SELECT spcname FROM pg_catalog.pg_tablespace ORDER BY spcname")
        for try await name in rows.decode(String.self) { names.append(name) }
        return names
    }

    // MARK: - Helpers
    private func execUpdate(_ sql: String) async throws -> Int {
        try await client.withConnection { conn in
            var count = 0
            let rows = try await conn.simpleQuery(sql)
            for try await _ in rows { count += 1 }
            return count
        }
    }

    private func quoteIdent(_ s: String) -> String {
        let escaped = s.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private func quoteLiteral(_ s: String) -> String {
        let escaped = s.replacingOccurrences(of: "'", with: "''")
        return "'\(escaped)'"
    }
}

// MARK: - Database Properties Model

public struct PostgresDatabaseProperties: Sendable {
    public let oid: String
    public let name: String
    public let owner: String
    public let encoding: String
    public let collation: String
    public let ctype: String
    public let icuLocale: String?
    public let connectionLimit: Int
    public let isTemplate: Bool
    public let allowConnections: Bool
    public let tablespace: String
    public let sizeBytes: Int64
    public let activeConnections: Int
    public let description: String?
    public let acl: String?
}

public struct PostgresDatabaseParameter: Sendable {
    public let name: String
    public let value: String
}

public enum PostgresAdminError: Error, LocalizedError {
    case notFound(String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let msg): return msg
        }
    }
}

