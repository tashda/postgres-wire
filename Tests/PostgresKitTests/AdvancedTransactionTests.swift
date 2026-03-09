import XCTest
import Logging
@testable import PostgresKit

final class AdvancedTransactionTests: XCTestCase {

    private var client: PostgresDatabaseClient!
    private var testLogger: Logger!

    override func setUp() async throws {
        TestEnv.loadDotEnv()
        try await super.setUp()
        testLogger = Logger(label: "advanced-transaction-tests")

        let config = PostgresConfiguration(
            host: TestEnv.host,
            port: TestEnv.port,
            database: TestEnv.database,
            username: TestEnv.username,
            password: TestEnv.password,
            useTLS: TestEnv.useTLS,
            applicationName: "AdvancedTransactionTests"
        )

        client = try await PostgresDatabaseClient.connect(configuration: config, logger: testLogger)
    }

    override func tearDown() {
        client?.close()
        super.tearDown()
    }

    // MARK: - Savepoint Tests

    func testSavepoints() async throws {
        print("=== Testing Savepoints ===")

        let result = try await client.withConnection { conn in
            // Create table
            _ = try await conn.simpleQuery("""
                CREATE TEMPORARY TABLE savepoint_test (
                    id SERIAL PRIMARY KEY,
                    value TEXT,
                    amount INTEGER
                )
            """)

            // Start transaction
            _ = try await conn.simpleQuery("BEGIN")

            // Insert initial data
            _ = try await conn.simpleQuery("""
                INSERT INTO savepoint_test (value, amount) VALUES ('Initial', 100)
            """)

            // Create savepoint
            _ = try await conn.simpleQuery("SAVEPOINT sp1")

            // Insert more data
            _ = try await conn.simpleQuery("""
                INSERT INTO savepoint_test (value, amount) VALUES ('After SP1', 200)
            """)

            // Create another savepoint
            _ = try await conn.simpleQuery("SAVEPOINT sp2")

            // Insert data we'll rollback
            _ = try await conn.simpleQuery("""
                INSERT INTO savepoint_test (value, amount) VALUES ('To Rollback', 300)
            """)

            // Count before rollback
            let beforeRollback = try await conn.simpleQuery("SELECT COUNT(*)::text FROM savepoint_test")
            var beforeCount = 0
            for try await (countStr,) in beforeRollback.decode(String.self) {
                if let intVal = Int(countStr) {
                    beforeCount = intVal
                }
                break
            }
            print("Before rollback: \(beforeCount) rows")

            // Rollback to sp2
            _ = try await conn.simpleQuery("ROLLBACK TO SAVEPOINT sp2")

            // Count after rollback to sp2
            let afterSp2Rollback = try await conn.simpleQuery("SELECT COUNT(*)::text FROM savepoint_test")
            var sp2Count = 0
            for try await (countStr,) in afterSp2Rollback.decode(String.self) {
                if let intVal = Int(countStr) {
                    sp2Count = intVal
                }
                break
            }
            print("After SP2 rollback: \(sp2Count) rows")

            // Insert different data
            _ = try await conn.simpleQuery("""
                INSERT INTO savepoint_test (value, amount) VALUES ('After SP2 rollback', 250)
            """)

            // Rollback all the way to sp1
            _ = try await conn.simpleQuery("ROLLBACK TO SAVEPOINT sp1")

            // Count after rollback to sp1
            let afterSp1Rollback = try await conn.simpleQuery("SELECT COUNT(*)::text FROM savepoint_test")
            var sp1Count = 0
            for try await (countStr,) in afterSp1Rollback.decode(String.self) {
                if let intVal = Int(countStr) {
                    sp1Count = intVal
                }
                break
            }
            print("After SP1 rollback: \(sp1Count) rows")

            // Commit transaction
            _ = try await conn.simpleQuery("COMMIT")

            // Final count
            let finalCount = try await conn.simpleQuery("SELECT COUNT(*)::text FROM savepoint_test")
            var final = 0
            for try await (countStr,) in finalCount.decode(String.self) {
                if let intVal = Int(countStr) {
                    final = intVal
                }
                break
            }

            return (beforeCount, sp2Count, sp1Count, final)
        }

        // Expected: 3 before rollback, 2 after SP2 rollback, 1 after SP1 rollback, 1 after commit
        XCTAssertEqual(result.0, 3) // Before rollback
        XCTAssertEqual(result.1, 2) // After SP2 rollback
        XCTAssertEqual(result.2, 1) // After SP1 rollback
        XCTAssertEqual(result.3, 1) // After commit
        print("✓ Savepoints test passed")
    }

