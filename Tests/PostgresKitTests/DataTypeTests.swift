import XCTest
import Logging
@testable import PostgresKit

final class DataTypeTests: XCTestCase {

    private var client: PostgresDatabaseClient!
    private var testLogger: Logger!

    override func setUp() async throws {
        TestEnv.loadDotEnv()
        try await super.setUp()
        testLogger = Logger(label: "datatype-tests")

        let config = PostgresConfiguration(
            host: TestEnv.host,
            port: TestEnv.port,
            database: TestEnv.database,
            username: TestEnv.username,
            password: TestEnv.password,
            useTLS: TestEnv.useTLS,
            applicationName: "DataTypeTests"
        )

        client = try await PostgresDatabaseClient.connect(configuration: config, logger: testLogger)
    }

    override func tearDown() {
        client?.close()
        super.tearDown()
    }

    // MARK: - Basic Data Types

    func testBasicDataTypes() async throws {
        print("=== Testing Basic Data Types ===")

        let result = try await client.withConnection { conn in
            _ = try await conn.simpleQuery("""
                CREATE TEMPORARY TABLE basic_types (
                    id SERIAL PRIMARY KEY,
                    text_col TEXT,
                    varchar_col VARCHAR(100),
                    char_col CHAR(10),
                    integer_col INTEGER,
                    bigint_col BIGINT,
                    smallint_col SMALLINT,
                    boolean_col BOOLEAN,
                    real_col REAL,
                    double_col DOUBLE PRECISION
                )
            """)

            // Insert test data
            _ = try await conn.query("""
                INSERT INTO basic_types (text_col, varchar_col, char_col, integer_col, bigint_col, smallint_col, boolean_col, real_col, double_col)
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
            """, binds: [
                PGData(string: "Hello World"),
                PGData(string: "Variable String"),
                PGData(string: "FixedLen  "),
                PGData(int32: 42),
                PGData(int64: 9223372036854775807),
                PGData(int32: 32767), // SmallInt max
                PGData(bool: true),
                PGData(float: 3.14159),
                PGData(double: 2.718281828459045)
            ])

            // Retrieve and verify data
            let rows = try await conn.query("""
                SELECT text_col, varchar_col, char_col, integer_col, bigint_col, smallint_col, boolean_col, real_col, double_col
                FROM basic_types
            """)

            var results: [(String, String, String, Int32, Int64, Int32, Bool, Float, Double)] = []
            for try await row in rows.decode((String, String, String, Int32, Int64, Int32, Bool, Float, Double).self) {
                results.append(row)
            }

            return results.count
        }

        XCTAssertEqual(result, 1)
        print("✓ Basic data types test passed")
    }

    // MARK: - Numeric Types

    func testNumericTypes() async throws {
        print("=== Testing Numeric Types ===")

        let result = try await client.withConnection { conn in
            _ = try await conn.simpleQuery("""
                CREATE TEMPORARY TABLE numeric_types (
                    id SERIAL PRIMARY KEY,
                    decimal_col DECIMAL(10,2),
                    numeric_col NUMERIC(15,5),
                    money_col MONEY
                )
            """)

            // Insert test data
            _ = try await conn.query("""
                INSERT INTO numeric_types (decimal_col, numeric_col, money_col)
                VALUES ($1, $2, $3)
            """, binds: [
                PGData(string: "12345.67"),
                PGData(string: "987654321.12345"),
                PGData(string: "9999.99")
            ])

            // Retrieve and verify
            let rows = try await conn.query("""
                SELECT decimal_col::text, numeric_col::text, money_col::text
                FROM numeric_types
            """)

            var results: [(String, String, String)] = []
            for try await (decimal, numeric, money) in rows.decode((String, String, String).self) {
                results.append((decimal, numeric, money))
                print("Decimal: \(decimal), Numeric: \(numeric), Money: \(money)")
            }

            return results.count
        }

        XCTAssertEqual(result, 1)
        print("✓ Numeric types test passed")
    }

    // MARK: - Date/Time Types

