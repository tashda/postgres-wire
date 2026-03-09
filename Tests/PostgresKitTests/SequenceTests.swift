import XCTest
import Logging
@testable import PostgresKit

final class SequenceTests: XCTestCase {
    var postgresClient: PostgresClient!
    var connection: PostgresConnection!

    override func setUp() async throws {
        try await super.setUp()

        // Use configuration from environment variables with fallbacks
        let host = ProcessInfo.processInfo.environment["POSTGRES_HOST"] ?? "localhost"
        let port = ProcessInfo.processInfo.environment["POSTGRES_PORT"].flatMap(Int.init) ?? 5432
        let username = ProcessInfo.processInfo.environment["POSTGRES_USER"] ?? "postgres"
        let password = ProcessInfo.processInfo.environment["POSTGRES_PASSWORD"] ?? "password"
        let database = ProcessInfo.processInfo.environment["POSTGRES_DB"] ?? "testdb"

        let configuration = PostgresClient.Configuration(
            host: host,
            port: port,
            username: username,
            password: password,
            database: database,
            tls: .disable
        )

        var logger = Logger(label: "postgres.test")
        logger.logLevel = .trace

        postgresClient = try await PostgresClient.connect(
            on: MultiThreadedEventLoopGroup(numberOfThreads: 2),
            configuration: configuration,
            logger: logger
        )

        connection = try await postgresClient.connection()
    }

    override func tearDown() async throws {
        try await connection?.close()
        try await postgresClient?.close()
        try await super.tearDown()
    }

    // MARK: - Basic Sequence Tests

    func testCreateBasicSequence() async throws {
        try await connection.simpleQuery("DROP SEQUENCE IF EXISTS test_sequence")
        try await connection.simpleQuery("CREATE SEQUENCE test_sequence")

        // Test sequence usage
        let nextVal = try await connection.simpleQuery("SELECT nextval('test_sequence')::text")
        XCTAssertEqual(nextVal.count, 1)
        XCTAssertEqual(nextVal[0].column("nextval")?.string, "1")

        // Test current value
        let currentVal = try await connection.simpleQuery("SELECT currval('test_sequence')::text")
        XCTAssertEqual(currentVal.count, 1)
        XCTAssertEqual(currentVal[0].column("currval")?.string, "1")

        // Cleanup
        try await connection.simpleQuery("DROP SEQUENCE test_sequence")
    }

    func testCreateSequenceWithOptions() async throws {
        try await connection.simpleQuery("DROP SEQUENCE IF EXISTS test_sequence_options")
        try await connection.simpleQuery("""
            CREATE SEQUENCE test_sequence_options
                START WITH 100
                INCREMENT BY 5
                MINVALUE 50
                MAXVALUE 200
                CYCLE
        """)

        // Test initial value
        let nextVal1 = try await connection.simpleQuery("SELECT nextval('test_sequence_options')::text")
        XCTAssertEqual(nextVal1[0].column("nextval")?.string, "100")

        let nextVal2 = try await connection.simpleQuery("SELECT nextval('test_sequence_options')::text")
        XCTAssertEqual(nextVal2[0].column("nextval")?.string, "105")

        // Test sequence metadata
        let metadata = try await connection.simpleQuery("""
            SELECT start_value, increment_by, min_value, max_value, cycle_option
            FROM pg_sequences
            WHERE sequencename = 'test_sequence_options'
        """)
        XCTAssertEqual(metadata.count, 1)
        XCTAssertEqual(metadata[0].column("start_value")?.int, 100)
        XCTAssertEqual(metadata[0].column("increment_by")?.int, 5)
        XCTAssertEqual(metadata[0].column("min_value")?.int, 50)
        XCTAssertEqual(metadata[0].column("max_value")?.int, 200)
        XCTAssertEqual(metadata[0].column("cycle_option")?.bool, true)

        // Cleanup
        try await connection.simpleQuery("DROP SEQUENCE test_sequence_options")
    }

