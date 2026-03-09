import XCTest
import Logging
@testable import PostgresKit

final class UserManagementTests: XCTestCase {

    private var client: PostgresDatabaseClient!
    private var testLogger: Logger!

    override func setUp() async throws {
        TestEnv.loadDotEnv()
        guard ProcessInfo.processInfo.environment["POSTGRES_HOST"] != nil else {
            throw XCTSkip("POSTGRES_HOST not set. Copy .env.example to .env and configure connection.")
        }
        try await super.setUp()
        testLogger = Logger(label: "user-management-tests")

        let config = PostgresConfiguration(
            host: TestEnv.host,
            port: TestEnv.port,
            database: TestEnv.database,
            username: TestEnv.username,
            password: TestEnv.password,
            useTLS: TestEnv.useTLS,
            applicationName: "UserManagementTests"
        )

        client = try await PostgresDatabaseClient.connect(configuration: config, logger: testLogger)
    }

    override func tearDown() {
        client?.close()
        super.tearDown()
    }

    // MARK: - Helpers

    private let suffix = UInt32.random(in: 0..<UInt32.max)

    private func dropRoleIfExists(_ name: String) async {
        try? await client.withConnection { conn in
            _ = try await conn.simpleQuery("DROP ROLE IF EXISTS \(name)")
        }
    }

    private func dropUserIfExists(_ name: String) async {
        try? await client.withConnection { conn in
            _ = try await conn.simpleQuery("DROP USER IF EXISTS \(name)")
        }
    }

    // MARK: - Role/User Management

    func testCreateAndDropRoles() async throws {
        let s = suffix
        let roleNames = ["reader_\(s)", "writer_\(s)", "admin_\(s)"]
        // Pre-clean in case of leftovers
        for r in roleNames { await dropRoleIfExists(r) }
        let superName = "super_\(s)"
        await dropRoleIfExists(superName)

        defer {
            Task.detached { [client, roleNames, superName] in
                for r in roleNames {
                    try? await client?.withConnection { conn in
                        _ = try await conn.simpleQuery("DROP ROLE IF EXISTS \(r)")
                    }
                }
                try? await client?.withConnection { conn in
                    _ = try await conn.simpleQuery("DROP ROLE IF EXISTS \(superName)")
                }
            }
        }

        let allRoles = roleNames + [superName]
        try await client.withConnection { conn in
            for roleName in roleNames {
                _ = try await conn.simpleQuery("CREATE ROLE \(roleName) WITH LOGIN PASSWORD 'test123'")
            }
            _ = try await conn.simpleQuery("""
                CREATE ROLE \(superName) WITH
                    SUPERUSER CREATEDB CREATEROLE LOGIN
                    PASSWORD 'superpass123'
            """)
        }

        // Verify roles exist
        let nameList = allRoles.joined(separator: "','")
        let verifyRows = try await client.simpleQuery("""
            SELECT rolname FROM pg_roles WHERE rolname = ANY(ARRAY['\(nameList)'])
        """)
        var verified: [String] = []
        for try await name in verifyRows.decode(String.self) { verified.append(name) }
        XCTAssertEqual(verified.count, allRoles.count, "All created roles should be verifiable")

        // Drop and verify
        let rolesToDrop = allRoles
        try await client.withConnection { conn in
            for r in rolesToDrop {
                _ = try await conn.simpleQuery("DROP ROLE IF EXISTS \(r)")
            }
        }

        let afterRows = try await client.simpleQuery("""
            SELECT rolname FROM pg_roles WHERE rolname = ANY(ARRAY['\(nameList)'])
        """)
        var remaining: [String] = []
        for try await name in afterRows.decode(String.self) { remaining.append(name) }
        XCTAssertEqual(remaining.count, 0, "All test roles should be dropped")
    }

    // MARK: - User Attributes