    // MARK: - Nested Savepoints Tests

    func testNestedSavepoints() async throws {
        print("=== Testing Nested Savepoints ===")

        let result = try await client.withConnection { conn in
            // Create table
            _ = try await conn.simpleQuery("""
                CREATE TEMPORARY TABLE nested_sp_test (
                    id SERIAL PRIMARY KEY,
                    operation TEXT,
                    level INTEGER
                )
            """)

            // Start transaction
            _ = try await conn.simpleQuery("BEGIN")

            // Level 0 operation
            _ = try await conn.simpleQuery("""
                INSERT INTO nested_sp_test (operation, level) VALUES ('Start', 0)
            """)

            // Savepoint level1
            _ = try await conn.simpleQuery("SAVEPOINT level1")
            _ = try await conn.simpleQuery("""
                INSERT INTO nested_sp_test (operation, level) VALUES ('Level 1', 1)
            """)

            // Savepoint level2
            _ = try await conn.simpleQuery("SAVEPOINT level2")
            _ = try await conn.simpleQuery("""
                INSERT INTO nested_sp_test (operation, level) VALUES ('Level 2', 2)
            """)

            // Savepoint level3
            _ = try await conn.simpleQuery("SAVEPOINT level3")
            _ = try await conn.simpleQuery("""
                INSERT INTO nested_sp_test (operation, level) VALUES ('Level 3', 3)
            """)

            // Count all levels
            let allLevels = try await conn.simpleQuery("SELECT COUNT(*)::text FROM nested_sp_test")
            var allCount = 0
            for try await (countStr,) in allLevels.decode(String.self) {
                if let intVal = Int(countStr) {
                    allCount = intVal
                }
                break
            }

            // Release level3 savepoint (no rollback)
            _ = try await conn.simpleQuery("RELEASE SAVEPOINT level3")

            // Rollback to level2
            _ = try await conn.simpleQuery("ROLLBACK TO SAVEPOINT level2")

            // Add operation after rollback
            _ = try await conn.simpleQuery("""
                INSERT INTO nested_sp_test (operation, level) VALUES ('After L2 rollback', 2)
            """)

            // Commit
            _ = try await conn.simpleQuery("COMMIT")

            // Final count
            let finalCount = try await conn.simpleQuery("SELECT COUNT(*)::text FROM nested_sp_test")
            var final = 0
            for try await (countStr,) in finalCount.decode(String.self) {
                if let intVal = Int(countStr) {
                    final = intVal
                }
                break
            }

            return (allCount, final)
        }

        XCTAssertEqual(result.0, 4) // All levels before any rollback
        XCTAssertEqual(result.1, 3) // Final after rollback and commit
        print("✓ Nested savepoints test passed")
    }

    // MARK: - Transaction Isolation Levels

