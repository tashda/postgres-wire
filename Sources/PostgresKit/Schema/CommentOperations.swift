import PostgresWire

/// High-level COMMENT operations for database objects.
public extension PostgresAdminClient {
    /// Set or clear the comment on a table.
    @discardableResult
    func commentOnTable(_ table: String, comment: String?) async throws -> Int {
        let commentSQL = comment.map { client.quoteLiteral($0) } ?? "NULL"
        return try await client.executeDDL("COMMENT ON TABLE \(client.quoteIdentifier(table)) IS \(commentSQL)")
    }

    /// Set or clear the comment on a column.
    @discardableResult
    func commentOnColumn(table: String, column: String, comment: String?) async throws -> Int {
        let commentSQL = comment.map { client.quoteLiteral($0) } ?? "NULL"
        return try await client.executeDDL("COMMENT ON COLUMN \(client.quoteIdentifier(table)).\(client.quoteIdentifier(column)) IS \(commentSQL)")
    }

    /// Set or clear the comment on an index.
    @discardableResult
    func commentOnIndex(_ index: String, comment: String?) async throws -> Int {
        let commentSQL = comment.map { client.quoteLiteral($0) } ?? "NULL"
        return try await client.executeDDL("COMMENT ON INDEX \(client.quoteIdentifier(index)) IS \(commentSQL)")
    }

    /// Set or clear the comment on a constraint.
    @discardableResult
    func commentOnConstraint(_ constraint: String, table: String, comment: String?) async throws -> Int {
        let commentSQL = comment.map { client.quoteLiteral($0) } ?? "NULL"
        return try await client.executeDDL("COMMENT ON CONSTRAINT \(client.quoteIdentifier(constraint)) ON \(client.quoteIdentifier(table)) IS \(commentSQL)")
    }

    /// Set or clear the comment on a function.
    @discardableResult
    func commentOnFunction(_ function: String, parameters: String = "", comment: String?) async throws -> Int {
        let commentSQL = comment.map { client.quoteLiteral($0) } ?? "NULL"
        return try await client.executeDDL("COMMENT ON FUNCTION \(client.quoteIdentifier(function))(\(parameters)) IS \(commentSQL)")
    }

    /// Set or clear the comment on a trigger.
    @discardableResult
    func commentOnTrigger(_ trigger: String, table: String, comment: String?) async throws -> Int {
        let commentSQL = comment.map { client.quoteLiteral($0) } ?? "NULL"
        return try await client.executeDDL("COMMENT ON TRIGGER \(client.quoteIdentifier(trigger)) ON \(client.quoteIdentifier(table)) IS \(commentSQL)")
    }

    /// Set or clear the comment on a schema.
    @discardableResult
    func commentOnSchema(_ schema: String, comment: String?) async throws -> Int {
        let commentSQL = comment.map { client.quoteLiteral($0) } ?? "NULL"
        return try await client.executeDDL("COMMENT ON SCHEMA \(client.quoteIdentifier(schema)) IS \(commentSQL)")
    }

    /// Set or clear the comment on a view.
    @discardableResult
    func commentOnView(_ view: String, comment: String?) async throws -> Int {
        let commentSQL = comment.map { client.quoteLiteral($0) } ?? "NULL"
        return try await client.executeDDL("COMMENT ON VIEW \(client.quoteIdentifier(view)) IS \(commentSQL)")
    }

    /// Set or clear the comment on a sequence.
    @discardableResult
    func commentOnSequence(_ sequence: String, comment: String?) async throws -> Int {
        let commentSQL = comment.map { client.quoteLiteral($0) } ?? "NULL"
        return try await client.executeDDL("COMMENT ON SEQUENCE \(client.quoteIdentifier(sequence)) IS \(commentSQL)")
    }

    /// Set or clear the comment on an extension.
    @discardableResult
    func commentOnExtension(_ extensionName: String, comment: String?) async throws -> Int {
        let commentSQL = comment.map { client.quoteLiteral($0) } ?? "NULL"
        return try await client.executeDDL("COMMENT ON EXTENSION \(client.quoteIdentifier(extensionName)) IS \(commentSQL)")
    }

    /// Set or clear the comment on a type.
    @discardableResult
    func commentOnType(_ type: String, comment: String?) async throws -> Int {
        let commentSQL = comment.map { client.quoteLiteral($0) } ?? "NULL"
        return try await client.executeDDL("COMMENT ON TYPE \(client.quoteIdentifier(type)) IS \(commentSQL)")
    }
}
