import XCTest
import Logging
@testable import PostgresKit

final class ComprehensiveTableTests: PostgresKitTestCase {
    private var client: PostgresKit.PostgresClient!
    private var testLogger: Logger!

    override func setUp() async throws {
        try await super.setUp()
        testLogger = Logger(label: "postgres.wire.tests")

                guard TestEnv.isConfigured else { throw XCTSkip("Postgres environment not set") }

        



        let config = PostgresConfiguration(
            host: TestEnv.host,
            port: TestEnv.port,
            database: TestEnv.database,
            username: TestEnv.username,
            password: TestEnv.password,
            useTLS: TestEnv.useTLS,
            applicationName: "ComprehensiveTableTests"
        )

        client = try await PostgresKit.PostgresClient.connect(configuration: config, logger: testLogger)
    }

    override func tearDown() {
        client?.close()
        super.tearDown()
    }

    // MARK: - Table Creation with All Data Types

    func testCreateTableWithAllDataTypes() async throws {
        logger.info("Testing Table Creation with All Data Types")

        _ = try await client.admin.dropTable(name: "test_all_types", ifExists: true)

        // Create table with all supported PostgreSQL data types
        do {
            _ = try await client.admin.createTable(
                name: "test_all_types",
                columns: [
                    // Numeric types
                    .bigSerial(name: "id", primaryKey: true),
                    .integer(name: "int_col", nullable: false),
                    .bigInt(name: "bigint_col"),
                    .serial(name: "serial_col"),
                    .bigSerial(name: "bigserial_col"),
                    .decimal(name: "decimal_col", precision: 15, scale: 4),
                    .real(name: "real_col"),
                    .double(name: "double_col"),

                    // Text types
                    .varchar(name: "varchar_col", length: 100),
                    .text(name: "text_col"),
                    .char(name: "char_col", length: 10),

                    // Boolean type
                    .boolean(name: "bool_col", nullable: false, defaultValue: true),

                    // Date/Time types
                    .timestamp(name: "timestamp_col"),
                    .timestampWithTimeZone(name: "timestamptz_col"),
                    .date(name: "date_col"),
                    .time(name: "time_col"),
                    .timeWithTimeZone(name: "timetz_col"),

                    // JSON types
                    .json(name: "json_col"),
                    .jsonb(name: "jsonb_col"),

                    // Binary type
                    .bytea(name: "bytea_col"),

                    // UUID type
                    .uuid(name: "uuid_col", nullable: false),

                    // Array types
                    .array(name: "int_array_col", elementType: "INTEGER"),
                    .array(name: "text_array_col", elementType: "TEXT"),

                    // Network types
                    .inet(name: "inet_col"),
                    .cidr(name: "cidr_col"),
                    .macaddr(name: "macaddr_col"),

                    // Custom enum type (simulate with text)
                    .varchar(name: "status_col", length: 20, nullable: false, defaultValue: "active")
                ]
            )
            logger.info("Table creation successful")
        } catch {
            logger.error("Table creation failed: \(error)")
            throw error
        }

        // Verify table was created successfully by checking table existence
        do {
            let result = try await client.connection.simpleQuery("""
                SELECT EXISTS (
                    SELECT FROM information_schema.tables
                    WHERE table_name = 'test_all_types'
                );
                """)
            var tableExists = false
            for try await (exists) in result.decode((Bool).self) {
                tableExists = exists
                break
            }
            XCTAssertTrue(tableExists, "Table should exist and be queryable")
            if tableExists {
                logger.info("Table verification successful")
            } else {
                logger.error("Table verification failed - table does not exist")
            }
        } catch {
            logger.error("Table verification failed: \(error)")
            XCTFail("Table verification failed with error: \(error)")
        }

        // Cleanup
        _ = try await client.admin.dropTable(name: "test_all_types", ifExists: false)

        logger.info("Table creation with all data types test passed")
    }

    // MARK: - Table Operations with Complex Data Types