    func testUserAttributes() async throws {
        let userName = "attr_user_\(suffix)"
        await dropUserIfExists(userName)
        let renamedName = "renamed_\(suffix)"
        await dropUserIfExists(renamedName)

        defer {
            Task.detached { [client, userName, renamedName] in
                try? await client?.withConnection { conn in
                    _ = try await conn.simpleQuery("DROP USER IF EXISTS \(renamedName)")
                    _ = try await conn.simpleQuery("DROP USER IF EXISTS \(userName)")
                }
            }
        }

        try await client.withConnection { conn in
            _ = try await conn.simpleQuery("""
                CREATE ROLE \(userName) WITH LOGIN PASSWORD 'attrpass123' CONNECTION LIMIT 5
            """)
            _ = try await conn.simpleQuery("ALTER ROLE \(userName) CONNECTION LIMIT 10")
            _ = try await conn.simpleQuery("ALTER ROLE \(userName) RENAME TO \(renamedName)")
            _ = try await conn.simpleQuery("ALTER ROLE \(renamedName) VALID UNTIL 'infinity'")
        }

        let userRows = try await client.simpleQuery("""
            SELECT rolname, rolcanlogin FROM pg_roles WHERE rolname = '\(renamedName)'
        """)
        var found = false
        for try await (name, canLogin) in userRows.decode((String, Bool).self) {
            XCTAssertEqual(name, renamedName)
            XCTAssertTrue(canLogin)
            found = true
        }
        XCTAssertTrue(found, "Should find the renamed user")
    }

    // MARK: - Role Membership

    func testRoleMembership() async throws {
        let s = suffix
        let deptEng = "dept_eng_\(s)"
        let deptSales = "dept_sales_\(s)"
        let john = "john_\(s)"
        let jane = "jane_\(s)"
        let bob = "bob_\(s)"
        let allNames = [john, jane, bob, deptEng, deptSales]

        for n in allNames { await dropRoleIfExists(n) }

        defer {
            Task.detached { [client, allNames] in
                for n in allNames {
                    try? await client?.withConnection { conn in
                        _ = try await conn.simpleQuery("DROP ROLE IF EXISTS \(n)")
                    }
                }
            }
        }

        try await client.withConnection { conn in
            _ = try await conn.simpleQuery("CREATE ROLE \(deptEng)")
            _ = try await conn.simpleQuery("CREATE ROLE \(deptSales)")
            _ = try await conn.simpleQuery("CREATE USER \(john) WITH PASSWORD 'pass123'")
            _ = try await conn.simpleQuery("CREATE USER \(jane) WITH PASSWORD 'pass123'")
            _ = try await conn.simpleQuery("CREATE USER \(bob) WITH PASSWORD 'pass123'")

            _ = try await conn.simpleQuery("GRANT \(deptEng) TO \(john)")
            _ = try await conn.simpleQuery("GRANT \(deptSales) TO \(jane)")
            _ = try await conn.simpleQuery("GRANT \(deptEng) TO \(bob)")
            _ = try await conn.simpleQuery("GRANT \(deptSales) TO \(bob)")
        }

        let membershipRows = try await client.simpleQuery("""
            SELECT ur1.rolname AS user_role, ur2.rolname AS role_membership
            FROM pg_roles ur1
            JOIN pg_auth_members pam ON ur1.oid = pam.member
            JOIN pg_roles ur2 ON pam.roleid = ur2.oid
            WHERE ur1.rolname IN ('\(john)', '\(jane)', '\(bob)')
            ORDER BY user_role, role_membership
        """)

        var memberships: [(String, String)] = []
        for try await (user, role) in membershipRows.decode((String, String).self) {
            memberships.append((user, role))
        }

        XCTAssertGreaterThan(memberships.count, 0, "Should have role memberships")
        // bob should have 2 memberships (eng + sales)
        let bobMemberships = memberships.filter { $0.0 == bob }
        XCTAssertEqual(bobMemberships.count, 2, "Bob should have 2 role memberships")
    }

    // MARK: - Default Privileges

