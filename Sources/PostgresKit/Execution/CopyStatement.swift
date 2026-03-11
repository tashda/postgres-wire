import Foundation

/// Internal PostgreSQL COPY statement parser.
internal struct CopyStatement {
    public enum Direction { case `in`, out }
    public enum Format { case csv, text }
    var direction: Direction
    var relation: String?
    var selectClause: String?
    var format: Format = .csv
    var header: Bool = false
    var delimiter: Character = ","
    var nullString: String? = nil
    var quote: Character = "\""

    static func parse(sql: String) throws -> CopyStatement {
        var s = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.uppercased().hasPrefix("COPY ") else {
            throw PostgresKitError.notSupported("Not a COPY statement")
        }
        s.removeFirst(5)
        var stmt = CopyStatement(direction: .out, relation: nil, selectClause: nil)
        if s.first == "(" {
            guard let end = s.firstIndex(of: ")") else { throw PostgresKitError.notSupported("Malformed COPY SELECT") }
            stmt.selectClause = String(s[s.index(after: s.startIndex)..<end])
            s = String(s[s.index(after: end)...]).trimmingCharacters(in: .whitespaces)
        } else {
            let upper = s.uppercased()
            if let range = upper.range(of: " FROM ") ?? upper.range(of: " TO ") {
                stmt.relation = String(s[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                s = String(s[range.lowerBound...])
            }
        }
        let upper = s.uppercased()
        if upper.contains(" FROM STDIN") { stmt.direction = .in }
        if upper.contains(" TO STDOUT") { stmt.direction = .out }
        if let withRange = upper.range(of: " WITH ") {
            let options = s[withRange.upperBound...].trimmingCharacters(in: .whitespaces)
            if options.range(of: "CSV", options: .caseInsensitive) != nil { stmt.format = .csv }
            if options.range(of: "HEADER", options: .caseInsensitive) != nil { stmt.header = true }
            if let delimRange = options.range(of: "DELIMITER", options: .caseInsensitive) {
                if let quote = options[delimRange.upperBound...].firstIndex(of: "'"), let quote2 = options[options.index(after: quote)...].firstIndex(of: "'") {
                    if let c = options[options.index(after: quote)..<quote2].first { stmt.delimiter = c }
                }
            }
            if let nullRange = options.range(of: "NULL", options: .caseInsensitive) {
                if let q1 = options[nullRange.upperBound...].firstIndex(of: "'"), let q2 = options[options.index(after: q1)...].firstIndex(of: "'") {
                    stmt.nullString = String(options[options.index(after: q1)..<q2])
                }
            }
            if let quoteRange = options.range(of: "QUOTE", options: .caseInsensitive) {
                if let q1 = options[quoteRange.upperBound...].firstIndex(of: "'"), let q2 = options[options.index(after: q1)...].firstIndex(of: "'") {
                    if let c = options[options.index(after: q1)..<q2].first { stmt.quote = c }
                }
            }
        }
        return stmt
    }

    func resolveTable() throws -> (schema: String?, table: String) {
        guard let relation else { throw PostgresKitError.notSupported("COPY SELECT requires SELECT fallback") }
        let parts = relation.split(separator: ".", maxSplits: 1).map(String.init)
        if parts.count == 2 {
            return (schema: parts[0].trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"")),
                    table: parts[1].trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
        }
        return (schema: nil, table: parts[0])
    }

    func selectSQL(usingClient client: PostgresDatabaseClient) async throws -> String {
        if let selectClause { return selectClause }
        let (schema, table) = try resolveTable()
        let columns = try await client.listColumns(schema: schema ?? "public", table: table)
        let colList = columns.map { column in
            let quoted = Self.quoteIdent(column.name)
            return "\(quoted)::text AS \(quoted)"
        }.joined(separator: ", ")
        return "SELECT \(colList) FROM \(Self.qualify(schema: schema, table: table))"
    }

    static func quoteIdent(_ s: String) -> String {
        "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
    static func qualify(schema: String?, table: String) -> String {
        if let schema { return "\(quoteIdent(schema)).\(quoteIdent(table))" }
        return quoteIdent(table)
    }
}
