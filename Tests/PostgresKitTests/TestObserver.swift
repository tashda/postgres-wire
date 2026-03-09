import XCTest

class TestObserver: NSObject, XCTestObservation {
    static func load() {
        XCTestObservationCenter.shared.addTestObserver(TestObserver())
    }

    override init() {
        super.init()
    }

    func testBundleWillStart(_ testBundle: Bundle) {
        TestEnv.loadDotEnv()
    }
}
