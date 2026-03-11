import Foundation

/// Internal quoting utilities for SQL generation
internal extension PostgresDatabaseClient {
    /// Quote an identifier to prevent SQL injection.
    /// Handles schema-qualified names like "app.users" → "app"."users".
    func quoteIdentifier(_ identifier: String) -> String {
        identifier.split(separator: ".", maxSplits: 1)
            .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
            .joined(separator: ".")
    }

    /// Quote a literal string to prevent SQL injection
    func quoteLiteral(_ literal: String) -> String {
        return "'\(literal.replacingOccurrences(of: "'", with: "''"))'"
    }
}
