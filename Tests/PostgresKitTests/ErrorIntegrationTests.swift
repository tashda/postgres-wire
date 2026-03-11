import XCTest
import Logging
@testable import PostgresKit

/// Integration tests for PostgresError with real database operations.
/// Tests unique violations, FK violations, syntax errors, and the
/// executeWithEnhancedError API against a live database.
final class ErrorIntegrationTests: PostgresKitTestCase {
    private var client: PostgresDatabaseClient!

    override func setUp() async throws {
        try await super.setUp()
        guard TestEnv.isConfigured else { throw XCTSkip("Postgres environment not set") }
        let config = PostgresConfiguration(
            host: TestEnv.host, port: TestEnv.port,
            database: TestEnv.database, username: TestEnv.username,
            password: TestEnv.password, useTLS: TestEnv.useTLS,
            applicationName: "ErrorIntegrationTests"
        )
        client = try await PostgresDatabaseClient.connect(configuration: config, logger: Logger(label: "error-integration-tests"))
    }

    override func tearDown() {
        client?.close()
        super.tearDown()
    }

    private func uniqueName(_ prefix: String = "err") -> String {
        "\(prefix)_\(UInt32.random(in: 0..<UInt32.max))"
    }

    // MARK: - Unique Violation via Real INSERT

    func testUniqueViolationThrowsPostgresError() async throws {
        let table = uniqueName()
        defer { Task { [client = self.client!] in _ = try? await client.dropTable(name: table, ifExists: true) } }

        _ = try await client.createTable(name: table, columns: [
            .bigSerial(name: "id", primaryKey: true),
            .text(name: "email", nullable: false)
        ])
        _ = try await client.addUniqueConstraint(table: table, columns: ["email"], constraintName: "\(table)_uk")

        _ = try await client.insert(into: table, columns: ["email"], values: [["test@example.com"]])

        do {
            _ = try await client.insert(into: table, columns: ["email"], values: [["test@example.com"]])
            XCTFail("Expected error for duplicate email")
        } catch {
            XCTAssertTrue(error is PostgresError, "Expected PostgresError, got \(type(of: error))")
            if let pgError = error as? PostgresError {
                XCTAssertTrue(pgError.isUniqueViolation, "Should detect unique violation")
                let debugInfo = pgError.withDebugging()
                XCTAssertFalse(debugInfo.description.isEmpty)
            }
        }
    }

    // MARK: - Foreign Key Violation via Real INSERT

    func testForeignKeyViolationThrowsPostgresError() async throws {
        let parent = uniqueName("parent")
        let child = uniqueName("child")
        defer { Task { [client = self.client!] in
            _ = try? await client.dropTable(name: child, ifExists: true)
            _ = try? await client.dropTable(name: parent, ifExists: true)
        }}

        _ = try await client.createTable(name: parent, columns: [
            .bigSerial(name: "id", primaryKey: true),
            .text(name: "name", nullable: false)
        ])
        _ = try await client.createTable(name: child, columns: [
            .bigSerial(name: "id", primaryKey: true),
            .bigInt(name: "parent_id", nullable: false),
            .text(name: "value")
        ])
        _ = try await client.addForeignKey(
            table: child, column: "parent_id",
            referencesTable: parent, referencesColumn: "id",
            constraintName: "\(child)_fk"
        )

        do {
            _ = try await client.insert(into: child, columns: ["parent_id", "value"], values: [[999, "Orphan"]])
            XCTFail("Expected foreign key violation")
        } catch {
            XCTAssertTrue(error is PostgresError, "Expected PostgresError, got \(type(of: error))")
            if let pgError = error as? PostgresError {
                XCTAssertTrue(pgError.isForeignKeyViolation, "Should detect FK violation")
            }
        }
    }

    // MARK: - Syntax Error

    func testSyntaxErrorThrowsPostgresError() async throws {
        do {
            _ = try await client.simpleQuery("SELEKT 1")
            XCTFail("Expected syntax error")
        } catch {
            XCTAssertTrue(error is PostgresError, "Expected PostgresError, got \(type(of: error))")
            if let pgError = error as? PostgresError {
                XCTAssertFalse(pgError.isConstraintViolation)
            }
        }
    }

