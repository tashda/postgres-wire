import Foundation

/// A legacy compatibility wrapper for database metadata introspection.
/// 
/// New code should prefer calling introspection methods directly on `PostgresClient`.
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

    public func listDatabases(using client: PostgresClient) async throws -> [String] {
        try await client.introspection.listDatabases()
    }

    public func isSuperuser(using client: PostgresClient) async throws -> Bool {
        try await client.introspection.checkSuperuser()
    }

    public func listSchemas(using client: PostgresClient) async throws -> [String] {
        try await client.introspection.listSchemas().map { $0.name }
    }

    public func listTablesAndViews(using client: PostgresClient, schema: String) async throws -> [SchemaObject] {
        try await client.introspection.listTablesAndViews(schema: schema)
    }

    public func listColumns(using client: PostgresClient, schema: String, table: String) async throws -> [PostgresColumnInfo] {
        try await client.introspection.listColumns(schema: schema, table: table)
    }

    public func columnsByTable(using client: PostgresClient, schema: String) async throws -> [String: [PostgresColumnDetail]] {
        try await client.introspection.columnsByTable(schema: schema)
    }

    public func primaryKey(using client: PostgresClient, schema: String, table: String) async throws -> PostgresPrimaryKeyInfo? {
        try await client.introspection.primaryKey(schema: schema, table: table)
    }

    public func foreignKeys(using client: PostgresClient, schema: String, table: String) async throws -> [PostgresForeignKeyInfo] {
        try await client.introspection.foreignKeys(schema: schema, table: table)
    }

    public func listIndexes(using client: PostgresClient, schema: String, table: String) async throws -> [PostgresIndexInfo] {
        try await client.introspection.listIndexes(schema: schema, table: table)
    }

    public func viewDefinition(using client: PostgresClient, schema: String, view: String) async throws -> String? {
        try await client.introspection.viewDefinition(schema: schema, view: view)
    }

    public func functionDefinition(using client: PostgresClient, schema: String, name: String) async throws -> String? {
        try await client.introspection.functionDefinition(schema: schema, name: name)
    }

    public func triggerDefinition(using client: PostgresClient, schema: String, name: String) async throws -> String? {
        try await client.introspection.triggerDefinition(schema: schema, name: name)
    }

    public func uniqueConstraints(using client: PostgresClient, schema: String, table: String) async throws -> [PostgresUniqueConstraintInfo] {
        try await client.introspection.uniqueConstraints(schema: schema, table: table)
    }

    public func dependencies(using client: PostgresClient, schema: String, table: String) async throws -> [PostgresDependencyInfo] {
        try await client.introspection.dependencies(schema: schema, table: table)
    }

    public func schemaSummary(
        using client: PostgresClient,
        schema: String,
        progress: (@Sendable (SummaryObjectType, Int, Int) async -> Void)? = nil
    ) async throws -> SchemaSummary {
        try await client.introspection.schemaSummary(schema: schema, progress: progress)
    }

    public func listRoles(using client: PostgresClient) async throws -> [PostgresRoleInfo] {
        try await client.security.listRoles()
    }

    public func listExtensions(using client: PostgresClient) async throws -> [PostgresExtensionInfo] {
        try await client.introspection.listExtensions()
    }

    public func listExtensionObjects(using client: PostgresClient, name: String) async throws -> [PostgresExtensionObject] {
        try await client.introspection.listExtensionObjects(name)
    }

    public func tableComment(using client: PostgresClient, schema: String, table: String) async throws -> String? {
        try await client.introspection.tableComment(schema: schema, table: table)
    }

    public func columnComments(using client: PostgresClient, schema: String, table: String) async throws -> [PostgresColumnComment] {
        try await client.introspection.columnComments(schema: schema, table: table)
    }

    public func functionComment(using client: PostgresClient, schema: String, name: String) async throws -> String? {
        try await client.introspection.functionComment(schema: schema, name: name)
    }

    public func triggerComment(using client: PostgresClient, schema: String, name: String) async throws -> String? {
        try await client.introspection.triggerComment(schema: schema, name: name)
    }

    public func databaseComment(using client: PostgresClient) async throws -> String? {
        try await client.introspection.databaseComment()
    }
}
