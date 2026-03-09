import Foundation

// Test the error conversion directly
print("Testing error type detection...")

// Simulate what the PSQLError might look like
let testError = NSError(domain: "PostgresNIO.PSQLError", code: 1, userInfo: [NSLocalizedDescriptionKey: "The operation couldn't be completed. (PostgresNIO.PSQLError error 1.)"])

print("Original error type: \(type(of: testError))")
print("Original error domain: \(testError.domain)")
print("Original error code: \(testError.code)")

// Test our conversion logic
if let psqLError = testError as? PSQLError {
    print("✅ Caught as direct PSQLError")
} else if let nsError = testError as? NSError, nsError.domain == "PostgresNIO.PSQLError" {
    print("✅ Caught as NSError with PSQLError domain")
} else {
    print("❌ Not caught as PSQLError")
    print("   Type: \(type(of: testError))")
}