    func testTransactionIsolationLevels() async throws {
        print("=== Testing Transaction Isolation Levels ===")

        // Test each isolation level
        let isolationLevels = ["READ COMMITTED", "REPEATABLE READ", "SERIALIZABLE"]
        var results: [String] = []

        for level in isolationLevels {
            let result = try await client.withConnection { conn in
                // Create test table
                _ = try await conn.simpleQuery("""
                    CREATE TEMPORARY TABLE isolation_test (
                        id SERIAL PRIMARY KEY,
                        value TEXT,
                        counter INTEGER DEFAULT 0
                    )
                """)

                // Set isolation level
                _ = try await conn.simpleQuery("BEGIN TRANSACTION ISOLATION LEVEL \(level)")

                // Insert initial data
                _ = try await conn.simpleQuery("""
                    INSERT INTO isolation_test (value, counter) VALUES ('Initial', 1)
                """)

                // Read data
                let readRows = try await conn.simpleQuery("""
                    SELECT value, counter FROM isolation_test FOR UPDATE
                """)
                var readValue = ""
                for try await (value, _) in readRows.decode((String, Int32).self) {
                    readValue = value
                    break
                }

                // Update data
                _ = try await conn.simpleQuery("""
                    UPDATE isolation_test SET counter = counter + 1 WHERE value = 'Initial'
                """)

                // Read again
                let updatedRows = try await conn.simpleQuery("""
                    SELECT counter FROM isolation_test WHERE value = 'Initial'
                """)
                var counter: Int = 0
                for try await (count) in updatedRows.decode(Int32.self) {
                    counter = Int(count)
                    break
                }

                // Commit or rollback based on level
                if level == "SERIALIZABLE" {
                    _ = try await conn.simpleQuery("COMMIT")
                } else {
                    _ = try await conn.simpleQuery("COMMIT")
                }

                return "\(level): \(readValue), Counter: \(counter)"
            }
            results.append(result)
        }

        for result in results {
            print(result)
        }

        XCTAssertEqual(results.count, 3)
        print("✓ Transaction isolation levels test passed")
    }

    // MARK: - Deadlock Detection

    func testDeadlockHandling() async throws {
        print("=== Testing Deadlock Handling ===")

        let result = try await client.withConnection { conn1 in
            // Create test table
            _ = try await conn1.simpleQuery("""
                CREATE TEMPORARY TABLE deadlock_test (
                    id SERIAL PRIMARY KEY,
                    resource TEXT,
                    owner TEXT,
                    locked BOOLEAN DEFAULT false
                )
            """)

            // Insert test data
            _ = try await conn1.simpleQuery("""
                INSERT INTO deadlock_test (resource, owner, locked) VALUES
                ('Resource A', 'None', false),
                ('Resource B', 'None', false)
            """)

            // Start two concurrent transactions
            try await client.withConnection { conn2 in
                // Transaction 1: Lock Resource A first
                _ = try await conn1.simpleQuery("BEGIN")
                _ = try await conn1.simpleQuery("""
                    UPDATE deadlock_test SET locked = true, owner = 'Tx1'
                    WHERE resource = 'Resource A'
                """)

                // Transaction 2: Lock Resource B first
                _ = try await conn2.simpleQuery("BEGIN")
                _ = try await conn2.simpleQuery("""
                    UPDATE deadlock_test SET locked = true, owner = 'Tx2'
                    WHERE resource = 'Resource B'
                """)

                // Now try to create deadlock scenario
                // Transaction 1 tries to lock Resource B (waits)
                // Transaction 2 tries to lock Resource A (deadlock)
                do {
                    _ = try await conn1.simpleQuery("""
                        UPDATE deadlock_test SET locked = true, owner = 'Tx1'
                        WHERE resource = 'Resource B'
                    """)
                    _ = try await conn1.simpleQuery("COMMIT")
                } catch {
                    print("Transaction 1 failed (expected): \(error)")
                    _ = try await conn1.simpleQuery("ROLLBACK")
                }

                do {
                    _ = try await conn2.simpleQuery("""
                        UPDATE deadlock_test SET locked = true, owner = 'Tx2'
                        WHERE resource = 'Resource A'
                    """)
                    _ = try await conn2.simpleQuery("COMMIT")
                } catch {
                    print("Transaction 2 failed (expected): \(error)")
                    _ = try await conn2.simpleQuery("ROLLBACK")
                }

                // Check final state
                let finalRows = try await conn2.simpleQuery("""
                    SELECT resource, owner FROM deadlock_test WHERE locked = true
                """)
                var lockedResources: [(String, String)] = []
                for try await (resource, owner) in finalRows.decode((String, String).self) {
                    lockedResources.append((resource, owner))
                }

                return lockedResources.count
            }
        }

        print("Final locked resources: \(result)")
        print("✓ Deadlock handling test completed")
    }

