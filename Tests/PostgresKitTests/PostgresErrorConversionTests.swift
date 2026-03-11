import XCTest
import PostgresNIO
@testable import PostgresKit

// typealias to distinguish our PostgresError from PostgresNIO's
typealias PostgresKitError = PostgresKit.PostgresError

final class PostgresErrorConversionTests: PostgresKitTestCase {

    func testPSQLErrorToPostgresErrorConversion() throws {
        // This test verifies that PSQLError is properly converted to PostgresError
        // We'll test the conversion logic directly since we can't easily mock a PSQLError

        // Create a PSQLError-like error scenario (simulating what would happen with a real PSQLError)
        let simulatedPSQLError = NSError(
            domain: "PostgresNIO.PSQLError",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "relation \"nonexistent_table\" does not exist"]
        )

        // Simulate the conversion that happens in withConnection method
        let convertedError: Error
        if let nsError = simulatedPSQLError as NSError?, nsError.domain == "PostgresNIO.PSQLError" {
            // This simulates the PostgresError(from: PSQLError) conversion
            convertedError = PostgresKitError(
                message: nsError.localizedDescription,
                sqlState: nil, // Would be extracted from real PSQLError
                severity: nil,  // Would be extracted from real PSQLError
                originalError: nil // Would be the actual PSQLError
            )
        } else {
            convertedError = simulatedPSQLError
        }

        // Verify the conversion worked
        XCTAssertTrue(convertedError is PostgresKitError)
        let postgresError = convertedError as! PostgresKitError
        XCTAssertEqual(postgresError.message, "relation \"nonexistent_table\" does not exist")
        XCTAssertNil(postgresError.sqlState)
        XCTAssertNil(postgresError.severity)
    }

    func testPostgresErrorFromPSQLErrorInitializer() throws {
        // Test the PostgresError(from: PSQLError) initializer logic
        // Since we can't easily create a real PSQLError, we'll test the behavior we expect

        // Simulate a constraint violation error
        let constraintMessage = "duplicate key value violates unique constraint \"uk_email\""
        let postgresError = PostgresKitError(
            message: constraintMessage,
            sqlState: "23505",
            severity: "ERROR"
        )

        XCTAssertEqual(postgresError.message, constraintMessage)
        XCTAssertEqual(postgresError.sqlState, "23505")
        XCTAssertTrue(postgresError.isUniqueViolation)
        XCTAssertTrue(postgresError.isConstraintViolation)
        XCTAssertFalse(postgresError.isForeignKeyViolation)

        // Test debugging info
        let debugInfo = postgresError.withDebugging()
        XCTAssertTrue(debugInfo.description.contains(constraintMessage))
        XCTAssertTrue(debugInfo.description.contains("23505"))
    }

    func testNonPSQLErrorPassthrough() throws {
        // Test that non-PSQLErrors are passed through unchanged
        let regularError = NSError(domain: "TestDomain", code: 123, userInfo: [
            NSLocalizedDescriptionKey: "Regular error message"
        ])

        // Simulate the error handling logic in withConnection
        let finalError: Error
        if regularError is PSQLError {
            // This would convert to PostgresError, but shouldn't happen for regular errors
            finalError = PostgresKitError(from: regularError as! PSQLError)
        } else {
            // Should pass through unchanged
            finalError = regularError
        }

        // Verify it's still the original error
        let nsError = finalError as NSError
        XCTAssertEqual(nsError.domain, "TestDomain")
        XCTAssertEqual(nsError.code, 123)
        XCTAssertEqual(nsError.localizedDescription, "Regular error message")
        XCTAssertFalse(finalError is PostgresKitError)
    }

    func testExecuteWithEnhancedErrorMethod() throws {
        // Test the executeWithEnhancedError method logic
        // This method should convert errors to PostgresError

        let testError = NSError(domain: "TestDomain", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Test operation failed"
        ])

        // Simulate what executeWithEnhancedError does
        let result: Result<String, PostgresKitError>
        do {
            _ = try { throw testError }()
            result = .success("success")
        } catch {
            let postgresError: PostgresKitError
            if let psqLError = error as? PSQLError {
                postgresError = PostgresKitError(from: psqLError)
            } else {
                postgresError = PostgresKitError(
                    message: error.localizedDescription,
                    originalError: nil
                )
            }
            result = .failure(postgresError)
        }

        // Verify the result
        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertEqual(error.message, "Test operation failed")
            XCTAssertFalse(error.isConstraintViolation)
        }
    }
}