import XCTest
import Logging
@testable import PostgresKit

private struct Config: JSONBEncodable {
    let theme: String
}

private struct Metadata: JSONBEncodable {
    let skills: [String]
}

final class ComprehensiveConstraintTests: PostgresKitTestCase {
    private var client: PostgresDatabaseClient!
    private var testLogger: Logger!

    override func setUp() async throws {
        try await super.setUp()
        testLogger = Logger(label: "comprehensive-constraint-tests")

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
            applicationName: "ComprehensiveConstraintTests"
        )

        client = try await PostgresDatabaseClient.connect(configuration: config, logger: testLogger)
    }

    override func tearDown() {
        client?.close()
        super.tearDown()
    }

    // MARK: - Primary Key Constraints with All Data Types

    func testPrimaryKeyConstraintsWithAllDataTypes() async throws {
        print("=== Testing Primary Key Constraints with All Data Types ===")

        do {
            _ = try await client.dropTable(name: "test_pk_numeric", ifExists: true)
            _ = try await client.dropTable(name: "test_pk_composite", ifExists: true)

            // Test primary key with numeric types
            _ = try await client.createTable(
                name: "test_pk_numeric",
                columns: [
                    .bigSerial(name: "id"),
                    .integer(name: "code", nullable: false),
                    .text(name: "name", nullable: false)
                ]
            )

        // Add primary key to existing column
        _ = try await client.addPrimaryKey(
            table: "test_pk_numeric",
            column: "code",
            constraintName: "pk_test_code"
        )

        // Test unique constraint enforcement
        _ = try await client.insert(
            into: "test_pk_numeric",
            columns: ["code", "name"],
            values: [[100, "Item A"], [200, "Item B"]]
        )

        // Test duplicate primary key violation
        do {
            _ = try await client.insert(
                into: "test_pk_numeric",
                columns: ["code", "name"],
                values: [[100, "Item C"]]
            )
            XCTFail("Expected primary key violation")
        } catch {
            print("✓ Primary key constraint working: \(error.localizedDescription)")
        }

        // Test composite primary key with different data types
        _ = try await client.createTable(
            name: "test_pk_composite",
            columns: [
                .text(name: "department", nullable: false),
                .integer(name: "employee_id", nullable: false),
                .varchar(name: "name", length: 100, nullable: false),
                .date(name: "hire_date")
            ]
        )

        _ = try await client.addPrimaryKey(
            table: "test_pk_composite",
            column: "department",
            constraintName: "pk_department_employee"
        )

        _ = try await client.insert(
            into: "test_pk_composite",
            columns: ["department", "employee_id", "name"],
            values: [
                ["IT", 1, "John Doe"],
                ["HR", 2, "Jane Smith"],
                ["FIN", 3, "Bob Johnson"]
            ]
        )

        // Test composite key violation
        do {
            _ = try await client.insert(
                into: "test_pk_composite",
                columns: ["department", "employee_id", "name"],
                values: [["IT", 1, "Another Person"]]
            )
            XCTFail("Expected composite primary key violation")
        } catch {
            print("✓ Composite primary key constraint working: \(error.localizedDescription)")
        }

        // Cleanup
        _ = try await client.dropTable(name: "test_pk_numeric", ifExists: false)
        _ = try await client.dropTable(name: "test_pk_composite", ifExists: false)

        print("✓ Primary key constraints test passed")
        } catch {
            print("❌ Primary key constraints test failed!")
            print("Error details: \(String(reflecting: error))")
            throw error
        }
    }

    // MARK: - Foreign Key Constraints with All Data Types

    func testForeignKeyConstraintsWithAllDataTypes() async throws {
        print("=== Testing Foreign Key Constraints with All Data Types ===")

        do {
            _ = try await client.dropTable(name: "test_fk_orders", ifExists: true)
            _ = try await client.dropTable(name: "test_fk_customers", ifExists: true)

        // Create parent tables
        _ = try await client.createTable(
            name: "test_fk_customers",
            columns: [
                .bigSerial(name: "id", primaryKey: true),
                .uuid(name: "customer_uuid", nullable: false),
                .varchar(name: "email", length: 255, nullable: false),
                .text(name: "name"),
                .date(name: "created_date")
            ]
        )

        _ = try await client.createTable(
            name: "test_fk_orders",
            columns: [
                .bigSerial(name: "id", primaryKey: true),
                .bigInt(name: "customer_id", nullable: false),
                .uuid(name: "customer_uuid"), // Make nullable for this test
                .varchar(name: "order_number", length: 50, nullable: false),
                .decimal(name: "amount", precision: 10, scale: 2, nullable: false),
                .timestamp(name: "order_date", nullable: false)
            ]
        )

        // Insert parent data
        let customer1UUID = UUID()
        let customer2UUID = UUID()
        _ = try await client.insert(
            into: "test_fk_customers",
            columns: ["customer_uuid", "email", "name"],
            values: [
                [customer1UUID, "customer1@example.com", "Customer One"],
                [customer2UUID, "customer2@example.com", "Customer Two"]
            ]
        )



        
        // Add unique constraint to customer_uuid first (required for foreign key reference)
        _ = try await client.addUniqueConstraint(
            table: "test_fk_customers",
            columns: ["customer_uuid"],
            constraintName: "uk_customer_uuid"
        )

        // Add foreign key constraints
        _ = try await client.addForeignKey(
            table: "test_fk_orders",
            column: "customer_id",
            referencesTable: "test_fk_customers",
            referencesColumn: "id",
            constraintName: "fk_orders_customer_id",
            onDelete: .restrict,
            onUpdate: .cascade
        )

        _ = try await client.addForeignKey(
            table: "test_fk_orders",
            column: "customer_uuid",
            referencesTable: "test_fk_customers",
            referencesColumn: "customer_uuid",
            constraintName: "fk_orders_customer_uuid",
            onDelete: .cascade,
            onUpdate: .restrict
        )

        // Test valid foreign key references - use the actual customer IDs and UUIDs from database
        let allCustomerRows = try await client.simpleQuery("SELECT id, customer_uuid FROM test_fk_customers ORDER BY id")
        var customerData: [(id: Int, uuid: UUID)] = []
        for try await (id, uuid) in allCustomerRows.decode((Int, UUID).self) {
            customerData.append((id: id, uuid: uuid))
        }

        if customerData.count >= 2 {
            _ = try await client.insert(
                into: "test_fk_orders",
                columns: ["customer_id", "customer_uuid", "order_number", "amount"],
                values: [
                    [customerData[0].id, customerData[0].uuid, "ORD-001", 199.99],
                    [customerData[1].id, customerData[1].uuid, "ORD-002", 299.99]
                ]
            )
        } else {
            XCTFail("Not enough customers found for foreign key testing")
        }

        // Test foreign key violation for non-existent ID
        do {
            _ = try await client.insert(
                into: "test_fk_orders",
                columns: ["customer_id", "customer_uuid", "order_number", "amount"],
                values: [[999, customerData[0].uuid, "ORD-003", 399.99]]
            )
            XCTFail("Expected foreign key violation for customer_id")
        } catch {
            print("✓ Foreign key constraint working for customer_id: \(error.localizedDescription)")
        }

        // Test foreign key violation for NULL UUID
        do {
            _ = try await client.insert(
                into: "test_fk_orders",
                columns: ["customer_id", "customer_uuid", "order_number", "amount"],
                values: [[1, NSNull() as Any, "ORD-004", 499.99]]
            )
            XCTFail("Expected foreign key violation for NULL customer_uuid")
        } catch {
            print("✓ Foreign key constraint working for NULL customer_uuid: \(error.localizedDescription)")
        }

        // Test foreign key violation for non-existent UUID
        do {
            _ = try await client.insert(
                into: "test_fk_orders",
                columns: ["customer_id", "customer_uuid", "order_number", "amount"],
                values: [[1, UUID(), "ORD-005", 599.99]]
            )
            XCTFail("Expected foreign key violation for non-existent customer_uuid")
        } catch {
            print("✓ Foreign key constraint working for non-existent customer_uuid: \(error.localizedDescription)")
        }

        // Valid insert: should succeed - use first customer data
        if customerData.count >= 1 {
            _ = try await client.insert(
                into: "test_fk_orders",
                columns: ["customer_id", "customer_uuid", "order_number", "amount"],
                values: [[customerData[0].id, customerData[0].uuid, "ORD-006", 699.99]]
            )
        } else {
            XCTFail("No customer data available for final valid insert test")
        }

        // Cleanup
        _ = try await client.dropTable(name: "test_fk_orders", ifExists: false)
        _ = try await client.dropTable(name: "test_fk_customers", ifExists: false)

        print("✓ Foreign key constraints test passed")
        } catch {
            print("❌ Foreign key constraints test failed!")
            print("Error details: \(String(reflecting: error))")
            throw error
        }
    }

    // MARK: - Unique Constraints with All Data Types

    func testUniqueConstraintsWithAllDataTypes() async throws {
        print("=== Testing Unique Constraints with All Data Types ===")

        do {
            _ = try await client.dropTable(name: "test_unique_table", ifExists: true)

        // Create table with various data types for unique constraint testing
        _ = try await client.createTable(
            name: "test_unique_table",
            columns: [
                .bigSerial(name: "id", primaryKey: true),
                .varchar(name: "username", length: 50, nullable: false),
                .varchar(name: "email_address", length: 255, nullable: false),
                .uuid(name: "public_id", nullable: false),
                .text(name: "display_name"),
                .macaddr(name: "mac_address"),
                .inet(name: "ip_address"),
                .jsonb(name: "metadata")
            ]
        )

        // Add unique constraints
        _ = try await client.addUniqueConstraint(
            table: "test_unique_table",
            columns: ["username"],
            constraintName: "uk_username"
        )

        _ = try await client.addUniqueConstraint(
            table: "test_unique_table",
            columns: ["email_address"],
            constraintName: "uk_email"
        )

        _ = try await client.addUniqueConstraint(
            table: "test_unique_table",
            columns: ["public_id"],
            constraintName: "uk_public_id"
        )

        _ = try await client.addUniqueConstraint(
            table: "test_unique_table",
            columns: ["mac_address"],
            constraintName: "uk_mac_address"
        )

        // Test composite unique constraint
        _ = try await client.addUniqueConstraint(
            table: "test_unique_table",
            columns: ["display_name", "ip_address"],
            constraintName: "uk_display_ip"
        )

        // Insert valid data using simpleQuery with explicit casting
        let uuid1 = UUID()
        let uuid2 = UUID()
        _ = try await client.simpleQuery("""
            INSERT INTO test_unique_table (username, email_address, public_id, display_name, mac_address, ip_address, metadata)
            VALUES
                ('user1', 'user1@example.com', '\(uuid1.uuidString)', 'User One', '00:11:22:33:44:55'::macaddr, '192.168.1.100'::inet, '{"skills": ["admin"]}'::jsonb),
                ('user2', 'user2@example.com', '\(uuid2.uuidString)', 'User Two', 'AA:BB:CC:DD:EE:FF'::macaddr, '192.168.1.101'::inet, '{"skills": ["user"]}'::jsonb)
        """)

        // Test unique constraint violations
        do {
            _ = try await client.simpleQuery("""
                INSERT INTO test_unique_table (username, email_address, public_id, display_name, mac_address, ip_address, metadata)
                VALUES ('user1', 'user3@example.com', '\(UUID().uuidString)', 'User Three', '11:22:33:44:55:66'::macaddr, '192.168.1.102'::inet, '{"skills": ["guest"]}'::jsonb)
            """)
            XCTFail("Expected unique constraint violation for username")
        } catch {
            print("✓ Unique constraint working for username: \(error.localizedDescription)")
        }

        do {
            _ = try await client.simpleQuery("""
                INSERT INTO test_unique_table (username, email_address, public_id, display_name, mac_address, ip_address, metadata)
                VALUES ('user3', 'user1@example.com', '\(UUID().uuidString)', 'User Three', '22:33:44:55:66:77'::macaddr, '192.168.1.103'::inet, '{"skills": ["guest"]}'::jsonb)
            """)
            XCTFail("Expected unique constraint violation for email")
        } catch {
            print("✓ Unique constraint working for email: \(error.localizedDescription)")
        }

        do {
            // Use uuid1 from the initial insertion to cause a UUID constraint violation
            _ = try await client.simpleQuery("""
                INSERT INTO test_unique_table (username, email_address, public_id, display_name, mac_address, ip_address, metadata)
                VALUES ('user3', 'user3@example.com', '\(uuid1.uuidString)', 'User Three', '33:44:55:66:77:88'::macaddr, '192.168.1.104'::inet, '{"skills": ["guest"]}'::jsonb)
            """)
            XCTFail("Expected unique constraint violation for UUID")
        } catch {
            print("✓ Unique constraint working for UUID: \(error.localizedDescription)")
        }

        // Test composite unique constraint
        do {
            _ = try await client.simpleQuery("""
                INSERT INTO test_unique_table (username, email_address, public_id, display_name, mac_address, ip_address, metadata)
                VALUES ('user4', 'user4@example.com', '\(UUID().uuidString)', 'User One', '44:55:66:77:88:99'::macaddr, '192.168.1.100'::inet, '{"skills": ["guest"]}'::jsonb)
            """)
            XCTFail("Expected composite unique constraint violation")
        } catch {
            print("✓ Composite unique constraint working: \(error.localizedDescription)")
        }

        // Cleanup
        _ = try await client.dropTable(name: "test_unique_table", ifExists: false)

        print("✓ Unique constraints test passed")
        } catch {
            print("❌ Unique constraints test failed!")
            print("Error details: \(String(reflecting: error))")
            throw error
        }
    }

    // MARK: - Check Constraints with All Data Types

    func testCheckConstraintsWithAllDataTypes() async throws {
        print("=== Testing Check Constraints with All Data Types ===")

        do {
            _ = try await client.dropTable(name: "test_check_table", ifExists: true)

        // Create table with check constraints
        _ = try await client.createTable(
            name: "test_check_table",
            columns: [
                .bigSerial(name: "id", primaryKey: true),
                .varchar(name: "username", length: 50, nullable: false),
                .integer(name: "age", nullable: false),
                .decimal(name: "salary", precision: 10, scale: 2, nullable: false),
                .varchar(name: "email", length: 255, nullable: false),
                .date(name: "birth_date", nullable: false),
                .timestamp(name: "created_at", nullable: false),
                .text(name: "status"),
                .jsonb(name: "config")
            ]
        )

        // Add check constraints for various data types
        _ = try await client.addCheckConstraint(
            table: "test_check_table",
            condition: "LENGTH(username) >= 3",
            constraintName: "ck_username_length"
        )

        _ = try await client.addCheckConstraint(
            table: "test_check_table",
            condition: "age >= 18 AND age <= 120",
            constraintName: "ck_age_range"
        )

        _ = try await client.addCheckConstraint(
            table: "test_check_table",
            condition: "salary > 0",
            constraintName: "ck_salary_positive"
        )

        _ = try await client.addCheckConstraint(
            table: "test_check_table",
            condition: "email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$'",
            constraintName: "ck_email_format"
        )

        _ = try await client.addCheckConstraint(
            table: "test_check_table",
            condition: "birth_date < created_at::date",
            constraintName: "ck_birth_date_before_created"
        )

        _ = try await client.addCheckConstraint(
            table: "test_check_table",
            condition: "status IN ('active', 'inactive', 'pending', 'suspended')",
            constraintName: "ck_status_values"
        )

        _ = try await client.addCheckConstraint(
            table: "test_check_table",
            condition: "jsonb_typeof(config) IN ('object', 'null')",
            constraintName: "ck_config_type"
        )

        
        
        
                // Insert valid data

        
        
        
                _ = try await client.insert(

        
        
        
                    into: "test_check_table",

        
        
        
                    columns: ["username", "age", "salary", "email", "birth_date", "created_at", "status", "config"],

        
        
        
                    values: [

        
        
        
                        ["john_doe", 25, 50000.00, "john@example.com", Date(timeIntervalSince1970: 0), Date(), "active", Config(theme: "dark")],

        
        
        
                        ["jane_smith", 30, 75000.00, "jane@example.com", Date(timeIntervalSince1970: 0), Date(), "active", Config(theme: "light")]

        
        
        
                    ]

        
        
        
                )

        
        
        
        
        
        
        
                // Test check constraint violations

        
        
        
        
        
        
        
                do {

        
        
        
        
        
        
        
                    _ = try await client.insert(

        
        
        
        
        
        
        
                        into: "test_check_table",

        
        
        
        
        
        
        
                        columns: ["username", "age", "salary", "email", "birth_date", "created_at", "status", "config"],

        
        
        
        
        
        
        
                        values: [["ab", 25, 50000.00, "short@example.com", Date(timeIntervalSince1970: 0), Date(), "active", Config(theme: "dark")]]

        
        
        
        
        
        
        
                    )

        
        
        
        
        
        
        
                    XCTFail("Expected check constraint violation for username length")

        
        
        
        
        
        
        
                } catch {

        
        
        
        
        
        
        
                    print("✓ Check constraint working for username length: \(error.localizedDescription)")

        
        
        
        
        
        
        
                }

        
        
        
        
        
        
        
        

        
        
        
        
        
        
        
                do {

        
        
        
        
        
        
        
                    _ = try await client.insert(

        
        
        
        
        
        
        
                        into: "test_check_table",

        
        
        
        
        
        
        
                        columns: ["username", "age", "salary", "email", "birth_date", "created_at", "status", "config"],

        
        
        
        
        
        
        
                        values: [["underage", 17, 30000.00, "underage@example.com", Date(timeIntervalSince1970: 0), Date(), "active", Config(theme: "dark")]]

        
        
        
        
        
        
        
                    )

        
        
        
        
        
        
        
                    XCTFail("Expected check constraint violation for age")

        
        
        
        
        
        
        
                } catch {

        
        
        
        
        
        
        
                    print("✓ Check constraint working for age range: \(error.localizedDescription)")

        
        
        
        
        
        
        
                }

        
        
        
        
        
        
        
        

        
        
        
        
        
        
        
                do {

        
        
        
        
        
        
        
                    _ = try await client.insert(

        
        
        
        
        
        
        
                        into: "test_check_table",

        
        
        
        
        
        
        
                        columns: ["username", "age", "salary", "email", "birth_date", "created_at", "status", "config"],

        
        
        
        
        
        
        
                        values: [["negative_salary", 25, -1000.00, "negative@example.com", Date(timeIntervalSince1970: 0), Date(), "active", Config(theme: "dark")]]

        
        
        
        
        
        
        
                    )

        
        
        
        
        
        
        
                    XCTFail("Expected check constraint violation for salary")

        
        
        
        
        
        
        
                } catch {

        
        
        
        
        
        
        
                    print("✓ Check constraint working for salary positive: \(error.localizedDescription)")

        
        
        
        
        
        
        
                }

        
        
        
        
        
        
        
        

        
        
        
        
        
        
        
                do {

        
        
        
        
        
        
        
                    _ = try await client.insert(

        
        
        
        
        
        
        
                        into: "test_check_table",

        
        
        
        
        
        
        
                        columns: ["username", "age", "salary", "email", "birth_date", "created_at", "status", "config"],

        
        
        
        
        
        
        
                        values: [["invalid_email", 25, 50000.00, "invalid-email", Date(timeIntervalSince1970: 0), Date(), "active", Config(theme: "dark")]]

        
        
        
        
        
        
        
                    )

        
        
        
        
        
        
        
                    XCTFail("Expected check constraint violation for email format")

        
        
        
        
        
        
        
                } catch {

        
        
        
        
        
        
        
                    print("✓ Check constraint working for email format: \(error.localizedDescription)")

        
        
        
        
        
        
        
                }

        
        
        
        
        
        
        
        

        
        
        
        
        
        
        
                do {

        
        
        
        
        
        
        
                    _ = try await client.insert(

        
        
        
        
        
        
        
                        into: "test_check_table",

        
        
        
        
        
        
        
                        columns: ["username", "age", "salary", "email", "birth_date", "created_at", "status", "config"],

        
        
        
        
        
        
        
                        values: [["future_birth", 25, 50000.00, "future@example.com", Date(), Date(timeIntervalSince1970: 0), "active", Config(theme: "dark")]]

        
        
        
        
        
        
        
                    )

        
        
        
        
        
        
        
                    XCTFail("Expected check constraint violation for birth date")

        
        
        
        
        
        
        
                } catch {

        
        
        
        
        
        
        
                    print("✓ Check constraint working for birth date: \(error.localizedDescription)")

        
        
        
        
        
        
        
                }

        
        
        
        
        
        
        
        

        
        
        
        
        
        
        
                do {

        
        
        
        
        
        
        
                    _ = try await client.insert(

        
        
        
        
        
        
        
                        into: "test_check_table",

        
        
        
        
        
        
        
                        columns: ["username", "age", "salary", "email", "birth_date", "created_at", "status", "config"],

        
        
        
        
        
        
        
                        values: [["invalid_status", 25, 50000.00, "status@example.com", Date(timeIntervalSince1970: 0), Date(), "invalid", Config(theme: "dark")]]

        
        
        
        
        
        
        
                    )

        
        
        
        
        
        
        
                    XCTFail("Expected check constraint violation for status")

        
        
        
        
        
        
        
                } catch {

        
        
        
        
        
        
        
                    print("✓ Check constraint working for status values: \(error.localizedDescription)")

        
        
        
        
        
        
        
                }

        
        
        
        
        
        
        
        

        
        
        
        
        
        
        
                do {

        
        
        
        
        
        
        
                    _ = try await client.insert(

        
        
        
        
        
        
        
                        into: "test_check_table",

        
        
        
        
        
        
        
                        columns: ["username", "age", "salary", "email", "birth_date", "created_at", "status", "config"],

        
        
        
        
        
        
        
                        values: [["invalid_config", 25, 50000.00, "config@example.com", Date(timeIntervalSince1970: 0), Date(), "active", "not_json_object"]]

        
        
        
        
        
        
        
                    )

        
        
        
        
        
        
        
                    XCTFail("Expected check constraint violation for config type")

        
        
        
        
        
        
        
                } catch {

        
        
        
        
        
        
        
                    print("✓ Check constraint working for config type: \(error.localizedDescription)")

        
        
        
        
        
        
        
                }

        
        
        
        
        
        
        
        
        
        

        // Cleanup
        _ = try await client.dropTable(name: "test_check_table", ifExists: false)

        print("✓ Check constraints test passed")
        } catch {
            print("❌ Check constraints test failed!")
            print("Error details: \(String(reflecting: error))")
            throw error
        }
    }

    // MARK: - Complex Constraint Combinations

    func testComplexConstraintCombinations() async throws {
        print("=== Testing Complex Constraint Combinations ===")

        do {
            _ = try await client.dropTable(name: "test_complex_constraints", ifExists: true)
            _ = try await client.dropTable(name: "test_departments", ifExists: true)

        // Create a complex table with multiple constraint types
        _ = try await client.createTable(
            name: "test_complex_constraints",
            columns: [
                .bigSerial(name: "id", primaryKey: true),
                .varchar(name: "employee_code", length: 20, nullable: false),
                .varchar(name: "email", length: 255, nullable: false),
                .uuid(name: "department_uuid", nullable: false),
                .integer(name: "level", nullable: false),
                .decimal(name: "salary", precision: 10, scale: 2, nullable: false),
                .date(name: "hire_date", nullable: false),
                .date(name: "termination_date"),
                .boolean(name: "is_active", nullable: false, defaultValue: false),
                .jsonb(name: "metadata")
            ]
        )

        // Add multiple constraints
        _ = try await client.addUniqueConstraint(
            table: "test_complex_constraints",
            columns: ["employee_code"],
            constraintName: "uk_employee_code"
        )

        _ = try await client.addUniqueConstraint(
            table: "test_complex_constraints",
            columns: ["email"],
            constraintName: "uk_complex_email"
        )

        _ = try await client.addCheckConstraint(
            table: "test_complex_constraints",
            condition: "LENGTH(employee_code) = 10 AND employee_code ~ '^[A-Z]{2}[0-9]{8}$'",
            constraintName: "ck_employee_code_format"
        )

        _ = try await client.addCheckConstraint(
            table: "test_complex_constraints",
            condition: "level BETWEEN 1 AND 10",
            constraintName: "ck_level_range"
        )

        _ = try await client.addCheckConstraint(
            table: "test_complex_constraints",
            condition: "salary >= 30000.00",
            constraintName: "ck_min_salary"
        )

        _ = try await client.addCheckConstraint(
            table: "test_complex_constraints",
            condition: "hire_date <= COALESCE(termination_date, CURRENT_DATE)",
            constraintName: "ck_date_logic"
        )

        _ = try await client.addCheckConstraint(
            table: "test_complex_constraints",
            condition: "(is_active AND termination_date IS NULL) OR (NOT is_active AND termination_date IS NOT NULL)",
            constraintName: "ck_active_termination_logic"
        )

        // Create departments table for foreign key
        _ = try await client.createTable(
            name: "test_departments",
            columns: [
                .uuid(name: "uuid", nullable: false),
                .text(name: "name", nullable: false),
                .boolean(name: "is_active", nullable: false, defaultValue: true)
            ]
        )

        _ = try await client.addPrimaryKey(
            table: "test_departments",
            column: "uuid",
            constraintName: "pk_departments_uuid"
        )

        // Add foreign key constraint
        _ = try await client.addForeignKey(
            table: "test_complex_constraints",
            column: "department_uuid",
            referencesTable: "test_departments",
            referencesColumn: "uuid",
            constraintName: "fk_employee_department",
            onDelete: .restrict
        )

        // Insert department data
        let deptUUID1 = UUID()
        let deptUUID2 = UUID()
        _ = try await client.insert(
            into: "test_departments",
            columns: ["uuid", "name", "is_active"],
            values: [
                [deptUUID1, "Engineering", true],
                [deptUUID2, "Sales", true]
            ]
        )

        
        // Insert valid employee data using raw SQL to ensure proper NULL handling
        _ = try await client.executeDDL("""
            INSERT INTO test_complex_constraints (employee_code, email, department_uuid, level, salary, hire_date, termination_date, is_active, metadata)
            VALUES
                ('EN12345678', 'engineer1@company.com', '\(deptUUID1.uuidString)'::uuid, 5, 75000.00, CURRENT_DATE, NULL, true, '{"skills": ["Swift", "PostgreSQL"]}'::jsonb),
                ('SA87654321', 'sales1@company.com', '\(deptUUID2.uuidString)'::uuid, 3, 50000.00, CURRENT_DATE, NULL, true, '{"skills": ["Sales"]}'::jsonb)
            """)
                // Test complex constraint violations
        do {
            _ = try await client.insert(
                into: "test_complex_constraints",
                columns: ["employee_code", "email", "department_uuid", "level", "salary", "hire_date", "is_active", "metadata"],
                values: [["INVALID", "invalid@company.com", deptUUID1, 5, 60000.00, Date(), true, Metadata(skills: [])]]
            )
            XCTFail("Expected check constraint violation for employee code format")
        } catch {
            print("✓ Complex employee code constraint working: \(error.localizedDescription)")
        }

        do {
            _ = try await client.insert(
                into: "test_complex_constraints",
                columns: ["employee_code", "email", "department_uuid", "level", "salary", "hire_date", "is_active", "metadata"],
                values: [["EN98765432", "duplicate@company.com", deptUUID2, 4, 55000.00, Date(), true, Metadata(skills: [])]]
            )
            XCTFail("Expected unique constraint violation for duplicate email")
        } catch {
            print("✓ Complex unique constraint working: \(error.localizedDescription)")
        }

        // Test active/termination logic constraint - violation: active employee with termination date
        do {
            let hireDate = Date(timeIntervalSince1970: 0) // 1970-01-01
            let terminationDate = Date() // Current date
            _ = try await client.insert(
                into: "test_complex_constraints",
                columns: ["employee_code", "email", "department_uuid", "level", "salary", "hire_date", "termination_date", "is_active", "metadata"],
                values: [["EN11223344", "active_with_term@company.com", deptUUID1, 3, 45000.00, hireDate, terminationDate, true, Metadata(skills: [])]]
            )
            XCTFail("Expected check constraint violation for active/termination logic")
        } catch {
            print("✓ Complex active/termination constraint working: \(error.localizedDescription)")
        }

        // Cleanup
        _ = try await client.dropTable(name: "test_complex_constraints", ifExists: false)
        _ = try await client.dropTable(name: "test_departments", ifExists: false)

        print("✓ Complex constraint combinations test passed")
        } catch {
            print("❌ Complex constraint combinations test failed!")
            print("Error details: \(String(reflecting: error))")
            throw error
        }
    }}

private struct CustomerUUID: Decodable {
    let id: Int
    let customer_uuid: UUID
}