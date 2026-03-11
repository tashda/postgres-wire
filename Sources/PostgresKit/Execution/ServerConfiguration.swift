import PostgresWire

/// Server configuration management.
public extension PostgresDatabaseClient {
    /// Set a server configuration parameter.
    @discardableResult
    func setConfiguration(parameter: String, value: String, local: Bool = false) async throws -> Int {
        let sql = "SET\(local ? " LOCAL" : "") \(quoteIdentifier(parameter)) TO '\(value.replacingOccurrences(of: "'", with: "''"))'"
        return try await executeDDL(sql)
    }

    /// Reset a server configuration parameter to its default value.
    @discardableResult
    func resetConfiguration(parameter: String, local: Bool = false) async throws -> Int {
        let sql = "RESET\(local ? " LOCAL" : "") \(quoteIdentifier(parameter))"
        return try await executeDDL(sql)
    }
}
