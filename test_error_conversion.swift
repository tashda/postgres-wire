#!/usr/bin/env swift

import Foundation
import PostgresKit

// Test error conversion
let client = PostgresClient()

Task {
    do {
        // Try to connect with invalid credentials to trigger an error
        try await client.connect(
            host: "localhost",
            port: 5432,
            username: "invalid_user",
            database: "invalid_db",
            password: "invalid_password"
        )
        print("❌ Expected connection to fail")
    } catch {
        print("✅ Caught error: \(type(of: error))")
        print("✅ Error description: \(error.localizedDescription)")

        if error is PostgresKit.PostgresError {
            print("✅ SUCCESS: Error was converted to PostgresError")
        } else {
            print("❌ FAILURE: Error was not converted to PostgresError")
            print("   Error type: \(type(of: error))")
        }
    }

    exit(0)
}

RunLoop.main.run()