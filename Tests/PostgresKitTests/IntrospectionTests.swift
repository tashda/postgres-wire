import XCTest
import Logging
@testable import PostgresKit

/// Tests for the new introspection APIs: listSequences, listTypes, listProcedures,
/// and SchemaSummary procedure support.
final class IntrospectionTests: PostgresKitTestCase {
    private var client: PostgresKit.PostgresClient!

    override func setUp() async throws {
        try await super.setUp()
        guard TestEnv.isConfigured else { throw XCTSkip("Postgres environment not set") }
        let config = PostgresConfiguration(
            host: TestEnv.host, port: TestEnv.port,
            database: TestEnv.database, username: TestEnv.username,
            password: TestEnv.password, useTLS: TestEnv.useTLS,
            applicationName: "IntrospectionTests"
        )
        client = try await PostgresKit.PostgresClient.connect(configuration: config, logger: Logger(label: "introspection-tests"))
    }

    override func tearDown() {
        client?.close()
        super.tearDown()
    }

    private func uniqueName(_ prefix: String = "intro") -> String {
        "\(prefix)_\(UInt32.random(in: 0..<UInt32.max))"
    }

    // MARK: - listSequences

    func testListSequencesFindsCreatedSequence() async throws {
        let seqName = uniqueName("seq")
        defer { Task { [client = self.client!] in
            _ = try? await client.admin.dropSequence(name: seqName, ifExists: true)
        }}

        _ = try await client.admin.createSequence(name: seqName)

        let sequences = try await client.introspection.listSequences(schema: "public")
        let names = sequences.map { $0.name }
        XCTAssertTrue(names.contains(seqName), "listSequences should include the newly created sequence '\(seqName)'")
    }

    func testListSequencesReturnsCorrectSchema() async throws {
        let seqName = uniqueName("seq")
        defer { Task { [client = self.client!] in
            _ = try? await client.admin.dropSequence(name: seqName, ifExists: true)
        }}

        _ = try await client.admin.createSequence(name: seqName)

        let sequences = try await client.introspection.listSequences(schema: "public")
        let match = sequences.first { $0.name == seqName }
        XCTAssertNotNil(match, "Should find the sequence")
        XCTAssertEqual(match?.schema, "public", "Schema should be public")
    }

    func testListSequencesExcludesOtherSchemas() async throws {
        // Sequences in 'app' schema should not appear when querying 'public'
        let seqName = uniqueName("seq")
        defer { Task { [client = self.client!] in
            _ = try? await client.connection.simpleQuery("DROP SEQUENCE IF EXISTS app.\(seqName)")
        }}

        _ = try await client.connection.simpleQuery("CREATE SEQUENCE app.\(seqName)")

        let publicSequences = try await client.introspection.listSequences(schema: "public")
        let names = publicSequences.map { $0.name }
        XCTAssertFalse(names.contains(seqName), "Sequence in 'app' schema should not appear in 'public' listing")

        let appSequences = try await client.introspection.listSequences(schema: "app")
        let appNames = appSequences.map { $0.name }
        XCTAssertTrue(appNames.contains(seqName), "Sequence should appear in 'app' schema listing")
    }

    // MARK: - listTypes

    func testListTypesFindsCreatedEnum() async throws {
        let typeName = uniqueName("status")
        defer { Task { [client = self.client!] in
            _ = try? await client.connection.simpleQuery("DROP TYPE IF EXISTS \(typeName)")
        }}

        _ = try await client.connection.simpleQuery("CREATE TYPE \(typeName) AS ENUM ('active', 'inactive', 'pending')")

        let types = try await client.introspection.listTypes(schema: "public")
        let match = types.first { $0.name == typeName }
        XCTAssertNotNil(match, "listTypes should include the newly created enum type '\(typeName)'")
        XCTAssertEqual(match?.kind, "enum", "Kind should be 'enum'")
        XCTAssertEqual(match?.schema, "public", "Schema should be 'public'")
    }

    func testListTypesFindsCompositeType() async throws {
        let typeName = uniqueName("addr")
        defer { Task { [client = self.client!] in
            _ = try? await client.connection.simpleQuery("DROP TYPE IF EXISTS \(typeName)")
        }}

        _ = try await client.connection.simpleQuery("CREATE TYPE \(typeName) AS (street TEXT, city TEXT, zip TEXT)")

        let types = try await client.introspection.listTypes(schema: "public")
        let match = types.first { $0.name == typeName }
        XCTAssertNotNil(match, "listTypes should include the composite type '\(typeName)'")
        XCTAssertEqual(match?.kind, "composite", "Kind should be 'composite'")
    }

