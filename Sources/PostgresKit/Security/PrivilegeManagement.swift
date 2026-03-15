import PostgresWire

/// High-level Privilege and Role Grant management.
public extension PostgresSecurityClient {
    /// Grant specified privileges on a table to a user or role.
    @discardableResult
    func grantPrivileges(
        privileges: [PostgresPrivilege],
        onTable: String,
        to: String,
        withGrantOption: Bool = false,
        cascade: Bool = false
    ) async throws -> Int {
        var parts: [String] = ["GRANT"]
        parts.append(privileges.map { $0.rawValue }.joined(separator: ", "))
        parts.append("ON TABLE \(client.quoteIdentifier(onTable))")
        parts.append("TO \(client.quoteIdentifier(to))")
        if withGrantOption { parts.append("WITH GRANT OPTION") }
        if cascade { parts.append("CASCADE") }
        return try await client.executeDDL(parts.joined(separator: " "))
    }

    /// Revoke specified privileges on a table from a user or role.
    @discardableResult
    func revokePrivileges(
        privileges: [PostgresPrivilege],
        onTable: String,
        from: String,
        grantOption: Bool = false,
        cascade: Bool = false
    ) async throws -> Int {
        var parts: [String] = ["REVOKE"]
        if grantOption { parts.append("GRANT OPTION FOR") }
        parts.append(privileges.map { $0.rawValue }.joined(separator: ", "))
        parts.append("ON TABLE \(client.quoteIdentifier(onTable))")
        parts.append("FROM \(client.quoteIdentifier(from))")
        if cascade { parts.append("CASCADE") }
        return try await client.executeDDL(parts.joined(separator: " "))
    }

    /// Grant membership in a role to a user or another role.
    @discardableResult
    func grantRole(
        role: String,
        to: String,
        admin: Bool = false,
        inherit: Bool? = nil,
        set: Bool? = nil
    ) async throws -> Int {
        var parts: [String] = ["GRANT \(client.quoteIdentifier(role))"]
        parts.append("TO \(client.quoteIdentifier(to))")
        // WITH ADMIN/INHERIT/SET syntax requires PG 16+; only include when non-default
        if admin { parts.append("WITH ADMIN OPTION") }
        return try await client.executeDDL(parts.joined(separator: " "))
    }

    /// Revoke membership in a role from a user or another role.
    @discardableResult
    func revokeRole(role: String, from: String, admin: Bool = false) async throws -> Int {
        var parts: [String] = ["REVOKE"]
        if admin { parts.append("ADMIN OPTION FOR") }
        parts.append("\(client.quoteIdentifier(role))")
        parts.append("FROM \(client.quoteIdentifier(from))")
        return try await client.executeDDL(parts.joined(separator: " "))
    }

    /// Grant privileges on a schema to a user or role.
    @discardableResult
    func grantSchemaPrivileges(
        privileges: [PostgresPrivilege],
        onSchema: String,
        to: String,
        withGrantOption: Bool = false
    ) async throws -> Int {
        var parts: [String] = ["GRANT"]
        parts.append(privileges.map { $0.rawValue }.joined(separator: ", "))
        parts.append("ON SCHEMA \(client.quoteIdentifier(onSchema))")
        parts.append("TO \(client.quoteIdentifier(to))")
        if withGrantOption { parts.append("WITH GRANT OPTION") }
        return try await client.executeDDL(parts.joined(separator: " "))
    }

    /// Revoke privileges on a schema from a user or role.
    @discardableResult
    func revokeSchemaPrivileges(
        privileges: [PostgresPrivilege],
        onSchema: String,
        from: String,
        cascade: Bool = false
    ) async throws -> Int {
        var parts: [String] = ["REVOKE"]
        parts.append(privileges.map { $0.rawValue }.joined(separator: ", "))
        parts.append("ON SCHEMA \(client.quoteIdentifier(onSchema))")
        parts.append("FROM \(client.quoteIdentifier(from))")
        if cascade { parts.append("CASCADE") }
        return try await client.executeDDL(parts.joined(separator: " "))
    }

    /// Alter default privileges for objects created in a schema.
    @discardableResult
    func alterDefaultPrivileges(
        schema: String,
        grant privileges: [PostgresPrivilege],
        onObjectType: PostgresObjectType = .tables,
        to: String
    ) async throws -> Int {
        let sql = "ALTER DEFAULT PRIVILEGES IN SCHEMA \(client.quoteIdentifier(schema)) GRANT \(privileges.map { $0.rawValue }.joined(separator: ", ")) ON \(onObjectType.rawValue) TO \(client.quoteIdentifier(to))"
        return try await client.executeDDL(sql)
    }

    /// Revoke altered default privileges for objects created in a schema.
    @discardableResult
    func revokeDefaultPrivileges(
        schema: String,
        revoke privileges: [PostgresPrivilege],
        onObjectType: PostgresObjectType = .tables,
        from: String
    ) async throws -> Int {
        let sql = "ALTER DEFAULT PRIVILEGES IN SCHEMA \(client.quoteIdentifier(schema)) REVOKE \(privileges.map { $0.rawValue }.joined(separator: ", ")) ON \(onObjectType.rawValue) FROM \(client.quoteIdentifier(from))"
        return try await client.executeDDL(sql)
    }

    /// Grant privileges on all tables in a schema.
    @discardableResult
    func grantAllTablesPrivileges(
        privileges: [PostgresPrivilege],
        inSchema: String,
        to: String,
        withGrantOption: Bool = false
    ) async throws -> Int {
        var parts: [String] = ["GRANT"]
        parts.append(privileges.map { $0.rawValue }.joined(separator: ", "))
        parts.append("ON ALL TABLES IN SCHEMA \(client.quoteIdentifier(inSchema))")
        parts.append("TO \(client.quoteIdentifier(to))")
        if withGrantOption { parts.append("WITH GRANT OPTION") }
        return try await client.executeDDL(parts.joined(separator: " "))
    }

    /// Revoke privileges on all tables in a schema.
    @discardableResult
    func revokeAllTablesPrivileges(
        privileges: [PostgresPrivilege],
        inSchema: String,
        from: String,
        cascade: Bool = false
    ) async throws -> Int {
        var parts: [String] = ["REVOKE"]
        parts.append(privileges.map { $0.rawValue }.joined(separator: ", "))
        parts.append("ON ALL TABLES IN SCHEMA \(client.quoteIdentifier(inSchema))")
        parts.append("FROM \(client.quoteIdentifier(from))")
        if cascade { parts.append("CASCADE") }
        return try await client.executeDDL(parts.joined(separator: " "))
    }
}
