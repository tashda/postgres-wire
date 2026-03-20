import XCTest
import PostgresKitTesting

final class PostgresFixtureBootstrapTests: XCTestCase {
    func testEnsureFixtureIsRepeatable() throws {
        guard ProcessInfo.processInfo.environment["USE_DOCKER"] == "1" else {
            throw XCTSkip("USE_DOCKER not set")
        }

        let first = try ensurePostgresTestFixture()
        let second = try ensurePostgresTestFixture()

        XCTAssertFalse(first.fixtureVersion.isEmpty)
        XCTAssertTrue(first.validations.contains("schema:app"))
        XCTAssertTrue(second.validations.contains("role:test_readonly"))
        XCTAssertEqual(first.port, second.port)
        XCTAssertEqual(first.image, second.image)
    }
}
