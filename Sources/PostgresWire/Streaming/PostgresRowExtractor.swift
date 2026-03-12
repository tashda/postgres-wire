import Foundation
import NIOCore
import PostgresNIO

/// Static utilities for extracting column metadata and raw cell data from ``PostgresRow``.
///
/// All methods are synchronous and `nonisolated` — no actor overhead per row.
public struct PostgresRowExtractor: Sendable {

    public init() {}

    /// Extract column metadata from a row.
    public nonisolated static func columns(from row: PostgresRow) -> [ColumnInfo] {
        var result: [ColumnInfo] = []
        result.reserveCapacity(row.count)
        for cell in row {
            result.append(ColumnInfo(
                name: cell.columnName,
                dataType: "\(cell.dataType)",
                isPrimaryKey: false,
                isNullable: true,
                maxLength: nil
            ))
        }
        return result
    }

    /// Extract raw cell bytes as `[Data?]` from a row.
    public nonisolated static func rawCellData(from row: PostgresRow) -> [Data?] {
        var result: [Data?] = []
        result.reserveCapacity(row.count)
        for cell in row {
            result.append(extractCellBytes(cell))
        }
        return result
    }

    /// Extract raw bytes and optionally format a preview in a single pass over the row's cells.
    ///
    /// When `formatPreview` is `true`, both `rawCells` and `preview` are populated in one
    /// iteration — avoiding a second pass. When `false`, `preview` is `nil`.
    public nonisolated static func extractRow(
        from row: PostgresRow,
        formatPreview: Bool,
        formatter: PostgresCellFormatter,
        formattingEnabled: Bool = true
    ) -> (rawCells: [Data?], preview: [String?]?) {
        let count = row.count
        var rawCells: [Data?] = []
        rawCells.reserveCapacity(count)

        var preview: [String?]? = formatPreview ? [] : nil
        preview?.reserveCapacity(count)

        for cell in row {
            rawCells.append(extractCellBytes(cell))
            if formatPreview {
                if formattingEnabled {
                    preview?.append(formatter.stringValue(for: cell))
                } else {
                    preview?.append(
                        PostgresCellFormatter.cheapStringValue(for: cell)
                            ?? formatter.stringValue(for: cell)
                    )
                }
            }
        }

        return (rawCells, preview)
    }

    // MARK: - Private

    private nonisolated static func extractCellBytes(_ cell: PostgresCell) -> Data? {
        guard var buffer = cell.bytes else { return nil }
        let readable = buffer.readableBytes
        guard readable > 0 else { return Data() }
        if let bytes = buffer.readBytes(length: readable) {
            return Data(bytes)
        }
        return Data()
    }
}
