import XCTest
import Logging
@testable import PostgresKit

final class SimpleSequenceTest: XCTestCase {
    private var client: PostgresDatabaseClient!
    private var testLogger: Logger!

    override func setUp() async throws {
        try await super.setUp()
        testLogger = Logger(label: "sequence-tests")

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
            applicationName: "SimpleSequenceTest"
        )

        client = try await PostgresDatabaseClient.connect(configuration: config, logger: testLogger)
    }

    override func tearDown() {
        client?.close()
        super.tearDown()
    }

    func testBasicSequenceOperations() async throws {
        print("=== Testing Basic Sequence Operations ===")

        // Clean up if sequence exists
        _ = try await client.dropSequence(name: "test_simple_seq", ifExists: true)

        // Create basic sequence
        _ = try await client.createSequence(name: "test_simple_seq")

        // Test nextval - using the new API method
        let nextVal1 = try await client.nextval("test_simple_seq")
        XCTAssertEqual(nextVal1, 1)

        let nextVal2 = try await client.nextval("test_simple_seq")
        XCTAssertEqual(nextVal2, 2)

        // Test currval (after nextval has been called) - using the new API method
        let currVal = try await client.currval("test_simple_seq")
        XCTAssertEqual(currVal, 2)

        // Test sequence with table - using the new API
        _ = try await client.dropTable(name: "test_seq_table", ifExists: true)
        _ = try await client.createTable(
            name: "test_seq_table",
            columns: [
                .integer(name: "id", nullable: false, defaultValue: nil),
                .varchar(name: "name", length: 50, nullable: false)
            ]
        )

        // Now we need to set up the default value using raw SQL since we don't have a method for this yet
        _ = try await client.simpleQuery("ALTER TABLE test_seq_table ALTER COLUMN id SET DEFAULT nextval('test_simple_seq')")

        // Insert data using sequence
        _ = try await client.simpleQuery("INSERT INTO test_seq_table (name) VALUES ('test1')")
        _ = try await client.simpleQuery("INSERT INTO test_seq_table (name) VALUES ('test2')")

        // Verify sequence-generated IDs
        let resultRows = try await client.simpleQuery("SELECT id, name FROM test_seq_table ORDER BY id")
        var results: [(Int, String)] = []
        for try await (id, name) in resultRows.decode((Int, String).self) {
            results.append((id, name))
        }
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].0, 3) // Should continue from 3
        XCTAssertEqual(results[0].1, "test1")
        XCTAssertEqual(results[1].0, 4)
        XCTAssertEqual(results[1].1, "test2")

        // Test setval - using the new API method
        _ = try await client.setval("test_simple_seq", value: 100)
        let nextVal3 = try await client.nextval("test_simple_seq")
        XCTAssertEqual(nextVal3, 101)

        // Clean up - using the new API
        _ = try await client.dropTable(name: "test_seq_table", ifExists: false)
        _ = try await client.dropSequence(name: "test_simple_seq", ifExists: false)

        print("✓ Basic sequence operations test passed")
    }

    func testSequenceWithOptions() async throws {
        print("=== Testing Sequence Options ===")

        // Clean up if sequence exists
        _ = try await client.dropSequence(name: "test_options_seq", ifExists: true)

        // Create sequence with options - using the new API
        _ = try await client.createSequence(
            name: "test_options_seq",
            startWith: 10,
            incrementBy: 5,
            minValue: 5,
            maxValue: 50,
            cycle: true
        )

        // Test initial value - using the new API method
        let nextVal1 = try await client.nextval("test_options_seq")
        XCTAssertEqual(nextVal1, 10)

        let nextVal2 = try await client.nextval("test_options_seq")
        XCTAssertEqual(nextVal2, 15)

        let nextVal3 = try await client.nextval("test_options_seq")
        XCTAssertEqual(nextVal3, 20)

        // Clean up
        _ = try await client.dropSequence(name: "test_options_seq", ifExists: false)

        print("✓ Sequence options test passed")
    }

    func testTemporarySequence() async throws {
        print("=== Testing Temporary Sequence ===")

        // Create temporary sequence - using the new API
        _ = try await client.createSequence(
            name: "temp_test_seq",
            temporary: true,
            startWith: 1000
        )

        // Test temporary sequence - using the new API method
        let nextVal = try await client.nextval("temp_test_seq")
        XCTAssertEqual(nextVal, 1000)

        // Temporary sequences don't need explicit cleanup - dropped at session end
        print("✓ Temporary sequence test passed")
    }
}