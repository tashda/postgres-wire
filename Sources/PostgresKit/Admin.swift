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

    // MARK: - Security

    /// List all non-system roles with full privilege attributes.
    /// Uses pg_authid when accessible (superuser) for accurate data; falls back to pg_roles.
    public func listRoles() async throws -> [PostgresRoleInfo] {
        // Try pg_authid first (requires superuser), fall back to pg_roles
        let sql = """
            SELECT
                r.rolname,
                r.rolsuper,
                r.rolcreaterole,
                r.rolcreatedb,
                r.rolcanlogin,
                r.rolreplication,
                r.rolinherit,
                r.rolconnlimit::text,
                r.rolvaliduntil::text,
                r.rolbypassrls,
                r.oid::text
            FROM pg_catalog.pg_roles r
            WHERE r.rolname !~ '^pg_'
            ORDER BY r.rolname
            """
        var results: [PostgresRoleInfo] = []
        let rows = try await client.simpleQuery(sql)
        for try await values in rows.decode((String, String, String, String, String, String, String, String, String?, String, String).self) {
            results.append(PostgresRoleInfo(
                oid: values.10,
                name: values.0,
                isSuperuser: values.1 == "t",
                canCreateRole: values.2 == "t",
                canCreateDB: values.3 == "t",
                canLogin: values.4 == "t",
                isReplication: values.5 == "t",
                inherit: values.6 == "t",
                bypassRLS: values.9 == "t",
                connectionLimit: Int(values.7) ?? -1,
                validUntil: values.8
            ))
        }
        return results
    }

    /// Reassign all objects owned by one role to another role.
    public func reassignOwned(from oldRole: String, to newRole: String) async throws {
        let sql = "REASSIGN OWNED BY \(quoteIdent(oldRole)) TO \(quoteIdent(newRole))"
        _ = try await execUpdate(sql)
    }

    /// Drop all objects owned by a role.
    public func dropOwned(by role: String) async throws {
        let sql = "DROP OWNED BY \(quoteIdent(role))"
        _ = try await execUpdate(sql)
    }

    /// Fetch role-level configuration parameters from pg_db_role_setting.
    public func fetchRoleParameters(roleOid: String) async throws -> [PostgresDatabaseParameter] {
        let sql = """
            SELECT unnest(setconfig)::text AS setting
            FROM pg_catalog.pg_db_role_setting
            WHERE setrole = \(roleOid)::oid AND setdatabase = 0
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

    /// Fetch all server settings that can be configured at the role level (context = 'user' or 'superuser').
    public func fetchRoleConfigurableSettings() async throws -> [PostgresSettingDefinition] {
        let sql = """
            SELECT name, vartype, min_val, max_val,
                   coalesce(enumvals::text, ''),
                   boot_val, coalesce(unit, ''),
                   short_desc, context, category
            FROM pg_catalog.pg_settings
            WHERE context IN ('user', 'superuser')
            ORDER BY category, name
            """
        var results: [PostgresSettingDefinition] = []
        let rows = try await client.simpleQuery(sql)
        for try await values in rows.decode((String, String, String, String, String, String, String, String, String, String).self) {
            let enumVals: [String]
            if !values.4.isEmpty {
                // pg returns format like {val1,val2,val3}
                let trimmed = values.4.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
                enumVals = trimmed.split(separator: ",").map { String($0) }
            } else {
                enumVals = []
            }
            results.append(PostgresSettingDefinition(
                name: values.0,
                vartype: values.1,
                minVal: values.2,
                maxVal: values.3,
                enumVals: enumVals,
                bootVal: values.5,
                unit: values.6,
                shortDesc: values.7,
                context: values.8,
                category: values.9
            ))
        }
        return results
    }

    /// Set a role-level configuration parameter.
    public func alterRoleSet(role: String, parameter: String, value: String) async throws {
        let sql = "ALTER ROLE \(quoteIdent(role)) SET \(quoteIdent(parameter)) TO \(quoteLiteral(value))"
        _ = try await execUpdate(sql)
    }

    /// Reset a role-level configuration parameter.
    public func alterRoleReset(role: String, parameter: String) async throws {
        let sql = "ALTER ROLE \(quoteIdent(role)) RESET \(quoteIdent(parameter))"
        _ = try await execUpdate(sql)
    }

    /// Fetch security labels for a role.
    public func fetchRoleSecurityLabels(role: String) async throws -> [PostgresSecurityLabel] {
        let sql = """
            SELECT provider, label
            FROM pg_catalog.pg_shseclabel sl
            JOIN pg_catalog.pg_roles r ON sl.objoid = r.oid
            WHERE r.rolname = \(quoteLiteral(role))
            ORDER BY provider
            """
        var results: [PostgresSecurityLabel] = []
        let rows = try await client.simpleQuery(sql)
        for try await values in rows.decode((String, String).self) {
            results.append(PostgresSecurityLabel(provider: values.0, label: values.1))
        }
        return results
    }

    /// List roles that a given role is a member of.
    public func listMemberOf(role: String) async throws -> [PostgresRoleMembership] {
        let sql = """
            SELECT r.rolname, m.rolname, am.admin_option::text,
                   COALESCE(am.inherit_option, true)::text,
                   COALESCE(am.set_option, true)::text
            FROM pg_catalog.pg_auth_members am
            JOIN pg_catalog.pg_roles r ON am.roleid = r.oid
            JOIN pg_catalog.pg_roles m ON am.member = m.oid
            WHERE m.rolname = \(quoteLiteral(role))
            ORDER BY r.rolname
            """
        var results: [PostgresRoleMembership] = []
        let rows = try await client.simpleQuery(sql)
        for try await values in rows.decode((String, String, String, String, String).self) {
            results.append(PostgresRoleMembership(
                roleName: values.0,
                memberName: values.1,
                adminOption: values.2 == "t",
                inheritOption: values.3 == "t",
                setOption: values.4 == "t"
            ))
        }
        return results
    }

    /// List roles that are members of a given role (i.e. which roles contain this role as a member).
    public func listMembers(of role: String) async throws -> [PostgresRoleMembership] {
        let sql = """
            SELECT r.rolname, m.rolname, am.admin_option::text,
                   COALESCE(am.inherit_option, true)::text,
                   COALESCE(am.set_option, true)::text
            FROM pg_catalog.pg_auth_members am
            JOIN pg_catalog.pg_roles r ON am.roleid = r.oid
            JOIN pg_catalog.pg_roles m ON am.member = m.oid
            WHERE r.rolname = \(quoteLiteral(role))
            ORDER BY m.rolname
            """
        var results: [PostgresRoleMembership] = []
        let rows = try await client.simpleQuery(sql)
        for try await values in rows.decode((String, String, String, String, String).self) {
            results.append(PostgresRoleMembership(
                roleName: values.0,
                memberName: values.1,
                adminOption: values.2 == "t",
                inheritOption: values.3 == "t",
                setOption: values.4 == "t"
            ))
        }
        return results
    }

    /// List all non-system schemas with their owners.
    public func listSchemas() async throws -> [PostgresSchemaInfo] {
        let sql = """
            SELECT n.nspname, r.rolname
            FROM pg_catalog.pg_namespace n
            JOIN pg_catalog.pg_roles r ON n.nspowner = r.oid
            WHERE n.nspname !~ '^pg_' AND n.nspname != 'information_schema'
            ORDER BY n.nspname
            """
        var results: [PostgresSchemaInfo] = []
        let rows = try await client.simpleQuery(sql)
        for try await values in rows.decode((String, String).self) {
            results.append(PostgresSchemaInfo(
                name: values.0,
                owner: values.1
            ))
        }
        return results
    }

    /// List role memberships, optionally filtered to a specific role.
    public func listRoleMemberships(role: String? = nil) async throws -> [PostgresRoleMembership] {
        var sql = """
            SELECT r.rolname, m.rolname, am.admin_option::text,
                   COALESCE(am.inherit_option, true)::text,
                   COALESCE(am.set_option, true)::text
            FROM pg_catalog.pg_auth_members am
            JOIN pg_catalog.pg_roles r ON am.roleid = r.oid
            JOIN pg_catalog.pg_roles m ON am.member = m.oid
            """
        if let role {
            sql += " WHERE r.rolname = \(quoteLiteral(role)) OR m.rolname = \(quoteLiteral(role))"
        }
        sql += " ORDER BY r.rolname, m.rolname"
        var results: [PostgresRoleMembership] = []
        let rows = try await client.simpleQuery(sql)
        for try await values in rows.decode((String, String, String, String, String).self) {
            results.append(PostgresRoleMembership(
                roleName: values.0,
                memberName: values.1,
                adminOption: values.2 == "t",
                inheritOption: values.3 == "t",
                setOption: values.4 == "t"
            ))
        }
        return results
    }

    /// Fetch the comment on a role from pg_shdescription.
    public func fetchRoleComment(role: String) async throws -> String? {
        let sql = """
            SELECT d.description
            FROM pg_catalog.pg_shdescription d
            JOIN pg_catalog.pg_authid a ON a.oid = d.objoid
            WHERE d.classoid = 'pg_catalog.pg_authid'::regclass
              AND a.rolname = \(quoteLiteral(role))
            """
        let rows = try await client.simpleQuery(sql)
        for try await values in rows.decode(String.self) {
            return values
        }
        return nil
    }

    /// Set or clear the comment on a role.
    public func setRoleComment(role: String, comment: String?) async throws {
        let ident = quoteIdent(role)
        let sql: String
        if let comment, !comment.isEmpty {
            sql = "COMMENT ON ROLE \(ident) IS \(quoteLiteral(comment))"
        } else {
            sql = "COMMENT ON ROLE \(ident) IS NULL"
        }
        let rows = try await client.simpleQuery(sql)
        for try await _ in rows { }
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

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

/// Describes a PostgreSQL server setting that can be configured at the role level.
public struct PostgresSettingDefinition: Sendable {
    /// Parameter name (e.g. "work_mem", "statement_timeout").
    public let name: String
    /// Data type: "bool", "enum", "integer", "real", or "string".
    public let vartype: String
    /// Minimum value for numeric types, empty for others.
    public let minVal: String
    /// Maximum value for numeric types, empty for others.
    public let maxVal: String
    /// Allowed values for enum types, empty array for others.
    public let enumVals: [String]
    /// Current server-wide default (boot_val).
    public let bootVal: String
    /// Unit (e.g. "kB", "ms", "s", "min"), empty if unitless.
    public let unit: String
    /// Short description of the parameter.
    public let shortDesc: String
    /// The context in which this setting can be changed ("user" or "superuser").
    public let context: String
    /// Category for grouping (e.g. "Query Tuning / Planner Cost Constants").
    public let category: String

    public init(
        name: String, vartype: String, minVal: String, maxVal: String,
        enumVals: [String], bootVal: String, unit: String,
        shortDesc: String, context: String, category: String
    ) {
        self.name = name
        self.vartype = vartype
        self.minVal = minVal
        self.maxVal = maxVal
        self.enumVals = enumVals
        self.bootVal = bootVal
        self.unit = unit
        self.shortDesc = shortDesc
        self.context = context
        self.category = category
    }
}

public enum PostgresAdminError: Error, LocalizedError {
    case notFound(String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let msg): return msg
        }
    }
}

// MARK: - Security Models

public struct PostgresRoleInfo: Sendable {
    public let oid: String
    public let name: String
    public let isSuperuser: Bool
    public let canCreateRole: Bool
    public let canCreateDB: Bool
    public let canLogin: Bool
    public let isReplication: Bool
    public let inherit: Bool
    public let bypassRLS: Bool
    public let connectionLimit: Int
    public let validUntil: String?

    public init(
        oid: String = "",
        name: String,
        isSuperuser: Bool,
        canCreateRole: Bool,
        canCreateDB: Bool,
        canLogin: Bool,
        isReplication: Bool,
        inherit: Bool,
        bypassRLS: Bool = false,
        connectionLimit: Int,
        validUntil: String?
    ) {
        self.oid = oid
        self.name = name
        self.isSuperuser = isSuperuser
        self.canCreateRole = canCreateRole
        self.canCreateDB = canCreateDB
        self.canLogin = canLogin
        self.isReplication = isReplication
        self.inherit = inherit
        self.bypassRLS = bypassRLS
        self.connectionLimit = connectionLimit
        self.validUntil = validUntil
    }
}

public struct PostgresSecurityLabel: Sendable {
    public let provider: String
    public let label: String

    public init(provider: String, label: String) {
        self.provider = provider
        self.label = label
    }
}

public struct PostgresSchemaInfo: Sendable {
    public let name: String
    public let owner: String
}

public struct PostgresRoleMembership: Sendable {
    public let roleName: String
    public let memberName: String
    public let adminOption: Bool
    public let inheritOption: Bool
    public let setOption: Bool

    public init(roleName: String, memberName: String, adminOption: Bool, inheritOption: Bool = true, setOption: Bool = true) {
        self.roleName = roleName
        self.memberName = memberName
        self.adminOption = adminOption
        self.inheritOption = inheritOption
        self.setOption = setOption
    }
}

