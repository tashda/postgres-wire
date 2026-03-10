import Foundation
import Logging
import Metrics
import PostgresWire
import PostgresNIO

public final class PostgresDatabaseClient: @unchecked Sendable {
    private let wire: PostgresWireClient
    private let logger: Logger
    private let registry = PreparedRegistry()

    private init(wire: PostgresWireClient, logger: Logger) {
        self.wire = wire
        var logger = logger
        logger[metadataKey: "component"] = "PostgresDatabaseClient"
        self.logger = logger
    }

    deinit { wire.close() }

    public static func connect(
        configuration: PostgresConfiguration,
        logger: Logger = .init(label: "postgres-kit")
    ) async throws -> PostgresDatabaseClient {
        let result: Result<PostgresDatabaseClient, PostgresError> = await PostgresDatabaseClient.executeWithEnhancedError {
            let wire = try await PostgresWireClient.connect(configuration: configuration.makeWireConfiguration(), logger: logger)
            return PostgresDatabaseClient(wire: wire, logger: logger)
        }
        switch result {
        case .success(let client):
            return client
        case .failure(let error):
            throw error
        }
    }

    public func close() { wire.close() }

    // Simple convenience query on pooled client.
    public func simpleQuery(_ sql: String) async throws -> WireRowSequence {
        try await withConnection { connection in
            try await connection.simpleQuery(sql)
        }
    }

    public func simpleQuery(_ sql: String, options: PostgresExecutionOptions?) async throws -> WireRowSequence {
        try await withConnection { connection in
            try await connection.query(sql, binds: [])
        }
    }

      // MARK: - Streaming API

    /// Execute a query with streaming and formatting
    public func streamQuery(
        _ sql: String,
        configuration: PostgresStreamConfiguration = .default,
        onUpdate: @escaping @Sendable (PostgresStreamUpdate) async -> Void,
        logger: Logger? = nil
    ) async throws -> PostgresStreamResult {
        let effectiveLogger = logger ?? self.logger
        let result: Result<PostgresStreamResult, PostgresError> = await PostgresDatabaseClient.executeWithEnhancedError {
            try await wire.streamQuery(sql, configuration: configuration, onUpdate: onUpdate, logger: effectiveLogger)
        }
        switch result {
        case .success(let streamResult):
            return streamResult
        case .failure(let error):
            throw error
        }
    }

    /// Execute a streaming query with automatic cursor management for large result sets
    public func streamQueryWithCursor(
        _ sql: String,
        configuration: PostgresStreamConfiguration = .default,
        onUpdate: @escaping @Sendable (PostgresStreamUpdate) async -> Void,
        logger: Logger? = nil
    ) async throws -> PostgresStreamResult {
        let effectiveLogger = logger ?? self.logger
        let result: Result<PostgresStreamResult, PostgresError> = await PostgresDatabaseClient.executeWithEnhancedError {
            try await wire.streamQueryWithCursor(sql, configuration: configuration, onUpdate: onUpdate, logger: effectiveLogger)
        }
        switch result {
        case .success(let streamResult):
            return streamResult
        case .failure(let error):
            throw error
        }
    }

    // Borrow a single connection for multi-step operations.
    public func withConnection<T>(
        _ body: @Sendable (PostgresDatabaseConnection) async throws -> T
    ) async throws -> T {
        do {
            return try await wire.withConnection { connection in
                let cache = await registry.statementCache(for: connection.id)
                let serverCache = await registry.serverPreparedCache(for: connection.id)
                return try await body(PostgresDatabaseConnection(wireConnection: connection, logger: logger, cache: cache, serverCache: serverCache))
            }
        } catch {
            throw PostgresKit.PostgresError.from(error)
        }
    }

    // MARK: - DDL Operations

    /// Execute a DDL statement and return the number of affected rows
    @discardableResult
    public func executeDDL(_ sql: String) async throws -> Int {
        let rows = try await simpleQuery(sql)
        var count = 0
        for try await _ in rows.decode((String?).self) {
            count += 1
        }
        return count
    }

    // MARK: - Table Operations

