@testable import PostgresKit
import XCTest

final class SearchSQLTests: XCTestCase {

    // MARK: - makeLikePattern

    func testMakeLikePattern_PlainString_Unchanged() {
        XCTAssertEqual(PostgresSearchSQL.makeLikePattern("foo"), "foo")
    }

    func testMakeLikePattern_TrimsWhitespace() {
        XCTAssertEqual(PostgresSearchSQL.makeLikePattern("  bar  "), "bar")
    }

    func testMakeLikePattern_EscapesPercent() {
        XCTAssertEqual(PostgresSearchSQL.makeLikePattern("100%"), "100\\%")
    }

    func testMakeLikePattern_EscapesUnderscore() {
        XCTAssertEqual(PostgresSearchSQL.makeLikePattern("some_table"), "some\\_table")
    }

    func testMakeLikePattern_EscapesBackslash() {
        XCTAssertEqual(PostgresSearchSQL.makeLikePattern("a\\b"), "a\\\\b")
    }

    func testMakeLikePattern_EscapesSingleQuote() {
        XCTAssertEqual(PostgresSearchSQL.makeLikePattern("o'reilly"), "o''reilly")
    }

    func testMakeLikePattern_MultipleSpecialChars() {
        let result = PostgresSearchSQL.makeLikePattern("a%b_c")
        XCTAssertEqual(result, "a\\%b\\_c")
    }

    func testMakeLikePattern_EmptyString() {
        XCTAssertEqual(PostgresSearchSQL.makeLikePattern(""), "")
    }

    // MARK: - tables()

    func testTablesBuilder() {
        let sql = PostgresSearchSQL.tables(pattern: "foo", limit: 25)
        XCTAssertTrue(sql.contains("table_name"))
        XCTAssertTrue(sql.contains("ILIKE '%foo%'"))
        XCTAssertTrue(sql.contains("LIMIT 25"))
        XCTAssertTrue(sql.contains("BASE TABLE"))
        XCTAssertTrue(sql.contains("pg_catalog"))
    }

    func testTablesBuilder_LimitApplied() {
        let sql = PostgresSearchSQL.tables(pattern: "t", limit: 5)
        XCTAssertTrue(sql.contains("LIMIT 5"))
        XCTAssertFalse(sql.contains("LIMIT 25"))
    }

    // MARK: - views()

    func testViewsBuilder() {
        let sql = PostgresSearchSQL.views(pattern: "my_view", limit: 20)
        XCTAssertTrue(sql.contains("information_schema.views"))
        XCTAssertTrue(sql.contains("ILIKE '%my_view%'"))
        XCTAssertTrue(sql.contains("LIMIT 20"))
        XCTAssertTrue(sql.contains("table_name"))
    }

    func testViewsBuilder_SearchesDefinition() {
        let sql = PostgresSearchSQL.views(pattern: "q", limit: 10)
        XCTAssertTrue(sql.contains("view_definition"))
    }

    // MARK: - materializedViews()

    func testMaterializedViewsBuilder() {
        let sql = PostgresSearchSQL.materializedViews(pattern: "mat", limit: 15)
        XCTAssertTrue(sql.contains("pg_matviews"))
        XCTAssertTrue(sql.contains("ILIKE '%mat%'"))
        XCTAssertTrue(sql.contains("LIMIT 15"))
        XCTAssertTrue(sql.contains("matviewname"))
    }

    // MARK: - functions()

    func testFunctionsBuilder() {
        let sql = PostgresSearchSQL.functions(pattern: "get", limit: 30)
        XCTAssertTrue(sql.contains("information_schema.routines"))
        XCTAssertTrue(sql.contains("FUNCTION"))
        XCTAssertTrue(sql.contains("ILIKE '%get%'"))
        XCTAssertTrue(sql.contains("LIMIT 30"))
    }

    // MARK: - procedures()

    func testProceduresBuilder() {
        let sql = PostgresSearchSQL.procedures(pattern: "proc", limit: 10)
        XCTAssertTrue(sql.contains("information_schema.routines"))
        XCTAssertTrue(sql.contains("PROCEDURE"))
        XCTAssertTrue(sql.contains("ILIKE '%proc%'"))
        XCTAssertTrue(sql.contains("LIMIT 10"))
    }

    // MARK: - triggers()

    func testTriggersBuilder() {
        let sql = PostgresSearchSQL.triggers(pattern: "audit", limit: 50)
        XCTAssertTrue(sql.contains("information_schema.triggers"))
        XCTAssertTrue(sql.contains("ILIKE '%audit%'"))
        XCTAssertTrue(sql.contains("LIMIT 50"))
        XCTAssertTrue(sql.contains("trigger_name"))
    }

    // MARK: - columns()

    func testColumnsBuilder() {
        let sql = PostgresSearchSQL.columns(pattern: "email", limit: 100)
        XCTAssertTrue(sql.contains("information_schema.columns"))
        XCTAssertTrue(sql.contains("ILIKE '%email%'"))
        XCTAssertTrue(sql.contains("LIMIT 100"))
        XCTAssertTrue(sql.contains("column_name"))
    }

    // MARK: - indexes()

    func testIndexesBuilder() {
        let sql = PostgresSearchSQL.indexes(pattern: "idx", limit: 40)
        XCTAssertTrue(sql.contains("pg_indexes"))
        XCTAssertTrue(sql.contains("ILIKE '%idx%'"))
        XCTAssertTrue(sql.contains("LIMIT 40"))
        XCTAssertTrue(sql.contains("indexname"))
    }

    // MARK: - foreignKeys()

    func testForeignKeysBuilder() {
        let sql = PostgresSearchSQL.foreignKeys(pattern: "bar", limit: 10)
        XCTAssertTrue(sql.contains("WITH fk_data"))
        XCTAssertTrue(sql.contains("ILIKE '%bar%'"))
        XCTAssertTrue(sql.contains("LIMIT 10"))
    }

    func testForeignKeysBuilder_IncludesReferencedTable() {
        let sql = PostgresSearchSQL.foreignKeys(pattern: "fk", limit: 10)
        XCTAssertTrue(sql.contains("referenced_table"))
        XCTAssertTrue(sql.contains("FOREIGN KEY"))
    }

    // MARK: - Excluded schemas

    func testAllBuilders_ExcludeSystemSchemas() {
        let builders: [(String, Int) -> String] = [
            PostgresSearchSQL.tables,
            PostgresSearchSQL.functions,
            PostgresSearchSQL.procedures,
            PostgresSearchSQL.columns,
        ]
        for builder in builders {
            let sql = builder("x", 10)
            XCTAssertTrue(sql.contains("pg_catalog"), "Should exclude pg_catalog: \(sql.prefix(80))")
            XCTAssertTrue(sql.contains("information_schema"), "Should exclude information_schema: \(sql.prefix(80))")
        }
    }
}

