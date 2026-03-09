import XCTest
@testable import PostgresWire
@testable import PostgresKit

final class PostgresExecutionOptionsTests: XCTestCase {
    func testSimpleQueryWithOptionsIfConfigured() async throws {
        guard let host = ProcessInfo.processInfo.environment["POSTGRES_HOST"],
              let portValue = ProcessInfo.processInfo.environment["POSTGRES_PORT"],
              let port = Int(portValue),
              let user = ProcessInfo.processInfo.environment["POSTGRES_USERNAME"],
              let pass = ProcessInfo.processInfo.environment["POSTGRES_PASSWORD"],
              let db = ProcessInfo.processInfo.environment["POSTGRES_DATABASE"]
        else {
            throw XCTSkip("Postgres credentials not configured")
        }

        let config = PostgresConfiguration(
            host: host,
            port: port,
            database: db,
            username: user,
            password: pass,
            useTLS: false
        )
        let client = try await PostgresDatabaseClient.connect(configuration: config)
        defer { client.close() }

        let options = PostgresExecutionOptions(
            mode: .auto,
            cursorThreshold: 25_000,
            fetchBaseline: 4_096,
            fetchRampMultiplier: 24,
            fetchRampMax: 524_288,
            progressThrottleMs: 120
        )

        let rows = try await client.simpleQuery("SELECT 1;", options: options)
        var sawRow = false
        for try await _ in rows {
            sawRow = true
            break
        }
        XCTAssertTrue(sawRow)
    }
}