    func testDateTimeTypes() async throws {
        print("=== Testing Date/Time Types ===")

        let result = try await client.withConnection { conn in
            _ = try await conn.simpleQuery("""
                CREATE TEMPORARY TABLE datetime_types (
                    id SERIAL PRIMARY KEY,
                    date_col DATE,
                    time_col TIME,
                    timestamp_col TIMESTAMP,
                    timestamptz_col TIMESTAMPTZ,
                    interval_col INTERVAL
                )
            """)

            // Insert test data
            _ = try await conn.query("""
                INSERT INTO datetime_types (date_col, time_col, timestamp_col, timestamptz_col, interval_col)
                VALUES ($1, $2, $3, $4, $5)
            """, binds: [
                PGData(string: "2024-01-15"),
                PGData(string: "14:30:00"),
                PGData(string: "2024-01-15 14:30:00"),
                PGData(string: "2024-01-15 14:30:00 UTC"),
                PGData(string: "2 days 3 hours 30 minutes")
            ])

            // Retrieve and verify
            let rows = try await conn.query("""
                SELECT date_col, time_col, timestamp_col, timestamptz_col, interval_col
                FROM datetime_types
            """)

            var results: [(String, String, String, String, String)] = []
            for try await row in rows.decode((String, String, String, String, String).self) {
                results.append(row)
                print("Date: \(row.0), Time: \(row.1), Timestamp: \(row.2), Timestamptz: \(row.3), Interval: \(row.4)")
            }

            return results.count
        }

        XCTAssertEqual(result, 1)
        print("✓ Date/Time types test passed")
    }

    // MARK: - JSON Types

    func testJSONTypes() async throws {
        print("=== Testing JSON Types ===")

        let result = try await client.withConnection { conn in
            _ = try await conn.simpleQuery("""
                CREATE TEMPORARY TABLE json_types (
                    id SERIAL PRIMARY KEY,
                    json_col JSON,
                    jsonb_col JSONB
                )
            """)

            let testJSON = """
            {
                "name": "John Doe",
                "age": 30,
                "active": true,
                "tags": ["developer", "swift"],
                "metadata": {"department": "engineering", "level": "senior"}
            }
            """

            // Insert test data
            _ = try await conn.query("""
                INSERT INTO json_types (json_col, jsonb_col)
                VALUES ($1::json, $2::jsonb)
            """, binds: [
                PGData(string: testJSON),
                PGData(string: testJSON)
            ])

            // Test JSON operations
            let rows = try await conn.query("""
                SELECT
                    json_col->>'name' as name,
                    json_col->>'age' as age,
                    jsonb_col->>'active' as active,
                    jsonb_col ? 'department' as has_department,
                    jsonb_col#>>'{metadata,department}' as department
                FROM json_types
            """)

            var results: [(String, String, String, Bool, String?)] = []
            for try await row in rows.decode((String, String, String, Bool, String?).self) {
                results.append(row)
                print("Name: \(row.0), Age: \(row.1), Active: \(row.2), Has Dept: \(row.3), Dept: \(row.4 ?? "nil")")
            }

            // Test JSON array operations
            let arrayRows = try await conn.query("""
                SELECT jsonb_col->'tags' as tags
                FROM json_types
            """)

            for try await (tags) in arrayRows.decode(String.self) {
                print("Tags: \(tags)")
            }

            return results.count
        }

        XCTAssertEqual(result, 1)
        print("✓ JSON types test passed")
    }

    // MARK: - Binary Types

    func testBinaryTypes() async throws {
        print("=== Testing Binary Types ===")

        let result = try await client.withConnection { conn in
            _ = try await conn.simpleQuery("""
                CREATE TEMPORARY TABLE binary_types (
                    id SERIAL PRIMARY KEY,
                    bytea_col BYTEA
                )
            """)

            // Create test binary data
            let testString = "Hello, Binary World! 🌍"
            let testData = Data(testString.utf8)

            // Insert binary data (Note: This might need special handling depending on the driver)
            _ = try await conn.query("""
                INSERT INTO binary_types (bytea_col)
                VALUES ($1)
            """, binds: [
                PGData(bytes: ByteBuffer(data: testData))
            ])

            // Retrieve and verify
            let rows = try await conn.query("""
                SELECT bytea_col FROM binary_types
            """)

            var results: [Data] = []
            for try await row in rows.decode(Data.self) {
                results.append(row)
                if let retrievedString = String(data: row, encoding: .utf8) {
                    print("Retrieved binary data: \(retrievedString)")
                }
            }

            return results.count
        }

        XCTAssertEqual(result, 1)
        print("✓ Binary types test passed")
    }

    // MARK: - Geometric Types

