import Foundation

/// Internal quoting utilities for SQL generation
internal extension PostgresDatabaseClient {
    /// Quote an identifier to prevent SQL injection
    func quoteIdentifier(_ identifier: String) -> String {
        return "\"\(identifier.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    /// Quote a literal string to prevent SQL injection
    func quoteLiteral(_ literal: String) -> String {
        return "'\(literal.replacingOccurrences(of: "'", with: "''"))'"
    }
}
