import XCTest
@testable import PostgresWire

final class StreamingDataTypeTests: XCTestCase {

    // MARK: - OID Mapping

    func testBooleanOID() {
        XCTAssertEqual(StreamingPostgresDataType(oid: 16), .boolean)
    }

    func testSmallIntOID() {
        XCTAssertEqual(StreamingPostgresDataType(oid: 21), .smallInt)
    }

    func testIntegerOID() {
        XCTAssertEqual(StreamingPostgresDataType(oid: 23), .integer)
    }

    func testBigIntOID() {
        XCTAssertEqual(StreamingPostgresDataType(oid: 20), .bigInt)
    }

    func testRealOID() {
        XCTAssertEqual(StreamingPostgresDataType(oid: 700), .real)
    }

    func testDoubleOID() {
        XCTAssertEqual(StreamingPostgresDataType(oid: 701), .double)
    }

    func testNumericOID() {
        XCTAssertEqual(StreamingPostgresDataType(oid: 1700), .numeric)
    }

    func testTextOID() {
        XCTAssertEqual(StreamingPostgresDataType(oid: 25), .text)
    }

    func testVarcharOID() {
        // varchar (1043) is mapped to .text
        XCTAssertEqual(StreamingPostgresDataType(oid: 1043), .text)
    }

    func testCharOID() {
        XCTAssertEqual(StreamingPostgresDataType(oid: 18), .char)
    }

    func testTimestampOID() {
        XCTAssertEqual(StreamingPostgresDataType(oid: 1114), .timestamp)
    }

    func testTimestamptzOID() {
        XCTAssertEqual(StreamingPostgresDataType(oid: 1184), .timestamptz)
    }

    func testDateOID() {
        XCTAssertEqual(StreamingPostgresDataType(oid: 1082), .date)
    }

    func testTimeOID() {
        XCTAssertEqual(StreamingPostgresDataType(oid: 1083), .time)
    }

    func testTimetzOID() {
        XCTAssertEqual(StreamingPostgresDataType(oid: 1266), .timetz)
    }

    func testIntervalOID() {
        XCTAssertEqual(StreamingPostgresDataType(oid: 1186), .interval)
    }

    func testUUIDOID() {
        XCTAssertEqual(StreamingPostgresDataType(oid: 2950), .uuid)
    }

    func testJSONOID() {
        XCTAssertEqual(StreamingPostgresDataType(oid: 114), .json)
    }

    func testJSONBOID() {
        XCTAssertEqual(StreamingPostgresDataType(oid: 3802), .jsonb)
    }

    func testByteaOID() {
        XCTAssertEqual(StreamingPostgresDataType(oid: 17), .bytea)
    }

    func testInetOID() {
        XCTAssertEqual(StreamingPostgresDataType(oid: 869), .inet)
    }

    func testCIDROID() {
        XCTAssertEqual(StreamingPostgresDataType(oid: 650), .cidr)
    }

    func testMacaddrOID() {
        XCTAssertEqual(StreamingPostgresDataType(oid: 829), .macaddr)
    }

    func testMacaddr8OID() {
        XCTAssertEqual(StreamingPostgresDataType(oid: 774), .macaddr8)
    }

    func testPointOID() {
        XCTAssertEqual(StreamingPostgresDataType(oid: 600), .point)
    }

    func testLineOID() {
        XCTAssertEqual(StreamingPostgresDataType(oid: 628), .line)
    }

    func testBoxOID() {
        XCTAssertEqual(StreamingPostgresDataType(oid: 603), .box)
    }

    func testPathOID() {
        XCTAssertEqual(StreamingPostgresDataType(oid: 602), .path)
    }

    func testPolygonOID() {
        XCTAssertEqual(StreamingPostgresDataType(oid: 604), .polygon)
    }

    func testCircleOID() {
        XCTAssertEqual(StreamingPostgresDataType(oid: 718), .circle)
    }

    func testArrayOIDs() {
        let arrayOIDs = [1007, 1015, 1016, 1008, 1009, 1028, 1021, 1022, 1000, 1001, 1020, 1002, 1005, 1003, 1006, 1017]
        for oid in arrayOIDs {
            XCTAssertEqual(StreamingPostgresDataType(oid: oid), .array, "OID \(oid) should map to .array")
        }
    }

    func testUnknownOID_ReturnsUnknown() {
        XCTAssertEqual(StreamingPostgresDataType(oid: 99999), .unknown)
        XCTAssertEqual(StreamingPostgresDataType(oid: 0), .unknown)
    }

    // MARK: - Raw Values

    func testRawValues() {
        XCTAssertEqual(StreamingPostgresDataType.boolean.rawValue, "bool")
        XCTAssertEqual(StreamingPostgresDataType.smallInt.rawValue, "int2")
        XCTAssertEqual(StreamingPostgresDataType.integer.rawValue, "int4")
        XCTAssertEqual(StreamingPostgresDataType.bigInt.rawValue, "int8")
        XCTAssertEqual(StreamingPostgresDataType.real.rawValue, "float4")
        XCTAssertEqual(StreamingPostgresDataType.double.rawValue, "float8")
        XCTAssertEqual(StreamingPostgresDataType.numeric.rawValue, "numeric")
        XCTAssertEqual(StreamingPostgresDataType.text.rawValue, "text")
        XCTAssertEqual(StreamingPostgresDataType.uuid.rawValue, "uuid")
        XCTAssertEqual(StreamingPostgresDataType.json.rawValue, "json")
        XCTAssertEqual(StreamingPostgresDataType.jsonb.rawValue, "jsonb")
        XCTAssertEqual(StreamingPostgresDataType.bytea.rawValue, "bytea")
        XCTAssertEqual(StreamingPostgresDataType.inet.rawValue, "inet")
        XCTAssertEqual(StreamingPostgresDataType.unknown.rawValue, "unknown")
    }
}
