import XCTest
import Logging
@testable import PostgresKit

final class TriggerTests: XCTestCase {

    private var client: PostgresDatabaseClient!
    private var testLogger: Logger!

    override func setUp() async throws {
        TestEnv.loadDotEnv()
        try await super.setUp()
        testLogger = Logger(label: "trigger-tests")

        let config = PostgresConfiguration(
            host: TestEnv.host,
            port: TestEnv.port,
            database: TestEnv.database,
            username: TestEnv.username,
            password: TestEnv.password,
            useTLS: TestEnv.useTLS,
            applicationName: "TriggerTests"
        )

        client = try await PostgresDatabaseClient.connect(configuration: config, logger: testLogger)
    }

    override func tearDown() {
        client?.close()
        super.tearDown()
    }

    // MARK: - Basic Trigger Tests

    func testBasicTriggers() async throws {
        print("=== Testing Basic Triggers ===")

        let result = try await client.withConnection { conn in
            // Create test table
            _ = try await conn.simpleQuery("""
                CREATE TEMPORARY TABLE products (
                    id SERIAL PRIMARY KEY,
                    name TEXT,
                    price NUMERIC,
                    stock_count INTEGER,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)

            // Create audit table
            _ = try await conn.simpleQuery("""
                CREATE TEMPORARY TABLE product_audit (
                    id SERIAL PRIMARY KEY,
                    action TEXT,
                    product_id INTEGER,
                    old_name TEXT,
                    new_name TEXT,
                    old_price NUMERIC,
                    new_price NUMERIC,
                    changed_by TEXT DEFAULT 'system',
                    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)

            // Create trigger function
            _ = try await conn.simpleQuery("""
                CREATE OR REPLACE FUNCTION audit_product_changes()
                RETURNS TRIGGER AS $$
                DECLARE
                    v_action TEXT;
                    v_old_name TEXT;
                    v_new_name TEXT;
                    v_old_price NUMERIC;
                    v_new_price NUMERIC;
                BEGIN
                    -- Determine action type
                    IF TG_OP = 'INSERT' THEN
                        v_action := 'INSERT';
                        v_old_name := NULL;
                        v_new_name := NEW.name;
                        v_old_price := NULL;
                        v_new_price := NEW.price;
                    ELSIF TG_OP = 'UPDATE' THEN
                        v_action := 'UPDATE';
                        v_old_name := OLD.name;
                        v_new_name := NEW.name;
                        v_old_price := OLD.price;
                        v_new_price := NEW.price;
                    ELSIF TG_OP = 'DELETE' THEN
                        v_action := 'DELETE';
                        v_old_name := OLD.name;
                        v_new_name := NULL;
                        v_old_price := OLD.price;
                        v_new_price := NULL;
                    END IF;

                    -- Insert audit record
                    INSERT INTO product_audit (action, product_id, old_name, new_name, old_price, new_price)
                    VALUES (v_action, COALESCE(NEW.id, OLD.id), v_old_name, v_new_name, v_old_price, v_new_price);

                    RETURN COALESCE(NEW, OLD);
                END;
                $$ LANGUAGE plpgsql
            """)

            // Create trigger
            _ = try await conn.simpleQuery("""
                CREATE TRIGGER product_audit_trigger
                AFTER INSERT OR UPDATE OR DELETE ON products
                FOR EACH ROW EXECUTE FUNCTION audit_product_changes()
            """)

            // Test INSERT trigger
            _ = try await conn.query("""
                INSERT INTO products (name, price, stock_count)
                VALUES ('Test Product 1', 99.99, 10)
            """)

            // Test UPDATE trigger
            _ = try await conn.query("""
                UPDATE products SET price = 89.99 WHERE name = 'Test Product 1'
            """)

            // Test DELETE trigger
            _ = try await conn.query("""
                INSERT INTO products (name, price, stock_count)
                VALUES ('Test Product 2', 49.99, 5)
            """)

            let deleteId = try await conn.query("""
                SELECT id FROM products WHERE name = 'Test Product 2'
            """)
            var productId = 0
            for try await (id) in deleteId.decode(Int32.self) {
                productId = id
                break
            }

            _ = try await conn.query("DELETE FROM products WHERE id = $1", binds: [PGData(int32: productId)])

            // Verify audit records
            let auditRows = try await conn.query("""
                SELECT action, product_id, old_name, new_name, old_price, new_price
                FROM product_audit
                ORDER BY changed_at
            """)

            var auditRecords: [(String, Int32, String?, String?, Double?, Double?)] = []
            for try await (action, prodId, oldName, newName, oldPrice, newPrice) in auditRows.decode((String, Int32, String?, String?, Double?, Double?).self) {
                auditRecords.append((action, prodId, oldName, newName, oldPrice, newPrice))
                print("Audit: \(action), ID: \(prodId), \(oldName ?? "NULL") -> \(newName ?? "NULL"), \(oldPrice ?? 0) -> \(newPrice ?? 0)")
            }

            // Clean up
            _ = try await conn.simpleQuery("DROP TRIGGER IF EXISTS product_audit_trigger")
            _ = try await conn.simpleQuery("DROP FUNCTION IF EXISTS audit_product_changes()")
            _ = try await conn.simpleQuery("DROP TABLE IF EXISTS product_audit")
            _ = try await conn.simpleQuery("DROP TABLE IF EXISTS products")

            return auditRecords.count
        }

        XCTAssertEqual(result, 4, "Should have 4 audit records (insert, update, insert, delete)")
        print("✓ Basic triggers test passed")
    }

    // MARK: - Conditional Triggers

    func testConditionalTriggers() async throws {
        print("=== Testing Conditional Triggers ===")

        let result = try await client.withConnection { conn in
            // Create test table
            _ = try await conn.simpleQuery("""
                CREATE TEMPORARY TABLE conditional_test (
                    id SERIAL PRIMARY KEY,
                    name TEXT,
                    status TEXT,
                    priority INTEGER,
                    last_modified TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)

            // Create trigger with conditions
            _ = try await conn.simpleQuery("""
                CREATE OR REPLACE FUNCTION conditional_update_trigger()
                RETURNS TRIGGER AS $$
                BEGIN
                    -- Only update timestamp if status actually changes
                    IF TG_OP = 'UPDATE' AND NEW.status IS DISTINCT FROM OLD.status THEN
                        NEW.last_modified = CURRENT_TIMESTAMP;
                    END IF;

                    -- Auto-update priority based on status
                    IF NEW.status = 'urgent' THEN
                        NEW.priority = GREATEST(NEW.priority, 100);
                    ELSIF NEW.status = 'normal' THEN
                        NEW.priority = GREATEST(NEW.priority, 50);
                    ELSIF NEW.status = 'low' THEN
                        NEW.priority = GREATEST(NEW.priority, 10);
                    END IF;

                    RETURN NEW;
                END;
                $$ LANGUAGE plpgsql
            """)

            _ = try await conn.simpleQuery("""
                CREATE TRIGGER conditional_before_update
                BEFORE UPDATE ON conditional_test
                FOR EACH ROW EXECUTE FUNCTION conditional_update_trigger()
            """)

            // Create trigger to log only high-priority changes
            _ = try await conn.simpleQuery("""
                CREATE OR REPLACE FUNCTION log_high_priority_changes()
                RETURNS TRIGGER AS $$
                BEGIN
                    IF NEW.priority >= 100 THEN
                        RAISE NOTICE 'High priority update detected: % (ID: %)', TG_OP, NEW.id;
                    END IF;
                    RETURN NEW;
                END;
                $$ LANGUAGE plpgsql
            """)

            _ = try await conn.simpleQuery("""
                CREATE TRIGGER high_priority_log
                AFTER UPDATE ON conditional_test
                FOR EACH ROW EXECUTE FUNCTION log_high_priority_changes()
            """)

            // Insert initial data
            _ = try await conn.query("""
                INSERT INTO conditional_test (name, status, priority)
                VALUES ('Task 1', 'normal', 30)
            """)

            let initialId = try await conn.query("""
                SELECT id FROM conditional_test WHERE name = 'Task 1'
            """)
            var taskId = 0
            for try await (id) in initialId.decode(Int32.self) {
                taskId = id
                break
            }

            // Test status change (should update timestamp and priority)
            _ = try await conn.query("""
                UPDATE conditional_test SET status = 'urgent' WHERE id = $1
            """, binds: [PGData(int32: taskId)])

            // Test another update that doesn't change status (should not update timestamp)
            _ = try await conn.query("""
                UPDATE conditional_test SET name = 'Urgent Task 1' WHERE id = $1
            """, binds: [PGData(int32: taskId)])

            // Verify the changes
            let resultRows = try await conn.query("""
                SELECT status, priority, last_modified FROM conditional_test WHERE id = $1
            """, binds: [PGData(int32: taskId)])

            var results: [(String, Int32, String)] = []
            for try await (status, priority, modified) in resultRows.decode((String, Int32, String).self) {
                results.append((status, priority, modified))
                print("Final State: Status=\(status), Priority=\(priority), Modified=\(modified)")
            }

            // Clean up
            _ = try await conn.simpleQuery("DROP TRIGGER IF EXISTS conditional_before_update")
            _ = try await conn.simpleQuery("DROP TRIGGER IF EXISTS high_priority_log")
            _ = try await conn.simpleQuery("DROP FUNCTION IF EXISTS conditional_update_trigger()")
            _ = try await conn.simpleQuery("DROP FUNCTION IF EXISTS log_high_priority_changes()")
            _ = try await conn.simpleQuery("DROP TABLE IF EXISTS conditional_test")

            return results.count
        }

        XCTAssertEqual(result, 1, "Should have one result row")
        print("✓ Conditional triggers test passed")
    }

    // MARK: - Statement vs Row Triggers

    func testStatementLevelTriggers() async throws {
        print("=== Testing Statement Level Triggers ===")

        let result = try await client.withConnection { conn in
            // Create test tables
            _ = try await conn.simpleQuery("""
                CREATE TEMPORARY TABLE statement_test (
                    id SERIAL PRIMARY KEY,
                    name TEXT,
                    operation TEXT
                )
            """)

            _ = try await conn.simpleQuery("""
                CREATE TEMPORARY TABLE operation_log (
                    id SERIAL PRIMARY KEY,
                    operation_type TEXT,
                    affected_rows INTEGER,
                    statement_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)

            // Statement-level trigger function
            _ = try await conn.simpleQuery("""
                CREATE OR REPLACE FUNCTION log_statement_operations()
                RETURNS TRIGGER AS $$
                DECLARE
                    v_operation TEXT;
                    v_row_count INTEGER;
                BEGIN
                    IF TG_OP = 'INSERT' THEN
                        v_operation := 'BULK INSERT';
                    ELSIF TG_OP = 'UPDATE' THEN
                        v_operation := 'BULK UPDATE';
                    ELSIF TG_OP = 'DELETE' THEN
                        v_operation := 'BULK DELETE';
                    END IF;

                    -- Count affected rows (approximation)
                    SELECT COUNT(*) INTO v_row_count FROM statement_test;

                    INSERT INTO operation_log (operation_type, affected_rows)
                    VALUES (v_operation, v_row_count);

                    RETURN NULL; -- Statement-level triggers must return NULL
                END;
                $$ LANGUAGE plpgsql
            """)

            // Row-level trigger function
            _ = try await conn.simpleQuery("""
                CREATE OR REPLACE FUNCTION log_row_operations()
                RETURNS TRIGGER AS $$
                BEGIN
                    IF TG_OP = 'INSERT' THEN
                        UPDATE statement_test SET operation = 'row_insert' WHERE id = NEW.id;
                    ELSIF TG_OP = 'UPDATE' THEN
                        UPDATE statement_test SET operation = 'row_update' WHERE id = NEW.id;
                    ELSIF TG_OP = 'DELETE' THEN
                        -- Log row deletion before it happens
                        RAISE NOTICE 'Deleting row: ID=%, Name=%', OLD.id, OLD.name;
                    END IF;

                    RETURN COALESCE(NEW, OLD);
                END;
                $$ LANGUAGE plpgsql
            """)

            // Create both statement and row level triggers
            _ = try await conn.simpleQuery("""
                CREATE TRIGGER statement_log_before
                BEFORE INSERT OR UPDATE OR DELETE ON statement_test
                FOR EACH STATEMENT EXECUTE FUNCTION log_statement_operations()
            """)

            _ = try await conn.simpleQuery("""
                CREATE TRIGGER row_log_before
                BEFORE INSERT OR UPDATE OR DELETE ON statement_test
                FOR EACH ROW EXECUTE FUNCTION log_row_operations()
            """)

            // Test bulk operations
            _ = try await conn.query("""
                INSERT INTO statement_test (name, operation) VALUES
                ('Test 1', 'initial'),
                ('Test 2', 'initial'),
                ('Test 3', 'initial')
            """)

            // Test bulk update
            _ = try await conn.query("""
                UPDATE statement_test SET name = name || ' - Updated'
            """)

            // Test bulk delete
            _ = try await conn.query("""
                DELETE FROM statement_test WHERE name LIKE '%Updated%'
            """)

            // Verify operation log
            let logRows = try await conn.query("""
                SELECT operation_type, affected_rows, statement_timestamp
                FROM operation_log
                ORDER BY statement_timestamp
            """)

            var logs: [(String, Int32, String)] = []
            for try await (operation, rows, timestamp) in logRows.decode((String, Int32, String).self) {
                logs.append((operation, rows, timestamp))
                print("Operation: \(operation), Rows: \(rows), Timestamp: \(timestamp)")
            }

            // Clean up
            _ = try await conn.simpleQuery("DROP TRIGGER IF EXISTS statement_log_before")
            _ = try await conn.simpleQuery("DROP TRIGGER IF EXISTS row_log_before")
            _ = try await conn.simpleQuery("DROP FUNCTION IF EXISTS log_statement_operations()")
            _ = try await conn.simpleQuery("DROP FUNCTION IF EXISTS log_row_operations()")
            _ = try await conn.simpleQuery("DROP TABLE IF EXISTS operation_log")
            _ = try await conn.simpleQuery("DROP TABLE IF EXISTS statement_test")

            return logs.count
        }

        XCTAssertEqual(result, 3, "Should have 3 operation logs (insert, update, delete)")
        print("✓ Statement level triggers test passed")
    }

    // MARK: - Instead Of Triggers

    func testInsteadOfTriggers() async throws {
        print("=== Testing INSTEAD OF Triggers ===")

        let result = try await client.withConnection { conn in
            // Create a view that looks like a table
            _ = try await conn.simpleQuery("""
                CREATE TEMPORARY TABLE employees (
                    id SERIAL PRIMARY KEY,
                    name TEXT,
                    department TEXT,
                    salary NUMERIC,
                    hire_date DATE
                )
            """)

            _ = try await conn.simpleQuery("""
                CREATE TEMPORARY TABLE employee_log (
                    id SERIAL PRIMARY KEY,
                    operation TEXT,
                    name TEXT,
                    department TEXT,
                    salary NUMERIC,
                    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)

            // Insert test data
            _ = try await conn.simpleQuery("""
                INSERT INTO employees (name, department, salary, hire_date) VALUES
                ('Alice', 'Engineering', 80000, '2020-01-15'),
                ('Bob', 'Sales', 60000, '2020-02-20'),
                ('Charlie', 'Engineering', 85000, '2020-03-10')
            """)

            // Create view
            _ = try await conn.simpleQuery("""
                CREATE VIEW employee_view AS
                SELECT id, name, department, salary FROM employees
            """)

            // Create INSTEAD OF trigger function for the view
            _ = try await conn.simpleQuery("""
                CREATE OR REPLACE FUNCTION employee_view_trigger()
                RETURNS TRIGGER AS $$
                BEGIN
                    IF TG_OP = 'INSERT' THEN
                        INSERT INTO employees (name, department, salary, hire_date)
                        VALUES (NEW.name, NEW.department, NEW.salary, CURRENT_DATE);

                        INSERT INTO employee_log (operation, name, department, salary)
                        VALUES ('INSERT', NEW.name, NEW.department, NEW.salary);

                        RETURN NEW;
                    ELSIF TG_OP = 'UPDATE' THEN
                        UPDATE employees
                        SET name = NEW.name,
                            department = NEW.department,
                            salary = NEW.salary
                        WHERE id = NEW.id;

                        INSERT INTO employee_log (operation, name, department, salary)
                        VALUES ('UPDATE', NEW.name, NEW.department, NEW.salary);

                        RETURN NEW;
                    ELSIF TG_OP = 'DELETE' THEN
                        DELETE FROM employees WHERE id = OLD.id;

                        INSERT INTO employee_log (operation, name, department, salary)
                        VALUES ('DELETE', OLD.name, OLD.department, OLD.salary);

                        RETURN OLD;
                    END IF;
                    RETURN NULL;
                END;
                $$ LANGUAGE plpgsql
            """)

            // Create INSTEAD OF trigger
            _ = try await conn.simpleQuery("""
                CREATE TRIGGER employee_view_trigger
                INSTEAD OF INSERT OR UPDATE OR DELETE ON employee_view
                FOR EACH ROW EXECUTE FUNCTION employee_view_trigger()
            """)

            // Test insert through view
            _ = try await conn.query("""
                INSERT INTO employee_view (name, department, salary)
                VALUES ('Diana', 'Marketing', 70000)
            """)

            // Test update through view
            _ = try await conn.query("""
                UPDATE employee_view SET salary = salary * 1.1 WHERE name = 'Alice'
            """)

            // Test delete through view
            _ = try await conn.query("""
                DELETE FROM employee_view WHERE name = 'Bob'
            """)

            // Verify data in actual table
            let dataRows = try await conn.query("""
                SELECT id, name, department, salary FROM employees ORDER BY id
            """)

            var employees: [(Int32, String, String, Double)] = []
            for try await (id, name, dept, salary) in dataRows.decode((Int32, String, String, Double).self) {
                employees.append((id, name, dept, salary))
                print("Employee: ID=\(id), Name=\(name), Dept=\(dept), Salary=\(salary)")
            }

            // Verify audit log
            let logRows = try await conn.query("""
                SELECT operation, name, department, salary FROM employee_log ORDER BY timestamp
            """)

            var logs: [(String, String, String, Double)] = []
            for try await (operation, name, dept, salary) in logRows.decode((String, String, String, Double).self) {
                logs.append((operation, name, dept, salary))
                print("Log: \(operation), Name=\(name), Dept=\(dept), Salary=\(salary)")
            }

            // Clean up
            _ = try await conn.simpleQuery("DROP TRIGGER IF EXISTS employee_view_trigger")
            _ = try await conn.simpleQuery("DROP FUNCTION IF EXISTS employee_view_trigger()")
            _ = try await conn.simpleQuery("DROP VIEW IF EXISTS employee_view")
            _ = try await conn.simpleQuery("DROP TABLE IF EXISTS employee_log")
            _ = try await conn.simpleQuery("DROP TABLE IF EXISTS employees")

            return (employees.count, logs.count)
        }

        XCTAssertGreaterThan(result.0, 0, "Should have employees after operations")
        XCTAssertGreaterThan(result.1, 0, "Should have audit log entries")
        print("✓ Instead of triggers test passed")
    }

    // MARK: - Recursive Triggers

    func testRecursiveTriggers() async throws {
        print("=== Testing Recursive Triggers ===")

        let result = try await client.withConnection { conn in
            // Create category hierarchy table
            _ = try await conn.simpleQuery("""
                CREATE TEMPORABLE TABLE categories (
                    id SERIAL PRIMARY KEY,
                    name TEXT,
                    parent_id INTEGER,
                    path TEXT,
                    depth INTEGER DEFAULT 0
                )
            """)

            // Create function to update path and depth
            _ = try await conn.simpleQuery("""
                CREATE OR REPLACE FUNCTION update_category_path()
                RETURNS TRIGGER AS $$
                DECLARE
                    v_parent_id INTEGER;
                    v_parent_path TEXT;
                    v_parent_depth INTEGER;
                BEGIN
                    v_parent_id := NEW.parent_id;

                    -- Base case: top-level category
                    IF v_parent_id IS NULL THEN
                        NEW.path := '/' || NEW.name || '/';
                        NEW.depth := 0;
                    ELSE
                        -- Get parent information
                        SELECT path, depth INTO v_parent_path, v_parent_depth
                        FROM categories
                        WHERE id = v_parent_id;

                        IF v_parent_path IS NULL THEN
                            -- Parent doesn't exist, create isolated path
                            NEW.path := '/' || NEW.name || '/';
                            NEW.depth := 0;
                        ELSE
                            NEW.path := v_parent_path || NEW.name || '/';
                            NEW.depth := v_parent_depth + 1;
                        END IF;
                    END IF;

                    -- Update all children to reflect new path
                    IF TG_OP = 'UPDATE' AND OLD.parent_id IS DISTINCT FROM NEW.parent_id THEN
                        UPDATE categories
                        SET path = REPLACE(path, OLD.path, NEW.path),
                            depth = depth - OLD.depth + NEW.depth
                        WHERE path LIKE OLD.path || '%'
                          AND id != NEW.id;
                    END IF;

                    RETURN NEW;
                END;
                $$ LANGUAGE plpgsql
            """)

            // Create recursive trigger
            _ = try await conn.simpleQuery("""
                CREATE TRIGGER update_category_trigger
                BEFORE INSERT OR UPDATE ON categories
                FOR EACH ROW EXECUTE FUNCTION update_category_path()
            """)

            // Test recursive category creation
            _ = try await conn.query("""
                INSERT INTO categories (name, parent_id) VALUES ('Root', NULL)
            """)

            // Get root ID
            let rootIdResult = try await conn.query("""
                SELECT id FROM categories WHERE name = 'Root'
            """)
            var rootId = 0
            for try await (id) in rootIdResult.decode(Int32.self) {
                rootId = id
                break
            }

            // Insert child categories
            _ = try await conn.query("""
                INSERT INTO categories (name, parent_id) VALUES
                ('Technology', $1),
                ('Science', $1),
                ('Arts', $1)
            """, binds: [PGData(int32: rootId)])

            // Get Technology ID
            let techIdResult = try await conn.query("""
                SELECT id FROM categories WHERE name = 'Technology' AND parent_id = $1
            """, binds: [PGData(int32: rootId)])
            var techId = 0
            for try await (id) in techIdResult.decode(Int32.self) {
                techId = id
                break
            }

            // Insert sub-categories
            _ = try await conn.query("""
                INSERT INTO categories (name, parent_id) VALUES
                ('Programming', $1),
                ('Hardware', $1)
            """, binds: [PGData(int32: techId)])

            // Verify the hierarchical structure
            let resultRows = try await conn.query("""
                SELECT id, name, parent_id, path, depth FROM categories ORDER BY path
            """)

            var categories: [(Int32, String, Int32?, String, Int32)] = []
            for try await (id, name, parentId, path, depth) in resultRows.decode((Int32, String, Int32?, String, Int32).self) {
                categories.append((id, name, parentId, path, depth))
                print("Category: ID=\(id), Name=\(name), Parent=\(parentId ?? 0), Path=\(path), Depth=\(depth)")
            }

            // Clean up
            _ = try await conn.simpleQuery("DROP TRIGGER IF EXISTS update_category_trigger")
            _ = try await conn.simpleQuery("DROP FUNCTION IF EXISTS update_category_path()")
            _ = try await conn.simpleQuery("DROP TABLE IF EXISTS categories")

            return categories.count
        }

        XCTAssertGreaterThan(result, 5, "Should have multiple categories in hierarchy")
        print("✓ Recursive triggers test passed")
    }
}