import PostgresWire

/// High-level COMMENT operations for database objects.
public extension PostgresDatabaseClient {
    /// Set or clear the comment on a table.
    @discardableResult
    func commentOnTable(_ table: String, comment: String?) async throws -> Int {
        let commentSQL = comment.map { quoteLiteral($0) } ?? "NULL"
        return try await executeDDL("COMMENT ON TABLE \(quoteIdentifier(table)) IS \(commentSQL)")
    }

    /// Set or clear the comment on a column.
    @discardableResult
    func commentOnColumn(table: String, column: String, comment: String?) async throws -> Int {
        let commentSQL = comment.map { quoteLiteral($0) } ?? "NULL"
        return try await executeDDL("COMMENT ON COLUMN \(quoteIdentifier(table)).\(quoteIdentifier(column)) IS \(commentSQL)")
    }

    /// Set or clear the comment on an index.
    @discardableResult
    func commentOnIndex(_ index: String, comment: String?) async throws -> Int {
        let commentSQL = comment.map { quoteLiteral($0) } ?? "NULL"
        return try await executeDDL("COMMENT ON INDEX \(quoteIdentifier(index)) IS \(commentSQL)")
    }

    /// Set or clear the comment on a constraint.
    @discardableResult
    func commentOnConstraint(_ constraint: String, table: String, comment: String?) async throws -> Int {
        let commentSQL = comment.map { quoteLiteral($0) } ?? "NULL"
        return try await executeDDL("COMMENT ON CONSTRAINT \(quoteIdentifier(constraint)) ON \(quoteIdentifier(table)) IS \(commentSQL)")
    }

    /// Set or clear the comment on a function.
    @discardableResult
    func commentOnFunction(_ function: String, parameters: String = "", comment: String?) async throws -> Int {
        let commentSQL = comment.map { quoteLiteral($0) } ?? "NULL"
        return try await executeDDL("COMMENT ON FUNCTION \(quoteIdentifier(function))(\(parameters)) IS \(commentSQL)")
    }

    /// Set or clear the comment on a trigger.
    @discardableResult
    func commentOnTrigger(_ trigger: String, table: String, comment: String?) async throws -> Int {
        let commentSQL = comment.map { quoteLiteral($0) } ?? "NULL"
        return try await executeDDL("COMMENT ON TRIGGER \(quoteIdentifier(trigger)) ON \(quoteIdentifier(table)) IS \(commentSQL)")
    }

    /// Set or clear the comment on a schema.
    @discardableResult
    func commentOnSchema(_ schema: String, comment: String?) async throws -> Int {
        let commentSQL = comment.map { quoteLiteral($0) } ?? "NULL"
        return try await executeDDL("COMMENT ON SCHEMA \(quoteIdentifier(schema)) IS \(commentSQL)")
    }

    /// Set or clear the comment on a view.
    @discardableResult
    func commentOnView(_ view: String, comment: String?) async throws -> Int {
        let commentSQL = comment.map { quoteLiteral($0) } ?? "NULL"
        return try await executeDDL("COMMENT ON VIEW \(quoteIdentifier(view)) IS \(commentSQL)")
    }

    /// Set or clear the comment on a sequence.
    @discardableResult
    func commentOnSequence(_ sequence: String, comment: String?) async throws -> Int {
        let commentSQL = comment.map { quoteLiteral($0) } ?? "NULL"
        return try await executeDDL("COMMENT ON SEQUENCE \(quoteIdentifier(sequence)) IS \(commentSQL)")
    }

    /// Set or clear the comment on an extension.
    @discardableResult
    func commentOnExtension(_ extensionName: String, comment: String?) async throws -> Int {
        let commentSQL = comment.map { quoteLiteral($0) } ?? "NULL"
        return try await executeDDL("COMMENT ON EXTENSION \(quoteIdentifier(extensionName)) IS \(commentSQL)")
    }

    /// Set or clear the comment on a type.
    @discardableResult
    func commentOnType(_ type: String, comment: String?) async throws -> Int {
        let commentSQL = comment.map { quoteLiteral($0) } ?? "NULL"
        return try await executeDDL("COMMENT ON TYPE \(quoteIdentifier(type)) IS \(commentSQL)")
    }
}