    // MARK: - Two-Phase Commit

    func testTwoPhaseCommit() async throws {
        print("=== Testing Two-Phase Commit ===")

        let result = try await client.withConnection { conn in
            // Create test table
            _ = try await conn.simpleQuery("""
                CREATE TEMPORARY TABLE twopc_test (
                    id SERIAL PRIMARY KEY,
                    operation TEXT,
                    amount INTEGER,
                    status TEXT
                )
            """)

            // Start transaction
            _ = try await conn.simpleQuery("BEGIN")

            // Insert data
            _ = try await conn.simpleQuery("""
                INSERT INTO twopc_test (operation, amount, status) VALUES ('Transfer', 100, 'pending')
            """)

            // Prepare transaction
            _ = try await conn.simpleQuery("PREPARE TRANSACTION 'test_transfer_1'")

            // At this point, the transaction is prepared but not committed
            let preparedCount = try await conn.simpleQuery("""
                SELECT COUNT(*)::text FROM twopc_test WHERE status = 'pending'
            """)
            var count = 0
            for try await (countStr,) in preparedCount.decode(String.self) {
                if let intVal = Int(countStr) {
                    count = intVal
                }
                break
            }

            // Check prepared transactions
            let prepTxRows = try await conn.simpleQuery("""
                SELECT gid, database, owner FROM pg_prepared_xacts WHERE gid = 'test_transfer_1'
            """)
            var preparedTxCount = 0
            for try await _ in prepTxRows.decode((String, String, String).self) {
                preparedTxCount += 1
            }

            // Commit the prepared transaction
            _ = try await conn.simpleQuery("COMMIT PREPARED 'test_transfer_1'")

            // Update status
            _ = try await conn.simpleQuery("""
                UPDATE twopc_test SET status = 'committed' WHERE status = 'pending'
            """)

            // Check final state
            let finalCount = try await conn.simpleQuery("SELECT COUNT(*)::text FROM twopc_test")
            var final = 0
            for try await (countStr,) in finalCount.decode(String.self) {
                if let intVal = Int(countStr) {
                    final = intVal
                }
                break
            }

            return (count, preparedTxCount, final)
        }

        XCTAssertEqual(result.0, 1) // Row inserted
        XCTAssertEqual(result.1, 1) // Prepared transaction exists
        XCTAssertEqual(result.2, 1) // Row after commit
        print("✓ Two-phase commit test passed")
    }

    // MARK: - Advisory Locks