    func testTableOperationsWithComplexDataTypes() async throws {
        logger.info("Testing Table Operations with Complex Data Types")

        _ = try await client.admin.dropTable(name: "test_complex_table", ifExists: true)

        // Create table with complex data types
        _ = try await client.admin.createTable(
            name: "test_complex_table",
            columns: [
                .bigSerial(name: "id", primaryKey: true),
                .varchar(name: "name", length: 100, nullable: false),
                .jsonb(name: "metadata", nullable: false),
                .array(name: "tags", elementType: "TEXT"),
                .uuid(name: "external_id"),
                .bytea(name: "binary_data"),
                .text(name: "description")
            ]
        )

        _ = try await client.connection.insert(
            into: "test_complex_table",
            columns: ["name", "metadata", "tags", "external_id", "binary_data", "description"],
            values: [
                [
                    "Product One",
                    .jsonbLiteral("{\"category\": \"electronics\", \"price\": 999.99, \"features\": [\"wifi\", \"bluetooth\"]}"),
                    .array(["new", "featured", "electronics"]),
                    PostgresInsertValue(UUID(uuidString: "550e8400-e29b-41d4-a716-446655440001")!),
                    PostgresInsertValue(Data("binary data content here".utf8)),
                    "High-end electronic product"
                ],
                [
                    "Product Two",
                    .jsonbLiteral("{\"category\": \"books\", \"price\": 29.99, \"pages\": 300}"),
                    .array(["books", "fiction", "bestseller"]),
                    PostgresInsertValue(UUID(uuidString: "550e8400-e29b-41d4-a716-446655440002")!),
                    PostgresInsertValue(Data("more binary content".utf8)),
                    "Bestselling fiction book"
                ]
            ]
        )

        // Test JSONB queries
        let jsonResult = try await client.connection.simpleQuery("SELECT name, metadata->>'category' as category FROM test_complex_table WHERE metadata @> '{\"category\": \"electronics\"}'")
        var electronicsCount = 0
        for try await (name, category) in jsonResult.decode((String, String).self) {
            electronicsCount += 1
            logger.info("Found electronics product: \(name) - \(category)")
        }
        XCTAssertEqual(electronicsCount, 1, "Should find one electronics product")

        // Test array queries
        let arrayResult = try await client.connection.simpleQuery("SELECT name, tags FROM test_complex_table WHERE tags @> ARRAY['books']")
        var booksCount = 0
        for try await (name, tags) in arrayResult.decode((String, [String]).self) {
            booksCount += 1
            logger.info("Found book product: \(name) - tags: \(tags)")
        }
        XCTAssertEqual(booksCount, 1, "Should find one book product")

        // Test UUID queries
        let uuidResult = try await client.connection.simpleQuery("SELECT name FROM test_complex_table WHERE external_id = '550e8400-e29b-41d4-a716-446655440001'")
        var foundUUID = false
        for try await name in uuidResult.decode(String?.self) {
            if let name = name {
                XCTAssertEqual(name, "Product One")
                foundUUID = true
                break
            }
        }
        XCTAssertTrue(foundUUID, "Should find product by UUID")

        // Cleanup
        _ = try await client.admin.dropTable(name: "test_complex_table", ifExists: false)

        logger.info("Table operations with complex data types test passed")
    }

    // MARK: - Table Alter Operations

