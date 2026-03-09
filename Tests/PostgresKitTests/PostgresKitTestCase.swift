import XCTest

class PostgresKitTestCase: XCTestCase {
    override func setUp() {
        super.setUp()
        TestEnv.loadDotEnv()
    }
}
