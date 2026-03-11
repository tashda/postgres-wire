import PostgresWire

/// High-level User and Role management.
public extension PostgresDatabaseClient {
    /// Create a new database user or role.
    @discardableResult
    func createUser(
        name: String,
        password: String? = nil,
        superuser: Bool = false,
        createDatabase: Bool = true,
        createRole: Bool = true,
        login: Bool = true,
        encrypted: Bool = true,
        inherit: Bool = true,
        replication: Bool = false,
        bypassRLS: Bool = false,
        validUntil: String? = nil,
        inRole: [String] = [],
        role: [String] = [],
        admin: [String] = []
    ) async throws -> Int {
        var parts: [String] = ["CREATE USER"]
        parts.append(quoteIdentifier(name))

        if let password {
            parts.append(encrypted ? "WITH ENCRYPTED PASSWORD '\(password)'" : "WITH PASSWORD '\(password)'")
        }

        if superuser { parts.append("SUPERUSER") } else { parts.append("NOSUPERUSER") }
        if createDatabase { parts.append("CREATEDB") } else { parts.append("NOCREATEDB") }
        if createRole { parts.append("CREATEROLE") } else { parts.append("NOCREATEROLE") }
        if login { parts.append("LOGIN") } else { parts.append("NOLOGIN") }
        if inherit { parts.append("INHERIT") } else { parts.append("NOINHERIT") }
        if replication { parts.append("REPLICATION") } else { parts.append("NOREPLICATION") }
        if bypassRLS { parts.append("BYPASSRLS") } else { parts.append("NOBYPASSRLS") }

        if let validUntil { parts.append("VALID UNTIL '\(validUntil)'") }

        if !inRole.isEmpty {
            parts.append("IN ROLE \(inRole.map(quoteIdentifier).joined(separator: ", "))")
        }

        if !role.isEmpty {
            parts.append("ROLE \(role.map(quoteIdentifier).joined(separator: ", "))")
        }

        if !admin.isEmpty {
            parts.append("ADMIN \(admin.map(quoteIdentifier).joined(separator: ", "))")
        }

        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Drop an existing user or role.
    @discardableResult
    func dropUser(name: String, ifExists: Bool = false) async throws -> Int {
        var parts: [String] = ["DROP USER"]
        if ifExists { parts.append("IF EXISTS") }
        parts.append(quoteIdentifier(name))
        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Modify an existing user or role's attributes.
    @discardableResult
    func alterUser(
        name: String,
        password: String? = nil,
        encrypted: Bool = true,
        superuser: Bool? = nil,
        createDatabase: Bool? = nil,
        createRole: Bool? = nil,
        login: Bool? = nil,
        inherit: Bool? = nil,
        replication: Bool? = nil,
        bypassRLS: Bool? = nil,
        validUntil: String? = nil,
        rename: String? = nil
    ) async throws -> Int {
        var parts: [String] = ["ALTER USER"]

        if let rename {
            parts.append("\(quoteIdentifier(name)) RENAME TO \(quoteIdentifier(rename))")
        } else {
            parts.append(quoteIdentifier(name))
            if let password {
                parts.append(encrypted ? "WITH ENCRYPTED PASSWORD '\(password)'" : "WITH PASSWORD '\(password)'")
            }
            if let superuser { parts.append(superuser ? "SUPERUSER" : "NOSUPERUSER") }
            if let createDatabase { parts.append(createDatabase ? "CREATEDB" : "NOCREATEDB") }
            if let createRole { parts.append(createRole ? "CREATEROLE" : "NOCREATEROLE") }
            if let login { parts.append(login ? "LOGIN" : "NOLOGIN") }
            if let inherit { parts.append(inherit ? "INHERIT" : "NOINHERIT") }
            if let replication { parts.append(replication ? "REPLICATION" : "NOREPLICATION") }
            if let bypassRLS { parts.append(bypassRLS ? "BYPASSRLS" : "NOBYPASSRLS") }
            if let validUntil { parts.append("VALID UNTIL '\(validUntil)'") }
        }

        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Reassign all objects owned by one role to another role.
    func reassignOwned(from oldRole: String, to newRole: String) async throws {
        let sql = "REASSIGN OWNED BY \(quoteIdentifier(oldRole)) TO \(quoteIdentifier(newRole))"
        _ = try await executeDDL(sql)
    }

    /// Drop all objects owned by a role.
    func dropOwned(by role: String) async throws {
        let sql = "DROP OWNED BY \(quoteIdentifier(role))"
        _ = try await executeDDL(sql)
    }

    /// Set a role-level configuration parameter.
    func alterRoleSet(role: String, parameter: String, value: String) async throws {
        let sql = "ALTER ROLE \(quoteIdentifier(role)) SET \(quoteIdentifier(parameter)) TO \(quoteLiteral(value))"
        _ = try await executeDDL(sql)
    }

    /// Reset a role-level configuration parameter.
    func alterRoleReset(role: String, parameter: String) async throws {
        let sql = "ALTER ROLE \(quoteIdentifier(role)) RESET \(quoteIdentifier(parameter))"
        _ = try await executeDDL(sql)
    }

    /// Set or clear the comment on a role.
    func setRoleComment(role: String, comment: String?) async throws {
        let sql: String
        if let comment, !comment.isEmpty {
            sql = "COMMENT ON ROLE \(quoteIdentifier(role)) IS \(quoteLiteral(comment))"
        } else {
            sql = "COMMENT ON ROLE \(quoteIdentifier(role)) IS NULL"
        }
        _ = try await executeDDL(sql)
    }
}