    func testDefaultPrivileges() async throws {
        let s = suffix
        let roleName = "priv_role_\(s)"
        let userName = "priv_user_\(s)"
        let schemaName = "priv_schema_\(s)"

        await dropRoleIfExists(userName)
        await dropRoleIfExists(roleName)

        defer {
            Task.detached { [client, schemaName, userName, roleName] in
                try? await client?.withConnection { conn in
                    _ = try await conn.simpleQuery("DROP SCHEMA IF EXISTS \(schemaName) CASCADE")
                }
                try? await client?.withConnection { conn in
                    _ = try await conn.simpleQuery("DROP USER IF EXISTS \(userName)")
                    _ = try await conn.simpleQuery("DROP ROLE IF EXISTS \(roleName)")
                }
            }
        }

        try await client.withConnection { conn in
            _ = try await conn.simpleQuery("CREATE ROLE \(roleName)")
            _ = try await conn.simpleQuery("CREATE USER \(userName) WITH PASSWORD 'test123'")
            _ = try await conn.simpleQuery("GRANT \(roleName) TO \(userName)")
            _ = try await conn.simpleQuery("CREATE SCHEMA \(schemaName)")
            _ = try await conn.simpleQuery("GRANT USAGE ON SCHEMA \(schemaName) TO \(roleName)")

            _ = try await conn.simpleQuery("""
                ALTER DEFAULT PRIVILEGES IN SCHEMA \(schemaName)
                GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO \(roleName)
            """)

            _ = try await conn.simpleQuery("""
                CREATE TABLE \(schemaName).test_tbl (id SERIAL PRIMARY KEY, name TEXT)
            """)
        }

        let aclRows = try await client.simpleQuery("""
            SELECT privilege_type
            FROM information_schema.role_table_grants
            WHERE table_schema = '\(schemaName)' AND table_name = 'test_tbl' AND grantee = '\(roleName)'
            ORDER BY privilege_type
        """)

        var privileges: [String] = []
        for try await priv in aclRows.decode(String.self) {
            privileges.append(priv)
        }

        XCTAssertGreaterThan(privileges.count, 0, "Should have default table privileges")
    }

    // MARK: - Row Level Security

    func testRowLevelSecurity() async throws {
        let s = suffix
        let table = "rls_test_\(s)"
        let alice = "alice_\(s)"
        let bob = "bob_\(s)"

        await dropUserIfExists(alice)
        await dropUserIfExists(bob)

        defer {
            Task.detached { [client, table, alice, bob] in
                try? await client?.withConnection { conn in
                    _ = try await conn.simpleQuery("DROP TABLE IF EXISTS \(table)")
                }
                try? await client?.withConnection { conn in
                    _ = try await conn.simpleQuery("DROP USER IF EXISTS \(alice)")
                    _ = try await conn.simpleQuery("DROP USER IF EXISTS \(bob)")
                }
            }
        }

        try await client.withConnection { conn in
            _ = try await conn.simpleQuery("""
                CREATE TABLE \(table) (
                    id SERIAL PRIMARY KEY,
                    owner TEXT,
                    category TEXT,
                    data TEXT
                )
            """)

            _ = try await conn.simpleQuery("CREATE USER \(alice) WITH PASSWORD 'alice123'")
            _ = try await conn.simpleQuery("CREATE USER \(bob) WITH PASSWORD 'bob123'")

            _ = try await conn.simpleQuery("""
                INSERT INTO \(table) (owner, category, data) VALUES
                ('alice', 'personal', 'Alice personal data'),
                ('bob', 'work', 'Bob work data'),
                ('alice', 'public', 'Alice public data'),
                ('bob', 'public', 'Bob public data')
            """)

            _ = try await conn.simpleQuery("ALTER TABLE \(table) ENABLE ROW LEVEL SECURITY")

            _ = try await conn.simpleQuery("""
                CREATE POLICY alice_policy_\(s) ON \(table)
                FOR ALL TO \(alice)
                USING (owner = 'alice' OR category = 'public')
            """)

            _ = try await conn.simpleQuery("""
                CREATE POLICY bob_policy_\(s) ON \(table)
                FOR ALL TO \(bob)
                USING (owner = 'bob' OR category = 'public')
            """)
        }

        // Verify policies exist
        let policyRows = try await client.simpleQuery("""
            SELECT policyname, cmd FROM pg_policies WHERE tablename = '\(table)' ORDER BY policyname
        """)

        var policies: [String] = []
        for try await (name, _) in policyRows.decode((String, String).self) {
            policies.append(name)
        }

        XCTAssertEqual(policies.count, 2, "Should have 2 RLS policies")

        // Verify data count (as superuser, sees all rows)
        let countRows = try await client.simpleQuery("SELECT COUNT(*)::text FROM \(table)")
        var totalCount = 0
        for try await countStr in countRows.decode(String.self) {
            totalCount = Int(countStr) ?? 0
        }
        XCTAssertEqual(totalCount, 4, "Should have 4 rows in test data")
    }
}
