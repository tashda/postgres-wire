import XCTest
@testable import PostgresKit

/// Unit tests for PostgresError creation, conversion, SQL state detection,
/// constraint violation helpers, and debugging info. No database required.
final class ErrorConversionTests: PostgresKitTestCase {

    // MARK: - Error Creation

    func testBasicErrorCreation() throws {
        let error = PostgresError(message: "Test error message")
        XCTAssertEqual(error.message, "Test error message")
        XCTAssertNil(error.sqlState)
        XCTAssertNil(error.severity)
        XCTAssertEqual(error.description, "Test error message")
        XCTAssertFalse(error.isForeignKeyViolation)
        XCTAssertFalse(error.isUniqueViolation)
        XCTAssertFalse(error.isConstraintViolation)
        XCTAssertFalse(error.isDataTypeMismatch)
    }

    func testErrorWithSQLState() throws {
        let error = PostgresError(
            message: "Unique constraint violation",
            sqlState: "23505",
            severity: "ERROR"
        )
        XCTAssertEqual(error.message, "Unique constraint violation")
        XCTAssertEqual(error.sqlState, "23505")
        XCTAssertEqual(error.severity, "ERROR")
    }

    // MARK: - SQL State Detection

    func testUniqueViolationDetection() throws {
        let error = PostgresError(message: "duplicate key", sqlState: "23505", severity: "ERROR")
        XCTAssertTrue(error.isUniqueViolation)
        XCTAssertTrue(error.isConstraintViolation)
        XCTAssertFalse(error.isForeignKeyViolation)
        XCTAssertTrue(error.isSQLState("23505"))
        XCTAssertFalse(error.isSQLState("23503"))
    }

    func testForeignKeyViolationDetection() throws {
        let error = PostgresError(message: "Foreign key violation", sqlState: "23503", severity: "ERROR")
        XCTAssertTrue(error.isForeignKeyViolation)
        XCTAssertTrue(error.isConstraintViolation)
        XCTAssertFalse(error.isUniqueViolation)
        XCTAssertTrue(error.isSQLState("23503"))
    }

    func testRestrictViolationDetection() throws {
        let error = PostgresError(message: "Restrict violation", sqlState: "23001", severity: "ERROR")
        XCTAssertTrue(error.isForeignKeyViolation)
        XCTAssertTrue(error.isConstraintViolation)
        XCTAssertFalse(error.isUniqueViolation)
        XCTAssertTrue(error.isSQLState("23001"))
    }

    func testDataTypeMismatchDetection() throws {
        let error = PostgresError(message: "Data type mismatch", sqlState: "42804", severity: "ERROR")
        XCTAssertTrue(error.isDataTypeMismatch)
        XCTAssertFalse(error.isConstraintViolation)
        XCTAssertFalse(error.isForeignKeyViolation)
        XCTAssertFalse(error.isUniqueViolation)
        XCTAssertTrue(error.isSQLState("42804"))
    }

    // MARK: - Debug Info

    func testDebugInfoWithServerInfo() throws {
        let serverInfo = [
            "constraintName": "uk_email",
            "tableName": "users",
            "detail": "Key (email)=(test@example.com) already exists."
        ]
        let error = PostgresError(
            message: "Duplicate key error",
            sqlState: "23505",
            severity: "ERROR",
            serverInfo: serverInfo
        )

        let debugInfo = error.withDebugging()
        XCTAssertEqual(debugInfo.message, "Duplicate key error")
        XCTAssertEqual(debugInfo.sqlState, "23505")
        XCTAssertEqual(debugInfo.constraintName, "uk_email")
        XCTAssertEqual(debugInfo.tableName, "users")
        XCTAssertEqual(debugInfo.detail, "Key (email)=(test@example.com) already exists.")

        let description = debugInfo.description
        XCTAssertTrue(description.contains("Duplicate key error"))
        XCTAssertTrue(description.contains("23505"))
        XCTAssertTrue(description.contains("uk_email"))
        XCTAssertTrue(description.contains("users"))
    }

    func testDebugInfoWithoutServerInfo() throws {
        let error = PostgresError(message: "Simple error")
        let debugInfo = error.withDebugging()
        XCTAssertEqual(debugInfo.message, "Simple error")
        XCTAssertNil(debugInfo.sqlState)
    }

    // MARK: - PSQLError Conversion

    func testPSQLErrorConversionSimulation() throws {
        // Simulate the conversion that happens in withConnection
        let simulatedPSQLError = NSError(
            domain: "PostgresNIO.PSQLError",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "relation \"nonexistent_table\" does not exist"]
        )

        let convertedError: Error
        if let nsError = simulatedPSQLError as NSError?, nsError.domain == "PostgresNIO.PSQLError" {
            convertedError = PostgresError(
                message: nsError.localizedDescription,
                sqlState: nil,
                severity: nil,
                originalError: nil
            )
        } else {
            convertedError = simulatedPSQLError
        }

        XCTAssertTrue(convertedError is PostgresError)
        let postgresError = convertedError as! PostgresError
        XCTAssertEqual(postgresError.message, "relation \"nonexistent_table\" does not exist")
    }

    func testNonPSQLErrorPassthrough() throws {
        let regularError = NSError(domain: "TestDomain", code: 123, userInfo: [
            NSLocalizedDescriptionKey: "Regular error message"
        ])

        let finalError: Error
        if regularError is PSQLError {
            finalError = PostgresError(from: regularError as! PSQLError)
        } else {
            finalError = regularError
        }

        let nsError = finalError as NSError
        XCTAssertEqual(nsError.domain, "TestDomain")
        XCTAssertEqual(nsError.code, 123)
        XCTAssertFalse(finalError is PostgresError)
    }

    // MARK: - Result Extensions

    func testResultExtensionsSuccess() throws {
        let result: Result<String, PostgresError> = .success("test")
        XCTAssertEqual(result.errorMessage, "No error")
        XCTAssertFalse(result.isConstraintViolation)
        XCTAssertFalse(result.isSQLState("23505"))
    }

    func testResultExtensionsFailure() throws {
        let result: Result<String, PostgresError> = .failure(
            PostgresError(message: "Test error", sqlState: "23505")
        )
        XCTAssertEqual(result.errorMessage, "Test error")
        XCTAssertTrue(result.isConstraintViolation)
        XCTAssertTrue(result.isSQLState("23505"))
    }

    // MARK: - executeWithEnhancedError

    func testExecuteWithEnhancedErrorSimulation() throws {
        let testError = NSError(domain: "TestDomain", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Test operation failed"
        ])

        let result: Result<String, PostgresError>
        do {
            _ = try { throw testError }()
            result = .success("success")
        } catch {
            let postgresError: PostgresError
            if let psqLError = error as? PSQLError {
                postgresError = PostgresError(from: psqLError)
            } else {
                postgresError = PostgresError(message: error.localizedDescription, originalError: nil)
            }
            result = .failure(postgresError)
        }

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertEqual(error.message, "Test operation failed")
            XCTAssertFalse(error.isConstraintViolation)
        }
    }
}