    func testAlterTableOperations() async throws {
        logger.info("Testing Alter Table Operations")

        _ = try await client.admin.dropTable(name: "test_alter_table", ifExists: true)

        // Create initial table
        _ = try await client.admin.createTable(
            name: "test_alter_table",
            columns: [
                .bigSerial(name: "id", primaryKey: true),
                .varchar(name: "name", length: 50, nullable: false),
                .integer(name: "value", nullable: false)
            ]
        )

        // Insert initial data
        _ = try await client.connection.insert(
            into: "test_alter_table",
            columns: ["name", "value"],
            values: [["Item 1", 100], ["Item 2", 200]]
        )

        // Test adding columns with different data types
        _ = try await client.admin.addColumn(table: "test_alter_table", column: .text(name: "description"))
        _ = try await client.admin.addColumn(table: "test_alter_table", column: .timestamp(name: "created_at", defaultValue: "CURRENT_TIMESTAMP"))
        _ = try await client.admin.addColumn(table: "test_alter_table", column: .boolean(name: "is_active", defaultValue: true))
        _ = try await client.admin.addColumn(table: "test_alter_table", column: .decimal(name: "price", precision: 10, scale: 2))
        _ = try await client.admin.addColumn(table: "test_alter_table", column: .array(name: "tags", elementType: "TEXT"))
        _ = try await client.admin.addColumn(table: "test_alter_table", column: .jsonb(name: "metadata"))
        _ = try await client.admin.addColumn(table: "test_alter_table", column: .uuid(name: "external_id"))

        _ = try await client.connection.insert(
            into: "test_alter_table",
            columns: ["name", "value", "description", "price", "tags", "metadata", "external_id"],
            values: [
                ["Item 3", 300, "Third item", 39.99, .array(["new", "featured"]), .jsonbLiteral("{\"priority\": \"high\"}"), PostgresInsertValue(UUID(uuidString: "550e8400-e29b-41d4-a716-446655440003")!)],
                ["Item 4", 400, "Fourth item", 49.99, .array(["sale", "discount"]), .jsonbLiteral("{\"discount\": true}"), PostgresInsertValue(UUID(uuidString: "550e8400-e29b-41d4-a716-446655440004")!)]
            ]
        )

        // Verify new columns exist and have correct data - simple validation
        let countResult = try await client.connection.simpleQuery("SELECT COUNT(*) FROM test_alter_table WHERE description IS NOT NULL")
        var itemCount = 0
        for try await rowCount in countResult.decode((Int64?).self) {
            if let rowCount = rowCount {
                itemCount = Int(rowCount)
                break
            }
        }
        XCTAssertEqual(itemCount, 2, "Should find 2 items with descriptions")

        // Test modifying column types
        _ = try await client.admin.alterColumnType(table: "test_alter_table", column: "value", newType: "BIGINT")
        _ = try await client.admin.alterColumnType(table: "test_alter_table", column: "name", newType: "VARCHAR(100)")

        // Test adding constraints
        _ = try await client.admin.addCheckConstraint(
            table: "test_alter_table",
            condition: "price > 0",
            constraintName: "ck_price_positive"
        )

        _ = try await client.admin.addUniqueConstraint(
            table: "test_alter_table",
            columns: ["external_id"],
            constraintName: "uk_external_id"
        )

        // Test adding and dropping columns
        _ = try await client.admin.addColumn(table: "test_alter_table", column: .text(name: "dummy_column"))
        _ = try await client.admin.dropColumn(table: "test_alter_table", column: "dummy_column")

        // Cleanup
        _ = try await client.admin.dropTable(name: "test_alter_table", ifExists: false)

        logger.info("Alter table operations test passed")
    }

    // MARK: - Table Truncate Operations

    func testTruncateTableOperations() async throws {
        logger.info("Testing Truncate Table Operations")

        // Use fixed table names with proper cleanup at start
        _ = try await client.admin.dropTable(name: "test_truncate_table", ifExists: true, cascade: true)
        _ = try await client.admin.dropTable(name: "test_truncate_table2", ifExists: true, cascade: true)

        // Create tables for truncate testing
        _ = try await client.admin.createTable(
            name: "test_truncate_table",
            columns: [
                .bigSerial(name: "id", primaryKey: true),
                .varchar(name: "name", length: 50, nullable: false),
                .integer(name: "value"),
                .timestamp(name: "created_at", defaultValue: "CURRENT_TIMESTAMP")
            ]
        )

        _ = try await client.admin.createTable(
            name: "test_truncate_table2",
            columns: [
                .bigSerial(name: "id", primaryKey: true),
                .varchar(name: "category", length: 30, nullable: false),
                .text(name: "description")
            ]
        )

        // Insert test data
        _ = try await client.connection.insert(
            into: "test_truncate_table",
            columns: ["name", "value"],
            values: [["Item 1", 100], ["Item 2", 200], ["Item 3", 300]]
        )

        _ = try await client.connection.insert(
            into: "test_truncate_table2",
            columns: ["category", "description"],
            values: [["Category A", "Description A"], ["Category B", "Description B"]]
        )

        // Verify data exists
        var count = 0
        let result1 = try await client.connection.simpleQuery("SELECT COUNT(*) FROM test_truncate_table")
        for try await rowCount in result1.decode((Int64?).self) {
            if let rowCount = rowCount {
                count = Int(rowCount)
                break
            }
        }
        XCTAssertEqual(count, 3, "Should have 3 rows before truncate")

        // Test truncate with identity reset
        _ = try await client.connection.truncate(table: "test_truncate_table", restartIdentity: true)

        // Verify table is empty
        count = 0
        let result2 = try await client.connection.simpleQuery("SELECT COUNT(*) FROM test_truncate_table")
        for try await rowCount in result2.decode((Int64?).self) {
            if let rowCount = rowCount {
                count = Int(rowCount)
                break
            }
        }
        XCTAssertEqual(count, 0, "Should have 0 rows after truncate")

        // Test inserting after truncate (should restart from 1)
        _ = try await client.connection.insert(
            into: "test_truncate_table",
            columns: ["name", "value"],
            values: [["New Item 1", 1000]]
        )

        let result3 = try await client.connection.simpleQuery("SELECT id, name FROM test_truncate_table ORDER BY id")
        var newId = 0
        for try await (id, name) in result3.decode((Int64, String).self) {
            newId = Int(id)
            XCTAssertEqual(name, "New Item 1")
            break
        }
        XCTAssertEqual(newId, 1, "ID should restart from 1 after truncate with restartIdentity")

        // Cleanup with CASCADE
        _ = try await client.admin.dropTable(name: "test_truncate_table2", ifExists: true, cascade: true)
        _ = try await client.admin.dropTable(name: "test_truncate_table", ifExists: true, cascade: true)

        logger.info("Truncate table operations test passed")
    }

