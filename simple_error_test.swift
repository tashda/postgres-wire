import Foundation
import PostgresKit
import Logging

// Simple test to verify error conversion works
print("Testing PostgresError conversion...")

let logger = Logger(label: "simple-test")
let client = PostgresDatabaseClient()

Task {
    do {
        let config = PostgresConfiguration(
            host: "localhost",
            port: 5432,
            database: "testdb",
            username: "postgres",
            password: ""
        )

        print("Attempting connection...")
        let connection = try await client.connect(configuration: config, logger: logger)
        print("✅ Connection successful!")

        // Try a simple operation
        let result = try await connection.simpleQuery("SELECT 1 as test_value")
        print("✅ Simple query successful!")

        // Try an operation that should cause an error
        _ = try await connection.simpleQuery("SELECT * FROM nonexistent_table_xyz")

    } catch {
        print("Caught error: \(type(of: error))")
        print("Error description: \(error.localizedDescription)")

        if error is PostgresKit.PostgresError {
            print("✅ SUCCESS: Error was properly converted to PostgresError!")
        } else {
            print("❌ Issue: Error was not converted to PostgresError")
            print("   Error type: \(type(of: error))")
        }
    }

    exit(0)
}

RunLoop.main.run()