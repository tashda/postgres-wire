import Foundation
import PostgresNIO

/// Enhanced PostgreSQL error handling with user-friendly API
public struct PostgresError: Error, CustomStringConvertible, Sendable {

    // MARK: - Public Properties

    /// User-friendly error message
    public let message: String

    /// SQL state code (optional for advanced users)
    public let sqlState: String?

    /// Severity level (optional for advanced users)
    public let severity: String?

    // MARK: - Internal Properties

    /// Full server information (available through withDebugging())
    internal let serverInfo: [String: String]?

    /// Original PSQLError (kept for compatibility)
    internal let originalError: PSQLError?

    // MARK: - Initialization

    internal init(
        message: String,
        sqlState: String? = nil,
        severity: String? = nil,
        serverInfo: [String: String]? = nil,
        originalError: PSQLError? = nil
    ) {
        self.message = message
        self.sqlState = sqlState
        self.severity = severity
        self.serverInfo = serverInfo
        self.originalError = originalError
    }

    /// Create from PSQLError with enhanced parsing
    internal init(from psqLError: PSQLError) {
        self.originalError = psqLError

        if let serverInfo = psqLError.serverInfo {
            self.sqlState = serverInfo[.sqlState]
            self.severity = serverInfo[.severity]

            // Build detailed message with constraint and table information
            var detailedMessage = serverInfo[.message] ?? psqLError.localizedDescription

            // Add constraint name if available
            if let constraintName = serverInfo[.constraintName] {
                detailedMessage += " (constraint: \(constraintName))"
            }

            // Add table name if available and constraint is not specified
            if serverInfo[.constraintName] == nil, let tableName = serverInfo[.tableName] {
                detailedMessage += " (table: \(tableName))"
            }

            // Add detail message if available
            if let detail = serverInfo[.detail], !detail.isEmpty {
                detailedMessage += " - \(detail)"
            }

            self.message = detailedMessage

            // a bit of a hack to get all the fields
            self.serverInfo = [
                "detail": serverInfo[.detail],
                "hint": serverInfo[.hint],
                "internalQuery": serverInfo[.internalQuery],
                "locationContext": serverInfo[.locationContext],
                "schemaName": serverInfo[.schemaName],
                "tableName": serverInfo[.tableName],
                "columnName": serverInfo[.columnName],
                "dataTypeName": serverInfo[.dataTypeName],
                "constraintName": serverInfo[.constraintName],
                "file": serverInfo[.file],
                "line": serverInfo[.line],
                "routine": serverInfo[.routine],
            ].compactMapValues { $0 }
        } else {
            // No serverInfo — this is a connection-level, TLS, or protocol error.
            // PSQLError.description deliberately returns a generic message to prevent
            // data leakage, so we must extract the real information from the error's
            // code and underlying cause.
            self.sqlState = nil
            self.severity = nil
            self.serverInfo = nil
            self.message = Self.extractMessage(from: psqLError)
        }
    }

    /// Extract a human-readable message from a PSQLError that has no serverInfo.
    ///
    /// PSQLError's `description` is intentionally generic ("PSQLError – Generic description
    /// to prevent accidental leakage..."), so we inspect the error code and underlying cause
    /// to produce something useful for end users.
    private static func extractMessage(from error: PSQLError) -> String {
        let underlying = error.underlying

        switch error.code {
        case .connectionError:
            return Self.describeConnectionError(underlying)

        case .failedToAddSSLHandler:
            if let underlying {
                return "TLS error: \(Self.underlyingDescription(underlying))"
            }
            return "Failed to establish a TLS connection to the server."

        case .sslUnsupported:
            return "The server does not support SSL/TLS connections."

        case .receivedUnencryptedDataAfterSSLRequest:
            return "Received unencrypted data after requesting an SSL connection."

        case .authMechanismRequiresPassword:
            return "The server requires a password but none was provided."

        case .unsupportedAuthMechanism:
            return "The server requested an authentication mechanism that is not supported."

        case .saslError:
            if let underlying {
                return "Authentication failed: \(Self.underlyingDescription(underlying))"
            }
            return "SASL authentication failed."

        case .serverClosedConnection:
            if let underlying {
                return "The server closed the connection: \(Self.underlyingDescription(underlying))"
            }
            return "The server closed the connection unexpectedly."

        case .clientClosedConnection:
            return "The connection was closed by the client."

        case .uncleanShutdown:
            return "The connection was shut down unexpectedly."

        case .queryCancelled:
            return "The query was cancelled."

        case .tooManyParameters:
            return "Too many parameters in the query."

        case .poolClosed:
            return "The connection pool has been closed."

        case .messageDecodingFailure:
            if let underlying {
                return "Failed to decode a message from the server: \(Self.underlyingDescription(underlying))"
            }
            return "Failed to decode a message from the server."

        case .unexpectedBackendMessage:
            return "Received an unexpected message from the server."

        case .invalidCommandTag:
            return "The server returned an invalid command tag."

        default:
            // Fallback: use the debug description which contains the real details
            if let underlying {
                return Self.underlyingDescription(underlying)
            }
            return String(reflecting: error)
        }
    }

