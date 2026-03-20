import Foundation
import PostgresKitTesting

do {
    let report = try ensurePostgresTestFixture()
    print("fixture=postgres")
    print("image=\(report.image)")
    print("port=\(report.port)")
    print("fixture_version=\(report.fixtureVersion)")
    print("reused_container=\(report.reusedContainer)")
    print("recreated_container=\(report.recreatedContainer)")
    print("validations=\(report.validations.joined(separator: ","))")
} catch {
    let message = "postgres-test-fixture failed: \(error)\n"
    FileHandle.standardError.write(Data(message.utf8))
    exit(1)
}
