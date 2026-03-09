import XCTest
import Logging
@testable import PostgresKit

final class ErrorHandlingIntegrationTest: XCTestCase {
    private var client: PostgresDatabaseClient!
    private var testLogger: Logger!

    override func setUp() async throws {
        try await super.setUp()
        testLogger = Logger(label: "error-handling-integration-test")

                guard let host = ProcessInfo.processInfo.environment["POSTGRES_HOST"],

                      let user = ProcessInfo.processInfo.environment["POSTGRES_USERNAME"],

                      let db = ProcessInfo.processInfo.environment["POSTGRES_DATABASE"],

                      let portStr = ProcessInfo.processInfo.environment["POSTGRES_PORT"],

                      let port = Int(portStr)

                else {

                    throw XCTSkip("POSTGRES_* environment not set; skipping integration test")

                }

        

                let password = ProcessInfo.processInfo.environment["POSTGRES_PASSWORD"]

                let useTLS = (ProcessInfo.processInfo.environment["POSTGRES_TLS"] ?? "false").lowercased() == "true"

        let config = PostgresConfiguration(
            host: host,
            port: port,
            database: db,
            username: user,
            password: password,
            useTLS: useTLS,
            applicationName: "ErrorHandlingIntegrationTest"
        )

        client = try await PostgresDatabaseClient.connect(configuration: config, logger: testLogger)
    }

    override func tearDown() {
        client?.close()
        super.tearDown()
    }

    func testPostgresErrorIsThrown() async throws {
        print("🧪 Testing PostgresError integration...")

        do {
            // Clean up first
            _ = try await client.dropTable(name: "error_test", ifExists: true)

            // Create a simple table
            _ = try await client.createTable(
                name: "error_test",
                columns: [
                    .bigSerial(name: "id", primaryKey: true),
                    .text(name: "email", nullable: false)
                ]
            )

            // Add unique constraint
            _ = try await client.addUniqueConstraint(
                table: "error_test",
                columns: ["email"],
                constraintName: "uk_email_test"
            )

            // Insert first record
            _ = try await client.insert(
                into: "error_test",
                columns: ["email"],
                values: [["test@example.com"]]
            )

            print("✅ First record inserted successfully")

            // Try to insert duplicate record - this should throw PostgresError
            do {
                _ = try await client.insert(
                    into: "error_test",
                    columns: ["email"],
                    values: [["test@example.com"]] // Duplicate email
                )
                XCTFail("Expected error for duplicate email")
            } catch {
                print("🔍 Error caught: \(type(of: error))")
                print("🔍 Error description: \(error.localizedDescription)")

                // This should be our PostgresError, not PSQLError
                XCTAssertTrue(error is PostgresKit.PostgresError, "Expected PostgresKit.PostgresError, got \(type(of: error))")

                if let postgresError = error as? PostgresKit.PostgresError {
                    print("✅ SUCCESS: Got PostgresKitError!")
                    print("Message: \(postgresError.message)")

                    // Check if we can detect the constraint violation
                    if postgresError.isUniqueViolation {
                        print("✅ Successfully detected unique violation")
                    }

                    // Test debugging info
                    let debugInfo = postgresError.withDebugging()
                    print("Debug info:")
                    print(debugInfo.description)
                } else {
                    XCTFail("Expected PostgresKitError but got \(type(of: error))")
                }
            }

            // Cleanup
            _ = try await client.dropTable(name: "error_test", ifExists: false)
            print("✅ PostgresError integration test completed successfully!")

        } catch {
            print("❌ PostgresError integration test failed!")
            print("Error details: \(String(reflecting: error))")
            throw error
        }
    }
}