    func testGeometricTypes() async throws {
        print("=== Testing Geometric Types ===")

        let result = try await client.withConnection { conn in
            _ = try await conn.simpleQuery("""
                CREATE TEMPORARY TABLE geometric_types (
                    id SERIAL PRIMARY KEY,
                    point_col POINT,
                    box_col BOX,
                    path_col PATH,
                    polygon_col POLYGON,
                    circle_col CIRCLE,
                    line_col LINE
                )
            """)

            // Insert test data
            _ = try await conn.query("""
                INSERT INTO geometric_types (point_col, box_col, path_col, polygon_col, circle_col, line_col)
                VALUES ($1, $2, $3, $4, $5, $6)
            """, binds: [
                PGData(string: "(10, 20)"),              // POINT
                PGData(string: "((0,0),(100,100))"),    // BOX
                PGData(string: "((0,0),(10,0),(10,10),(0,10),(0,0))"), // PATH
                PGData(string: "((0,0),(10,0),(10,10),(0,10))"), // POLYGON
                PGData(string: "<(50,50),25>"),         // CIRCLE (center, radius)
                PGData(string: "{-1,0,1}")             // LINE (A,B,C where Ax + By + C = 0)
            ])

            // Retrieve and verify
            let rows = try await conn.query("""
                SELECT point_col, box_col, path_col, polygon_col, circle_col, line_col
                FROM geometric_types
            """)

            var results: [(String, String, String, String, String, String)] = []
            for try await row in rows.decode((String, String, String, String, String, String).self) {
                results.append(row)
                print("Point: \(row.0), Box: \(row.1), Path: \(row.2), Polygon: \(row.3), Circle: \(row.4), Line: \(row.5)")
            }

            return results.count
        }

        XCTAssertEqual(result, 1)
        print("✓ Geometric types test passed")
    }

    // MARK: - Network Types

    func testNetworkTypes() async throws {
        print("=== Testing Network Types ===")

        let result = try await client.withConnection { conn in
            _ = try await conn.simpleQuery("""
                CREATE TEMPORARY TABLE network_types (
                    id SERIAL PRIMARY KEY,
                    inet_col INET,
                    cidr_col CIDR,
                    macaddr_col MACADDR
                )
            """)

            // Insert test data
            _ = try await conn.query("""
                INSERT INTO network_types (inet_col, cidr_col, macaddr_col)
                VALUES ($1, $2, $3)
            """, binds: [
                PGData(string: "192.168.1.1/24"),       // INET
                PGData(string: "10.0.0.0/8"),           // CIDR
                PGData(string: "08:00:2b:01:02:03")     // MACADDR
            ])

            // Retrieve and verify
            let rows = try await conn.query("""
                SELECT inet_col, cidr_col, macaddr_col
                FROM network_types
            """)

            var results: [(String, String, String)] = []
            for try await row in rows.decode((String, String, String).self) {
                results.append(row)
                print("INET: \(row.0), CIDR: \(row.1), MACADDR: \(row.2)")
            }

            // Test network operations
            let netRows = try await conn.query("""
                SELECT
                    inet_col << '192.168.0.0/16' as is_in_network,
                    masklen(inet_col) as mask_length,
                    host(inet_col) as host_address
                FROM network_types
            """)

            for try await (inNetwork, maskLen, host) in netRows.decode((Bool, Int32, String).self) {
                print("In Network: \(inNetwork), Mask Length: \(maskLen), Host: \(host)")
            }

            return results.count
        }

        XCTAssertEqual(result, 1)
        print("✓ Network types test passed")
    }

    // MARK: - Text Search Types

    func testTextSearchTypes() async throws {
        print("=== Testing Text Search Types ===")

        let result = try await client.withConnection { conn in
            _ = try await conn.simpleQuery("""
                CREATE TEMPORARY TABLE textsearch_types (
                    id SERIAL PRIMARY KEY,
                    tsvector_col TSVECTOR,
                    tsquery_col TSQUERY,
                    text_col TEXT
                )
            """)

            // Insert test data
            _ = try await conn.query("""
                INSERT INTO textsearch_types (tsvector_col, tsquery_col, text_col)
                VALUES ($1, $2, $3)
            """, binds: [
                PGData(string: "a fat cat sat on a mat and ate a rat"), // TSVECTOR
                PGData(string: "cat & mat"),                               // TSQUERY
                PGData(string: "The quick brown fox jumps over the lazy dog")
            ])

            // Update tsvector from text
            _ = try await conn.simpleQuery("""
                UPDATE textsearch_types
                SET tsvector_col = to_tsvector('english', text_col)
                WHERE id = 1
            """)

            // Test text search operations
            let rows = try await conn.query("""
                SELECT
                    tsvector_col,
                    tsquery_col,
                    tsvector_col @@ tsquery_col as matches,
                    ts_rank(tsvector_col, tsquery_col) as rank
                FROM textsearch_types
            """)

            var results: [(String, String, Bool, Float)] = []
            for try await row in rows.decode((String, String, Bool, Float).self) {
                results.append(row)
                print("TSVector: \(row.0), TSQuery: \(row.1), Matches: \(row.2), Rank: \(row.3)")
            }

            // Test headline function
            let headlineRows = try await conn.query("""
                SELECT ts_headline('english', text_col, tsquery_col) as headline
                FROM textsearch_types
            """)

            for try await (headline) in headlineRows.decode(String.self) {
                print("Headline: \(headline)")
            }

            return results.count
        }

        XCTAssertEqual(result, 1)
        print("✓ Text search types test passed")
    }

