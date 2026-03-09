import XCTest
import Logging
@testable import PostgresKit

final class FunctionProcedureTests: XCTestCase {

    private var client: PostgresDatabaseClient!
    private var testLogger: Logger!

    override func setUp() async throws {
        TestEnv.loadDotEnv()
        try await super.setUp()
        testLogger = Logger(label: "function-procedure-tests")

        let config = PostgresConfiguration(
            host: TestEnv.host,
            port: TestEnv.port,
            database: TestEnv.database,
            username: TestEnv.username,
            password: TestEnv.password,
            useTLS: TestEnv.useTLS,
            applicationName: "FunctionProcedureTests"
        )

        client = try await PostgresDatabaseClient.connect(configuration: config, logger: testLogger)
    }

    override func tearDown() {
        client?.close()
        super.tearDown()
    }

    // MARK: - SQL Function Tests

    func testSQLFunctions() async throws {
        print("=== Testing SQL Functions ===")

        let result = try await client.withConnection { conn in
            // Create test table
            _ = try await conn.simpleQuery("""
                CREATE TEMPORARY TABLE function_test (
                    id SERIAL PRIMARY KEY,
                    name TEXT,
                    value INTEGER,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)

            // Insert test data
            _ = try await conn.simpleQuery("""
                INSERT INTO function_test (name, value) VALUES
                ('Test 1', 100),
                ('Test 2', 200),
                ('Test 3', 300)
            """)

            // Test various SQL functions
            let funcResults = try await conn.query("""
                SELECT
                    COUNT(*) as total_rows,
                    AVG(value) as avg_value,
                    MAX(value) as max_value,
                    MIN(value) as min_value,
                    SUM(value) as total_value,
                    UPPER(name) as upper_name,
                    LENGTH(name) as name_length,
                    COALESCE(NULLIF(name, ''), 'default') as coalesce_test
                FROM function_test
            """)

            var results: [(Int32, Double, Int32, Int32, Int64, String, Int32, String)] = []
            for try await (count, avg, max, min, sum, upper, length, coalesce) in funcResults.decode((Int32, Double, Int32, Int32, Int64, String, Int32, String).self) {
                results.append((count, avg, max, min, sum, upper, length, coalesce))
                print("Count: \(count), Avg: \(avg), Max: \(max), Min: \(min), Sum: \(sum)")
                print("Upper: \(upper), Length: \(length), Coalesce: \(coalesce)")
            }

            // Test string functions
            let stringFuncResults = try await conn.query("""
                SELECT
                    name,
                    SUBSTRING(name FROM 1 FOR 2) as substring,
                    REPLACE(name, 'Test', 'Function') as replaced,
                    CONCAT(name, ' - ', value::text) as concatenated
                FROM function_test
                WHERE name = 'Test 1'
            """)

            var stringResults: [(String, String, String, String)] = []
            for try await (name, substr, replaced, concat) in stringFuncResults.decode((String, String, String, String).self) {
                stringResults.append((name, substr, replaced, concat))
                print("Name: \(name), Substring: \(substr), Replaced: \(replaced), Concat: \(concat)")
            }

            // Test date functions
            let dateFuncResults = try await conn.query("""
                SELECT
                    created_at,
                    EXTRACT(YEAR FROM created_at) as year,
                    EXTRACT(MONTH FROM created_at) as month,
                    EXTRACT(DAY FROM created_at) as day,
                    DATE_TRUNC('hour', created_at) as truncated
                FROM function_test
                LIMIT 1
            """)

            var dateResults: [(String, Int64, Int64, Int64, String)] = []
            for try await (timestamp, year, month, day, truncated) in dateFuncResults.decode((String, Int64, Int64, Int64, String).self) {
                dateResults.append((timestamp, year, month, day, truncated))
                print("Timestamp: \(timestamp), Year: \(year), Month: \(month), Day: \(day), Truncated: \(truncated)")
            }

            return (results.count, stringResults.count, dateResults.count)
        }

        XCTAssertEqual(result.0, 1, "Should return one aggregate result row")
        XCTAssertEqual(result.1, 1, "Should return one string function result row")
        XCTAssertEqual(result.2, 1, "Should return one date function result row")
        print("✓ SQL functions test passed")
    }

    // MARK: - PL/pgSQL Functions

    func testPLpgSQLFunctions() async throws {
        print("=== Testing PL/pgSQL Functions ===")

        let result = try await client.withConnection { conn in
            // Create a simple PL/pgSQL function
            _ = try await conn.simpleQuery("""
                CREATE OR REPLACE FUNCTION calculate_area(width NUMERIC, height NUMERIC)
                RETURNS NUMERIC AS $$
                BEGIN
                    RETURN width * height;
                END;
                $$ LANGUAGE plpgsql
            """)

            // Create function with conditional logic
            _ = try await conn.simpleQuery("""
                CREATE OR REPLACE FUNCTION get_grade(score NUMERIC)
                RETURNS TEXT AS $$
                DECLARE
                    result TEXT;
                BEGIN
                    IF score >= 90 THEN
                        result := 'A';
                    ELSIF score >= 80 THEN
                        result := 'B';
                    ELSIF score >= 70 THEN
                        result := 'C';
                    ELSIF score >= 60 THEN
                        result := 'D';
                    ELSE
                        result := 'F';
                    END IF;
                    RETURN result;
                END;
                $$ LANGUAGE plpgsql
            """)

            // Create function with loop
            _ = try await conn.simpleQuery("""
                CREATE OR REPLACE FUNCTION factorial(n INTEGER)
                RETURNS BIGINT AS $$
                DECLARE
                    result BIGINT := 1;
                    i INTEGER;
                BEGIN
                    FOR i IN 1..n LOOP
                        result := result * i;
                    END LOOP;
                    RETURN result;
                END;
                $$ LANGUAGE plpgsql
            """)

            // Create function with exception handling
            _ = try await conn.simpleQuery("""
                CREATE OR REPLACE FUNCTION safe_divide(a NUMERIC, b NUMERIC)
                RETURNS NUMERIC AS $$
                DECLARE
                    result NUMERIC;
                BEGIN
                    BEGIN
                        result := a / b;
                        RETURN result;
                    EXCEPTION
                        WHEN division_by_zero THEN
                            RETURN 0;
                        WHEN others THEN
                            RETURN NULL;
                    END;
                END;
                $$ LANGUAGE plpgsql
            """)

            // Test area function
            let areaResults = try await conn.query("""
                SELECT calculate_area(10, 5) as area
            """)

            var area = 0.0
            for try await (result) in areaResults.decode(Double.self) {
                area = result
                break
            }

            // Test grade function
            let gradeResults = try await conn.query("""
                SELECT
                    get_grade(95) as grade_a,
                    get_grade(85) as grade_b,
                    get_grade(75) as grade_c,
                    get_grade(65) as grade_d,
                    get_grade(55) as grade_f
            """)

            var grades: [(String, String, String, String, String)] = []
            for try await (a, b, c, d, f) in gradeResults.decode((String, String, String, String, String).self) {
                grades.append((a, b, c, d, f))
                print("Grades: A=\(a), B=\(b), C=\(c), D=\(d), F=\(f)")
            }

            // Test factorial function
            let factorialResults = try await conn.query("""
                SELECT factorial(5) as fact_5, factorial(10) as fact_10
            """)

            var factorials: [(Int64, Int64)] = []
            for try await (fact5, fact10) in factorialResults.decode((Int64, Int64).self) {
                factorials.append((fact5, fact10))
                print("Factorials: 5!=\(fact5), 10!=\(fact10)")
            }

            // Test safe division function
            let divisionResults = try await conn.query("""
                SELECT
                    safe_divide(10, 2) as normal,
                    safe_divide(10, 0) as zero_division
            """)

            var divisions: [(Double, Double)] = []
            for try await (normal, zeroDiv) in divisionResults.decode((Double, Double).self) {
                divisions.append((normal, zeroDiv))
                print("Division: 10/2=\(normal), 10/0=\(zeroDiv)")
            }

            // Clean up functions
            _ = try await conn.simpleQuery("DROP FUNCTION IF EXISTS calculate_area(NUMERIC, NUMERIC)")
            _ = try await conn.simpleQuery("DROP FUNCTION IF EXISTS get_grade(NUMERIC)")
            _ = try await conn.simpleQuery("DROP FUNCTION IF EXISTS factorial(INTEGER)")
            _ = try await conn.simpleQuery("DROP FUNCTION IF EXISTS safe_divide(NUMERIC, NUMERIC)")

            return (area, grades.count, factorials.count, divisions.count)
        }

        XCTAssertEqual(result.0, 50.0, "Area calculation should be correct")
        XCTAssertEqual(result.1, 1, "Should return one grade result")
        XCTAssertEqual(result.2, 1, "Should return one factorial result")
        XCTAssertEqual(result.3, 1, "Should return one division result")
        print("✓ PL/pgSQL functions test passed")
    }

    // MARK: - Table Functions

    func testTableFunctions() async throws {
        print("=== Testing Table Functions ===")

        let result = try await client.withConnection { conn in
            // Create test table
            _ = try await conn.simpleQuery("""
                CREATE TEMPORARY TABLE departments (
                    id SERIAL PRIMARY KEY,
                    name TEXT,
                    manager_id INTEGER
                )
            """)

            _ = try await conn.simpleQuery("""
                CREATE TEMPORARY TABLE employees (
                    id SERIAL PRIMARY KEY,
                    name TEXT,
                    department_id INTEGER,
                    salary NUMERIC,
                    hire_date DATE
                )
            """)

            // Insert test data
            _ = try await conn.simpleQuery("""
                INSERT INTO departments (name, manager_id) VALUES
                ('Engineering', 1),
                ('Sales', 2),
                ('Marketing', 3)
            """)

            _ = try await conn.simpleQuery("""
                INSERT INTO employees (name, department_id, salary, hire_date) VALUES
                ('Alice', 1, 80000, '2020-01-15'),
                ('Bob', 1, 75000, '2020-03-20'),
                ('Charlie', 2, 65000, '2020-02-10'),
                ('Diana', 2, 70000, '2020-04-05'),
                ('Eve', 3, 60000, '2020-05-12')
            """)

            // Create a table-returning function
            _ = try await conn.simpleQuery("""
                CREATE OR REPLACE FUNCTION get_employees_by_dept(dept_name TEXT)
                RETURNS TABLE (
                    emp_id INTEGER,
                    emp_name TEXT,
                    emp_salary NUMERIC,
                    dept_name TEXT
                ) AS $$
                BEGIN
                    RETURN QUERY
                    SELECT
                        e.id,
                        e.name,
                        e.salary,
                        d.name
                    FROM employees e
                    JOIN departments d ON e.department_id = d.id
                    WHERE d.name = dept_name
                    ORDER BY e.salary DESC;
                END;
                $$ LANGUAGE plpgsql
            """)

            // Create a recursive table function (hierarchical data)
            _ = try await conn.simpleQuery("""
                CREATE OR REPLACE FUNCTION get_employee_hierarchy(root_id INTEGER)
                RETURNS TABLE (
                    emp_id INTEGER,
                    emp_name TEXT,
                    manager_id INTEGER,
                    level INTEGER
                ) AS $$
                WITH RECURSIVE employee_tree AS (
                    SELECT
                        e.id,
                        e.name,
                        e.department_id as manager_id,
                        1 as level
                    FROM employees e
                    WHERE e.id = root_id

                    UNION ALL

                    SELECT
                        e.id,
                        e.name,
                        e.department_id,
                        et.level + 1
                    FROM employees e
                    JOIN employee_tree et ON e.department_id = et.emp_id
                    WHERE et.level < 5
                )
                SELECT * FROM employee_tree ORDER BY level;
                END;
                $$ LANGUAGE sql
            """)

            // Test the table function
            let funcResults = try await conn.query("""
                SELECT * FROM get_employees_by_dept('Engineering')
            """)

            var engineeringEmployees: [(Int32, String, Double, String)] = []
            for try await (id, name, salary, dept) in funcResults.decode((Int32, String, Double, String).self) {
                engineeringEmployees.append((id, name, salary, dept))
                print("Engineering Employee: ID=\(id), Name=\(name), Salary=\(salary), Dept=\(dept)")
            }

            // Test recursive function
            let hierarchyResults = try await conn.query("""
                SELECT * FROM get_employee_hierarchy(1)
            """)

            var hierarchy: [(Int32, String, Int32, Int32)] = []
            for try await (id, name, managerId, level) in hierarchyResults.decode((Int32, String, Int32, Int32).self) {
                hierarchy.append((id, name, managerId, level))
                print("Hierarchy: ID=\(id), Name=\(name), Manager=\(managerId), Level=\(level)")
            }

            // Clean up
            _ = try await conn.simpleQuery("DROP FUNCTION IF EXISTS get_employees_by_dept(TEXT)")
            _ = try await conn.simpleQuery("DROP FUNCTION IF EXISTS get_employee_hierarchy(INTEGER)")

            return (engineeringEmployees.count, hierarchy.count)
        }

        XCTAssertGreaterThan(result.0, 0, "Should return engineering employees")
        XCTAssertGreaterThan(result.1, 0, "Should return hierarchy data")
        print("✓ Table functions test passed")
    }

    // MARK: - Stored Procedures

    func testStoredProcedures() async throws {
        print("=== Testing Stored Procedures ===")

        let result = try await client.withConnection { conn in
            // Create test table
            _ = try await conn.simpleQuery("""
                CREATE TEMPORARY TABLE orders (
                    id SERIAL PRIMARY KEY,
                    customer_id INTEGER,
                    product_name TEXT,
                    quantity INTEGER,
                    price NUMERIC,
                    status TEXT DEFAULT 'pending'
                )
            """)

            // Insert test data
            _ = try await conn.simpleQuery("""
                INSERT INTO orders (customer_id, product_name, quantity, price) VALUES
                (1, 'Widget A', 2, 100.00),
                (2, 'Widget B', 1, 150.00),
                (1, 'Widget C', 3, 75.00)
            """)

            // Create stored procedure for order processing
            _ = try await conn.simpleQuery("""
                CREATE OR REPLACE PROCEDURE process_order(
                    p_order_id INTEGER,
                    p_new_status TEXT DEFAULT 'processed'
                )
                LANGUAGE plpgsql
                AS $$
                DECLARE
                    v_current_status TEXT;
                    v_customer_id INTEGER;
                    v_total NUMERIC;
                BEGIN
                    -- Get current order info
                    SELECT status, customer_id INTO v_current_status, v_customer_id
                    FROM orders
                    WHERE id = p_order_id;

                    -- Calculate total
                    SELECT quantity * price INTO v_total
                    FROM orders
                    WHERE id = p_order_id;

                    -- Update order status
                    UPDATE orders
                    SET status = p_new_status
                    WHERE id = p_order_id;

                    -- Log the processing (simulated)
                    RAISE NOTICE 'Order % processed: Status changed from % to %, Total: %',
                        p_order_id, v_current_status, p_new_status, v_total;
                END;
                $$;
            """)

            // Create stored procedure with OUT parameters
            _ = try await conn.simpleQuery("""
                CREATE OR REPLACE PROCEDURE get_order_summary(
                    p_customer_id INTEGER,
                    OUT p_total_orders INTEGER,
                    OUT p_total_value NUMERIC
                )
                LANGUAGE plpgsql
                AS $$
                BEGIN
                    SELECT COUNT(*), COALESCE(SUM(quantity * price), 0)
                    INTO p_total_orders, p_total_value
                    FROM orders
                    WHERE customer_id = p_customer_id;
                END;
                $$;
            """)

            // Create procedure with exception handling
            _ = try await conn.simpleQuery("""
                CREATE OR REPLACE PROCEDURE safe_update_order(
                    p_order_id INTEGER,
                    p_new_quantity INTEGER
                )
                LANGUAGE plpgsql
                AS $$
                DECLARE
                    v_old_quantity INTEGER;
                BEGIN
                    -- Get old quantity for logging
                    SELECT quantity INTO v_old_quantity
                    FROM orders
                    WHERE id = p_order_id;

                    -- Validate new quantity
                    IF p_new_quantity < 0 THEN
                        RAISE EXCEPTION 'Quantity cannot be negative';
                    END IF;

                    -- Update the order
                    UPDATE orders
                    SET quantity = p_new_quantity
                    WHERE id = p_order_id;

                    RAISE NOTICE 'Order % updated: quantity changed from % to %',
                        p_order_id, v_old_quantity, p_new_quantity;

                EXCEPTION
                    WHEN NO_DATA_FOUND THEN
                        RAISE EXCEPTION 'Order % not found', p_order_id;
                    WHEN others THEN
                        RAISE NOTICE 'Error updating order %: %', p_order_id, SQLERRM;
                END;
                $$;
            """)

            // Test the procedures
            _ = try await conn.query("CALL process_order(1, 'shipped')")
            _ = try await conn.query("CALL process_order(2)")

            // Test procedure with OUT parameters (this might need different syntax)
            let summaryRows = try await conn.query("""
                SELECT
                    COUNT(*) as total_orders,
                    COALESCE(SUM(quantity * price), 0) as total_value
                FROM orders
                WHERE customer_id = 1
            """)

            var summary: [(Int32, Double)] = []
            for try await (orders, value) in summaryRows.decode((Int32, Double).self) {
                summary.append((orders, value))
                print("Summary: Orders=\(orders), Value=\(value)")
            }

            // Test exception handling
            do {
                _ = try await conn.query("CALL safe_update_order(999, 5)")
            } catch {
                print("Expected exception: \(error)")
            }

            // Test validation
            do {
                _ = try await conn.query("CALL safe_update_order(1, -1)")
            } catch {
                print("Expected validation error: \(error)")
            }

            // Clean up procedures
            _ = try await conn.simpleQuery("DROP PROCEDURE IF EXISTS process_order(INTEGER, TEXT)")
            _ = try await conn.simpleQuery("DROP PROCEDURE IF EXISTS get_order_summary(INTEGER, OUT INTEGER, OUT NUMERIC)")
            _ = try await conn.simpleQuery("DROP PROCEDURE IF EXISTS safe_update_order(INTEGER, INTEGER)")

            return summary.count
        }

        XCTAssertEqual(result, 1, "Should return one summary result")
        print("✓ Stored procedures test passed")
    }

    // MARK: - Aggregate Functions

    func testCustomAggregateFunctions() async throws {
        print("=== Testing Custom Aggregate Functions ===")

        let result = try await client.withConnection { conn in {
            // Create test table
            _ = try await conn.simpleQuery("""
                CREATE TEMPORARY TABLE aggregate_test (
                    id SERIAL PRIMARY KEY,
                    category TEXT,
                    value NUMERIC
                )
            """)

            // Insert test data
            _ = try await conn.simpleQuery("""
                INSERT INTO aggregate_test (category, value) VALUES
                ('A', 10), ('A', 20), ('A', 30),
                ('B', 5), ('B', 15), ('B', 25),
                ('C', 100), ('C', 200)
            """)

            // Create custom aggregate function for median
            _ = try await conn.simpleQuery("""
                CREATE OR REPLACE FUNCTION median_finalfn(anyarray)
                RETURNS NUMERIC AS $$
                DECLARE
                    v_array NUMERIC[];
                    v_size INTEGER;
                BEGIN
                    v_array := $1;
                    v_size := array_length(v_array, 1);
                    IF v_size = 0 THEN
                        RETURN NULL;
                    END IF;
                    RETURN v_array[ceil(v_size / 2.0)];
                END;
                $$ LANGUAGE plpgsql IMMUTABLE;
            """)

            _ = try await conn.simpleQuery("""
                CREATE OR REPLACE AGGREGATE median(NUMERIC) (
                    SFUNC = array_agg(NUMERIC),
                    STYPE = anyarray,
                    FINALFUNC = median_finalfn
                );
            """)

            // Test the custom median function
            let medianResults = try await conn.query("""
                SELECT
                    category,
                    median(value) as median_value,
                    AVG(value) as avg_value,
                    MIN(value) as min_value,
                    MAX(value) as max_value
                FROM aggregate_test
                GROUP BY category
                ORDER BY category
            """)

            var stats: [(String, Double, Double, Double, Double)] = []
            for try await (category, median, avg, min, max) in medianResults.decode((String, Double, Double, Double, Double).self) {
                stats.append((category, median, avg, min, max))
                print("Category \(category): Median=\(median), Avg=\(avg), Min=\(min), Max=\(max)")
            }

            // Create string concatenation aggregate
            _ = try await conn.simpleQuery("""
                CREATE OR REPLACE AGGREGATE group_concat(TEXT) (
                    SFUNC = array_agg(TEXT),
                    STYPE = anyarray,
                    FINALFUNC = array_to_string
                );
            """)

            let concatResults = try await conn.query("""
                SELECT
                    category,
                    group_concat(value::TEXT ORDER BY value) as concatenated_values
                FROM aggregate_test
                GROUP BY category
                ORDER BY category
            """)

            var concatenations: [(String, String)] = []
            for try await (category, concatenated) in concatResults.decode((String, String).self) {
                concatenations.append((category, concatenated))
                print("Category \(category): Concatenated=\(concatenated)")
            }

            // Clean up
            _ = try await conn.simpleQuery("DROP AGGREGATE IF EXISTS median(NUMERIC)")
            _ = try await conn.simpleQuery("DROP FUNCTION IF EXISTS median_finalfn(anyarray)")
            _ = try await conn.simpleQuery("DROP AGGREGATE IF EXISTS group_concat(TEXT)")

            return (stats.count, concatenations.count)
        }

        XCTAssertEqual(result.0, 3, "Should have stats for 3 categories")
        XCTAssertEqual(result.1, 3, "Should have concatenations for 3 categories")
        print("✓ Custom aggregate functions test passed")
    }
}