import XCTest
import Logging
import Foundation
@testable import PostgresKit

final class BulkCopyTests: PostgresKitTestCase {
    private var client: PostgresDatabaseClient!
    private let tableName = "pgwire_bulk_copy_\(UInt32.random(in: 0..<UInt32.max))"
    
    override func setUp() async throws {
        // super.setUp() is class-based and handled by PostgresKitTestCase class setUp.
        // We still need to load env if not using Docker
        TestEnv.loadDotEnv()
        
        guard ProcessInfo.processInfo.environment["POSTGRES_HOST"] != nil || ProcessInfo.processInfo.environment["USE_DOCKER"] == "1" else {
            throw XCTSkip("POSTGRES_HOST not set. Copy .env.example to .env and configure connection.")
        }
        
        let config = PostgresConfiguration(
            host: TestEnv.host,
            port: TestEnv.port,
            database: TestEnv.database,
            username: TestEnv.username,
            password: TestEnv.password,
            useTLS: TestEnv.useTLS,
            applicationName: "BulkCopyTests"
        )
        client = try await PostgresDatabaseClient.connect(configuration: config, logger: Logger(label: "bulk-tests"))
        let t = tableName
        try await client.withConnection { conn in
            _ = try await conn.simpleQuery("CREATE TABLE IF NOT EXISTS \(t) (id INTEGER, name TEXT, score INTEGER)")
        }
    }
    
    override func tearDown() async throws {
        if let client = client {
            let t = tableName
            try? await client.withConnection { conn in
                _ = try? await conn.simpleQuery("DROP TABLE IF EXISTS \(t)")
            }
            client.close()
        }
    }
    
    private var bulkCopy: PostgresBulkCopy {
        PostgresBulkCopy(client: client, logger: Logger(label: "bulk-copy"))
    }
    
    // MARK: - copyOut via SELECT subquery
    // ... rest of the file remains the same ...
}