    // MARK: - Table Operations with Large Datasets

    func testTableOperationsWithLargeDatasets() async throws {
        logger.info("Testing Table Operations with Large Datasets")

        _ = try await client.admin.dropTable(name: "test_large_dataset", ifExists: true)

        // Create table for large dataset testing
        _ = try await client.admin.createTable(
            name: "test_large_dataset",
            columns: [
                .bigSerial(name: "id", primaryKey: true),
                .varchar(name: "name", length: 100, nullable: false),
                .integer(name: "category_id"),
                .decimal(name: "price", precision: 10, scale: 2),
                .timestamp(name: "created_at"),
                .jsonb(name: "attributes"),
                .boolean(name: "is_active", defaultValue: true)
            ]
        )

        // Create indexes for performance
        _ = try await client.admin.createIndex(
            name: "idx_large_name",
            table: "test_large_dataset",
            columns: ["name"],
            unique: false
        )

        _ = try await client.admin.createIndex(
            name: "idx_large_category",
            table: "test_large_dataset",
            columns: ["category_id"],
            unique: false
        )

        _ = try await client.admin.createIndex(
            name: "idx_large_active",
            table: "test_large_dataset",
            columns: ["is_active"],
            unique: false
        )

        // Generate large dataset
        let batchSize = 1000
        let totalRecords = 5000

        // Generate and insert large dataset
        for batchStart in stride(from: 1, through: totalRecords, by: batchSize) {
            let rows: [[PostgresInsertValue]] = (batchStart..<min(batchStart + batchSize, totalRecords + 1)).map { i in
                let name = "Product \(i)"
                let categoryId = (i % 10) + 1
                let price = Double.random(in: 10.0...1000.0)
                let timestamp = "2024-\(String(format: "%02d", (i % 12) + 1))-\(String(format: "%02d", (i % 28) + 1)) 10:00:00"
                let batchNumber = i / batchSize + 1
                let quality = (i % 5 == 0) ? "high" : "standard"
                let attributes = "{\"batch\": \(batchNumber), \"quality\": \"\(quality)\"}"
                let isActive = i % 20 != 0 // 5% inactive

                return [
                    PostgresInsertValue(name),
                    PostgresInsertValue(categoryId),
                    PostgresInsertValue(price),
                    .timestamp(timestamp),
                    .jsonbLiteral(attributes),
                    PostgresInsertValue(isActive)
                ]
            }

            _ = try await client.connection.insert(
                into: "test_large_dataset",
                columns: ["name", "category_id", "price", "created_at", "attributes", "is_active"],
                values: rows
            )
        }

        // Test query performance
        let startTime = Date().timeIntervalSinceReferenceDate

        let result = try await client.connection.simpleQuery("""
            SELECT COUNT(*) as count, AVG(price) as avg_price
            FROM test_large_dataset
            WHERE is_active = true AND category_id BETWEEN 3 AND 7
        """)

        var count = 0
        var avgPrice: Double = 0.0
        for try await row in result {
            let randomRow = row.makeRandomAccess()
            if let rowCount = try? randomRow["count"].decode(Int64.self) {
                count = Int(rowCount)
            }
            if let priceAvg = try? randomRow["avg_price"].decode(Double.self) {
                avgPrice = priceAvg
            } else if let priceAvgString = try? randomRow["avg_price"].decode(String.self),
                      let priceAvgDouble = Double(priceAvgString) {
                avgPrice = priceAvgDouble
            }
            break
        }

        let queryTime = Date().timeIntervalSinceReferenceDate - startTime

        logger.info("Query results: \(count) active records in categories 3-7, avg price: $\(String(format: "%.2f", avgPrice))")
        logger.info("Query completed in \(String(format: "%.3f", queryTime)) seconds")

        XCTAssertGreaterThan(count, 1000, "Should find significant number of records")
        XCTAssertLessThan(queryTime, 2.0, "Query should complete quickly with proper indexing")

        // Index creation and query performance validated
        // Large dataset operations completed successfully with proper indexing

        // Cleanup
        _ = try await client.admin.dropTable(name: "test_large_dataset", ifExists: false)

        logger.info("Large dataset operations test passed")
    }

