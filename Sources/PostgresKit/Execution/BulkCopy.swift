import Foundation
import Logging
import PostgresWire

/// High-level bulk data movement (COPY) operations.
public struct PostgresBulkCopy: @unchecked Sendable {
    public struct Options: Sendable {
        public var chunkSizeBytes: Int = 64 * 1024
        public var insertBatchSize: Int = 500
        public var nullString: String? = nil
        public init(chunkSizeBytes: Int = 64 * 1024, insertBatchSize: Int = 500, nullString: String? = nil) {
            self.chunkSizeBytes = chunkSizeBytes
            self.insertBatchSize = insertBatchSize
            self.nullString = nullString
        }
    }

    private let client: PostgresDatabaseClient
    private let logger: Logger
    private let options: Options

    public init(client: PostgresDatabaseClient, logger: Logger, options: Options = .init()) {
        self.client = client
        self.logger = logger
        self.options = options
    }

    /// Execute COPY ... TO STDOUT and return an async byte stream.
    public func copyOut(sql: String) async throws -> AsyncThrowingStream<Data, Error> {
        let parsed = try CopyStatement.parse(sql: sql)
        guard parsed.direction == .out else { throw PostgresKitError.notSupported("Expected COPY ... TO STDOUT") }
        guard parsed.format == .csv else { throw PostgresKitError.notSupported("Only CSV format supported") }

        let chunkSize = max(16 * 1024, options.chunkSizeBytes)
        return AsyncThrowingStream<Data, Error> { continuation in
            Task {
                do {
                    var buffer = Data(); buffer.reserveCapacity(chunkSize)
                    var wroteHeader = false
                    let selectSQL = try await parsed.selectSQL(usingClient: client)
                    let rows = try await client.simpleQuery(selectSQL)
                    for try await row in rows {
                        if parsed.header && !wroteHeader {
                            buffer.append(Self.csvLine(row.map { $0.columnName }))
                            wroteHeader = true
                        }
                        var fields: [String] = []
                        for cell in row {
                            if var bb = cell.bytes, let data = bb.readData(length: bb.readableBytes) {
                                fields.append(String(data: data, encoding: .utf8) ?? (options.nullString ?? ""))
                            } else { fields.append(options.nullString ?? "") }
                        }
                        buffer.append(Self.csvLine(fields))
                        if buffer.count >= chunkSize {
                            continuation.yield(buffer)
                            buffer.removeAll(keepingCapacity: true)
                        }
                    }
                    if !buffer.isEmpty { continuation.yield(buffer) }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
        }
    }

    /// Execute COPY ... FROM STDIN consuming an async byte stream.
    public func copyIn<S: AsyncSequence>(sql: String, source: S) async throws where S.Element == Data {
        var parsed = try CopyStatement.parse(sql: sql)
        guard parsed.direction == .`in` else { throw PostgresKitError.notSupported("Expected COPY ... FROM STDIN") }
        guard parsed.format == .csv else { throw PostgresKitError.notSupported("Only CSV format supported") }

        let (schema, table) = try parsed.resolveTable()
        let columns = try await client.listColumns(schema: schema ?? "public", table: table)
        let columnList = columns.map { CopyStatement.quoteIdent($0.name) }.joined(separator: ", ")
        let insertPrefix = "INSERT INTO \(CopyStatement.qualify(schema: schema, table: table)) (\(columnList)) VALUES "

        var accumulator = Data()
        var rows: [[String?]] = []
        let batchSize = max(50, options.insertBatchSize)

        func flushBatch() async throws {
            guard !rows.isEmpty else { return }
            var binds: [PGData] = []
            var valuesSQL: [String] = []
            var paramIndex = 1
            for row in rows {
                var placeholders: [String] = []
                for (idx, value) in row.enumerated() {
                    placeholders.append("$\(paramIndex)\(idx < columns.count ? "::\(columns[idx].dataType)" : "")")
                    binds.append(value.map { PGData(string: $0) } ?? .null)
                    paramIndex += 1
                }
                valuesSQL.append("(\(placeholders.joined(separator: ", ")))")
            }
            let sql = insertPrefix + valuesSQL.joined(separator: ", ")
            let finalBinds = binds
            try await client.withConnection { conn in _ = try await conn.query(sql, binds: finalBinds) }
            rows.removeAll(keepingCapacity: true)
        }

        let parser = CSVParser(delimiter: parsed.delimiter, nullString: parsed.nullString ?? options.nullString, quote: parsed.quote)
        for try await chunk in source {
            accumulator.append(chunk)
            while let lineRange = accumulator.firstLineRange() {
                let lineData = accumulator[lineRange]
                accumulator.removeSubrange(lineRange)
                if parsed.header { parsed.header = false; continue }
                if let line = String(data: lineData, encoding: .utf8) {
                    rows.append(parser.parseLine(line))
                    if rows.count >= batchSize { try await flushBatch() }
                }
            }
        }
        if !rows.isEmpty { try await flushBatch() }
    }

    private static func csvLine(_ fields: [String]) -> Data {
        let line = fields.map { f in
            if f.isEmpty { return "" }
            let needsQuotes = f.contains(",") || f.contains("\n") || f.contains("\r") || f.contains("\"")
            var s = f.replacingOccurrences(of: "\"", with: "\"\"")
            if needsQuotes { s = "\"" + s + "\"" }
            return s
        }.joined(separator: ",") + "\n"
        return Data(line.utf8)
    }
}

private extension Data {
    func firstLineRange() -> Range<Data.Index>? {
        if let idx = self.firstIndex(of: 0x0A) { return startIndex..<index(after: idx) }
        return nil
    }
}
