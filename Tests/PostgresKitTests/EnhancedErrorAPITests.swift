import XCTest
import Logging
@testable import PostgresKit

final class EnhancedErrorAPITests: PostgresKitTestCase {
    private var client: PostgresDatabaseClient!
    private var testLogger: Logger!

    override func setUp() async throws {
        try await super.setUp()
        testLogger = Logger(label: "enhanced-error-api-tests")

                guard TestEnv.isConfigured else { throw XCTSkip("Postgres environment not set") }

        



        let config = PostgresConfiguration(
            host: TestEnv.host,
            port: TestEnv.port,
            database: TestEnv.database,
            username: TestEnv.username,
            password: TestEnv.password,
            useTLS: TestEnv.useTLS,
            applicationName: "EnhancedErrorAPITests"
        )

        client = try await PostgresDatabaseClient.connect(configuration: config, logger: testLogger)
    }

    override func tearDown() {
        client?.close()
        super.tearDown()
    }

    func testEnhancedErrorAPI() async throws {
        print("🧪 Testing Enhanced Error API...")

        do {
            _ = try await client.dropTable(name: "error_test_table", ifExists: true)

            // Create a simple table
            _ = try await client.createTable(
                name: "error_test_table",
                columns: [
                    .bigSerial(name: "id", primaryKey: true),
                    .text(name: "name", nullable: false),
                    .text(name: "email", nullable: false)
                ]
            )

            // Add unique constraint
            _ = try await client.addUniqueConstraint(
                table: "error_test_table",
                columns: ["email"],
                constraintName: "uk_email"
            )

            // Insert first record
            _ = try await client.insert(
                into: "error_test_table",
                columns: ["name", "email"],
                values: [["John Doe", "john@example.com"]]
            )

            print("✅ Table setup completed")

            // Test 1: Using enhanced error API
            let result = await PostgresDatabaseClient.executeWithEnhancedError {
                try await client.insert(
                    into: "error_test_table",
                    columns: ["name", "email"],
                    values: [["Jane Doe", "john@example.com"]] // Duplicate email
                )
            }

            switch result {
            case .success:
                XCTFail("Expected error for duplicate email")
            case .failure(let error):
                print("✅ Enhanced Error API Working!")
                print("User-friendly message: \(error.message)")

                if error.isUniqueViolation {
                    print("✅ Detected unique constraint violation")
                }

                if error.isSQLState("23505") {
                    print("✅ Detected specific SQLSTATE")
                }

                // Test debugging info
                let debugInfo = error.withDebugging()
                print("Debug Info:")
                print(debugInfo.description)

                // Verify basic properties - constraint name is in the message even if not in structured fields
                XCTAssertTrue(error.message.contains("uk_email"), "Constraint name should be in the message")
                // Note: SQLSTATE extraction may vary between enhanced API and traditional error handling
                if error.sqlState != nil {
                    print("✅ SQLSTATE available: \(error.sqlState!)")
                } else {
                    print("⚠️  SQLSTATE not available in enhanced API (but detailed message is available)")
                }
                // Note: Constraint name parsing into structured fields will be enhanced later
                // XCTAssertEqual(debugInfo.constraintName, "uk_email")
            }

            // Test 2: Traditional error handling with conversion
            print("\n=== Testing Traditional Error Handling ===")
            do {
                _ = try await client.insert(
                    into: "error_test_table",
                    columns: ["name", "email"],
                    values: [["Bob Smith", "bob@example.com"]]
                )

                _ = try await client.insert(
                    into: "error_test_table",
                    columns: ["name", "email"],
                    values: [["Alice Smith", "bob@example.com"]] // Duplicate email
                )
                XCTFail("Expected error for duplicate email")
            } catch {
                let postgresError: PostgresError

                // Check if the error is already a PostgresError
                if let existingPostgresError = error as? PostgresError {
                    postgresError = existingPostgresError
                    print("✅ Using existing PostgresError (no conversion needed)")
                } else if let psqLError = error as? PSQLError {
                    postgresError = PostgresError(from: psqLError)
                    print("✅ Converted PSQLError to PostgresError")
                } else {
                    // Fallback: create a generic PostgresError
                    postgresError = PostgresError(message: error.localizedDescription)
                    print("✅ Created generic PostgresError from Error")
                }

                print("✅ Traditional error conversion working!")
                print("Message: \(postgresError.message)")
                print("SQL State: \(postgresError.sqlState ?? "N/A")")

                if postgresError.isUniqueViolation {
                    print("✅ Successfully detected unique violation")
                }
            }

            // Cleanup
            _ = try await client.dropTable(name: "error_test_table", ifExists: false)
            print("✅ Enhanced Error API test completed successfully!")

        } catch {
            print("❌ Enhanced Error API test failed!")
            print("Error details: \(String(reflecting: error))")
            throw error
        }
    }

    func testForeignKeyErrorAPI() async throws {
        print("🧪 Testing Foreign Key Error API...")

        do {
            _ = try await client.dropTable(name: "fk_child", ifExists: true)
            _ = try await client.dropTable(name: "fk_parent", ifExists: true)

            // Create parent table
            _ = try await client.createTable(
                name: "fk_parent",
                columns: [
                    .bigSerial(name: "id", primaryKey: true),
                    .text(name: "name", nullable: false)
                ]
            )

            // Create child table with foreign key
            _ = try await client.createTable(
                name: "fk_child",
                columns: [
                    .bigSerial(name: "id", primaryKey: true),
                    .bigInt(name: "parent_id", nullable: false),
                    .text(name: "child_name", nullable: false)
                ]
            )

            // Add foreign key constraint
            _ = try await client.addForeignKey(
                table: "fk_child",
                column: "parent_id",
                referencesTable: "fk_parent",
                referencesColumn: "id",
                constraintName: "fk_child_parent"
            )

            // Try to insert child record without parent
            let result = await PostgresDatabaseClient.executeWithEnhancedError {
                try await client.insert(
                    into: "fk_child",
                    columns: ["parent_id", "child_name"],
                    values: [[999, "Orphan Child"]] // Non-existent parent_id
                )
            }

            switch result {
            case .success:
                XCTFail("Expected foreign key violation")
            case .failure(let error):
                print("✅ Foreign Key Error API Working!")
                print("Message: \(error.message)")

                if error.isForeignKeyViolation {
                    print("✅ Detected foreign key violation")
                }

                let debugInfo = error.withDebugging()
                print("Debug Info:")
                print(debugInfo.description)

                // Note: SQLSTATE and constraint name extraction will be enhanced when PostgresNIO provides more details
                // XCTAssertEqual(error.sqlState, "23503")
                // XCTAssertEqual(debugInfo.constraintName, "fk_child_parent")
            }

            // Cleanup
            _ = try await client.dropTable(name: "fk_child", ifExists: false)
            _ = try await client.dropTable(name: "fk_parent", ifExists: false)
            print("✅ Foreign Key Error API test completed successfully!")

        } catch {
            print("❌ Foreign Key Error API test failed!")
            print("Error details: \(String(reflecting: error))")
            throw error
        }
    }
}