    /// Create a new table with the specified columns and constraints
    public func createTable(
        name: String,
        columns: [PostgresColumnDefinition],
        temporary: Bool = false,
        ifNotExists: Bool = false
    ) async throws -> Int {
        var parts: [String] = []
        parts.append("CREATE")
        if temporary { parts.append("TEMPORARY") }
        parts.append("TABLE")
        if ifNotExists { parts.append("IF NOT EXISTS") }
        parts.append(quoteIdentifier(name))

        let columnDefinitions = columns.map { column in
            var columnDef = "\(quoteIdentifier(column.name)) \(column.dataType)"

            if let defaultValue = column.defaultValue {
                columnDef += " DEFAULT \(defaultValue)"
            }

            if column.nullable == false {
                columnDef += " NOT NULL"
            }

            if column.primaryKey {
                columnDef += " PRIMARY KEY"
            }

            if column.unique {
                columnDef += " UNIQUE"
            }

            return columnDef
        }.joined(separator: ", ")

        parts.append("(\(columnDefinitions))")

        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Drop a table
    @discardableResult
    public func dropTable(name: String, ifExists: Bool = false, cascade: Bool = false) async throws -> Int {
        var parts: [String] = ["DROP TABLE"]
        if ifExists { parts.append("IF EXISTS") }
        parts.append(quoteIdentifier(name))
        if cascade { parts.append("CASCADE") }
        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Alter a table to add a column
    @discardableResult
    public func addColumn(
        table: String,
        column: PostgresColumnDefinition
    ) async throws -> Int {
        var columnDef = "\(quoteIdentifier(column.name)) \(column.dataType)"

        if let defaultValue = column.defaultValue {
            columnDef += " DEFAULT \(defaultValue)"
        }

        if column.nullable == false {
            columnDef += " NOT NULL"
        }

        let sql = "ALTER TABLE \(quoteIdentifier(table)) ADD COLUMN \(columnDef)"
        return try await executeDDL(sql)
    }

    /// Alter a table to drop a column
    @discardableResult
    public func dropColumn(table: String, column: String) async throws -> Int {
        let sql = "ALTER TABLE \(quoteIdentifier(table)) DROP COLUMN \(quoteIdentifier(column))"
        return try await executeDDL(sql)
    }

    // MARK: - Index Operations

    /// Create an index on a table
    @discardableResult
    public func createIndex(
        name: String,
        table: String,
        columns: [String],
        unique: Bool = false,
        ifNotExists: Bool = false
    ) async throws -> Int {
        var parts: [String] = ["CREATE"]
        if unique { parts.append("UNIQUE") }
        parts.append("INDEX")
        if ifNotExists { parts.append("IF NOT EXISTS") }
        parts.append(quoteIdentifier(name))
        parts.append("ON \(quoteIdentifier(table))")

        let columnList = columns.map { quoteIdentifier($0) }.joined(separator: ", ")
        parts.append("(\(columnList))")

        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Drop an index
    @discardableResult
    public func dropIndex(name: String, ifExists: Bool = false, cascade: Bool = false) async throws -> Int {
        var parts: [String] = ["DROP INDEX"]
        if ifExists { parts.append("IF EXISTS") }
        parts.append(quoteIdentifier(name))
        if cascade { parts.append("CASCADE") }
        return try await executeDDL(parts.joined(separator: " "))
    }

    // MARK: - Sequence Operations

    /// Create a new sequence
    @discardableResult
    public func createSequence(
        name: String,
        temporary: Bool = false,
        ifNotExists: Bool = false,
        startWith: Int? = nil,
        incrementBy: Int? = nil,
        minValue: Int? = nil,
        maxValue: Int? = nil,
        cache: Int? = nil,
        cycle: Bool = false
    ) async throws -> Int {
        var parts: [String] = ["CREATE"]
        if temporary { parts.append("TEMPORARY") }
        parts.append("SEQUENCE")
        if ifNotExists { parts.append("IF NOT EXISTS") }
        parts.append(quoteIdentifier(name))

        if let startWith = startWith {
            parts.append("START WITH \(startWith)")
        }

        if let incrementBy = incrementBy {
            parts.append("INCREMENT BY \(incrementBy)")
        }

        if let minValue = minValue {
            parts.append("MINVALUE \(minValue)")
        }

        if let maxValue = maxValue {
            parts.append("MAXVALUE \(maxValue)")
        }

        if let cache = cache {
            parts.append("CACHE \(cache)")
        }

        if cycle {
            parts.append("CYCLE")
        }

        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Drop a sequence
    @discardableResult
    public func dropSequence(name: String, ifExists: Bool = false, cascade: Bool = false) async throws -> Int {
        var parts: [String] = ["DROP SEQUENCE"]
        if ifExists { parts.append("IF EXISTS") }
        parts.append(quoteIdentifier(name))
        if cascade { parts.append("CASCADE") }
        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Get the next value from a sequence
    public func nextval(_ sequenceName: String) async throws -> Int {
        let sql = "SELECT nextval(\(quoteLiteral(sequenceName))::text)::bigint as value"
        let rows = try await simpleQuery(sql)

        for try await value in rows.decode(Int.self) {
            return value
        }

        throw PostgresKit.PostgresError.protocolError("Sequence \(sequenceName) returned no value")
    }

    /// Get the current value from a sequence
    public func currval(_ sequenceName: String) async throws -> Int {
        let sql = "SELECT currval(\(quoteLiteral(sequenceName))::text)::bigint as value"
        let rows = try await simpleQuery(sql)

        for try await value in rows.decode(Int.self) {
            return value
        }

        throw PostgresKit.PostgresError.protocolError("Sequence \(sequenceName) returned no value")
    }

    /// Set a sequence value
    @discardableResult
    public func setval(_ sequenceName: String, value: Int, isCalled: Bool = true) async throws -> Int {
        let sql = "SELECT setval(\(quoteLiteral(sequenceName))::text, \(value), \(isCalled))"
        return try await executeDDL(sql)
    }

    // MARK: - View Operations

    /// Create a view
    @discardableResult
    public func createView(
        name: String,
        query: String,
        temporary: Bool = false,
        orReplace: Bool = false
    ) async throws -> Int {
        var parts: [String] = ["CREATE"]
        if orReplace { parts.append("OR REPLACE") }
        if temporary { parts.append("TEMPORARY") }
        parts.append("VIEW")
        parts.append(quoteIdentifier(name))
        parts.append("AS \(query)")

        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Drop a view
    @discardableResult
    public func dropView(name: String, ifExists: Bool = false, cascade: Bool = false) async throws -> Int {
        var parts: [String] = ["DROP VIEW"]
        if ifExists { parts.append("IF EXISTS") }
        parts.append(quoteIdentifier(name))
        if cascade { parts.append("CASCADE") }
        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Create a materialized view
    @discardableResult
    public func createMaterializedView(
        name: String,
        query: String,
        ifNotExists: Bool = false
    ) async throws -> Int {
        var parts: [String] = ["CREATE MATERIALIZED VIEW"]
        if ifNotExists { parts.append("IF NOT EXISTS") }
        parts.append(quoteIdentifier(name))
        parts.append("AS \(query)")

        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Refresh a materialized view
    @discardableResult
    public func refreshMaterializedView(name: String, concurrently: Bool = false) async throws -> Int {
        var parts: [String] = ["REFRESH MATERIALIZED VIEW"]
        if concurrently { parts.append("CONCURRENTLY") }
        parts.append(quoteIdentifier(name))

        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Drop a materialized view
    @discardableResult
    public func dropMaterializedView(name: String, ifExists: Bool = false, cascade: Bool = false) async throws -> Int {
        var parts: [String] = ["DROP MATERIALIZED VIEW"]
        if ifExists { parts.append("IF EXISTS") }
        parts.append(quoteIdentifier(name))
        if cascade { parts.append("CASCADE") }
        return try await executeDDL(parts.joined(separator: " "))
    }

    // MARK: - Database Operations

    /// Create a new database
    @discardableResult
    public func createDatabase(name: String, ifNotExists: Bool = false, owner: String? = nil, template: String = "template1", encoding: String? = nil) async throws -> Int {
        var parts: [String] = ["CREATE DATABASE"]
        if ifNotExists { parts.append("IF NOT EXISTS") }
        parts.append(quoteIdentifier(name))
        parts.append("WITH TEMPLATE \(quoteIdentifier(template))")

        if let owner {
            parts.append("OWNER \(quoteIdentifier(owner))")
        }

        if let encoding {
            parts.append("ENCODING '\(encoding)'")
        }

        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Drop a database
    @discardableResult
    public func dropDatabase(name: String, ifExists: Bool = false, withForce: Bool = false) async throws -> Int {
        var parts: [String] = ["DROP DATABASE"]
        if ifExists { parts.append("IF EXISTS") }
        parts.append(quoteIdentifier(name))
        if withForce { parts.append("WITH (FORCE)") }
        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Change database connection
    @discardableResult
    public func useDatabase(_ name: String) async throws -> Int {
        return try await executeDDL("SET search_path TO \(quoteIdentifier(name))")
    }

    // MARK: - Schema Operations

    /// Create a new schema
    @discardableResult
    public func createSchema(name: String, ifNotExists: Bool = false, authorization: String? = nil) async throws -> Int {
        var parts: [String] = ["CREATE SCHEMA"]
        if ifNotExists { parts.append("IF NOT EXISTS") }
        parts.append(quoteIdentifier(name))

        if let authorization {
            parts.append("AUTHORIZATION \(quoteIdentifier(authorization))")
        }

        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Drop a schema
    @discardableResult
    public func dropSchema(name: String, ifExists: Bool = false, cascade: Bool = false) async throws -> Int {
        var parts: [String] = ["DROP SCHEMA"]
        if ifExists { parts.append("IF EXISTS") }
        parts.append(quoteIdentifier(name))
        if cascade { parts.append("CASCADE") }
        return try await executeDDL(parts.joined(separator: " "))
    }

    // MARK: - User and Role Management

    /// Create a new user/role
    @discardableResult
    public func createUser(
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

        if let validUntil {
            parts.append("VALID UNTIL '\(validUntil)'")
        }

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

    /// Drop a user/role
    @discardableResult
    public func dropUser(name: String, ifExists: Bool = false) async throws -> Int {
        var parts: [String] = ["DROP USER"]
        if ifExists { parts.append("IF EXISTS") }
        parts.append(quoteIdentifier(name))
        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Alter user role attributes
    @discardableResult
    public func alterUser(
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

            if let superuser {
                parts.append(superuser ? "SUPERUSER" : "NOSUPERUSER")
            }

            if let createDatabase {
                parts.append(createDatabase ? "CREATEDB" : "NOCREATEDB")
            }

            if let createRole {
                parts.append(createRole ? "CREATEROLE" : "NOCREATEROLE")
            }

            if let login {
                parts.append(login ? "LOGIN" : "NOLOGIN")
            }

            if let inherit {
                parts.append(inherit ? "INHERIT" : "NOINHERIT")
            }

            if let replication {
                parts.append(replication ? "REPLICATION" : "NOREPLICATION")
            }

            if let bypassRLS {
                parts.append(bypassRLS ? "BYPASSRLS" : "NOBYPASSRLS")
            }

            if let validUntil {
                parts.append("VALID UNTIL '\(validUntil)'")
            }
        }

        return try await executeDDL(parts.joined(separator: " "))
    }

    // MARK: - Privilege Management

    /// Grant privileges on a table
    @discardableResult
    public func grantPrivileges(
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

    /// Revoke privileges on a table
    @discardableResult
    public func revokePrivileges(
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

    /// Grant role membership with optional ADMIN, INHERIT, and SET options.
    @discardableResult
    public func grantRole(role: String, to: String, admin: Bool = false, inherit: Bool? = nil, set: Bool? = nil) async throws -> Int {
        var parts: [String] = ["GRANT \(quoteIdentifier(role))"]
        parts.append("TO \(quoteIdentifier(to))")
        var options: [String] = []
        if admin { options.append("ADMIN TRUE") } else { options.append("ADMIN FALSE") }
        if let inherit { options.append("INHERIT \(inherit ? "TRUE" : "FALSE")") }
        if let set { options.append("SET \(set ? "TRUE" : "FALSE")") }
        if !options.isEmpty { parts.append("WITH \(options.joined(separator: ", "))") }
        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Revoke role membership
    @discardableResult
    public func revokeRole(role: String, from: String, admin: Bool = false) async throws -> Int {
        var parts: [String] = ["REVOKE"]
        if admin { parts.append("ADMIN OPTION FOR") }
        parts.append("\(quoteIdentifier(role))")
        parts.append("FROM \(quoteIdentifier(from))")
        return try await executeDDL(parts.joined(separator: " "))
    }

    // MARK: - Constraint Operations

    /// Add primary key constraint to table
    @discardableResult
    public func addPrimaryKey(table: String, column: String, constraintName: String? = nil) async throws -> Int {
        let name = constraintName ?? "pk_\(table)_\(column)"
        let sql = "ALTER TABLE \(quoteIdentifier(table)) ADD CONSTRAINT \(quoteIdentifier(name)) PRIMARY KEY (\(quoteIdentifier(column)))"
        return try await executeDDL(sql)
    }

    /// Add foreign key constraint to table
    @discardableResult
    public func addForeignKey(
        table: String,
        column: String,
        referencesTable: String,
        referencesColumn: String,
        constraintName: String? = nil,
        onDelete: PostgresForeignKeyAction? = nil,
        onUpdate: PostgresForeignKeyAction? = nil
    ) async throws -> Int {
        let name = constraintName ?? "fk_\(table)_\(column)_\(referencesTable)_\(referencesColumn)"
        var parts: [String] = [
            "ALTER TABLE \(quoteIdentifier(table))",
            "ADD CONSTRAINT \(quoteIdentifier(name))",
            "FOREIGN KEY (\(quoteIdentifier(column)))",
            "REFERENCES \(quoteIdentifier(referencesTable))(\(quoteIdentifier(referencesColumn)))"
        ]

        if let onDelete {
            parts.append("ON DELETE \(onDelete.rawValue)")
        }

        if let onUpdate {
            parts.append("ON UPDATE \(onUpdate.rawValue)")
        }

        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Add unique constraint to table
    @discardableResult
    public func addUniqueConstraint(table: String, columns: [String], constraintName: String? = nil) async throws -> Int {
        let name = constraintName ?? "uq_\(table)_\(columns.joined(separator: "_"))"
        let columnList = columns.map { quoteIdentifier($0) }.joined(separator: ", ")
        let sql = "ALTER TABLE \(quoteIdentifier(table)) ADD CONSTRAINT \(quoteIdentifier(name)) UNIQUE (\(columnList))"
        return try await executeDDL(sql)
    }

    /// Add check constraint to table
    @discardableResult
    public func addCheckConstraint(table: String, condition: String, constraintName: String) async throws -> Int {
        let sql = "ALTER TABLE \(quoteIdentifier(table)) ADD CONSTRAINT \(quoteIdentifier(constraintName)) CHECK (\(condition))"
        return try await executeDDL(sql)
    }

    /// Drop constraint from table
    @discardableResult
    public func dropConstraint(table: String, constraintName: String, cascade: Bool = false) async throws -> Int {
        var parts: [String] = [
            "ALTER TABLE \(quoteIdentifier(table))",
            "DROP CONSTRAINT \(quoteIdentifier(constraintName))"
        ]
        if cascade { parts.append("CASCADE") }
        return try await executeDDL(parts.joined(separator: " "))
    }

    // MARK: - Function and Procedure Operations

    /// Create a SQL function
    @discardableResult
    public func createFunction(
        name: String,
        parameters: [PostgresFunctionParameter],
        returnType: String,
        body: String,
        language: PostgresFunctionLanguage = .sql,
        orReplace: Bool = false,
        security: PostgresFunctionSecurity = .definer,
        immutable: Bool = false,
        stable: Bool = false,
        volatile: Bool = false,
        returnsNullOnNullInput: Bool = false,
        strict: Bool = false,
        cost: Int? = nil,
        rows: Int? = nil
    ) async throws -> Int {
        var parts: [String] = ["CREATE"]
        if orReplace { parts.append("OR REPLACE") }
        parts.append("FUNCTION")
        parts.append(quoteIdentifier(name))

        let paramList = parameters.map { param in
            var paramDef = "\(quoteIdentifier(param.name))"
            paramDef += " \(param.dataType)"
            if param.defaultValue != nil {
                paramDef += " DEFAULT \(param.defaultValue!)"
            }
            if param.mode == .`in` { paramDef = "IN " + paramDef }
            else if param.mode == .`out` { paramDef = "OUT " + paramDef }
            else if param.mode == .`inout` { paramDef = "INOUT " + paramDef }
            return paramDef
        }.joined(separator: ", ")

        parts.append("(\(paramList))")
        parts.append("RETURNS \(returnType)")
        parts.append("LANGUAGE \(language.rawValue)")

        if immutable { parts.append("IMMUTABLE") }
        else if stable { parts.append("STABLE") }
        else if volatile { parts.append("VOLATILE") }

        if security == .definer { parts.append("SECURITY DEFINER") }
        else if security == .invoker { parts.append("SECURITY INVOKER") }

        if returnsNullOnNullInput { parts.append("RETURNS NULL ON NULL INPUT") }
        if strict { parts.append("STRICT") }

        if let cost {
            parts.append("COST \(cost)")
        }

        if let rows {
            parts.append("ROWS \(rows)")
        }

        parts.append("AS \(quoteLiteral(body))")

        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Drop a function
    @discardableResult
    public func dropFunction(name: String, parameters: [String] = [], ifExists: Bool = false, cascade: Bool = false) async throws -> Int {
        var parts: [String] = ["DROP FUNCTION"]
        if ifExists { parts.append("IF EXISTS") }
        parts.append(quoteIdentifier(name))
        if !parameters.isEmpty {
            parts.append("(\(parameters.joined(separator: ", ")))")
        }
        if cascade { parts.append("CASCADE") }
        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Execute a function and return the result
    public func executeFunction<T: PostgresDecodable & Sendable>(
        _ name: String,
        parameters: [Any] = [],
        decodeTo: T.Type
    ) async throws -> T {
        // Process parameters outside the Sendable closure to avoid capture issues
        let paramPlaceholders = parameters.enumerated().map { index, _ in "$\(index + 1)" }.joined(separator: ", ")
        let binds = parameters.map { param in
            if let string = param as? String {
                return PGData(string: string)
            } else if let int = param as? Int {
                return PGData(int32: Int32(int))
            } else if let bool = param as? Bool {
                return PGData(bool: bool)
            } else {
                return PGData(string: String(describing: param))
            }
        }
        let sql = "SELECT * FROM \(quoteIdentifier(name))(\(paramPlaceholders))"

        return try await withConnection { conn in
            let rows = try await conn.query(sql, binds: binds)

            for try await value in rows.decode(decodeTo) {
                return value
            }

            throw PostgresKit.PostgresError.protocolError("Function \(name) returned no value")
        }
    }

    // MARK: - Trigger Operations

    /// Create a trigger
    @discardableResult
    public func createTrigger(
        name: String,
        table: String,
        event: PostgresTriggerEvent,
        operations: [PostgresTriggerOperation],
        procedure: String,
        orReplace: Bool = false,
        constraint: Bool = false,
        forEach: PostgresTriggerForEach = .row,
        when: String? = nil
    ) async throws -> Int {
        var parts: [String] = ["CREATE"]
        if orReplace { parts.append("OR REPLACE") }
        parts.append("TRIGGER")
        if constraint { parts.append("CONSTRAINT") }
        parts.append(quoteIdentifier(name))

        parts.append(event.rawValue)

        let operationList = operations.map { $0.rawValue }.joined(separator: " OR ")
        parts.append(operationList)

        parts.append("ON \(quoteIdentifier(table))")

        if let when {
            parts.append("WHEN (\(when))")
        }

        parts.append("FOR EACH \(forEach.rawValue)")
        parts.append("EXECUTE PROCEDURE \(quoteIdentifier(procedure))")

        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Drop a trigger
    @discardableResult
    public func dropTrigger(name: String, table: String, ifExists: Bool = false) async throws -> Int {
        var parts: [String] = ["DROP TRIGGER"]
        if ifExists { parts.append("IF EXISTS") }
        parts.append(quoteIdentifier(name))
        parts.append("ON \(quoteIdentifier(table))")
        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Enable or disable a trigger
    @discardableResult
    public func alterTrigger(name: String, table: String, enabled: Bool) async throws -> Int {
        let sql = "ALTER TABLE \(quoteIdentifier(table)) \(enabled ? "ENABLE" : "DISABLE") TRIGGER \(quoteIdentifier(name))"
        return try await executeDDL(sql)
    }

    // MARK: - Enhanced Index Operations

    /// Create an index with advanced options
    @discardableResult
    public func createAdvancedIndex(
        name: String,
        table: String,
        columns: [PostgresIndexColumn],
        indexType: PostgresIndexType = .btree,
        unique: Bool = false,
        ifNotExists: Bool = false,
        whereClause: String? = nil,
        tablespace: String? = nil,
        nullsDistinct: Bool = true
    ) async throws -> Int {
        var parts: [String] = ["CREATE"]
        if unique { parts.append("UNIQUE") }
        parts.append("INDEX")
        if ifNotExists { parts.append("IF NOT EXISTS") }
        parts.append(quoteIdentifier(name))
        parts.append("ON \(quoteIdentifier(table))")

        // Index method
        parts.append("USING \(indexType)")

        // Columns with optional ordering
        let columnList = columns.map { column in
            var colDef = quoteIdentifier(column.name)
            if let order = column.order {
                colDef += " " + order.rawValue
            }
            if let nullsOrder = column.nullsOrder {
                colDef += " NULLS " + nullsOrder.rawValue
            }
            return colDef
        }.joined(separator: ", ")
        parts.append("(\(columnList))")

        if let whereClause {
            parts.append("WHERE \(whereClause)")
        }

        if let tablespace {
            parts.append("TABLESPACE \(quoteIdentifier(tablespace))")
        }

        if !nullsDistinct {
            parts.append("NULLS NOT DISTINCT")
        }

        return try await executeDDL(parts.joined(separator: " "))
    }

    // MARK: - Data Manipulation Operations

    /// Insert data into a table
    @discardableResult
    public func insert(
        into table: String,
        columns: [String] = [],
        values: [[Any]]
    ) async throws -> Int {
        // Process values outside the Sendable closure to avoid capture issues
        let isEmpty = values.isEmpty
        let processedValues = try values.map { row in
            try row.map { value in
                try toPGData(value: value)
            }
        }

        return try await withConnection { conn in
            if isEmpty { return 0 }

            let columnList = columns.isEmpty ? "" : "(\(columns.map(quoteIdentifier).joined(separator: ", ")))"

            // Generate proper parameter placeholders using pre-processed values
            var allBinds: [PGData] = []
            var bindIndex = 1
            let valuePlaceholders = processedValues.enumerated().map { rowIndex, processedRow in
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

    /// Update data in a table
    @discardableResult
    public func update(
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

    /// Delete data from a table
    @discardableResult
    public func delete(
        from table: String,
        whereClause: String? = nil
    ) async throws -> Int {
        var sql = "DELETE FROM \(quoteIdentifier(table))"
        if let whereClause {
            sql += " WHERE \(whereClause)"
        }
        return try await executeDDL(sql)
    }

    /// Truncate a table (remove all rows efficiently)
    @discardableResult
    public func truncate(table: String, cascade: Bool = false, restartIdentity: Bool = false) async throws -> Int {
        var parts: [String] = ["TRUNCATE TABLE"]
        parts.append(quoteIdentifier(table))
        if cascade { parts.append("CASCADE") }
        if restartIdentity { parts.append("RESTART IDENTITY") } else { parts.append("CONTINUE IDENTITY") }
        return try await executeDDL(parts.joined(separator: " "))
    }

    // MARK: - Extension and Type Operations

    /// Create an enum type
    @discardableResult
    public func createEnum(name: String, values: [String], ifNotExists: Bool = false) async throws -> Int {
        var parts: [String] = ["CREATE TYPE"]
        if ifNotExists { parts.append("IF NOT EXISTS") }
        parts.append(quoteIdentifier(name))
        parts.append("AS ENUM")

        let valueList = values.map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" }.joined(separator: ", ")
        parts.append("(\(valueList))")

        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Drop an enum type
    @discardableResult
    public func dropEnum(name: String, ifExists: Bool = false, cascade: Bool = false) async throws -> Int {
        var parts: [String] = ["DROP TYPE"]
        if ifExists { parts.append("IF EXISTS") }
        parts.append(quoteIdentifier(name))
        if cascade { parts.append("CASCADE") }
        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Add a value to an existing enum type
    @discardableResult
    public func addEnumValue(type: String, value: String, before: String? = nil, after: String? = nil) async throws -> Int {
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

    /// Rename a value in an enum type
    @discardableResult
    public func renameEnumValue(type: String, oldValue: String, newValue: String) async throws -> Int {
        let sql = "ALTER TYPE \(quoteIdentifier(type)) RENAME VALUE '\(oldValue.replacingOccurrences(of: "'", with: "''"))' TO '\(newValue.replacingOccurrences(of: "'", with: "''"))'"
        return try await executeDDL(sql)
    }

    // MARK: - Table Operations (Enhanced)

    /// Rename a table
    @discardableResult
    public func renameTable(oldName: String, newName: String) async throws -> Int {
        let sql = "ALTER TABLE \(quoteIdentifier(oldName)) RENAME TO \(quoteIdentifier(newName))"
        return try await executeDDL(sql)
    }

    /// Add column to table with enhanced options
    @discardableResult
    public func addColumn(
        table: String,
        column: PostgresColumnDefinition,
        using: String? = nil
    ) async throws -> Int {
        var columnDef = "\(quoteIdentifier(column.name)) \(column.dataType)"

        if let defaultValue = column.defaultValue {
            columnDef += " DEFAULT \(defaultValue)"
        }

        if column.nullable == false {
            columnDef += " NOT NULL"
        }

        if column.primaryKey {
            columnDef += " PRIMARY KEY"
        }

        if column.unique {
            columnDef += " UNIQUE"
        }

        var parts: [String] = [
            "ALTER TABLE \(quoteIdentifier(table))",
            "ADD COLUMN \(columnDef)"
        ]

        if let using {
            parts.append("USING \(using)")
        }

        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Rename a column
    @discardableResult
    public func renameColumn(table: String, oldName: String, newName: String) async throws -> Int {
        let sql = "ALTER TABLE \(quoteIdentifier(table)) RENAME COLUMN \(quoteIdentifier(oldName)) TO \(quoteIdentifier(newName))"
        return try await executeDDL(sql)
    }

    /// Alter column data type
    @discardableResult
    public func alterColumnType(table: String, column: String, newType: String, using: String? = nil) async throws -> Int {
        var parts: [String] = [
            "ALTER TABLE \(quoteIdentifier(table))",
            "ALTER COLUMN \(quoteIdentifier(column))",
            "TYPE \(newType)"
        ]

        if let using {
            parts.append("USING \(using)")
        }

        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Alter column default value
    @discardableResult
    public func alterColumnDefault(table: String, column: String, defaultValue: String?) async throws -> Int {
        let sql: String
        if let defaultValue = defaultValue {
            sql = "ALTER TABLE \(quoteIdentifier(table)) ALTER COLUMN \(quoteIdentifier(column)) SET DEFAULT \(defaultValue)"
        } else {
            sql = "ALTER TABLE \(quoteIdentifier(table)) ALTER COLUMN \(quoteIdentifier(column)) DROP DEFAULT"
        }
        return try await executeDDL(sql)
    }

    /// Alter column nullability
    @discardableResult
    public func alterColumnNullability(table: String, column: String, nullable: Bool) async throws -> Int {
        let sql = "ALTER TABLE \(quoteIdentifier(table)) ALTER COLUMN \(quoteIdentifier(column)) \(nullable ? "DROP" : "SET") NOT NULL"
        return try await executeDDL(sql)
    }

    // MARK: - Copy Operations

    /// Copy data from one table to another
    @discardableResult
    public func copyTable(
        from sourceTable: String,
        to targetTable: String,
        columns: [String]? = nil
    ) async throws -> Int {
        let columnList = columns.map { "(\($0.map(quoteIdentifier).joined(separator: ", ")))" } ?? ""
        let sql = "INSERT INTO \(quoteIdentifier(targetTable))\(columnList) SELECT * FROM \(quoteIdentifier(sourceTable))"
        return try await executeDDL(sql)
    }

    /// Create table as select from another table
    @discardableResult
    public func createTableAs(
        name: String,
        selectQuery: String,
        temporary: Bool = false,
        ifNotExists: Bool = false
    ) async throws -> Int {
        var parts: [String] = ["CREATE"]
        if temporary { parts.append("TEMPORARY") }
        parts.append("TABLE")
        if ifNotExists { parts.append("IF NOT EXISTS") }
        parts.append(quoteIdentifier(name))
        parts.append("AS \(selectQuery)")

        return try await executeDDL(parts.joined(separator: " "))
    }

    // MARK: - Server Configuration Operations

    /// Set a server configuration parameter
    @discardableResult
    public func setConfiguration(parameter: String, value: String, local: Bool = false) async throws -> Int {
        let sql = "SET\(local ? " LOCAL" : "") \(quoteIdentifier(parameter)) TO '\(value.replacingOccurrences(of: "'", with: "''"))'"
        return try await executeDDL(sql)
    }

    /// Reset a server configuration parameter to default
    @discardableResult
    public func resetConfiguration(parameter: String, local: Bool = false) async throws -> Int {
        let sql = "RESET\(local ? " LOCAL" : "") \(quoteIdentifier(parameter))"
        return try await executeDDL(sql)
    }

    // MARK: - Lock Operations

    /// Lock a table
    @discardableResult
    public func lock(table: String, mode: PostgresLockMode, nowait: Bool = false) async throws -> Int {
        var sql = "LOCK TABLE \(quoteIdentifier(table)) IN \(mode.rawValue)"
        if nowait { sql += " NOWAIT" }
        return try await executeDDL(sql)
    }

    /// Advisory lock functions
    public func advisoryLock(key: Int64) async throws -> Bool {
        let rows = try await simpleQuery("SELECT pg_advisory_lock(\(key)) as locked")
        for try await locked in rows.decode(Bool.self) {
            return locked
        }
        throw PostgresKit.PostgresError.protocolError("Advisory lock query failed")
    }

    public func tryAdvisoryLock(key: Int64) async throws -> Bool {
        let rows = try await simpleQuery("SELECT pg_try_advisory_lock(\(key)) as locked")
        for try await locked in rows.decode(Bool.self) {
            return locked
        }
        throw PostgresKit.PostgresError.protocolError("Advisory lock query failed")
    }

    public func advisoryUnlock(key: Int64) async throws -> Bool {
        let rows = try await simpleQuery("SELECT pg_advisory_unlock(\(key)) as unlocked")
        for try await unlocked in rows.decode(Bool.self) {
            return unlocked
        }
        throw PostgresKit.PostgresError.protocolError("Advisory unlock query failed")
    }

    // MARK: - Transaction Operations

    /// Begin a transaction
    @discardableResult
    public func beginTransaction() async throws -> Int {
        return try await executeDDL("BEGIN")
    }

    /// Begin a transaction with isolation level
    @discardableResult
    public func beginTransaction(isolation: PostgresIsolationLevel, readOnly: Bool = false, deferrable: Bool = false) async throws -> Int {
        var parts: [String] = ["BEGIN TRANSACTION"]
        parts.append("ISOLATION LEVEL \(isolation.rawValue)")
        if readOnly { parts.append("READ ONLY") }
        if deferrable { parts.append("DEFERRABLE") }
        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Commit a transaction
    @discardableResult
    public func commit() async throws -> Int {
        return try await executeDDL("COMMIT")
    }

    /// Rollback a transaction
    @discardableResult
    public func rollback() async throws -> Int {
        return try await executeDDL("ROLLBACK")
    }

    /// Create a savepoint
    @discardableResult
    public func createSavepoint(_ name: String) async throws -> Int {
        return try await executeDDL("SAVEPOINT \(quoteIdentifier(name))")
    }

    /// Rollback to a savepoint
    @discardableResult
    public func rollbackToSavepoint(_ name: String) async throws -> Int {
        return try await executeDDL("ROLLBACK TO SAVEPOINT \(quoteIdentifier(name))")
    }

    /// Release a savepoint
    @discardableResult
    public func releaseSavepoint(_ name: String) async throws -> Int {
        return try await executeDDL("RELEASE SAVEPOINT \(quoteIdentifier(name))")
    }

    // MARK: - Utility Functions

    /// Quote an identifier to prevent SQL injection
    private func quoteIdentifier(_ identifier: String) -> String {
        return "\"\(identifier.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    /// Quote a literal string to prevent SQL injection
    private func quoteLiteral(_ literal: String) -> String {
        return "'\(literal.replacingOccurrences(of: "'", with: "''"))'"
    }

    private func toPGData(value: Any) throws -> PGData {
        if let encodable = value as? PostgresEncodable {
            var data = PGData(type: encodable.pgDataType)
            try encodable.encode(into: &data)
            return data
        } else {
            throw PostgresError.encodingError(type: type(of: value))
        }
    }
}

// Registry associates a per-connection StatementCache via connection identity.
private actor PreparedRegistry {
    private var stmtCaches: [ObjectIdentifier: StatementCache] = [:]
    private var serverCaches: [ObjectIdentifier: PreparedServerCache] = [:]

    func statementCache(for id: ObjectIdentifier) -> StatementCache {
        if let cache = stmtCaches[id] { return cache }
        let new = StatementCache(capacity: 256)
        stmtCaches[id] = new
        return new
    }

    func serverPreparedCache(for id: ObjectIdentifier) -> PreparedServerCache {
        if let cache = serverCaches[id] { return cache }
        let new = PreparedServerCache(capacity: 128)
        serverCaches[id] = new
        return new
    }
}
