import XCTest
@testable import PostgresKit

final class PostgresErrorIntegrationTests: PostgresKitTestCase {

    func testPostgresErrorCreation() throws {
        // Test that PostgresError can be created and has the expected properties
        let errorMessage = "Test error message"
        let postgresError = PostgresError(message: errorMessage)

        XCTAssertEqual(postgresError.message, errorMessage)
        XCTAssertNil(postgresError.sqlState)
        XCTAssertNil(postgresError.severity)
        XCTAssertEqual(postgresError.description, errorMessage)
        XCTAssertFalse(postgresError.isForeignKeyViolation)
        XCTAssertFalse(postgresError.isUniqueViolation)
        XCTAssertFalse(postgresError.isConstraintViolation)
        XCTAssertFalse(postgresError.isDataTypeMismatch)
    }

    func testPostgresErrorWithSQLState() throws {
        // Test PostgresError with SQL state
        let postgresError = PostgresError(
            message: "Unique constraint violation",
            sqlState: "23505",
            severity: "ERROR"
        )

        XCTAssertEqual(postgresError.message, "Unique constraint violation")
        XCTAssertEqual(postgresError.sqlState, "23505")
        XCTAssertEqual(postgresError.severity, "ERROR")
        XCTAssertTrue(postgresError.isUniqueViolation)
        XCTAssertTrue(postgresError.isConstraintViolation)
        XCTAssertFalse(postgresError.isForeignKeyViolation)
        XCTAssertTrue(postgresError.isSQLState("23505"))
        XCTAssertFalse(postgresError.isSQLState("23503"))
    }

    func testPostgresErrorDebugInfo() throws {
        // Test debugging functionality
        let serverInfo = [
            "constraintName": "uk_email",
            "tableName": "users",
            "detail": "Key (email)=(test@example.com) already exists."
        ]

        let postgresError = PostgresError(
            message: "Duplicate key error",
            sqlState: "23505",
            severity: "ERROR",
            serverInfo: serverInfo
        )

        let debugInfo = postgresError.withDebugging()
        XCTAssertEqual(debugInfo.message, "Duplicate key error")
        XCTAssertEqual(debugInfo.sqlState, "23505")
        XCTAssertEqual(debugInfo.constraintName, "uk_email")
        XCTAssertEqual(debugInfo.tableName, "users")
        XCTAssertEqual(debugInfo.detail, "Key (email)=(test@example.com) already exists.")

        // Test that debugInfo.description contains expected information
        let description = debugInfo.description
        XCTAssertTrue(description.contains("Duplicate key error"))
        XCTAssertTrue(description.contains("23505"))
        XCTAssertTrue(description.contains("uk_email"))
        XCTAssertTrue(description.contains("users"))
    }

    func testResultExtensions() throws {
        // Test Result extensions for PostgresError
        let successResult: Result<String, PostgresError> = .success("test")
        let failureResult: Result<String, PostgresError> = .failure(
            PostgresError(message: "Test error", sqlState: "23505")
        )

        XCTAssertEqual(successResult.errorMessage, "No error")
        XCTAssertFalse(successResult.isConstraintViolation)
        XCTAssertFalse(successResult.isSQLState("23505"))

        XCTAssertEqual(failureResult.errorMessage, "Test error")
        XCTAssertTrue(failureResult.isConstraintViolation)
        XCTAssertTrue(failureResult.isSQLState("23505"))
    }

    func testForeignViolationError() throws {
        // Test foreign key violation error
        let foreignKeyError = PostgresError(
            message: "Foreign key violation",
            sqlState: "23503",
            severity: "ERROR"
        )

        XCTAssertTrue(foreignKeyError.isForeignKeyViolation)
        XCTAssertTrue(foreignKeyError.isConstraintViolation)
        XCTAssertFalse(foreignKeyError.isUniqueViolation)
        XCTAssertTrue(foreignKeyError.isSQLState("23503"))
        XCTAssertFalse(foreignKeyError.isSQLState("23505"))
    }

    func testDataTypeMismatchError() throws {
        // Test data type mismatch error
        let typeError = PostgresError(
            message: "Data type mismatch",
            sqlState: "42804",
            severity: "ERROR"
        )

        XCTAssertTrue(typeError.isDataTypeMismatch)
        XCTAssertFalse(typeError.isConstraintViolation) // 42xxx class is not constraint violation
        XCTAssertFalse(typeError.isForeignKeyViolation)
        XCTAssertFalse(typeError.isUniqueViolation)
        XCTAssertTrue(typeError.isSQLState("42804"))
    }
}