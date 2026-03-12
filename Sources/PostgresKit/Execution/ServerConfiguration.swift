import PostgresWire

/// Server configuration management.
public extension PostgresAdminClient {
    /// Set a server configuration parameter.
    @discardableResult
    func setConfiguration(parameter: String, value: String, local: Bool = false) async throws -> Int {
        let sql = "SET\(local ? " LOCAL" : "") \(client.quoteIdentifier(parameter)) TO '\(value.replacingOccurrences(of: "'", with: "''"))'"
        return try await client.executeDDL(sql)
    }

    /// Reset a server configuration parameter to its default value.
    @discardableResult
    func resetConfiguration(parameter: String, local: Bool = false) async throws -> Int {
        let sql = "RESET\(local ? " LOCAL" : "") \(client.quoteIdentifier(parameter))"
        return try await client.executeDDL(sql)
    }

    /// Show the current value of a server configuration parameter.
    func showConfiguration(parameter: String) async throws -> String? {
        let rows = try await client.simpleQuery("SHOW \(client.quoteIdentifier(parameter))")
        for try await value in rows.decode(String?.self) { return value }
        return nil
    }
}
