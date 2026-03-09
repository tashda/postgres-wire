import XCTest
import Logging
@testable import PostgresKit

/// Integration tests for custom PostgresEncodable types (IPAddress, MACAddress).
/// Verifies that encode(into:) produces data that PostgreSQL accepts and returns correctly.
final class EncodableRoundTripTests: XCTestCase {
    private var client: PostgresDatabaseClient!

    override func setUp() async throws {
        TestEnv.loadDotEnv()
        guard ProcessInfo.processInfo.environment["POSTGRES_HOST"] != nil else {
            throw XCTSkip("POSTGRES_HOST not set. Copy .env.example to .env and configure connection.")
        }
        let config = PostgresConfiguration(
            host: TestEnv.host,
            port: TestEnv.port,
            database: TestEnv.database,
            username: TestEnv.username,
            password: TestEnv.password,
            useTLS: TestEnv.useTLS,
            applicationName: "EncodableRoundTripTests"
        )
        client = try await PostgresDatabaseClient.connect(configuration: config, logger: Logger(label: "encodable-tests"))
    }

    override func tearDown() async throws {
        client?.close()
    }

    // MARK: - IPAddress

    func testIPAddressV4_EncodeAndQueryRoundTrip() async throws {
        let ip = IPAddress(string: "192.168.1.100")
        var pgData = PGData(type: ip.pgDataType)
        try ip.encode(into: &pgData)
        let encoded = pgData

        let result = try await client.withConnection { conn in
            try await conn.query("SELECT $1::inet::text AS addr", binds: [encoded])
        }
        var returned = ""
        for try await v in result.decode(String.self) { returned = v; break }

        XCTAssertTrue(returned.contains("192.168.1.100"),
                      "Returned address '\(returned)' should contain the original IP")
    }

    func testIPAddressV6_EncodeAndQueryRoundTrip() async throws {
        let ip = IPAddress(string: "::1")
        var pgData = PGData(type: ip.pgDataType)
        try ip.encode(into: &pgData)
        let encoded = pgData

        let result = try await client.withConnection { conn in
            try await conn.query("SELECT $1::inet::text AS addr", binds: [encoded])
        }
        var returned = ""
        for try await v in result.decode(String.self) { returned = v; break }
        XCTAssertFalse(returned.isEmpty, "IPv6 address should be returned by PostgreSQL")
    }

    func testIPAddressCIDR_EncodeAndQueryRoundTrip() async throws {
        let ip = IPAddress(string: "10.0.0.0/8")
        var pgData = PGData(type: ip.pgDataType)
        try ip.encode(into: &pgData)
        let encoded = pgData

        let result = try await client.withConnection { conn in
            try await conn.query("SELECT $1::inet::text AS addr", binds: [encoded])
        }
        var returned = ""
        for try await v in result.decode(String.self) { returned = v; break }
        XCTAssertTrue(returned.contains("10"), "CIDR range should be accepted and returned")
    }

    func testIPAddressInsertAndSelectFromTable() async throws {
        let table = "pgwire_ip_test_\(UInt32.random(in: 0..<UInt32.max))"
        try await client.withConnection { conn in
            _ = try await conn.simpleQuery("CREATE TABLE \(table) (id SERIAL PRIMARY KEY, addr INET)")
        }
        defer {
            Task.detached { [client, table] in
                try? await client?.withConnection { conn in
                    _ = try? await conn.simpleQuery("DROP TABLE IF EXISTS \(table)")
                }
            }
        }

        let testIP = IPAddress(string: "172.16.0.1")
        var pgData = PGData(type: testIP.pgDataType)
        try testIP.encode(into: &pgData)
        let encoded = pgData

        try await client.withConnection { conn in
            _ = try await conn.query("INSERT INTO \(table) (addr) VALUES ($1::inet)", binds: [encoded])
        }

        let rows = try await client.simpleQuery("SELECT addr::text FROM \(table)")
        var addrs: [String] = []
        for try await addr in rows.decode(String.self) { addrs.append(addr) }

        XCTAssertEqual(addrs.count, 1)
        XCTAssertTrue(addrs[0].contains("172.16.0.1"), "Stored IP should be retrieved correctly")
    }

    func testIPAddressDataTypeIsInet() {
        let ip = IPAddress(string: "1.2.3.4")
        XCTAssertEqual(ip.pgDataType, .inet)
    }

    // MARK: - MACAddress

    func testMACAddress_ValidFormat_DoesNotThrow() throws {
        let mac = MACAddress(string: "AA:BB:CC:DD:EE:FF")
        var pgData = PGData(type: mac.pgDataType)
        XCTAssertNoThrow(try mac.encode(into: &pgData), "Valid MAC address encoding should not throw")
    }

    func testMACAddress_InvalidFormat_ThrowsEncodingError() {
        let mac = MACAddress(string: "not-a-mac")
        var pgData = PGData(type: mac.pgDataType)
        XCTAssertThrowsError(try mac.encode(into: &pgData), "Invalid MAC address should throw") { error in
            XCTAssertTrue(error is PostgresKit.PostgresError, "Error should be PostgresError, got: \(type(of: error))")
        }
    }

    func testMACAddress_TooFewComponents_ThrowsEncodingError() {
        let mac = MACAddress(string: "AA:BB:CC")
        var pgData = PGData(type: mac.pgDataType)
        XCTAssertThrowsError(try mac.encode(into: &pgData))
    }

    func testMACAddress_InsertAndSelectFromTable() async throws {
        let table = "pgwire_mac_test_\(UInt32.random(in: 0..<UInt32.max))"
        try await client.withConnection { conn in
            _ = try await conn.simpleQuery("CREATE TABLE \(table) (id SERIAL PRIMARY KEY, addr MACADDR)")
        }
        defer {
            Task.detached { [client, table] in
                try? await client?.withConnection { conn in
                    _ = try? await conn.simpleQuery("DROP TABLE IF EXISTS \(table)")
                }
            }
        }

        let mac = MACAddress(string: "12:34:56:78:9a:bc")
        var pgData = PGData(type: mac.pgDataType)
        try mac.encode(into: &pgData)
        let encoded = pgData

        try await client.withConnection { conn in
            _ = try await conn.query("INSERT INTO \(table) (addr) VALUES ($1::macaddr)", binds: [encoded])
        }

        let rows = try await client.simpleQuery("SELECT addr::text FROM \(table)")
        var addrs: [String] = []
        for try await addr in rows.decode(String.self) { addrs.append(addr) }

        XCTAssertEqual(addrs.count, 1)
        XCTAssertFalse(addrs[0].isEmpty, "Stored MAC address should be returned")
        XCTAssertTrue(addrs[0].contains(":"), "Returned value should be in MAC address format")
    }

    func testMACAddress_DataTypeIsMacaddr() {
        let mac = MACAddress(string: "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(mac.pgDataType, .macaddr)
    }

    // MARK: - Multiple Encodable Types Together

    func testMultipleEncodableTypesInQuery() async throws {
        let ip = IPAddress(string: "192.168.0.1")
        var ipData = PGData(type: ip.pgDataType)
        try ip.encode(into: &ipData)
        let encodedIP = ipData

        let result = try await client.withConnection { conn in
            try await conn.query(
                "SELECT $1::inet::text AS ip, $2::text AS name",
                binds: [encodedIP, PGData(string: "test")]
            )
        }

        var count = 0
        for try await _ in result.decode((String, String).self) { count += 1 }
        XCTAssertEqual(count, 1, "Should return exactly one row")
    }
}