    /// Produce a human-readable description of a connection error's underlying cause.
    private static func describeConnectionError(_ underlying: (any Error)?) -> String {
        guard let underlying else {
            return "Could not connect to the server."
        }

        // IOError has errnoCode — use it directly for reliable matching
        if let ioError = underlying as? IOError {
            return describeIOError(ioError)
        }

        let desc = String(describing: underlying).lowercased()

        // ChannelError — typically connect timeout
        if desc.contains("channelerror") || desc.contains("connecttimeout") {
            return "Connection timed out. The server may be unreachable."
        }

        // DNS resolution failures
        if desc.contains("name or service not known")
            || desc.contains("nodename nor servname provided")
            || desc.contains("could not resolve")
            || desc.contains("getaddrinfo")
            || desc.contains("no such host") {
            return "Could not resolve hostname. Check the server address."
        }

        if desc.contains("connection refused") {
            return "Connection refused. The server may not be running or the port may be wrong."
        }

        if desc.contains("timed out") || desc.contains("timeout") {
            return "Connection timed out. The server may be unreachable."
        }

        if desc.contains("network is unreachable") || desc.contains("no route to host") {
            return "Network is unreachable."
        }

        return "Could not connect to the server: \(String(describing: underlying))"
    }

    /// Translate IOError errno codes into user-friendly messages.
    private static func describeIOError(_ error: IOError) -> String {
        switch error.errnoCode {
        case 1:  // EPERM
            return "Connection failed. The server may not be running or the address is unreachable."
        case 13: // EACCES
            return "Permission denied when connecting to the server."
        case 51: // ENETUNREACH
            return "Network is unreachable."
        case 60: // ETIMEDOUT
            return "Connection timed out. The server may be unreachable."
        case 61: // ECONNREFUSED
            return "Connection refused. The server may not be running or the port may be wrong."
        case 64: // EHOSTDOWN
            return "The server appears to be down."
        case 65: // EHOSTUNREACH
            return "No route to host. The server may be unreachable."
        default:
            return "Connection failed: \(String(describing: error))"
        }
    }

    /// Get a useful string from an underlying error, preferring localizedDescription
    /// but falling back to the debug representation if the localized one is generic/empty.
    private static func underlyingDescription(_ error: any Error) -> String {
        let localized = error.localizedDescription
        // If localizedDescription is useful (not just the type name pattern), use it
        // Otherwise fall back to reflecting
        if localized.contains("PSQLError") && localized.contains("Generic description") {
            return String(reflecting: error)
        }
        return localized
    }



    /// Convert any error thrown during a Postgres operation into a PostgresError.
    /// Handles PSQLError (with and without serverInfo), NSError wrappers, and
    /// arbitrary Swift errors.
    internal static func from(_ error: any Error) -> PostgresError {
        if let psqlError = error as? PSQLError {
            return PostgresError(from: psqlError)
        }
        if let postgresError = error as? PostgresError {
            return postgresError
        }
        if let ioError = error as? IOError {
            return PostgresError(message: describeIOError(ioError))
        }
        // Produce a useful message from the underlying error
        let description = error.localizedDescription
        return PostgresError(message: description)
    }

    /// Create custom protocol error (for legacy compatibility)
    internal static func protocolError(_ message: String) -> PostgresError {
        return PostgresError(message: message)
    }

    /// Create encoding error
    internal static func encodingError(message: String, type: Any.Type) -> PostgresError {
        return PostgresError(message: message)
    }

    /// Create encoding error
    internal static func encodingError(type: Any.Type) -> PostgresError {
        return PostgresError(message: "Could not encode value of type \(type) to PGData")
    }

    // MARK: - Public API

    /// Get detailed debugging information
    /// - Returns: Complete error details including server info, constraint names, etc.
    public func withDebugging() -> PostgresErrorDebugInfo {
        return PostgresErrorDebugInfo(
            message: message,
            sqlState: sqlState,
            severity: severity,
            serverInfo: serverInfo ?? [:],
            originalError: originalError
        )
    }

