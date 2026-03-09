import XCTest
import Logging
@testable import PostgresKit

final class DDLTests: XCTestCase {

    private var client: PostgresDatabaseClient!
    private var testLogger: Logger!

    override func setUp() async throws {
        TestEnv.loadDotEnv()
        try await super.setUp()
        testLogger = Logger(label: "ddl-tests")

        // Check if required environment variables are set
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
            applicationName: "DDLTests"
        )

        client = try await PostgresDatabaseClient.connect(configuration: config, logger: testLogger)
    }

    override func tearDown() {
        client?.close()
        super.tearDown()
    }

    // MARK: - Table Creation Tests

    func testCreateTableWithAllDataTypes() async throws {
        print("=== Testing CREATE TABLE with all data types ===")

        // Drop table if it exists
        _ = try await client.dropTable(name: "all_types_test", ifExists: true)

        // Create table using PostgresClient API
        _ = try await client.createTable(
            name: "all_types_test",
            columns: [
                .serial(name: "id", primaryKey: true),
                .text(name: "text_col"),
                .varchar(name: "varchar_col", length: 255),
                .char(name: "char_col", length: 10),
                .integer(name: "integer_col"),
                .bigInt(name: "bigint_col"),
                .integer(name: "smallint_col"), // Using integer for SMALLINT
                .decimal(name: "decimal_col", precision: 10, scale: 2),
                .decimal(name: "numeric_col", precision: 15, scale: 5),
                .real(name: "real_col"),
                .double(name: "double_col"),
                .boolean(name: "boolean_col"),
                .date(name: "date_col"),
                .time(name: "time_col"),
                .timestamp(name: "timestamp_col"),
                .timestampWithTimeZone(name: "timestamptz_col"),
                .uuid(name: "uuid_col"),
                .json(name: "json_col"),
                .jsonb(name: "jsonb_col"),
                .bytea(name: "bytea_col"),
                .text(name: "point_col"), // Using text for geometric types
                .text(name: "box_col"),
                .text(name: "path_col"),
                .text(name: "polygon_col"),
                .text(name: "line_col"),
                .text(name: "circle_col"),
                .cidr(name: "cidr_col"),
                .inet(name: "inet_col"),
                .macaddr(name: "macaddr_col"),
                .text(name: "tsvector_col"), // Using text for TSVECTOR
                .text(name: "tsquery_col"), // Using text for TSQUERY
                .array(name: "array_col", elementType: "INTEGER"),
                .timestamp(name: "created_at")
            ]
        )

        // Verify table was created successfully by querying it
        let result = try await client.simpleQuery("""
            SELECT column_name, data_type, character_maximum_length
            FROM information_schema.columns
            WHERE table_name = 'all_types_test'
            ORDER BY ordinal_position
        """)

        var columnCount = 0
        for try await (name, dataType, maxLength) in result.decode((String, String, Int?).self) {
            print("Column: \(name), Type: \(dataType), Max Length: \(maxLength ?? -1)")
            columnCount += 1
        }

        // Should have at least 25+ columns
        XCTAssertGreaterThan(columnCount, 25)
        print("Successfully created table with \(columnCount) columns")

        // Test data insertion using API with raw SQL for complex types
        let testUUID = UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!

        _ = try await client.executeDDL("""
            INSERT INTO all_types_test (text_col, varchar_col, integer_col, bigint_col, boolean_col, uuid_col, jsonb_col, array_col)
            VALUES ('Test text', 'Test varchar', 42, 999999999, true, '\(testUUID.uuidString)'::uuid, '{"key": "value"}'::jsonb, '{1,2,3}'::integer[])
            """)

        print("✓ Successfully inserted test data into all types table")
    }

    func testCreateTableWithConstraints() async throws {
        print("=== Testing CREATE TABLE with constraints ===")

        // Clean up existing tables
        _ = try await client.dropTable(name: "employees", ifExists: true)
        _ = try await client.dropTable(name: "departments", ifExists: true)

        // Create referenced table using PostgresClient API
        _ = try await client.createTable(
            name: "departments",
            columns: [
                .serial(name: "id", primaryKey: true),
                .varchar(name: "name", length: 100, nullable: false),
                .varchar(name: "code", length: 10, nullable: false)
            ]
        )

        // Add unique constraint to departments table
        _ = try await client.addUniqueConstraint(
            table: "departments",
            columns: ["name"],
            constraintName: "uk_departments_name"
        )

        // Insert test data using PostgresClient API
        _ = try await client.insert(
            into: "departments",
            columns: ["name", "code"],
            values: [["Engineering", "ENG"], ["Sales", "SLS"]]
        )

        // Create table with various constraints using PostgresClient API
        _ = try await client.createTable(
            name: "employees",
            columns: [
                .serial(name: "id", primaryKey: true),
                .varchar(name: "first_name", length: 50, nullable: false),
                .varchar(name: "last_name", length: 50, nullable: false),
                .varchar(name: "email", length: 100, nullable: false),
                .integer(name: "age"),
                .decimal(name: "salary", precision: 10, scale: 2),
                .integer(name: "department_id"),
                .date(name: "hire_date"),
                .boolean(name: "is_active", defaultValue: true),
                .timestamp(name: "created_at")
            ]
        )

        // Add constraints using PostgresClient API
        _ = try await client.addUniqueConstraint(
            table: "employees",
            columns: ["email"],
            constraintName: "uk_employees_email"
        )

        _ = try await client.addCheckConstraint(
            table: "employees",
            condition: "age >= 18 AND age <= 100",
            constraintName: "ck_employees_age"
        )

        _ = try await client.addCheckConstraint(
            table: "employees",
            condition: "email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$'",
            constraintName: "ck_employees_email_format"
        )

        _ = try await client.addForeignKey(
            table: "employees",
            column: "department_id",
            referencesTable: "departments",
            referencesColumn: "id",
            constraintName: "fk_employees_department"
        )

            // Test constraint violations using PostgresClient API
        do {
            _ = try await client.insert(
                into: "employees",
                columns: ["first_name", "last_name", "email", "age"],
                values: [["John", "Doe", "invalid-email", 25]]
            )
            XCTFail("Should have failed with email constraint violation")
        } catch {
            print("✓ Email constraint violation caught: \(error.localizedDescription)")
        }

        do {
            _ = try await client.insert(
                into: "employees",
                columns: ["first_name", "last_name", "email", "age"],
                values: [["Jane", "Doe", "jane@example.com", 15]]
            )
            XCTFail("Should have failed with age check constraint violation")
        } catch {
            print("✓ Age constraint violation caught: \(error.localizedDescription)")
        }

        // Test valid insert
        _ = try await client.insert(
            into: "employees",
            columns: ["first_name", "last_name", "email", "age", "department_id"],
            values: [["John", "Doe", "john@example.com", 30, 1]]
        )

        // Test unique constraint
        do {
            _ = try await client.insert(
                into: "employees",
                columns: ["first_name", "last_name", "email", "age"],
                values: [["John", "Smith", "john@example.com", 35]]
            )
            XCTFail("Should have failed with unique constraint violation")
        } catch {
            print("✓ Unique constraint violation caught: \(error.localizedDescription)")
        }

        // Count employees using PostgresClient API
        let countRows = try await client.simpleQuery("SELECT COUNT(*)::text FROM employees")
        var count = 0
        for try await (countStr,) in countRows.decode(String.self) {
            if let intVal = Int(countStr) {
                count = intVal
            }
            break
        }

        XCTAssertEqual(count, 1)
        print("✓ All constraint tests passed")
    }

    // MARK: - Table Alteration Tests

    func testAlterTable() async throws {
        print("=== Testing ALTER TABLE operations ===")

        let result = try await client.withConnection { conn in
            // Create initial table
            _ = try await conn.simpleQuery("""
                CREATE TEMPORARY TABLE alter_test (
                    id SERIAL PRIMARY KEY,
                    name VARCHAR(50)
                )
            """)

            // Test ADD COLUMN
            _ = try await conn.simpleQuery("ALTER TABLE alter_test ADD COLUMN age INTEGER")
            _ = try await conn.simpleQuery("ALTER TABLE alter_test ADD COLUMN email VARCHAR(100)")

            // Test ALTER COLUMN TYPE
            _ = try await conn.simpleQuery("ALTER TABLE alter_test ALTER COLUMN name TYPE VARCHAR(100)")

            // Test SET DEFAULT
            _ = try await conn.simpleQuery("ALTER TABLE alter_test ALTER COLUMN age SET DEFAULT 25")

            // Test SET NOT NULL (need to update existing nulls first)
            _ = try await conn.simpleQuery("ALTER TABLE alter_test ALTER COLUMN age SET NOT NULL")

            // Test DROP COLUMN
            _ = try await conn.simpleQuery("ALTER TABLE alter_test DROP COLUMN email")

            // Test ADD CONSTRAINT
            _ = try await conn.simpleQuery("ALTER TABLE alter_test ADD CONSTRAINT check_name CHECK (length(name) > 2)")

            // Test RENAME COLUMN
            _ = try await conn.simpleQuery("ALTER TABLE alter_test RENAME COLUMN name TO full_name")

            // Insert test data
            _ = try await conn.simpleQuery("""
                INSERT INTO alter_test (full_name) VALUES ('John Doe')
            """)

            // Verify the data uses the default age
            let rows = try await conn.simpleQuery("SELECT id, full_name, age FROM alter_test")
            var results: [(Int32, String, Int32)] = []
            for try await (id, name, age) in rows.decode((Int32, String, Int32).self) {
                results.append((id, name, age))
            }

            return results.first?.2 ?? 0
        }

        XCTAssertEqual(result, 25) // Should use the default age
        print("✓ ALTER TABLE operations completed successfully")
    }

    // MARK: - Index Tests

    func testCreateAndDropIndexes() async throws {
        print("=== Testing Index operations ===")

        // Clean up existing table
        _ = try await client.dropTable(name: "index_test", ifExists: true)

        // Create table using PostgresClient API
        _ = try await client.createTable(
            name: "index_test",
            columns: [
                .serial(name: "id", primaryKey: true),
                .varchar(name: "name", length: 100),
                .varchar(name: "email", length: 100),
                .integer(name: "age"),
                .timestamp(name: "created_at", defaultValue: "CURRENT_TIMESTAMP")
            ]
        )

        // Insert test data using PostgresClient API
        var testData: [[Any]] = []
        for i in 1...100 {
            testData.append([
                "User \(i)",
                "user\(i)@example.com",
                20 + (i % 50)
            ])
        }

        _ = try await client.insert(
            into: "index_test",
            columns: ["name", "email", "age"],
            values: testData
        )

        // Test CREATE INDEX using PostgresClient API
        _ = try await client.createIndex(
            name: "idx_index_test_name",
            table: "index_test",
            columns: ["name"],
            unique: false
        )

        _ = try await client.createIndex(
            name: "idx_index_test_email",
            table: "index_test",
            columns: ["email"],
            unique: false
        )

        _ = try await client.createIndex(
            name: "idx_index_test_age",
            table: "index_test",
            columns: ["age"],
            unique: false
        )

        // Test CREATE UNIQUE INDEX using PostgresClient API
        _ = try await client.createIndex(
            name: "idx_index_test_unique_name",
            table: "index_test",
            columns: ["name"],
            unique: true
        )

        // Test composite index using PostgresClient API
        _ = try await client.createIndex(
            name: "idx_index_test_composite",
            table: "index_test",
            columns: ["name", "age"],
            unique: false
        )

        // Verify indexes exist using PostgresClient API
        let indexRows = try await client.simpleQuery("""
            SELECT indexname, indexdef
            FROM pg_indexes
            WHERE tablename = 'index_test'
            ORDER BY indexname
        """)

        var indexCount = 0
        for try await (indexName, indexDef) in indexRows.decode((String, String).self) {
            print("Index: \(indexName) - \(indexDef)")
            indexCount += 1
        }

        // Test index usage with EXPLAIN using PostgresClient API
        let explainRows = try await client.simpleQuery("""
            EXPLAIN (FORMAT JSON) SELECT * FROM index_test WHERE name = 'User 42'
        """)

        for try await (plan) in explainRows.decode(String.self) {
            print("Query plan: \(plan)")
        }

        // Test DROP INDEX using PostgresClient API
        _ = try await client.dropIndex(name: "idx_index_test_name", ifExists: false)
        _ = try await client.dropIndex(name: "idx_index_test_email", ifExists: false)
        _ = try await client.dropIndex(name: "idx_index_test_age", ifExists: false)
        _ = try await client.dropIndex(name: "idx_index_test_unique_name", ifExists: false)
        _ = try await client.dropIndex(name: "idx_index_test_composite", ifExists: false)

        XCTAssertGreaterThan(indexCount, 4) // Should have created at least 4 indexes
        print("✓ Index operations completed successfully")
    }

    // MARK: - Foreign Key Tests

    func testForeignKeys() async throws {
        print("=== Testing Foreign Key operations ===")

        let result = try await client.withConnection { conn in
            // Create parent tables
            _ = try await conn.simpleQuery("""
                CREATE TEMPORARY TABLE authors (
                    id SERIAL PRIMARY KEY,
                    name VARCHAR(100) NOT NULL,
                    email VARCHAR(100) UNIQUE
                )
            """)

            _ = try await conn.simpleQuery("""
                CREATE TEMPORARY TABLE publishers (
                    id SERIAL PRIMARY KEY,
                    name VARCHAR(100) NOT NULL
                )
            """)

            // Create child table with foreign keys
            _ = try await conn.simpleQuery("""
                CREATE TEMPORARY TABLE books (
                    id SERIAL PRIMARY KEY,
                    title VARCHAR(200) NOT NULL,
                    author_id INTEGER NOT NULL REFERENCES authors(id) ON DELETE CASCADE,
                    publisher_id INTEGER REFERENCES publishers(id) ON DELETE SET NULL,
                    isbn VARCHAR(20) UNIQUE,
                    published_date DATE
                )
            """)

            // Insert test data
            _ = try await conn.simpleQuery("""
                INSERT INTO authors (name, email) VALUES
                ('J.K. Rowling', 'jk@rowling.com'),
                ('Stephen King', 'stephen@king.com')
            """)

            _ = try await conn.simpleQuery("""
                INSERT INTO publishers (name) VALUES
                ('Bloomsbury'), ('Penguin Books')
            """)

            _ = try await conn.simpleQuery("""
                INSERT INTO books (title, author_id, publisher_id, isbn, published_date) VALUES
                ('Harry Potter 1', 1, 1, '978-0-7475-3268-9', '1997-06-26'),
                ('The Shining', 2, 2, '978-0-385-12167-5', '1977-01-28')
            """)

            // Test foreign key constraint violation
            do {
                _ = try await conn.simpleQuery("""
                    INSERT INTO books (title, author_id, publisher_id, isbn)
                    VALUES ('Invalid Book', 999, 1, 'invalid-isbn')
                """)
                XCTFail("Should have failed with foreign key violation")
            } catch {
                print("✓ Foreign key constraint violation caught: \(error)")
            }

            // Verify initial state
            let initialCountRows = try await conn.simpleQuery("SELECT COUNT(*)::text FROM books")
            var initialCount = 0
            for try await (countStr,) in initialCountRows.decode(String.self) {
                if let intVal = Int(countStr) {
                    initialCount = intVal
                }
                break
            }
            print("Initial books count: \(initialCount)")

            // Count books before delete operations
            let beforeCountRows = try await conn.simpleQuery("SELECT COUNT(*)::text FROM books")
            var beforeCount = 0
            for try await (countStr,) in beforeCountRows.decode(String.self) {
                if let intVal = Int(countStr) {
                    beforeCount = intVal
                }
                break
            }

            // Test CASCADE delete
            _ = try await conn.simpleQuery("DELETE FROM authors WHERE id = 1")

            // Test SET NULL delete
            _ = try await conn.simpleQuery("DELETE FROM publishers WHERE id = 2")

            // Count remaining books after both operations
            let afterCountRows = try await conn.simpleQuery("SELECT COUNT(*)::text FROM books")
            var afterCount = 0
            for try await (countStr,) in afterCountRows.decode(String.self) {
                if let intVal = Int(countStr) {
                    afterCount = intVal
                }
                break
            }

            let affectedCount = beforeCount - afterCount
            print("Books before: \(beforeCount), after: \(afterCount), affected: \(affectedCount)")

            return affectedCount
        }

        XCTAssertEqual(result, 1) // 1 book deleted via CASCADE
        print("✓ Foreign key operations completed successfully - affected \(result) records")
        print("✓ Foreign key operations completed successfully")
    }

    // MARK: - Drop Table Tests

    func testDropTable() async throws {
        print("=== Testing DROP TABLE operations ===")

        let result = try await client.withConnection { conn in
            // Create table
            _ = try await conn.simpleQuery("""
                CREATE TEMPORARY TABLE drop_test (
                    id SERIAL PRIMARY KEY,
                    name VARCHAR(50)
                )
            """)

            // Insert data
            _ = try await conn.simpleQuery("INSERT INTO drop_test (name) VALUES ('Test')")

            // Verify table exists
            let beforeCount = try await conn.simpleQuery("SELECT COUNT(*)::text FROM drop_test")
            var before = 0
            for try await (countStr,) in beforeCount.decode(String.self) {
                if let intVal = Int(countStr) {
                    before = intVal
                }
                break
            }

            // Drop table
            _ = try await conn.simpleQuery("DROP TABLE drop_test")

            // Try to query dropped table (should fail)
            do {
                _ = try await conn.simpleQuery("SELECT COUNT(*)::text FROM drop_test")
                XCTFail("Should have failed - table should not exist")
            } catch {
                print("✓ Table successfully dropped - query failed as expected: \(error)")
            }

            // Test IF EXISTS
            _ = try await conn.simpleQuery("DROP TABLE IF EXISTS drop_test") // Should not error

            return before
        }

        XCTAssertEqual(result, 1)
        print("✓ DROP TABLE operations completed successfully")
    }
}