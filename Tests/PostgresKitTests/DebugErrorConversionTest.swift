import XCTest
import PostgresNIO
@testable import PostgresKit
import PostgresWire

final class DebugErrorConversionTest: XCTestCase {

    func testDirectPSQLErrorConversion() throws {
        print("🧪 Testing direct PSQLError conversion...")

        // Create a simple PSQLError for testing
        // Since we can't easily create a real PSQLError, let's create a mock NSError
        // that simulates what a PSQLError might look like
        let mockError = NSError(
            domain: "PostgresNIO.PSQLError",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Test PSQLError message"]
        )

        print("Created mock error: \(mockError.localizedDescription)")
        print("Error type: \(type(of: mockError))")

        // Test if our error conversion logic would work
        do {
            // Simulate throwing and catching the error
            throw mockError
        } catch {
            print("Caught error: \(type(of: error))")

            // This is the same logic as in withConnection
            if let psqLError = error as? PSQLError {
                print("✅ Detected PSQLError, converting...")
                let postgresError = PostgresKit.PostgresError(from: psqLError)
                print("✅ Created PostgresError: \(type(of: postgresError))")
                print("Message: \(postgresError.message)")
            } else if let nsError = error as? NSError, nsError.domain == "PostgresNIO.PSQLError" {
                print("✅ Detected PSQLError wrapped in NSError, converting...")
                let postgresError = PostgresKit.PostgresError(message: nsError.localizedDescription)
                print("✅ Created PostgresError: \(type(of: postgresError))")
                print("Message: \(postgresError.message)")
            } else {
                print("❌ Not detected as PSQLError")
                print("Available types: \(type(of: error))")

                // Let's see what we can cast it to
                if error is NSError {
                    print("✅ Can cast to NSError")
                    let nsError = error as! NSError
                    print("Domain: \(nsError.domain)")
                    print("Code: \(nsError.code)")
                }
            }
        }
    }

    func testWithRealPSQLErrorIfPossible() async throws {
        print("🧪 Testing with real Postgres connection...")

        do {
            let connection = try await PostgresConnection.connect(
                on: MultiThreadedEventLoopGroup.singleton.any(),
                configuration: .init(
                    host: "nonexistent-host-12345.com",
                    port: 5432,
                    username: "nonexistent",
                    password: "wrong",
                    database: "nonexistent",
                    tls: .disable
                ),
                id: 1,
                logger: Logger(label: "test")
            ).get()
            XCTFail("Expected connection to fail")
            try await connection.close().get()
        } catch let error as PSQLError {
            print("🔍 Caught connection error: \(error)")
            XCTAssert(error.code == .connectionError, "Expected a connection error, but got \(error.code)")
        } catch {
            XCTFail("Expected a PSQLError, but got \(type(of: error))")
        }
    }
}