import PostgresWire

/// High-level Sequence Data Definition Language (DDL) operations.
public extension PostgresDatabaseClient {
    /// Create a new sequence.
    @discardableResult
    func createSequence(
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

        if let startWith { parts.append("START WITH \(startWith)") }
        if let incrementBy { parts.append("INCREMENT BY \(incrementBy)") }
        if let minValue { parts.append("MINVALUE \(minValue)") }
        if let maxValue { parts.append("MAXVALUE \(maxValue)") }
        if let cache { parts.append("CACHE \(cache)") }
        if cycle { parts.append("CYCLE") }

        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Drop an existing sequence.
    @discardableResult
    func dropSequence(name: String, ifExists: Bool = false, cascade: Bool = false) async throws -> Int {
        var parts: [String] = ["DROP SEQUENCE"]
        if ifExists { parts.append("IF EXISTS") }
        parts.append(quoteIdentifier(name))
        if cascade { parts.append("CASCADE") }
        return try await executeDDL(parts.joined(separator: " "))
    }

    /// Advance the sequence and return its new value.
    func nextval(_ sequenceName: String) async throws -> Int {
        let sql = "SELECT nextval(\(quoteLiteral(sequenceName))::text)::bigint as value"
        let rows = try await simpleQuery(sql)
        for try await value in rows.decode(Int.self) { return value }
        throw PostgresKit.PostgresError.protocolError("Sequence \(sequenceName) returned no value")
    }

    /// Return the most recently obtained value for the sequence in the current session.
    func currval(_ sequenceName: String) async throws -> Int {
        let sql = "SELECT currval(\(quoteLiteral(sequenceName))::text)::bigint as value"
        let rows = try await simpleQuery(sql)
        for try await value in rows.decode(Int.self) { return value }
        throw PostgresKit.PostgresError.protocolError("Sequence \(sequenceName) returned no value")
    }

    /// Reset the sequence's counter value.
    @discardableResult
    func setval(_ sequenceName: String, value: Int, isCalled: Bool = true) async throws -> Int {
        let sql = "SELECT setval(\(quoteLiteral(sequenceName))::text, \(value), \(isCalled))"
        return try await executeDDL(sql)
    }
}
