import XCTest
import Logging
@testable import PostgresKit

final class BasicTests: PostgresKitTestCase {

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
            applicationName: "BasicTests"
        )

        client = try await PostgresKit.PostgresClient.connect(configuration: config, logger: testLogger)
    }

    override func tearDown() {
        client?.close()
        super.tearDown()
    }

    // MARK: - Basic Connection Tests

    func testBasicConnection() async throws {
        let rows = try await client.connection.simpleQuery("SELECT 1 as test_value")
        var values: [Int] = []
        for try await value in rows.decode(Int.self) {
            values.append(value)
        }
        XCTAssertEqual(values, [1])
    }

    func testSimpleQuery() async throws {
        let rows = try await client.connection.simpleQuery("SELECT 'hello' as message")
        var messages: [String] = []
        for try await message in rows.decode(String.self) {
            messages.append(message)
        }
        XCTAssertEqual(messages, ["hello"])
    }

    func testParameterizedQuery() async throws {
        let result = try await client.connection.withConnection { conn in
            try await conn.query("SELECT $1::text as value", binds: [PGData(string: "parameterized")])
        }

        var values: [String] = []
        for try await value in result.decode(String.self) {
            values.append(value)
        }
        XCTAssertEqual(values, ["parameterized"])
    }

    func testMultipleParameterBinding() async throws {
        let result = try await client.connection.withConnection { conn in
            try await conn.query(
                "SELECT $1::text as text, $2::integer as number, $3::boolean as bool",
                binds: [
                    PGData(string: "test"),
                    PGData(int32: 123),
                    PGData(bool: true)
                ]
            )
        }

        var count = 0
        for try await _ in result.decode((String, Int32, Bool).self) {
            count += 1
        }
        XCTAssertEqual(count, 1)
    }

    // MARK: - Data Type Tests

    func testBasicDataTypes() async throws {
        let result = try await client.connection.withConnection { conn in
            try await conn.query("""
                SELECT
                    $1::text as text_field,
                    $2::integer as int_field,
                    $3::bigint as bigint_field,
                    $4::boolean as bool_field,
                    $5::real as real_field,
                    $6::double precision as double_field
            """, binds: [
                PGData(string: "test_text"),
                PGData(int32: 42),
                PGData(int64: 1234567890),
                PGData(bool: true),
                PGData(float: 3.14),
                PGData(double: 2.718281828459045)
            ])
        }

        var count = 0
        for try await _ in result.decode((String, Int32, Int64, Bool, Float, Double).self) {
            count += 1
        }
        XCTAssertEqual(count, 1)
    }

    func testNullValueHandling() async throws {
        let result = try await client.connection.withConnection { conn in
            try await conn.query("SELECT NULL as null_value, 'not_null' as text_value", binds: [])
        }

        var count = 0
        for try await _ in result.decode((String?, String).self) {
            count += 1
        }
        XCTAssertEqual(count, 1)
    }

    // MARK: - Transaction Tests

    func testSimpleTransaction() async throws {
        _ = try await client.admin.createTable(
            name: "test_tx",
            columns: [
                .serial(name: "id", primaryKey: true),
                .text(name: "value")
            ],
            temporary: true
        )

        let log = self.logger
        let result = try await client.connection.withConnection { conn in
            _ = try await conn.beginTransaction()
            _ = try await conn.insert(into: "test_tx", columns: ["value"], values: [["test1"], ["test2"]])
            _ = try await conn.commit()

            // Simple approach: test each query individually
            var insertCount = 0

            // Count the rows using a simple approach
            let countRows = try await conn.simpleQuery("SELECT COUNT(*)::text FROM test_tx")
            for try await countStr in countRows.decode(String.self) {
                if let intVal = Int(countStr) {
                    insertCount = intVal
                }
                break
            }
            log.debug("testSimpleTransaction: Final COUNT = \(insertCount)")

            return Int32(insertCount)
        }

        XCTAssertEqual(result, 2)
    }

    func testTransactionRollback() async throws {
        _ = try await client.admin.createTable(
            name: "test_rollback",
            columns: [
                .serial(name: "id", primaryKey: true),
                .text(name: "value")
            ],
            temporary: true
        )

        let log2 = self.logger
        let result = try await client.connection.withConnection { conn in
            _ = try await conn.beginTransaction()
            _ = try await conn.insert(into: "test_rollback", columns: ["value"], values: [["rollback_test"]])
            _ = try await conn.rollback()

            // Simple approach: test each query individually
            var rollbackCount = 0

            // Count the rows using a simple approach
            let countRows = try await conn.simpleQuery("SELECT COUNT(*)::text FROM test_rollback")
            for try await countStr in countRows.decode(String.self) {
                if let intVal = Int(countStr) {
                    rollbackCount = intVal
                }
                break
            }
            log2.debug("testTransactionRollback: Final COUNT = \(rollbackCount)")

            return Int32(rollbackCount)
        }

        XCTAssertEqual(result, 0)
    }

    // MARK: - Error Handling Tests

    func testQueryErrorHandling() async throws {
        do {
            _ = try await client.connection.simpleQuery("SELECT * FROM nonexistent_table")
            XCTFail("Expected query to fail")
        } catch {
            XCTAssertTrue(error is PostgresError || error is PostgresKitError || error is PSQLError)
        }
    }

    func testParameterizedQueryError() async throws {
        do {
            _ = try await client.connection.withConnection { conn in
                try await conn.query("SELECT * FROM nonexistent_table", binds: [])
            }
            XCTFail("Expected query to fail")
        } catch {
            XCTAssertTrue(error is PostgresError || error is PostgresKitError || error is PSQLError)
        }
    }

    // MARK: - Streaming Tests

    func testBasicStreaming() async throws {
        let result = try await client.connection.streamQuery(
            "SELECT generate_series(1, 10) as number"
        ) { _ in
            // Simple callback that doesn't need to capture mutable state
        }

        // If we get here without error, streaming worked
        XCTAssertNotNil(result)
    }

    func testStreamingWithConfiguration() async throws {
        let config = PostgresStreamConfiguration {
            $0.initialPreviewRows = 5
            $0.streamingFetchSize = 10
        }

        let result = try await client.connection.streamQuery(
            "SELECT generate_series(1, 20) as number",
            configuration: config
        ) { _ in
            // Simple callback
        }

        // If we get here without error, streaming with config worked
        XCTAssertNotNil(result)
    }

    // MARK: - Connection Management Tests

    func testMultipleConnections() async throws {
        let result1 = try await client.connection.simpleQuery("SELECT 1")
        let result2 = try await client.connection.simpleQuery("SELECT 2")
        let result3 = try await client.connection.simpleQuery("SELECT 3")

        let values1 = try await result1.decode(Int.self).reduce(into: []) { $0.append($1) }
        let values2 = try await result2.decode(Int.self).reduce(into: []) { $0.append($1) }
        let values3 = try await result3.decode(Int.self).reduce(into: []) { $0.append($1) }

        XCTAssertEqual(values1, [1])
        XCTAssertEqual(values2, [2])
        XCTAssertEqual(values3, [3])
    }

    func testConnectionReuse() async throws {
        let result1 = try await client.connection.withConnection { conn in
            try await conn.simpleQuery("SELECT 1")
        }

        let result2 = try await client.connection.withConnection { conn in
            try await conn.simpleQuery("SELECT 2")
        }

        let values1 = try await result1.decode(Int.self).reduce(into: []) { $0.append($1) }
        let values2 = try await result2.decode(Int.self).reduce(into: []) { $0.append($1) }

        XCTAssertEqual(values1, [1])
        XCTAssertEqual(values2, [2])
    }

    // MARK: - Edge Cases

    func testEmptyResultSet() async throws {
        let result = try await client.connection.simpleQuery("SELECT 1 WHERE 1 = 0")
        var count = 0
        for try await _ in result.decode(Int.self) {
            count += 1
        }
        XCTAssertEqual(count, 0)
    }

    func testSingleRowResult() async throws {
        let result = try await client.connection.simpleQuery("SELECT 42 as answer")
        var answers: [Int] = []
        for try await answer in result.decode(Int.self) {
            answers.append(answer)
        }
        XCTAssertEqual(answers, [42])
    }

    func testSpecialCharacters() async throws {
        let specialText = "Special chars: àáâãäåæçèéêë"

        let result = try await client.connection.withConnection { conn in
            try await conn.query("SELECT $1::text as special_text", binds: [PGData(string: specialText)])
        }

        var retrievedText: String?
        for try await text in result.decode(String.self) {
            retrievedText = text
        }

        XCTAssertEqual(retrievedText, specialText)
    }
}
