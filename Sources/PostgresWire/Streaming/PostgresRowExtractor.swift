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
            // Store dataType as "TYPE(OID)" e.g. "INTEGER(23)" for type-aware spool decode
            let typeString = "\(cell.dataType)(\(cell.dataType.rawValue))"
            result.append(ColumnInfo(
                name: cell.columnName,
                dataType: typeString,
                isPrimaryKey: false,
                isNullable: true,
                maxLength: nil
            ))
        }
        return result
    }

    // MARK: - Single-Pass Encode

    /// Encode a ``PostgresRow`` directly into compact binary row format and optionally
    /// produce preview strings — all in a single pass over the row's cells.
    ///
    /// Binary format per cell: `0x00` (null) **or** `0x01` + UInt32-LE length + raw bytes.
    ///
    /// Uses unsafe pointer writes to avoid `Data.append` CoW overhead per cell.
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
        let columnCount = row.count
        var preview: [String?]? = formatPreview ? [] : nil
        preview?.reserveCapacity(columnCount)

        // Estimate buffer size: flag(1) + length(4) + avgData(~32) per column
        var capacity = columnCount * 40
        var rawBuffer = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: 8)
        var offset = 0

        for cell in row {
            if let cellBytes = cell.bytes {
                let byteCount = cellBytes.readableBytes
                let needed = offset + 5 + byteCount // flag(1) + length(4) + data
                if needed > capacity {
                    let newCapacity = max(needed, capacity * 2)
                    let newBuffer = UnsafeMutableRawPointer.allocate(byteCount: newCapacity, alignment: 8)
                    newBuffer.copyMemory(from: rawBuffer, byteCount: offset)
                    rawBuffer.deallocate()
                    rawBuffer = newBuffer
                    capacity = newCapacity
                }
                rawBuffer.storeBytes(of: UInt8(0x01), toByteOffset: offset, as: UInt8.self)
                offset &+= 1
                rawBuffer.storeBytes(of: UInt32(byteCount).littleEndian, toByteOffset: offset, as: UInt32.self)
                offset &+= 4
                if byteCount > 0 {
                    cellBytes.withUnsafeReadableBytes { src in
                        if let base = src.baseAddress {
                            (rawBuffer + offset).copyMemory(from: base, byteCount: byteCount)
                        }
                    }
                }
                offset &+= byteCount
            } else {
                if offset + 1 > capacity {
                    let newCapacity = max(offset + 1, capacity * 2)
                    let newBuffer = UnsafeMutableRawPointer.allocate(byteCount: newCapacity, alignment: 8)
                    newBuffer.copyMemory(from: rawBuffer, byteCount: offset)
                    rawBuffer.deallocate()
                    rawBuffer = newBuffer
                    capacity = newCapacity
                }
                rawBuffer.storeBytes(of: UInt8(0x00), toByteOffset: offset, as: UInt8.self)
                offset &+= 1
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

        let encoded = Data(bytesNoCopy: rawBuffer, count: offset, deallocator: .custom { ptr, _ in ptr.deallocate() })
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
