import PostgresWire

/// High-level Privilege and Role Grant management.
public extension PostgresDatabaseClient {
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
        parts.append("ON TABLE \(quoteIdentifier(onTable))")
        parts.append("TO \(quoteIdentifier(to))")
        if withGrantOption { parts.append("WITH GRANT OPTION") }
        if cascade { parts.append("CASCADE") }
        return try await executeDDL(parts.joined(separator: " "))
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
        parts.append("ON TABLE \(quoteIdentifier(onTable))")
        parts.append("FROM \(quoteIdentifier(from))")
        if cascade { parts.append("CASCADE") }
        return try await executeDDL(parts.joined(separator: " "))
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
        var parts: [String] = ["GRANT \(quoteIdentifier(role))"]
        parts.append("TO \(quoteIdentifier(to))")
        var options: [String] = []
        options.append("ADMIN \(admin ? "TRUE" : "FALSE")")
        if let inherit { options.append("INHERIT \(inherit ? "TRUE" : "FALSE")") }
        if let set { options.append("SET \(set ? "TRUE" : "FALSE")") }
        if !options.isEmpty { parts.append("WITH \(options.joined(separator: ", "))") }
        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Revoke membership in a role from a user or another role.
    @discardableResult
    func revokeRole(role: String, from: String, admin: Bool = false) async throws -> Int {
        var parts: [String] = ["REVOKE"]
        if admin { parts.append("ADMIN OPTION FOR") }
        parts.append("\(quoteIdentifier(role))")
        parts.append("FROM \(quoteIdentifier(from))")
        return try await executeDDL(parts.joined(separator: " "))
    }
}