    // MARK: - Nonexistent Table Error

    func testNonexistentTableError() async throws {
        let fakeName = uniqueName("nonexistent")
        do {
            _ = try await client.simpleQuery("SELECT * FROM \(fakeName)")
            XCTFail("Expected error for nonexistent table")
        } catch {
            XCTAssertTrue(error is PostgresError, "Expected PostgresError, got \(type(of: error))")
        }
    }

    // MARK: - executeWithEnhancedError API

    func testExecuteWithEnhancedErrorUniqueViolation() async throws {
        let table = uniqueName()
        defer { Task { [client = self.client!] in _ = try? await client.dropTable(name: table, ifExists: true) } }

        _ = try await client.createTable(name: table, columns: [
            .bigSerial(name: "id", primaryKey: true),
            .text(name: "name", nullable: false),
            .text(name: "email", nullable: false)
        ])
        _ = try await client.addUniqueConstraint(table: table, columns: ["email"], constraintName: "\(table)_uk")

        _ = try await client.insert(into: table, columns: ["name", "email"], values: [["John", "john@example.com"]])

        let result = await PostgresDatabaseClient.executeWithEnhancedError {
            try await client.insert(
                into: table,
                columns: ["name", "email"],
                values: [["Jane", "john@example.com"]]
            )
        }

        switch result {
        case .success:
            XCTFail("Expected error for duplicate email")
        case .failure(let error):
            XCTAssertTrue(error.isUniqueViolation || error.message.contains("uk_"), "Should detect unique violation")
            let debugInfo = error.withDebugging()
            XCTAssertFalse(debugInfo.description.isEmpty)
        }
    }

    func testExecuteWithEnhancedErrorForeignKeyViolation() async throws {
        let parent = uniqueName("parent")
        let child = uniqueName("child")
        defer { Task { [client = self.client!] in
            _ = try? await client.dropTable(name: child, ifExists: true)
            _ = try? await client.dropTable(name: parent, ifExists: true)
        }}

        _ = try await client.createTable(name: parent, columns: [
            .bigSerial(name: "id", primaryKey: true),
            .text(name: "name", nullable: false)
        ])
        _ = try await client.createTable(name: child, columns: [
            .bigSerial(name: "id", primaryKey: true),
            .bigInt(name: "parent_id", nullable: false),
            .text(name: "value")
        ])
        _ = try await client.addForeignKey(
            table: child, column: "parent_id",
            referencesTable: parent, referencesColumn: "id",
            constraintName: "\(child)_fk"
        )

        let result = await PostgresDatabaseClient.executeWithEnhancedError {
            try await client.insert(into: child, columns: ["parent_id", "value"], values: [[999, "Orphan"]])
        }

        switch result {
        case .success:
            XCTFail("Expected foreign key violation")
        case .failure(let error):
            XCTAssertTrue(error.isForeignKeyViolation || error.message.contains("fk_"), "Should detect FK violation")
        }
    }

    // MARK: - Error Conversion from Traditional catch

    func testTraditionalCatchConvertsToPostgresError() async throws {
        let table = uniqueName()
        defer { Task { [client = self.client!] in _ = try? await client.dropTable(name: table, ifExists: true) } }

        _ = try await client.createTable(name: table, columns: [
            .bigSerial(name: "id", primaryKey: true),
            .text(name: "email", nullable: false)
        ])
        _ = try await client.addUniqueConstraint(table: table, columns: ["email"], constraintName: "\(table)_uk")

        _ = try await client.insert(into: table, columns: ["email"], values: [["bob@example.com"]])

        do {
            _ = try await client.insert(into: table, columns: ["email"], values: [["bob@example.com"]])
            XCTFail("Expected duplicate error")
        } catch {
            let postgresError: PostgresError
            if let existingError = error as? PostgresError {
                postgresError = existingError
            } else if let psqlError = error as? PSQLError {
                postgresError = PostgresError(from: psqlError)
            } else {
                postgresError = PostgresError(message: error.localizedDescription)
            }

            XCTAssertTrue(postgresError.isUniqueViolation || postgresError.message.lowercased().contains("duplicate"))
        }
    }
}