    /// Check if this is a specific type of SQL error
    /// - Parameter sqlState: SQLSTATE code to check against
    /// - Returns: true if the error matches the given SQLSTATE
    public func isSQLState(_ sqlState: String) -> Bool {
        return self.sqlState == sqlState
    }

    /// Check if this is a constraint violation error
    public var isConstraintViolation: Bool {
        return sqlState?.hasPrefix("23") == true
    }

    /// Check if this is a foreign key violation error
    public var isForeignKeyViolation: Bool {
        return sqlState == "23503"
    }

    /// Check if this is a unique constraint violation error
    public var isUniqueViolation: Bool {
        return sqlState == "23505"
    }

    /// Check if this is a data type mismatch error
    public var isDataTypeMismatch: Bool {
        return sqlState == "42804"
    }

    // MARK: - CustomStringConvertible

    public var description: String {
        return message
    }
}

// MARK: - LocalizedError

extension PostgresError: LocalizedError {
    public var errorDescription: String? {
        return message
    }

    public var failureReason: String? {
        return message
    }

    public var recoverySuggestion: String? {
        if isForeignKeyViolation {
            return "Ensure the referenced key exists in the parent table"
        } else if isUniqueViolation {
            return "Ensure the values are unique within the constraint"
        } else if isConstraintViolation {
            return "Check that the data satisfies all constraint requirements"
        }
        return nil
    }

    public var helpAnchor: String? {
        if let sqlState = sqlState {
            return "https://www.postgresql.org/docs/current/errcodes-appendix.html#ERRCODES-\(sqlState)"
        }
        return nil
    }
}

/// Detailed debugging information for PostgreSQL errors
public struct PostgresErrorDebugInfo: CustomStringConvertible, Sendable {
    public let message: String
    public let sqlState: String?
    public let severity: String?
    public let serverInfo: [String: String]
    public let originalError: PSQLError?

    // MARK: - Convenience Properties

    /// Constraint name if available
    public var constraintName: String? {
        return serverInfo["constraintName"]
    }

    /// Table name if available
    public var tableName: String? {
        return serverInfo["tableName"]
    }

    /// Schema name if available
    public var schemaName: String? {
        return serverInfo["schemaName"]
    }

    /// Detail message if available
    public var detail: String? {
        return serverInfo["detail"]
    }

    /// Hint if available
    public var hint: String? {
        return serverInfo["hint"]
    }

    // MARK: - CustomStringConvertible

    public var description: String {
        var result = "PostgresErrorDebugInfo:\n"
        result += "  Message: \(message)\n"

        if let sqlState = sqlState {
            result += "  SQL State: \(sqlState)\n"
        }

        if let severity = severity {
            result += "  Severity: \(severity)\n"
        }

        if let constraintName = constraintName {
            result += "  Constraint: \(constraintName)\n"
        }

        if let tableName = tableName {
            result += "  Table: \(tableName)\n"
        }

        if let schemaName = schemaName {
            result += "  Schema: \(schemaName)\n"
        }

        if let detail = detail {
            result += "  Detail: \(detail)\n"
        }

        if let hint = hint {
            result += "  Hint: \(hint)\n"
        }

        if !serverInfo.isEmpty {
            result += "  Server Info: \(serverInfo)\n"
        }

        return result
    }
}

// MARK: - Error Handling Extensions

extension PostgresDatabaseClient {

    /// Execute operation with enhanced error handling
    /// - Parameter operation: Async operation to perform
    /// - Returns: Result with PostgresError on failure
    public static func executeWithEnhancedError<T>(
        _ operation: () async throws -> T
    ) async -> Result<T, PostgresError> {
        do {
            let result = try await operation()
            return .success(result)
        } catch {
            return .failure(PostgresError.from(error))
        }
    }
}

// MARK: - Result Type Helpers

extension Result where Failure == PostgresError {

    /// Get user-friendly error message
    public var errorMessage: String {
        switch self {
        case .success:
            return "No error"
        case .failure(let error):
            return error.message
        }
    }

    /// Check if error is a specific SQL state
    public func isSQLState(_ sqlState: String) -> Bool {
        switch self {
        case .success:
            return false
        case .failure(let error):
            return error.isSQLState(sqlState)
        }
    }

    /// Check if error is a constraint violation
    public var isConstraintViolation: Bool {
        switch self {
        case .success:
            return false
        case .failure(let error):
            return error.isConstraintViolation
        }
    }
}