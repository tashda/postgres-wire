import Foundation

/// A legacy compatibility wrapper for database metadata introspection.
/// 
/// New code should prefer calling introspection methods directly on `PostgresDatabaseClient`.
public struct PostgresMetadata: Sendable {
    public typealias Column = PostgresColumnInfo
    public typealias ColumnDetail = PostgresColumnDetail
    public typealias Index = PostgresIndexInfo
    public typealias PrimaryKey = PostgresPrimaryKeyInfo
    public typealias ForeignKey = PostgresForeignKeyInfo
    public typealias UniqueConstraint = PostgresUniqueConstraintInfo
    public typealias Dependency = PostgresDependencyInfo
    public typealias Role = PostgresRoleInfo
    public typealias ExtensionInfo = PostgresExtensionInfo
    public typealias ColumnComment = PostgresColumnComment

    public init() {}

    public func listDatabases(using client: PostgresDatabaseClient) async throws -> [String] {
        try await client.listDatabases()
    }

    public func listSchemas(using client: PostgresDatabaseClient) async throws -> [String] {
        try await client.listSchemas().map { $0.name }
    }

    public func listTablesAndViews(using client: PostgresDatabaseClient, schema: String) async throws -> [SchemaObject] {
        try await client.listTablesAndViews(schema: schema)
    }

    public func listColumns(using client: PostgresDatabaseClient, schema: String, table: String) async throws -> [PostgresColumnInfo] {
        try await client.listColumns(schema: schema, table: table)
    }

    public func columnsByTable(using client: PostgresDatabaseClient, schema: String) async throws -> [String: [PostgresColumnDetail]] {
        try await client.columnsByTable(schema: schema)
    }

    public func primaryKey(using client: PostgresDatabaseClient, schema: String, table: String) async throws -> PostgresPrimaryKeyInfo? {
        try await client.primaryKey(schema: schema, table: table)
    }

    public func foreignKeys(using client: PostgresDatabaseClient, schema: String, table: String) async throws -> [PostgresForeignKeyInfo] {
        try await client.foreignKeys(schema: schema, table: table)
    }

    public func listIndexes(using client: PostgresDatabaseClient, schema: String, table: String) async throws -> [PostgresIndexInfo] {
        try await client.listIndexes(schema: schema, table: table)
    }

    public func viewDefinition(using client: PostgresDatabaseClient, schema: String, view: String) async throws -> String? {
        try await client.viewDefinition(schema: schema, view: view)
    }

    public func functionDefinition(using client: PostgresDatabaseClient, schema: String, name: String) async throws -> String? {
        try await client.functionDefinition(schema: schema, name: name)
    }

    public func triggerDefinition(using client: PostgresDatabaseClient, schema: String, name: String) async throws -> String? {
        try await client.triggerDefinition(schema: schema, name: name)
    }

    public func uniqueConstraints(using client: PostgresDatabaseClient, schema: String, table: String) async throws -> [PostgresUniqueConstraintInfo] {
        try await client.uniqueConstraints(schema: schema, table: table)
    }

    public func dependencies(using client: PostgresDatabaseClient, schema: String, table: String) async throws -> [PostgresDependencyInfo] {
        try await client.dependencies(schema: schema, table: table)
    }

    public func schemaSummary(
        using client: PostgresDatabaseClient,
        schema: String,
        progress: (@Sendable (PostgresDatabaseClient.SummaryObjectType, Int, Int) async -> Void)? = nil
    ) async throws -> PostgresDatabaseClient.SchemaSummary {
        try await client.schemaSummary(schema: schema, progress: progress)
    }

    public func listRoles(using client: PostgresDatabaseClient) async throws -> [PostgresRoleInfo] {
        try await client.listRoles()
    }

    public func listExtensions(using client: PostgresDatabaseClient) async throws -> [PostgresExtensionInfo] {
        try await client.listExtensions()
    }

    public func tableComment(using client: PostgresDatabaseClient, schema: String, table: String) async throws -> String? {
        try await client.tableComment(schema: schema, table: table)
    }

    public func columnComments(using client: PostgresDatabaseClient, schema: String, table: String) async throws -> [PostgresColumnComment] {
        try await client.columnComments(schema: schema, table: table)
    }

    public func functionComment(using client: PostgresDatabaseClient, schema: String, name: String) async throws -> String? {
        try await client.functionComment(schema: schema, name: name)
    }

    public func triggerComment(using client: PostgresDatabaseClient, schema: String, name: String) async throws -> String? {
        try await client.triggerComment(schema: schema, name: name)
    }

    public func databaseComment(using client: PostgresDatabaseClient) async throws -> String? {
        try await client.databaseComment()
    }
}
