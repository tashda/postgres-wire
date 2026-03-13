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

    // MARK: - Single-Pass Encode

    /// Encode a ``PostgresRow`` directly into compact binary row format and optionally
    /// produce preview strings — all without intermediate `[Data?]` allocations.
    ///
    /// Binary format per cell: `0x00` (null) **or** `0x01` + UInt32-LE length + raw bytes.
    ///
    /// - Parameters:
    ///   - row: The Postgres row to encode.
    ///   - formatPreview: When `true`, also formats each cell to a display string.
    ///   - formatter: The cell formatter to use for preview strings.
    ///   - formattingEnabled: When `false`, uses the cheap fast-path for preview.
    /// - Returns: The encoded binary data and optional preview strings.
    public nonisolated static func encodeBinaryRow(
        from row: PostgresRow,
        formatPreview: Bool,
        formatter: PostgresCellFormatter,
        formattingEnabled: Bool = true
    ) -> (encodedRow: Data, preview: [String?]?) {
        // Pass 1: compute exact encoded size and optionally format preview strings
        var totalSize = 0
        var preview: [String?]? = formatPreview ? [] : nil
        preview?.reserveCapacity(row.count)

        for cell in row {
            totalSize &+= 1
            if let buffer = cell.bytes {
                totalSize &+= 4 &+ buffer.readableBytes
            }
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

        // Pass 2: encode binary row with pre-sized allocation (zero reallocation)
        var encoded = Data(count: totalSize)
        encoded.withUnsafeMutableBytes { mutableBytes in
            guard let base = mutableBytes.baseAddress else { return }
            var offset = 0
            for cell in row {
                if let buffer = cell.bytes {
                    base.storeBytes(of: UInt8(0x01), toByteOffset: offset, as: UInt8.self)
                    offset &+= 1
                    let count = buffer.readableBytes
                    var length = UInt32(count).littleEndian
                    withUnsafeBytes(of: &length) { ptr in
                        memcpy(base.advanced(by: offset), ptr.baseAddress!, 4)
                    }
                    offset &+= 4
                    if count > 0 {
                        buffer.withUnsafeReadableBytes { bufPtr in
                            if let p = bufPtr.baseAddress {
                                memcpy(base.advanced(by: offset), p, count)
                            }
                        }
                        offset &+= count
                    }
                } else {
                    base.storeBytes(of: UInt8(0x00), toByteOffset: offset, as: UInt8.self)
                    offset &+= 1
                }
            }
        }

        return (encoded, preview)
    }

    // MARK: - Legacy (kept for backward compatibility)

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