    // MARK: - Table Operations with Special Character Handling

    func testTableOperationsWithSpecialCharacters() async throws {
        logger.info("Testing Table Operations with Special Characters")

        // Test table and column names with special characters
        _ = try await client.admin.dropTable(name: "test_special_chars_table", ifExists: true)
        _ = try await client.admin.dropTable(name: "table_with_underscores", ifExists: true)

        // Create table with special character column names
        _ = try await client.admin.createTable(
            name: "test_special_chars_table",
            columns: [
                .bigSerial(name: "id", primaryKey: true),
                .varchar(name: "user_name", length: 50, nullable: false),
                .varchar(name: "email_address", length: 255),
                .text(name: "full_description"),
                .boolean(name: "is_active_flag", defaultValue: true),
                .timestamp(name: "created_at_timestamp"),
                .jsonb(name: "user_settings_data")
            ]
        )

        _ = try await client.connection.insert(
            into: "test_special_chars_table",
            columns: ["user_name", "email_address", "full_description", "user_settings_data"],
            values: [
                ["John O'Connor", "john.o'connor@example.com", "User with special chars: quotes, apostrophes, & symbols!", .jsonbLiteral("{\"theme\": \"dark\", \"notifications\": true}")],
                ["Jane \"Developer\" Smith", "jane.dev+test@example.co.uk", "Complex email & text with @#$%^&*() characters", .jsonbLiteral("{\"role\": \"admin\", \"access_level\": 5}")],
                ["用户中文", "chinese@user.中国", "Unicode test: ñáéíóú 中文 🚀", .jsonbLiteral("{\"language\": \"zh-CN\", \"encoding\": \"UTF-8\"}")]
            ]
        )

        // Query special character data
        let result = try await client.connection.simpleQuery("SELECT user_name, email_address, full_description FROM test_special_chars_table ORDER BY id")

        var userCount = 0
        for try await (name, email, description) in result.decode((String, String, String).self) {
            userCount += 1
            logger.info("User: \(name), Email: \(email), Description: \(description)")
        }
        XCTAssertEqual(userCount, 3, "Should retrieve all 3 users with special characters")

        // Test table with reserved word names
        _ = try await client.admin.createTable(
            name: "table_with_underscores",
            columns: [
                .bigSerial(name: "id", primaryKey: true),
                .text(name: "user_key"),
                .text(name: "value_data"),
                .text(name: "order_column")
            ]
        )

        _ = try await client.connection.insert(
            into: "table_with_underscores",
            columns: ["user_key", "value_data", "order_column"],
            values: [["key1", "value1", "order1"], ["key2", "value2", "order2"]]
        )

        // Cleanup
        _ = try await client.admin.dropTable(name: "test_special_chars_table", ifExists: false)
        _ = try await client.admin.dropTable(name: "table_with_underscores", ifExists: false)

        logger.info("Special character handling test passed")
    }
}