    // MARK: - Array Types

    func testArrayTypes() async throws {
        print("=== Testing Array Types ===")

        let result = try await client.withConnection { conn in
            _ = try await conn.simpleQuery("""
                CREATE TEMPORARY TABLE array_types (
                    id SERIAL PRIMARY KEY,
                    int_array_col INTEGER[],
                    text_array_col TEXT[],
                    mixed_array_col TEXT[]
                )
            """)

            // Insert test data
            _ = try await conn.query("""
                INSERT INTO array_types (int_array_col, text_array_col, mixed_array_col)
                VALUES ($1, $2, $3)
            """, binds: [
                PGData(string: "{1,2,3,4,5}"),                    // INTEGER[]
                PGData(string: "{apple,banana,cherry}"),          // TEXT[]
                PGData(string: "{\"hello\",42,true}")             // Mixed array (as text)
            ])

            // Retrieve and verify
            let rows = try await conn.query("""
                SELECT
                    int_array_col,
                    text_array_col,
                    mixed_array_col,
                    array_length(int_array_col, 1) as int_length,
                    text_array_col[2] as second_element,
                    3 = ANY(int_array_col) as contains_three
                FROM array_types
            """)

            var results: [(String, String, String, Int32, String?, Bool)] = []
            for try await row in rows.decode((String, String, String, Int32, String?, Bool).self) {
                results.append(row)
                print("Int Array: \(row.0), Text Array: \(row.1), Mixed: \(row.2)")
                print("Length: \(row.3), Second Element: \(row.4 ?? "nil"), Contains 3: \(row.5)")
            }

            // Test array operations
            let arrayOpRows = try await conn.query("""
                SELECT
                    unnest(int_array_col) as element,
                    array_append(int_array_col, 6) as appended,
                    array_remove(int_array_col, 3) as removed
                FROM array_types
            """)

            var elementCount = 0
            for try await (element, appended, removed) in arrayOpRows.decode((Int32, String, String).self) {
                print("Element: \(element), Appended: \(appended), Removed: \(removed)")
                elementCount += 1
            }

            return results.count
        }

        XCTAssertEqual(result, 1)
        print("✓ Array types test passed")
    }

    // MARK: - UUID Type

    func testUUIDType() async throws {
        print("=== Testing UUID Type ===")

        let result = try await client.withConnection { conn in
            _ = try await conn.simpleQuery("""
                CREATE TEMPORARY TABLE uuid_types (
                    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                    name VARCHAR(100),
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)

            // Insert with explicit UUID
            let testUUID = "550e8400-e29b-41d4-a716-446655440000"
            _ = try await conn.query("""
                INSERT INTO uuid_types (id, name)
                VALUES ($1, $2)
            """, binds: [
                PGData(string: testUUID),
                PGData(string: "Test Record")
            ])

            // Insert with default UUID
            _ = try await conn.simpleQuery("""
                INSERT INTO uuid_types (name)
                VALUES ('Auto UUID')
            """)

            // Retrieve and verify
            let rows = try await conn.query("""
                SELECT id, name FROM uuid_types ORDER BY id
            """)

            var results: [(String, String)] = []
            for try await row in rows.decode((String, String).self) {
                results.append(row)
                print("UUID: \(row.0), Name: \(row.1)")
            }

            // Test UUID functions
            let funcRows = try await conn.query("""
                SELECT
                    gen_random_uuid() as new_uuid,
                    version() as uuid_version
            """)

            for try await (newUUID, version) in funcRows.decode((String, String).self) {
                print("Generated UUID: \(newUUID), Version: \(version)")
            }

            return results.count
        }

        XCTAssertEqual(result, 2)
        print("✓ UUID type test passed")
    }
}