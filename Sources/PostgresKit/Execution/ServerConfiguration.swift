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

    /// Show the current value of a server configuration parameter.
    func showConfiguration(parameter: String) async throws -> String? {
        let rows = try await simpleQuery("SHOW \(quoteIdentifier(parameter))")
        for try await value in rows.decode(String?.self) { return value }
        return nil
    }
}