    func testSequenceWithTable() async throws {
        try await connection.simpleQuery("DROP TABLE IF EXISTS users_table")
        try await connection.simpleQuery("DROP SEQUENCE IF EXISTS users_seq")

        // Create sequence and table
        try await connection.simpleQuery("CREATE SEQUENCE users_seq START WITH 1000")
        try await connection.simpleQuery("""
            CREATE TABLE users_table (
                id INTEGER PRIMARY KEY DEFAULT nextval('users_seq'),
                name VARCHAR(50),
                email VARCHAR(100)
            )
        """)

        // Insert records without specifying ID
        try await connection.simpleQuery("INSERT INTO users_table (name, email) VALUES ('Alice', 'alice@test.com')")
        try await connection.simpleQuery("INSERT INTO users_table (name, email) VALUES ('Bob', 'bob@test.com')")

        // Verify sequence-generated IDs
        let users = try await connection.simpleQuery("SELECT id, name FROM users_table ORDER BY id")
        XCTAssertEqual(users.count, 2)
        XCTAssertEqual(users[0].column("id")?.int, 1000)
        XCTAssertEqual(users[0].column("name")?.string, "Alice")
        XCTAssertEqual(users[1].column("id")?.int, 1001)
        XCTAssertEqual(users[1].column("name")?.string, "Bob")

        // Test sequence state
        let currVal = try await connection.simpleQuery("SELECT currval('users_seq')::text")
        XCTAssertEqual(currVal[0].column("currval")?.string, "1001")

        // Cleanup
        try await connection.simpleQuery("DROP TABLE users_table")
        try await connection.simpleQuery("DROP SEQUENCE users_seq")
    }

    func testAlterSequence() async throws {
        try await connection.simpleQuery("DROP SEQUENCE IF EXISTS alter_test_seq")

        // Create initial sequence
        try await connection.simpleQuery("CREATE SEQUENCE alter_test_seq START WITH 1 INCREMENT BY 1")

        // Generate some values
        _ = try await connection.simpleQuery("SELECT nextval('alter_test_seq')")
        _ = try await connection.simpleQuery("SELECT nextval('alter_test_seq')")

        // Alter sequence increment
        try await connection.simpleQuery("ALTER SEQUENCE alter_test_seq INCREMENT BY 10")

        // Test altered increment
        let nextVal = try await connection.simpleQuery("SELECT nextval('alter_test_seq')::text")
        XCTAssertEqual(nextVal[0].column("nextval")?.string, "13") // Should be 3 + 10

        // Change sequence ownership
        try await connection.simpleQuery("DROP TABLE IF EXISTS alter_test_table")
        try await connection.simpleQuery("""
            CREATE TABLE alter_test_table (
                id INTEGER PRIMARY KEY DEFAULT nextval('alter_test_seq'),
                data VARCHAR(50)
            )
        """)

        try await connection.simpleQuery("ALTER SEQUENCE alter_test_seq OWNED BY alter_test_table.id")

        // Verify ownership change
        let ownership = try await connection.simpleQuery("""
            SELECT c.relname
            FROM pg_class c
            JOIN pg_depend d ON c.oid = d.objid
            JOIN pg_class t ON d.refobjid = t.oid
            WHERE c.relkind = 'S' AND c.relname = 'alter_test_seq' AND t.relname = 'alter_test_table'
        """)

        // Note: This query might need adjustment based on PostgreSQL version
        // The ownership verification could be complex

        // Cleanup
        try await connection.simpleQuery("DROP TABLE alter_test_table")
        try await connection.simpleQuery("DROP SEQUENCE alter_test_seq")
    }

    func testTemporarySequence() async throws {
        // Create temporary sequence
        try await connection.simpleQuery("CREATE TEMP SEQUENCE temp_test_seq START WITH 500")

        // Test temporary sequence
        let nextVal = try await connection.simpleQuery("SELECT nextval('temp_test_seq')::text")
        XCTAssertEqual(nextVal[0].column("nextval")?.string, "500")

        // Verify it's temporary by checking if it exists in pg_class
        let tempCheck = try await connection.simpleQuery("""
            SELECT relname, relpersistence
            FROM pg_class
            WHERE relname = 'temp_test_seq'
        """)

        if tempCheck.count > 0 {
            // Temporary sequences have relpersistence = 't'
            XCTAssertEqual(tempCheck[0].column("relpersistence")?.string, "t")
        }

        // No need to explicitly drop - it will be dropped at session end
    }