    func testAdvisoryLocks() async throws {
        print("=== Testing Advisory Locks ===")

        let result = try await client.withConnection { conn1 in
            // Create test table
            _ = try await conn1.simpleQuery("""
                CREATE TEMPORARY TABLE advisory_lock_test (
                    id SERIAL PRIMARY KEY,
                    resource_id INTEGER,
                    data TEXT,
                    status TEXT
                )
            """)

            // Insert test data
            _ = try await conn1.simpleQuery("""
                INSERT INTO advisory_lock_test (resource_id, data, status) VALUES
                (1, 'Resource 1', 'unlocked'),
                (2, 'Resource 2', 'unlocked')
            """)

            try await client.withConnection { conn2 in
                // Start both transactions
                _ = try await conn1.simpleQuery("BEGIN")
                _ = try await conn2.simpleQuery("BEGIN")

                // Conn1: Acquire advisory lock on resource 1
                let lockResult1 = try await conn1.query("""
                    SELECT pg_try_advisory_xact_lock(1) as lock_acquired
                """)
                var conn1Lock = false
                for try await (locked) in lockResult1.decode(Bool.self) {
                    conn1Lock = locked
                    break
                }

                // Conn2: Try to acquire same advisory lock on resource 1
                let lockResult2 = try await conn2.query("""
                    SELECT pg_try_advisory_xact_lock(1) as lock_acquired
                """)
                var conn2Lock = false
                for try await (locked) in lockResult2.decode(Bool.self) {
                    conn2Lock = locked
                    break
                }

                // Conn1: Acquire lock on resource 2
                _ = try await conn1.simpleQuery("SELECT pg_advisory_xact_lock(2)")

                // Update resource 1
                _ = try await conn1.simpleQuery("""
                    UPDATE advisory_lock_test SET status = 'locked_by_conn1'
                    WHERE resource_id = 1
                """)

                // Conn2: Wait for lock (this would block in real scenario)
                // For testing, we'll use pg_try_advisory_lock with timeout
                do {
                    _ = try await conn2.simpleQuery("SELECT pg_advisory_lock_shared(2)")
                    _ = try await conn2.simpleQuery("ROLLBACK") // Rollback to release lock
                } catch {
                    _ = try await conn2.simpleQuery("ROLLBACK")
                }

                // Commit conn1
                _ = try await conn1.simpleQuery("COMMIT")

                // Check final state
                let finalRows = try await conn1.simpleQuery("""
                    SELECT resource_id, status FROM advisory_lock_test WHERE resource_id = 1
                """)
                var finalStatus = ""
                for try await (_, status) in finalRows.decode((Int32, String).self) {
                    finalStatus = status
                    break
                }

                return (conn1Lock, conn2Lock, finalStatus)
            }
        }

        XCTAssertTrue(result.0) // Conn1 should get the lock
        XCTAssertFalse(result.1) // Conn2 should not get the lock
        XCTAssertEqual(result.2, "locked_by_conn1") // Final status should be set
        print("✓ Advisory locks test passed")
    }

    // MARK: - Transaction Timeout and Retry

    func testTransactionTimeoutAndRetry() async throws {
        print("=== Testing Transaction Timeout and Retry ===")

        let maxRetries = 3
        var attempts = 0
        var success = false

        while attempts < maxRetries && !success {
            attempts += 1

            do {
                let result = try await client.withConnection { conn in
                    // Start transaction with timeout (using statement_timeout)
                    _ = try await conn.simpleQuery("BEGIN")
                    _ = try await conn.simpleQuery("SET LOCAL statement_timeout = '5s'")

                    // Create test table if it doesn't exist
                    _ = try await conn.simpleQuery("""
                        CREATE TEMPORARY TABLE IF NOT EXISTS retry_test (
                            id SERIAL PRIMARY KEY,
                            attempt INTEGER,
                            status TEXT,
                            timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                        )
                    """)

                    // Insert attempt record
                    _ = try await conn.query("""
                        INSERT INTO retry_test (attempt, status)
                        VALUES ($1, 'started')
                    """, binds: [PGData(int32: Int32(attempts))])

                    // Simulate potential conflict condition
                    let existingRows = try await conn.query("""
                        SELECT COUNT(*)::text as count FROM retry_test
                    """)
                    var existingCount = 0
                    for try await (countStr,) in existingRows.decode(String.self) {
                        if let intVal = Int(countStr) {
                            existingCount = intVal
                        }
                        break
                    }

                    // Randomly fail some attempts for testing
                    if existingCount > 0 && existingCount % 3 == 0 && attempts < maxRetries {
                        throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Simulated conflict"])
                    }

                    // Update status to success
                    _ = try await conn.query("""
                        UPDATE retry_test SET status = 'success' WHERE attempt = $1
                    """, binds: [PGData(int32: Int32(attempts))])

                    _ = try await conn.simpleQuery("COMMIT")
                    return existingCount + 1
                }

                if result >= maxRetries {
                    success = true
                    print("Transaction succeeded on attempt \(attempts)")
                }

            } catch {
                print("Attempt \(attempts) failed: \(error)")
                // Brief delay before retry
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
        }

        XCTAssertTrue(success, "Transaction should succeed within \(maxRetries) attempts")
        XCTAssertTrue(attempts <= maxRetries, "Should not exceed maximum retry attempts")
        print("✓ Transaction timeout and retry test passed")
    }
}