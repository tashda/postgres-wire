import XCTest
@testable import PostgresWire
@testable import PostgresKit

final class PostgresExecutionOptionsTests: PostgresKitTestCase {
    func testSimpleQueryWithOptionsIfConfigured() async throws {
        guard TestEnv.isConfigured else { throw XCTSkip("Postgres environment not set") }

        let config = PostgresConfiguration(
            host: TestEnv.host,
            port: TestEnv.port,
            database: TestEnv.database,
            username: TestEnv.username,
            password: TestEnv.password,
            useTLS: TestEnv.useTLS
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