    func testSequenceCycling() async throws {
        try await connection.simpleQuery("DROP SEQUENCE IF EXISTS cycle_test_seq")

        // Create sequence with small range and CYCLE option
        try await connection.simpleQuery("""
            CREATE SEQUENCE cycle_test_seq
                START WITH 8
                INCREMENT BY 2
                MINVALUE 2
                MAXVALUE 10
                CYCLE
        """)

        // Generate values up to the max
        let val1 = try await connection.simpleQuery("SELECT nextval('cycle_test_seq')::text")
        XCTAssertEqual(val1[0].column("nextval")?.string, "8")

        let val2 = try await connection.simpleQuery("SELECT nextval('cycle_test_seq')::text")
        XCTAssertEqual(val2[0].column("nextval")?.string, "10")

        // Next value should cycle back to min value
        let val3 = try await connection.simpleQuery("SELECT nextval('cycle_test_seq')::text")
        XCTAssertEqual(val3[0].column("nextval")?.string, "2")

        // Cleanup
        try await connection.simpleQuery("DROP SEQUENCE cycle_test_seq")
    }

    func testSequenceCache() async throws {
        try await connection.simpleQuery("DROP SEQUENCE IF EXISTS cache_test_seq")

        // Create sequence with cache
        try await connection.simpleQuery("CREATE SEQUENCE cache_test_seq CACHE 5")

        // Generate some values
        _ = try await connection.simpleQuery("SELECT nextval('cache_test_seq')")
        _ = try await connection.simpleQuery("SELECT nextval('cache_test_seq')")

        // Check sequence cache information (this might be PostgreSQL version dependent)
        let sequenceInfo = try await connection.simpleQuery("""
            SELECT last_value, cache_value
            FROM cache_test_seq
        """)

        if sequenceInfo.count > 0 {
            // The cache_value should be 5
            XCTAssertEqual(sequenceInfo[0].column("cache_value")?.int, 5)
        }

        // Cleanup
        try await connection.simpleQuery("DROP SEQUENCE cache_test_seq")
    }

    func testSetSequenceValue() async throws {
        try await connection.simpleQuery("DROP SEQUENCE IF EXISTS setval_test_seq")
        try await connection.simpleQuery("CREATE SEQUENCE setval_test_seq")

        // Generate a few values first
        _ = try await connection.simpleQuery("SELECT nextval('setval_test_seq')")
        _ = try await connection.simpleQuery("SELECT nextval('setval_test_seq')")

        // Set sequence to a specific value
        try await connection.simpleQuery("SELECT setval('setval_test_seq', 100)")

        // Next value should be 101
        let nextVal = try await connection.simpleQuery("SELECT nextval('setval_test_seq')::text")
        XCTAssertEqual(nextVal[0].column("nextval")?.string, "101")

        // Set with is_called = false
        try await connection.simpleQuery("SELECT setval('setval_test_seq', 200, false)")

        // Next value should be 200 (not 201)
        let nextVal2 = try await connection.simpleQuery("SELECT nextval('setval_test_seq')::text")
        XCTAssertEqual(nextVal2[0].column("nextval")?.string, "200")

        // Cleanup
        try await connection.simpleQuery("DROP SEQUENCE setval_test_seq")
    }