    func testListTypesExcludesOtherSchemas() async throws {
        let typeName = uniqueName("myenum")
        defer { Task { [client = self.client!] in
            _ = try? await client.connection.simpleQuery("DROP TYPE IF EXISTS app.\(typeName)")
        }}

        _ = try await client.connection.simpleQuery("CREATE TYPE app.\(typeName) AS ENUM ('a', 'b')")

        let publicTypes = try await client.introspection.listTypes(schema: "public")
        let publicNames = publicTypes.map { $0.name }
        XCTAssertFalse(publicNames.contains(typeName), "Type in 'app' schema should not appear in 'public' listing")

        let appTypes = try await client.introspection.listTypes(schema: "app")
        let appNames = appTypes.map { $0.name }
        XCTAssertTrue(appNames.contains(typeName), "Type should appear in 'app' schema listing")
    }

    // MARK: - listProcedures

    func testListProceduresFindsCreatedProcedure() async throws {
        let procName = uniqueName("proc")
        defer { Task { [client = self.client!] in
            _ = try? await client.connection.simpleQuery("DROP PROCEDURE IF EXISTS \(procName)")
        }}

        _ = try await client.connection.simpleQuery("""
            CREATE PROCEDURE \(procName)()
            LANGUAGE SQL
            AS $$ SELECT 1; $$
            """)

        let procedures = try await client.introspection.listProcedures(schema: "public")
        XCTAssertTrue(procedures.contains(procName), "listProcedures should include the newly created procedure '\(procName)'")
    }

    func testListProceduresExcludesFunctions() async throws {
        let fnName = uniqueName("fn")
        let procName = uniqueName("proc")
        defer { Task { [client = self.client!] in
            _ = try? await client.admin.dropFunction(name: fnName, ifExists: true)
            _ = try? await client.connection.simpleQuery("DROP PROCEDURE IF EXISTS \(procName)")
        }}

        _ = try await client.admin.createFunction(
            name: fnName,
            parameters: [],
            returnType: "INTEGER",
            body: "SELECT 42;",
            language: .sql,
            immutable: true
        )
        _ = try await client.connection.simpleQuery("""
            CREATE PROCEDURE \(procName)()
            LANGUAGE SQL
            AS $$ SELECT 1; $$
            """)

        let procedures = try await client.introspection.listProcedures(schema: "public")
        XCTAssertTrue(procedures.contains(procName), "Should include the procedure")
        XCTAssertFalse(procedures.contains(fnName), "Should NOT include the function")
    }

    func testListProceduresExcludesOtherSchemas() async throws {
        let procName = uniqueName("proc")
        defer { Task { [client = self.client!] in
            _ = try? await client.connection.simpleQuery("DROP PROCEDURE IF EXISTS app.\(procName)")
        }}

        _ = try await client.connection.simpleQuery("""
            CREATE PROCEDURE app.\(procName)()
            LANGUAGE SQL
            AS $$ SELECT 1; $$
            """)

        let publicProcs = try await client.introspection.listProcedures(schema: "public")
        XCTAssertFalse(publicProcs.contains(procName), "Procedure in 'app' schema should not appear in 'public' listing")

        let appProcs = try await client.introspection.listProcedures(schema: "app")
        XCTAssertTrue(appProcs.contains(procName), "Procedure should appear in 'app' schema listing")
    }

    // MARK: - SchemaSummary includes procedures

    func testSchemaSummaryIncludesProcedure() async throws {
        let procName = uniqueName("proc")
        defer { Task { [client = self.client!] in
            _ = try? await client.connection.simpleQuery("DROP PROCEDURE IF EXISTS \(procName)")
        }}

        _ = try await client.connection.simpleQuery("""
            CREATE PROCEDURE \(procName)()
            LANGUAGE SQL
            AS $$ SELECT 1; $$
            """)

        let summary = try await client.introspection.schemaSummary(schema: "public")
        let procedureObjects = summary.objects.filter { $0.type == .procedure }
        let names = procedureObjects.map { $0.name }
        XCTAssertTrue(names.contains(procName), "SchemaSummary should include the procedure '\(procName)' with type .procedure")
    }

    func testSchemaSummaryProcedureHasCorrectType() async throws {
        let procName = uniqueName("proc")
        defer { Task { [client = self.client!] in
            _ = try? await client.connection.simpleQuery("DROP PROCEDURE IF EXISTS \(procName)")
        }}

        _ = try await client.connection.simpleQuery("""
            CREATE PROCEDURE \(procName)()
            LANGUAGE SQL
            AS $$ SELECT 1; $$
            """)

        let summary = try await client.introspection.schemaSummary(schema: "public")
        let match = summary.objects.first { $0.name == procName }
        XCTAssertNotNil(match, "Should find procedure in summary")
        XCTAssertEqual(match?.type, .procedure, "Type should be .procedure")
        XCTAssertTrue(match?.columns.isEmpty ?? false, "Procedures should have no columns")
    }
}
