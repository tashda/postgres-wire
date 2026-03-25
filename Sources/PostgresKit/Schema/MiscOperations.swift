import PostgresWire

/// DDL operations for aggregates, operators, languages, casts, and backup utilities.
public extension PostgresAdminClient {

    // MARK: - Aggregates

    /// Create an aggregate function.
    @discardableResult
    func createAggregate(
        name: String,
        inputType: String,
        sfunc: String,
        stype: String,
        initcond: String? = nil,
        schema: String? = nil
    ) async throws -> Int {
        let qualifiedName = schema.map { "\(client.quoteIdentifier($0)).\(client.quoteIdentifier(name))" } ?? client.quoteIdentifier(name)
        var clauses: [String] = [
            "sfunc = \(sfunc)",
            "stype = \(stype)"
        ]
        if let initcond {
            clauses.append("initcond = '\(initcond)'")
        }
        let sql = "CREATE AGGREGATE \(qualifiedName)(\(inputType)) (\(clauses.joined(separator: ", ")))"
        return try await client.executeDDL(sql)
    }

    /// Drop an aggregate function.
    @discardableResult
    func dropAggregate(
        name: String,
        inputType: String,
        ifExists: Bool = false,
        cascade: Bool = false,
        schema: String? = nil
    ) async throws -> Int {
        let qualifiedName = schema.map { "\(client.quoteIdentifier($0)).\(client.quoteIdentifier(name))" } ?? client.quoteIdentifier(name)
        var parts: [String] = ["DROP AGGREGATE"]
        if ifExists { parts.append("IF EXISTS") }
        parts.append("\(qualifiedName)(\(inputType))")
        if cascade { parts.append("CASCADE") }
        return try await client.executeDDL(parts.joined(separator: " "))
    }

    // MARK: - Operators

    /// Create an operator.
    @discardableResult
    func createOperator(
        name: String,
        leftType: String?,
        rightType: String?,
        procedure: String,
        commutator: String? = nil,
        negator: String? = nil,
        schema: String? = nil
    ) async throws -> Int {
        let qualifiedName = schema.map { "\(client.quoteIdentifier($0)).\(name)" } ?? name
        var clauses: [String] = ["function = \(procedure)"]
        if let leftType { clauses.append("leftarg = \(leftType)") }
        if let rightType { clauses.append("rightarg = \(rightType)") }
        if let commutator { clauses.append("commutator = \(commutator)") }
        if let negator { clauses.append("negator = \(negator)") }
        let sql = "CREATE OPERATOR \(qualifiedName) (\(clauses.joined(separator: ", ")))"
        return try await client.executeDDL(sql)
    }

    /// Drop an operator.
    @discardableResult
    func dropOperator(
        name: String,
        leftType: String?,
        rightType: String?,
        ifExists: Bool = false,
        cascade: Bool = false,
        schema: String? = nil
    ) async throws -> Int {
        let qualifiedName = schema.map { "\(client.quoteIdentifier($0)).\(name)" } ?? name
        let left = leftType ?? "NONE"
        let right = rightType ?? "NONE"
        var parts: [String] = ["DROP OPERATOR"]
        if ifExists { parts.append("IF EXISTS") }
        parts.append("\(qualifiedName)(\(left), \(right))")
        if cascade { parts.append("CASCADE") }
        return try await client.executeDDL(parts.joined(separator: " "))
    }

    // MARK: - Languages

    /// Create a procedural language.
    @discardableResult
    func createLanguage(
        name: String,
        trusted: Bool = false,
        handler: String? = nil,
        validator: String? = nil
    ) async throws -> Int {
        if handler == nil {
            // Simple form for built-in languages
            let sql = "CREATE LANGUAGE \(client.quoteIdentifier(name))"
            return try await client.executeDDL(sql)
        }
        var parts: [String] = ["CREATE"]
        if trusted { parts.append("TRUSTED") }
        parts.append("LANGUAGE \(client.quoteIdentifier(name))")
        if let handler { parts.append("HANDLER \(handler)") }
        if let validator { parts.append("VALIDATOR \(validator)") }
        return try await client.executeDDL(parts.joined(separator: " "))
    }

    /// Drop a procedural language.
    @discardableResult
    func dropLanguage(
        name: String,
        ifExists: Bool = false,
        cascade: Bool = false
    ) async throws -> Int {
        var parts: [String] = ["DROP LANGUAGE"]
        if ifExists { parts.append("IF EXISTS") }
        parts.append(client.quoteIdentifier(name))
        if cascade { parts.append("CASCADE") }
        return try await client.executeDDL(parts.joined(separator: " "))
    }

    // MARK: - Casts

    /// Create a type cast.
    @discardableResult
    func createCast(
        sourceType: String,
        targetType: String,
        function: String? = nil,
        asAssignment: Bool = false,
        asImplicit: Bool = false
    ) async throws -> Int {
        var parts: [String] = ["CREATE CAST (\(sourceType) AS \(targetType))"]
        if let function {
            parts.append("WITH FUNCTION \(function)")
        } else {
            parts.append("WITHOUT FUNCTION")
        }
        if asAssignment { parts.append("AS ASSIGNMENT") }
        if asImplicit { parts.append("AS IMPLICIT") }
        return try await client.executeDDL(parts.joined(separator: " "))
    }

    /// Drop a type cast.
    @discardableResult
    func dropCast(
        sourceType: String,
        targetType: String,
        ifExists: Bool = false
    ) async throws -> Int {
        var parts: [String] = ["DROP CAST"]
        if ifExists { parts.append("IF EXISTS") }
        parts.append("(\(sourceType) AS \(targetType))")
        return try await client.executeDDL(parts.joined(separator: " "))
    }

    // MARK: - Prepared Transactions

    /// Commit a prepared (two-phase) transaction.
    func commitPrepared(gid: String) async throws {
        let sql = "COMMIT PREPARED \(client.quoteLiteral(gid))"
        _ = try await client.executeDDL(sql)
    }

    /// Rollback a prepared (two-phase) transaction.
    func rollbackPrepared(gid: String) async throws {
        let sql = "ROLLBACK PREPARED \(client.quoteLiteral(gid))"
        _ = try await client.executeDDL(sql)
    }

    // MARK: - Backup Utilities

    /// Build a pg_dumpall command string. Echo executes the returned command via Process.
    func pgDumpAllCommand(
        globalsOnly: Bool = false,
        rolesOnly: Bool = false,
        tablespacesOnly: Bool = false,
        outputFile: String? = nil
    ) -> String {
        var parts: [String] = ["pg_dumpall"]
        if globalsOnly { parts.append("--globals-only") }
        if rolesOnly { parts.append("--roles-only") }
        if tablespacesOnly { parts.append("--tablespaces-only") }
        if let outputFile { parts.append("--file=\(outputFile)") }
        return parts.joined(separator: " ")
    }
}