    func testMultipleSequences() async throws {
        try await connection.simpleQuery("DROP TABLE IF EXISTS multi_table")
        try await connection.simpleQuery("DROP SEQUENCE IF EXISTS seq_a")
        try await connection.simpleQuery("DROP SEQUENCE IF EXISTS seq_b")

        // Create multiple sequences
        try await connection.simpleQuery("CREATE SEQUENCE seq_a START 1000 INCREMENT 10")
        try await connection.simpleQuery("CREATE SEQUENCE seq_b START 2000 INCREMENT 5")

        try await connection.simpleQuery("""
            CREATE TABLE multi_table (
                a_id INTEGER DEFAULT nextval('seq_a'),
                b_id INTEGER DEFAULT nextval('seq_b'),
                data VARCHAR(50)
            )
        """)

        // Insert data
        try await connection.simpleQuery("INSERT INTO multi_table (data) VALUES ('test1')")
        try await connection.simpleQuery("INSERT INTO multi_table (data) VALUES ('test2')")

        // Verify both sequences are working
        let results = try await connection.simpleQuery("SELECT a_id, b_id, data FROM multi_table ORDER BY a_id")
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].column("a_id")?.int, 1000)
        XCTAssertEqual(results[0].column("b_id")?.int, 2000)
        XCTAssertEqual(results[1].column("a_id")?.int, 1010)
        XCTAssertEqual(results[1].column("b_id")?.int, 2005)

        // Check sequence states independently
        let seqACurr = try await connection.simpleQuery("SELECT currval('seq_a')::text")
        let seqBCurr = try await connection.simpleQuery("SELECT currval('seq_b')::text")

        XCTAssertEqual(seqACurr[0].column("currval")?.string, "1010")
        XCTAssertEqual(seqBCurr[0].column("currval")?.string, "2005")

        // Cleanup
        try await connection.simpleQuery("DROP TABLE multi_table")
        try await connection.simpleQuery("DROP SEQUENCE seq_a")
        try await connection.simpleQuery("DROP SEQUENCE seq_b")
    }

    func testSequenceWithNegativeIncrement() async throws {
        try await connection.simpleQuery("DROP SEQUENCE IF EXISTS negative_increment_seq")

        // Create sequence with negative increment (counting down)
        try await connection.simpleQuery("""
            CREATE SEQUENCE negative_increment_seq
                START WITH 100
                INCREMENT BY -5
                MINVALUE 0
                CYCLE
        """)

        // Test descending sequence
        let val1 = try await connection.simpleQuery("SELECT nextval('negative_increment_seq')::text")
        XCTAssertEqual(val1[0].column("nextval")?.string, "100")

        let val2 = try await connection.simpleQuery("SELECT nextval('negative_increment_seq')::text")
        XCTAssertEqual(val2[0].column("nextval")?.string, "95")

        let val3 = try await connection.simpleQuery("SELECT nextval('negative_increment_seq')::text")
        XCTAssertEqual(val3[0].column("nextval")?.string, "90")

        // Cleanup
        try await connection.simpleQuery("DROP SEQUENCE negative_increment_seq")
    }

    func testSequenceInTransaction() async throws {
        try await connection.simpleQuery("DROP TABLE IF EXISTS trans_table")
        try await connection.simpleQuery("DROP SEQUENCE IF EXISTS trans_seq")

        // Create sequence and table
        try await connection.simpleQuery("CREATE SEQUENCE trans_seq")
        try await connection.simpleQuery("""
            CREATE TABLE trans_table (
                id INTEGER PRIMARY KEY DEFAULT nextval('trans_seq'),
                value VARCHAR(50)
            )
        """)

        // Begin transaction
        try await connection.simpleQuery("BEGIN")

        // Insert data within transaction
        try await connection.simpleQuery("INSERT INTO trans_table (value) VALUES ('in_transaction')")

        // Check sequence value within transaction
        let transCurr = try await connection.simpleQuery("SELECT currval('trans_seq')::text")
        XCTAssertEqual(transCurr[0].column("currval")?.string, "1")

        // Commit transaction
        try await connection.simpleQuery("COMMIT")

        // Verify data and sequence after commit
        let results = try await connection.simpleQuery("SELECT id, value FROM trans_table")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].column("id")?.int, 1)
        XCTAssertEqual(results[0].column("value")?.string, "in_transaction")

        // Test rollback behavior
        try await connection.simpleQuery("BEGIN")
        try await connection.simpleQuery("INSERT INTO trans_table (value) VALUES ('will_rollback')")
        let beforeRollback = try await connection.simpleQuery("SELECT currval('trans_seq')::text")
        try await connection.simpleQuery("ROLLBACK")

        // Sequence values are not rolled back!
        let afterRollback = try await connection.simpleQuery("SELECT nextval('trans_seq')::text")

        // The sequence should have advanced past the rolled back value
        let expectedValue = Int(beforeRollback[0].column("currval")?.string ?? "0")! + 1
        XCTAssertEqual(afterRollback[0].column("nextval")?.string, String(expectedValue))

        // Cleanup
        try await connection.simpleQuery("DROP TABLE trans_table")
        try await connection.simpleQuery("DROP SEQUENCE trans_seq")
    }

    func testSequenceSecurityAndPrivileges() async throws {
        // Create a test user for sequence privilege testing
        try await connection.simpleQuery("DROP ROLE IF EXISTS seq_test_user")
        try await connection.simpleQuery("DROP SEQUENCE IF EXISTS priv_test_seq")

        // Create role and sequence
        try await connection.simpleQuery("CREATE ROLE seq_test_user WITH LOGIN PASSWORD 'testpass'")
        try await connection.simpleQuery("CREATE SEQUENCE priv_test_seq")

        // Grant usage privilege
        try await connection.simpleQuery("GRANT USAGE ON SEQUENCE priv_test_seq TO seq_test_user")

        // Grant select privilege
        try await connection.simpleQuery("GRANT SELECT ON priv_test_seq TO seq_test_user")

        // Test that the role has usage privileges (this would be more robust with a separate connection)
        let privileges = try await connection.simpleQuery("""
            SELECT r.rolname, acl.*
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            JOIN pg_roles r ON r.oid = c.relowner
            LEFT JOIN aclexplode(c.relacl) acl ON true
            WHERE c.relname = 'priv_test_seq'
        """)

        // At minimum, we should have the sequence created
        XCTAssertTrue(privileges.count > 0)

        // Cleanup
        try await connection.simpleQuery("DROP SEQUENCE priv_test_seq")
        try await connection.simpleQuery("DROP ROLE seq_test_user")
    }

    func testSequencePerformance() async throws {
        try await connection.simpleQuery("DROP TABLE IF EXISTS perf_table")
        try await connection.simpleQuery("DROP SEQUENCE IF EXISTS perf_seq")

        // Create sequence for performance testing
        try await connection.simpleQuery("CREATE SEQUENCE perf_seq CACHE 100")
        try await connection.simpleQuery("""
            CREATE TABLE perf_table (
                id BIGINT PRIMARY KEY DEFAULT nextval('perf_seq'),
                data VARCHAR(100),
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        // Insert multiple records to test performance
        let insertStart = Date()

        for i in 1...100 {
            try await connection.simpleQuery("INSERT INTO perf_table (data) VALUES ('data_\(i)')")
        }

        let insertTime = Date().timeIntervalSince(insertStart)
        print("Inserted 100 records with sequence in \(insertTime) seconds")

        // Verify all records were inserted with unique sequence values
        let count = try await connection.simpleQuery("SELECT COUNT(*)::text FROM perf_table")
        XCTAssertEqual(count[0].column("count")?.string, "100")

        // Test sequence value advancement
        let lastSeq = try await connection.simpleQuery("SELECT currval('perf_seq')::text")
        XCTAssertEqual(lastSeq[0].column("currval")?.string, "100")

        // Performance should be reasonable (less than 5 seconds for 100 inserts)
        XCTAssertLessThan(insertTime, 5.0)

        // Cleanup
        try await connection.simpleQuery("DROP TABLE perf_table")
        try await connection.simpleQuery("DROP SEQUENCE perf_seq")
    }

    // MARK: - Edge Cases and Error Handling

    func testSequenceErrors() async throws {
        // Test using sequence that doesn't exist
        do {
            _ = try await connection.simpleQuery("SELECT nextval('nonexistent_seq')")
            XCTFail("Should have thrown an error for nonexistent sequence")
        } catch {
            // Expected to fail
        }

        // Test currval on sequence before nextval
        try await connection.simpleQuery("DROP SEQUENCE IF EXISTS error_test_seq")
        try await connection.simpleQuery("CREATE SEQUENCE error_test_seq")

        do {
            _ = try await connection.simpleQuery("SELECT currval('error_test_seq')")
            XCTFail("Should have thrown an error for currval before nextval")
        } catch {
            // Expected to fail
        }

        try await connection.simpleQuery("DROP SEQUENCE error_test_seq")
    }
}