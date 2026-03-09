import XCTest
import Logging
@testable import PostgresKit

final class IntegrationTests: XCTestCase {
    func testConnectAndSelectOneIfConfigured() async throws {
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
            applicationName: "PostgresKitTests"
        )
        let client = try await PostgresDatabaseClient.connect(configuration: config, logger: .init(label: "tests"))
        defer { client.close() }
        let rows = try await client.simpleQuery("SELECT 1")
        var values: [Int] = []
        for try await value in rows.decode(Int.self) { values.append(value) }
        XCTAssertEqual(values, [1])
    }
}

