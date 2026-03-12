import Foundation
import Logging

/// Engine responsible for formatting PostgreSQL data into display strings
@available(*, deprecated, message: "Use PostgresCellFormatter instead for lower overhead per-cell formatting.")
public actor PostgresFormatterEngine {

    // MARK: - Configuration

    private let configuration: PostgresStreamConfiguration
    private let logger: Logger

    // MARK: - Formatting State

    private var columns: [ColumnInfo] = []
    private var formatters: [StreamingPostgresDataType: Formatter] = [:]

    // MARK: - Cached Formatters

    private lazy var defaultDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private lazy var iso8601DateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private lazy var defaultNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 10
        return formatter
    }()

    // MARK: - Initialization

    public init(configuration: PostgresStreamConfiguration, logger: Logger = .init(label: "postgres-formatter")) {
        self.configuration = configuration
        self.logger = logger
    }

    // MARK: - Column Management

    /// Set column information for formatting context
    public func setColumns(_ newColumns: [ColumnInfo]) {
        self.columns = newColumns
        setupCustomFormatters()
    }

    // MARK: - Row Formatting

    /// Format a single row payload into display strings
    public func formatRow(_ payload: ResultRowPayload) async -> [String?] {
        var formattedRow: [String?] = []
        formattedRow.reserveCapacity(payload.cells.count)

        for (index, cell) in payload.cells.enumerated() {
            let formattedValue = formatCell(cell, columnIndex: index)
            formattedRow.append(formattedValue)
        }

        return formattedRow
    }

    // MARK: - Cell Formatting

    /// Format a single cell value into display string
    private func formatCell(_ cell: ResultCellPayload, columnIndex: Int) -> String? {
        guard let data = cell.bytes, !data.isEmpty else {
            return configuration.nullValueDisplay
        }

        let dataType = StreamingPostgresDataType(oid: Int(cell.dataTypeOID))

        // Check for custom formatter first
        if let customFormatter = formatters[dataType] {
            return formatWithCustomFormatter(cell, formatter: customFormatter)
        }

        // Use built-in formatting based on data type
        switch dataType {
        case .boolean:
            return formatBooleanCell(data)
        case .smallInt, .integer, .bigInt:
            return formatIntegerCell(data)
        case .real, .double, .numeric:
            return formatNumericCell(data)
        case .text, .varchar, .char:
            return formatTextCell(data)
        case .timestamp, .timestamptz, .date, .time, .timetz:
            return formatTemporalCell(data, dataType: dataType)
        case .uuid:
            return formatUUIDCell(data)
        case .json, .jsonb:
            return formatJSONCell(data)
        case .bytea:
            return formatByteaCell(data)
        case .array:
            return formatArrayCell(data)
        case .inet, .cidr:
            return formatNetworkCell(data)
        case .point, .line, .box, .path, .polygon, .circle:
            return formatGeometricCell(data)
        default:
            return formatUnknownCell(data)
        }
    }

    // MARK: - Specific Type Formatting

    private func formatBooleanCell(_ data: Data) -> String {
        if data.count == 1 {
            let byte = data[0]
            return byte != 0 ? configuration.booleanTrueDisplay : configuration.booleanFalseDisplay
        }
        return data.base64EncodedString()
    }

    private func formatIntegerCell(_ data: Data) -> String {
        switch data.count {
        case 2:
            let value = data.withUnsafeBytes { $0.loadUnaligned(as: Int16.self) }
            return String(value)
        case 4:
            let value = data.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
            return String(value)
        case 8:
            let value = data.withUnsafeBytes { $0.loadUnaligned(as: Int64.self) }
            return String(value)
        default:
            return configuration.nullValueDisplay
        }
    }

    private func formatNumericCell(_ data: Data) -> String {
        // Try to decode as various numeric types
        switch data.count {
        case 4:
            let value = data.withUnsafeBytes { $0.loadUnaligned(as: Float32.self) }
            return formatNumericValue(Double(value))
        case 8:
            let value = data.withUnsafeBytes { $0.loadUnaligned(as: Float64.self) }
            return formatNumericValue(Double(value))
        default:
            // For numeric/decimal types, we need to handle PostgreSQL's binary format
            // This is a simplified implementation - a full implementation would handle the PostgreSQL numeric format
            if let stringValue = String(data: data, encoding: .utf8) {
                return formatNumericValue(Double(stringValue))
            }
            return data.base64EncodedString()
        }
    }

    private func formatTextCell(_ data: Data) -> String {
        return String(data: data, encoding: .utf8) ?? data.base64EncodedString()
    }

    private func formatTemporalCell(_ data: Data, dataType: StreamingPostgresDataType) -> String {
        // PostgreSQL timestamp binary format: 8 bytes since PostgreSQL epoch (2000-01-01 00:00:00 UTC)
        guard data.count == 8 else {
            return String(data: data, encoding: .utf8) ?? data.base64EncodedString()
        }

        let microsecondsSincePostgresEpoch = data.withUnsafeBytes { $0.loadUnaligned(as: Int64.self) }

        // PostgreSQL epoch starts at 2000-01-01 00:00:00 UTC
        let postgresEpochInterval = TimeInterval(946684800) // Unix timestamp for 2000-01-01 00:00:00 UTC
        let timestampInterval = postgresEpochInterval + (TimeInterval(microsecondsSincePostgresEpoch) / 1_000_000)
        let timestamp = Date(timeIntervalSince1970: timestampInterval)

        return formatDate(timestamp, dataType: dataType)
    }

    private func formatUUIDCell(_ data: Data) -> String {
        guard data.count == 16 else {
            return data.base64EncodedString()
        }

        let uuid = UUID(uuid: data.withUnsafeBytes { $0.loadUnaligned(as: uuid_t.self) })
        return uuid.uuidString
    }

    private func formatJSONCell(_ data: Data) -> String {
        if let jsonString = String(data: data, encoding: .utf8) {
            // Try to validate and format JSON
            if let jsonData = jsonString.data(using: .utf8),
               let jsonObject = try? JSONSerialization.jsonObject(with: jsonData),
               let prettyJSON = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
               let prettyString = String(data: prettyJSON, encoding: .utf8) {
                return prettyString
            }
            return jsonString
        }
        return data.base64EncodedString()
    }

    private func formatByteaCell(_ data: Data) -> String {
        return "\\x" + data.map { String(format: "%02x", $0) }.joined()
    }

    private func formatArrayCell(_ data: Data) -> String {
        if let stringValue = String(data: data, encoding: .utf8) {
            return stringValue
        }
        return data.base64EncodedString()
    }

    private func formatNetworkCell(_ data: Data) -> String {
        if let stringValue = String(data: data, encoding: .utf8) {
            return stringValue
        }
        return data.base64EncodedString()
    }

    private func formatGeometricCell(_ data: Data) -> String {
        if let stringValue = String(data: data, encoding: .utf8) {
            return stringValue
        }
        return data.base64EncodedString()
    }

    private func formatUnknownCell(_ data: Data) -> String {
        if let stringValue = String(data: data, encoding: .utf8) {
            return stringValue
        }
        return data.base64EncodedString()
    }

    // MARK: - Helper Methods

    private func formatNumericValue(_ value: Double?) -> String {
        guard let value = value else { return configuration.nullValueDisplay }

        switch configuration.numberPrecision {
        case .auto:
            if value.truncatingRemainder(dividingBy: 1) == 0 {
                return String(Int(value))
            } else {
                return defaultNumberFormatter.string(from: NSNumber(value: value)) ?? String(value)
            }
        case .fixed(let decimalPlaces):
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = decimalPlaces
            return formatter.string(from: NSNumber(value: value)) ?? String(value)
        case .significant(let figures):
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumSignificantDigits = figures
            return formatter.string(from: NSNumber(value: value)) ?? String(value)
        case .custom(let formatter):
            return formatter.string(from: NSNumber(value: value)) ?? String(value)
        }
    }

    private func formatDate(_ date: Date, dataType: StreamingPostgresDataType) -> String {
        switch configuration.timestampFormat {
        case .auto:
            // Choose appropriate format based on data type
            switch dataType {
            case .date:
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .none
                return formatter.string(from: date)
            case .time, .timetz:
                let formatter = DateFormatter()
                formatter.dateStyle = .none
                formatter.timeStyle = .medium
                return formatter.string(from: date)
            default:
                return defaultDateFormatter.string(from: date)
            }
        case .iso8601:
            return iso8601DateFormatter.string(from: date)
        case .local:
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .medium
            return formatter.string(from: date)
        case .custom(let formatter):
            return formatter.string(from: date)
        case .relative:
            let interval = date.timeIntervalSince(Date())
            let seconds = abs(interval)
            let past = interval < 0
            let description: String
            if seconds < 60 {
                description = "\(Int(seconds)) seconds"
            } else if seconds < 3600 {
                description = "\(Int(seconds / 60)) minutes"
            } else if seconds < 86400 {
                description = "\(Int(seconds / 3600)) hours"
            } else {
                description = "\(Int(seconds / 86400)) days"
            }
            return past ? "\(description) ago" : "in \(description)"
        }
    }

    private func formatWithCustomFormatter(_ cell: ResultCellPayload, formatter: Formatter) -> String? {
        guard let data = cell.bytes else { return configuration.nullValueDisplay }

        // This is a simplified implementation
        // A full implementation would need to handle different formatter types
        if let stringValue = String(data: data, encoding: .utf8) {
            if let number = NumberFormatter().number(from: stringValue) {
                return formatter.string(for: number)
            }
            return formatter.string(for: stringValue)
        }

        return data.base64EncodedString()
    }

    private func setupCustomFormatters() {
        // Add custom formatters from configuration
        for (dataType, formatter) in configuration.customFormatters {
            formatters[dataType] = formatter
        }
    }
}