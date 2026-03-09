import XCTest
import Logging
@testable import PostgresKit

final class ViewTests: XCTestCase {

    private var client: PostgresDatabaseClient!
    private var testLogger: Logger!

    override func setUp() async throws {
        TestEnv.loadDotEnv()
        try await super.setUp()
        testLogger = Logger(label: "view-tests")

        let config = PostgresConfiguration(
            host: TestEnv.host,
            port: TestEnv.port,
            database: TestEnv.database,
            username: TestEnv.username,
            password: TestEnv.password,
            useTLS: TestEnv.useTLS,
            applicationName: "ViewTests"
        )

        client = try await PostgresDatabaseClient.connect(configuration: config, logger: testLogger)
    }

    override func tearDown() {
        client?.close()
        super.tearDown()
    }

    // MARK: - Basic View Tests

    func testBasicViews() async throws {
        print("=== Testing Basic Views ===")

        let result = try await client.withConnection { conn in
            // Create base tables
            _ = try await conn.simpleQuery("""
                CREATE TEMPORARY TABLE employees (
                    id SERIAL PRIMARY KEY,
                    name TEXT NOT NULL,
                    department_id INTEGER,
                    salary NUMERIC,
                    hire_date DATE NOT NULL,
                    is_active BOOLEAN DEFAULT true
                )
            """)

            _ = try await conn.simpleQuery("""
                CREATE TEMPORARY TABLE departments (
                    id SERIAL PRIMARY KEY,
                    name TEXT NOT NULL,
                    manager_id INTEGER,
                    budget NUMERIC
                )
            """)

            // Insert test data
            _ = try await conn.simpleQuery("""
                INSERT INTO departments (name, manager_id, budget) VALUES
                ('Engineering', 1, 500000),
                ('Sales', 2, 300000),
                ('Marketing', 3, 200000),
                ('HR', 4, 150000)
            """)

            _ = try await conn.simpleQuery("""
                INSERT INTO employees (name, department_id, salary, hire_date, is_active) VALUES
                ('Alice Johnson', 1, 80000, '2020-01-15', true),
                ('Bob Smith', 1, 75000, '2020-02-20', true),
                ('Charlie Brown', 2, 65000, '2019-11-10', true),
                ('Diana Prince', 2, 70000, '2020-03-05', true),
                ('Eve Wilson', 3, 60000, '2020-04-12', true),
                ('Frank Davis', 3, 55000, '2019-12-01', false),
                ('Grace Lee', 4, 50000, '2020-02-14', true)
            """)

            // Create simple views
            _ = try await conn.simpleQuery("""
                CREATE VIEW employee_summary AS
                SELECT
                    e.id,
                    e.name,
                    d.name as department_name,
                    e.salary,
                    e.hire_date,
                    e.is_active
                FROM employees e
                JOIN departments d ON e.department_id = d.id
            """)

            _ = try await conn.simpleQuery("""
                CREATE VIEW department_summary AS
                SELECT
                    d.id,
                    d.name as department_name,
                    d.budget,
                    COUNT(e.id) as employee_count,
                    COALESCE(AVG(e.salary), 0) as avg_salary,
                    COALESCE(SUM(e.salary), 0) as total_salary
                FROM departments d
                LEFT JOIN employees e ON d.id = e.department_id
                WHERE e.is_active = true OR e.is_active IS NULL
                GROUP BY d.id, d.name, d.budget
            """)

            // Create filtered view
            _ = try await conn.simpleQuery("""
                CREATE VIEW high_paid_employees AS
                SELECT
                    e.id,
                    e.name,
                    e.salary,
                    d.name as department_name
                FROM employees e
                JOIN departments d ON e.department_id = d.id
                WHERE e.salary > 70000 AND e.is_active = true
                ORDER BY e.salary DESC
            """)

            // Test view functionality
            let summaryRows = try await conn.query("""
                SELECT * FROM employee_summary WHERE department_name = 'Engineering' ORDER BY name
            """)

            var engineeringEmployees: [(Int32, String, String, Double, String, Bool)] = []
            for try await (id, name, dept, salary, hireDate, active) in summaryRows.decode((Int32, String, String, Double, String, Bool).self) {
                engineeringEmployees.append((id, name, dept, salary, hireDate, active))
                print("Engineering Employee: ID=\(id), Name=\(name), Dept=\(dept), Salary=\(salary), Hire=\(hireDate), Active=\(active)")
            }

            let deptSummaryRows = try await conn.query("""
                SELECT * FROM department_summary ORDER BY total_salary DESC
            """)

            var deptSummaries: [(Int32, String, Double, Int32, Double, Double)] = []
            for try await (id, name, budget, count, avgSalary, totalSalary) in deptSummaryRows.decode((Int32, String, Double, Int32, Double, Double).self) {
                deptSummaries.append((id, name, budget, count, avgSalary, totalSalary))
                print("Department: ID=\(id), Name=\(name), Budget=\(budget), Employees=\(count), Avg Salary=\(avgSalary), Total=\(totalSalary)")
            }

            let highPaidRows = try await conn.query("""
                SELECT COUNT(*) as high_paid_count FROM high_paid_employees
            """)

            var highPaidCount = 0
            for try await (count) in highPaidRows.decode(Int32.self) {
                highPaidCount = count
                break
            }

            // Clean up
            _ = try await conn.simpleQuery("DROP VIEW IF EXISTS high_paid_employees")
            _ = try await conn.simpleQuery("DROP VIEW IF EXISTS department_summary")
            _ = try await conn.simpleQuery("DROP VIEW IF EXISTS employee_summary")
            _ = try await conn.simpleQuery("DROP TABLE IF EXISTS employees")
            _ = try await conn.simpleQuery("DROP TABLE IF EXISTS departments")

            return (engineeringEmployees.count, deptSummaries.count, highPaidCount)
        }

        XCTAssertEqual(result.0, 2, "Should have 2 engineering employees")
        XCTAssertEqual(result.1, 4, "Should have 4 department summaries")
        XCTAssertEqual(result.2, 3, "Should have 3 high-paid employees")
        print("✓ Basic views test passed")
    }

    // MARK: - Materialized View Tests

    func testMaterializedViews() async throws {
        print("=== Testing Materialized Views ===")

        let result = try await conn.withConnection { conn in
            // Enable required extension
            do {
                _ = try await conn.simpleQuery("CREATE EXTENSION IF NOT EXISTS pg_stat_statements")
            } catch {
                print("Note: pg_stat_statements extension might not be available or already installed")
            }

            // Create base tables
            _ = try await conn.simpleQuery("""
                CREATE TEMPORARY TABLE sales_data (
                    id SERIAL PRIMARY KEY,
                    product_id INTEGER,
                    product_name TEXT,
                    category TEXT,
                    quantity INTEGER,
                    unit_price NUMERIC,
                    sale_date DATE,
                    region TEXT
                )
            """)

            _ = try await conn.simpleQuery("""
                CREATE TEMPORARY TABLE product_categories (
                    id SERIAL PRIMARY KEY,
                    name TEXT NOT NULL,
                    parent_id INTEGER
                )
            """)

            // Insert test data
            _ = try await conn.simpleQuery("""
                INSERT INTO product_categories (name, parent_id) VALUES
                ('Electronics', NULL),
                ('Computers', 1),
                ('Phones', 1),
                ('Clothing', NULL),
                ('Men', 4),
                ('Women', 4),
                ('Home', NULL)
            """)

            _ = try await conn.simpleQuery("""
                INSERT INTO sales_data (product_id, product_name, category, quantity, unit_price, sale_date, region) VALUES
                (101, 'Laptop Pro', 'Computers', 10, 1200.00, '2024-01-15', 'North'),
                (102, 'iPhone 15', 'Phones', 25, 999.00, '2024-01-16', 'South'),
                (103, 'T-Shirt', 'Clothing', 50, 25.00, '2024-01-17', 'East'),
                (104, 'Dress', 'Clothing', 30, 75.00, '2024-01-18', 'West'),
                (105, 'Coffee Maker', 'Home', 15, 89.99, '2024-01-19', 'North'),
                (106, 'Desk Lamp', 'Home', 20, 45.00, '2024-01-20', 'South')
            """)

            // Create materialized view
            _ = try await conn.simpleQuery("""
                CREATE MATERIALIZED VIEW sales_summary AS
                SELECT
                    sd.region,
                    pc.name as category_name,
                    COUNT(*) as transaction_count,
                    SUM(sd.quantity) as total_quantity,
                    SUM(sd.quantity * sd.unit_price) as total_revenue,
                    AVG(sd.unit_price) as avg_unit_price,
                    MIN(sd.unit_price) as min_unit_price,
                    MAX(sd.unit_price) as max_unit_price
                FROM sales_data sd
                JOIN product_categories pc ON sd.category = pc.name
                GROUP BY sd.region, pc.name
                ORDER BY total_revenue DESC
            """)

            // Create another materialized view for product performance
            _ = try await conn.simpleQuery("""
                CREATE MATERIALIZED VIEW product_performance AS
                SELECT
                    sd.product_id,
                    sd.product_name,
                    pc.name as category_name,
                    SUM(sd.quantity) as total_sold,
                    SUM(sd.quantity * sd.unit_price) as total_revenue,
                    COUNT(*) as sale_count,
                    AVG(sd.unit_price) as avg_price,
                    MIN(sd.sale_date) as first_sale,
                    MAX(sd.sale_date) as last_sale
                FROM sales_data sd
                JOIN product_categories pc ON sd.category = pc.name
                GROUP BY sd.product_id, sd.product_name, pc.name
                ORDER BY total_revenue DESC
            """)

            // Test materialized view queries
            let summaryRows = try await conn.query("""
                SELECT * FROM sales_summary WHERE region = 'North'
            """)

            var northSummaries: [(String, String, Int32, Int64, Double, Double, Double, Double)] = []
            for try await (region, category, txCount, quantity, revenue, avgPrice, minPrice, maxPrice) in summaryRows.decode((String, String, Int32, Int64, Double, Double, Double, Double).self) {
                northSummaries.append((region, category, txCount, quantity, revenue, avgPrice, minPrice, maxPrice))
                print("North Region - Category: \(category), Transactions: \(txCount), Quantity: \(quantity), Revenue: \(revenue)")
            }

            let performanceRows = try await conn.query("""
                SELECT * FROM product_performance WHERE category_name = 'Electronics' ORDER BY total_revenue DESC
            """)

            var performance: [(Int32, String, String, Int64, Double, Int32, Double, String, String)] = []
            for try await (productId, productName, category, totalSold, totalRevenue, saleCount, avgPrice, firstSale, lastSale) in performanceRows.decode((Int32, String, String, Int64, Double, Int32, Double, String, String).self) {
                performance.append((productId, productName, category, totalSold, totalRevenue, saleCount, avgPrice, firstSale, lastSale))
                print("Product: ID=\(productId), Name=\(productName), Category=\(category), Sold: \(totalSold), Revenue=\(totalRevenue)")
            }

            // Test materialized view maintenance
            let beforeRefresh = try await conn.query("""
                SELECT COUNT(*)::text as row_count FROM sales_summary
            """)

            var beforeCount = 0
            for try await (countStr) in beforeRefresh.decode(String.self) {
                if let intVal = Int(countStr) {
                    beforeCount = intVal
                }
                break
            }

            // Simulate data changes
            _ = try await conn.query("""
                INSERT INTO sales_data (product_id, product_name, category, quantity, unit_price, sale_date, region) VALUES
                (107, 'Tablet', 'Electronics', 5, 300.00, '2024-01-21', 'East')
            """)

            // Test REFRESH
            _ = try await conn.simpleQuery("REFRESH MATERIALIZED VIEW sales_summary")

            let afterRefresh = try await conn.query("""
                SELECT COUNT(*)::text as row_count FROM sales_summary
            """)

            var afterCount = 0
            for try await (countStr) in afterRefresh.decode(String.self) {
                if let intVal = Int(countStr) {
                    afterCount = intVal
                }
                break
            }

            // Get materialized view stats
            let statsRows = try await conn.query("""
                SELECT
                    schemaname,
                    viewname,
                    nspname,
                    size
                FROM pg_matviews
                WHERE viewname LIKE '%summary%'
            """)

            var stats: [(String, String, String, Int64)] = []
            for try await (schema, view, nspname, size) in statsRows.decode((String, String, String, Int64).self) {
                stats.append((schema, view, nspname, size))
                print("Materialized View: \(schema).\(view), Namespace: \(nspname), Size: \(size) bytes")
            }

            // Clean up
            _ = try await conn.simpleQuery("DROP MATERIALIZED VIEW IF EXISTS product_performance")
            _ = try await conn.simpleQuery("DROP MATERIALIZED VIEW IF EXISTS sales_summary")
            _ = try await conn.simpleQuery("DROP TABLE IF EXISTS sales_data")
            _ = try await conn.simpleQuery("DROP TABLE IF EXISTS product_categories")

            return (northSummaries.count, performance.count, beforeCount, afterCount, stats.count)
        }

        XCTAssertGreaterThan(result.0, 0, "Should have North region summaries")
        XCTAssertGreaterThan(result.1, 0, "Should have Electronics performance data")
        XCTAssertTrue(result.3 < result.4, "Should have more rows after refresh")
        XCTAssertGreaterThan(result.5, 0, "Should have materialized view stats")
        print("✓ Materialized views test passed")
    }

    // MARK: - Recursive Views

    func testRecursiveViews() async throws {
        print("=== Testing Recursive Views ===")

        let result = try await client.withConnection { conn in {
            // Enable recursive views if needed (PostgreSQL 9.3+)
            do {
                _ = try await conn.simpleQuery("SET LOCAL search_path = public, pg_catalog")
                _ = try await conn.simpleQuery("CREATE EXTENSION IF NOT EXISTS tablefunc")
            } catch {
                print("Note: tablefunc extension might not be available")
            }

            // Create category hierarchy table
            _ = try await conn.simpleQuery("""
                CREATE TEMPORARY TABLE categories (
                    id SERIAL PRIMARY KEY,
                    name TEXT NOT NULL,
                    parent_id INTEGER,
                    lft INTEGER,
                    rgt INTEGER,
                    depth INTEGER DEFAULT 0
                )
            """)

            // Insert hierarchical data
            _ = try await conn.simpleQuery("""
                INSERT INTO categories (name, parent_id) VALUES
                ('Root', NULL)
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

            // Insert categories (hierarchical structure)
            _ = try await conn.query("""
                INSERT INTO categories (name, parent_id) VALUES
                ('Technology', $1),
                ('Science', $1),
                ('Arts', $1)
            """, binds: [PGData(int32: rootId)])

            let techIdResult = try await conn.query("""
                SELECT id FROM categories WHERE name = 'Technology' AND parent_id = $1
            """, binds: [PGData(int32: rootId)])
            var techId = 0
            for try await (id) in techIdResult.decode(Int32.self) {
                techId = id
                break
            }

            _ = try await conn.query("""
                INSERT INTO categories (name, parent_id) VALUES
                ('Programming', $1),
                ('Databases', $1),
                ('Web Development', $1)
            """, binds: [PGData(int32: techId)])

            let scienceIdResult = try await conn.query("""
                SELECT id FROM categories WHERE name = 'Science' AND parent_id = $1
            """, binds: [PGInt32: rootId)])
            var scienceId = 0
            for try await (id) in scienceIdResult.decode(Int32.self) {
                scienceId = id
                break
            }

            _ = try await conn.query("""
                INSERT INTO categories (name, parent_id) VALUES
                ('Physics', $1),
                ('Chemistry', $1),
                ('Biology', $1)
            """, binds: [PGData(int32: scienceId)])

            // Update lft/rgt values for nested set model
            _ = try await conn.simpleQuery("""
                WITH RECURSIVE category_tree AS (
                    SELECT id, 1, 2 FROM categories WHERE parent_id IS NULL AND name = 'Root'
                    UNION ALL
                    SELECT c.id, ct.lft + 1, ct.rgt + 1
                    FROM categories c
                    JOIN category_tree ct ON c.parent_id = ct.id
                    WHERE ct.lft < ct.rgt - 1
                )
                UPDATE categories c
                SET lft = ct.lft, rgt = ct.rgt
                FROM category_tree ct
                WHERE c.id = ct.id
            """)

            // Create recursive view for category hierarchy
            _ = try await conn.simpleQuery("""
                CREATE OR REPLACE VIEW category_hierarchy AS
                WITH RECURSIVE category_tree AS (
                    -- Base case: root categories
                    SELECT
                        id,
                        name,
                        parent_id,
                        0 as level,
                        ARRAY[name] as path
                    FROM categories
                    WHERE parent_id IS NULL

                    UNION ALL

                    -- Recursive case: child categories
                    SELECT
                        c.id,
                        c.name,
                        c.parent_id,
                        ct.level + 1,
                        ct.path || c.name
                    FROM categories c
                    JOIN category_tree ct ON c.parent_id = ct.id
                )
                SELECT
                    id,
                    name,
                    parent_id,
                    level,
                    array_to_string(path, ' -> ') as category_path
                FROM category_tree
                ORDER BY path, name
            """)

            // Test recursive view
            let hierarchyRows = try await conn.query("""
                SELECT * FROM category_hierarchy WHERE level <= 2 ORDER BY path
            """)

            var hierarchy: [(Int32, String, Int32?, Int32, String)] = []
            for try await (id, name, parentId, level, path) in hierarchyRows.decode((Int32, String, Int32?, Int32, String).self) {
                hierarchy.append((id, name, parentId, level, path))
                print("Category: ID=\(id), Name=\(name), Parent=\(parentId ?? 0), Level=\(level), Path=\(path)")
            }

            // Create view showing category depth
            _ = try await conn.simpleQuery("""
                CREATE OR REPLACE VIEW category_depth_stats AS
                SELECT
                    id,
                    name,
                    depth,
                    (rgt - lft - 1) as number_of_children
                FROM categories
                ORDER BY depth, name
            """)

            let depthRows = try await conn.query("""
                SELECT COUNT(*) as categories_by_depth FROM (
                    SELECT depth, COUNT(*) FROM categories GROUP BY depth
                ) depth_stats
            """)

            var depthStats: [Int32] = []
            for try await (count) in depthRows.decode(Int32.self) {
                depthStats.append(count)
                print("Depth statistics: \(depthStats) depth levels")
            }

            // Clean up
            _ = try await conn.simpleQuery("DROP VIEW IF EXISTS category_depth_stats")
            _ = try await conn.simpleQuery("DROP VIEW IF EXISTS category_hierarchy")
            _ = try await conn.simpleQuery("DROP TABLE IF EXISTS categories")

            return (hierarchy.count, depthStats.count)
        }

        XCTAssertGreaterThan(result.0, 0, "Should have category hierarchy data")
        XCTAssertGreaterThan(result.1, 0, "Should have depth statistics")
        print("✓ Recursive views test passed")
    }

    // WITH RECURSIVE category_tree AS (
    -- Base case: root categories
    -- Recursive case: child categories

    // MARK: - Performance Optimization Views

    func testPerformanceOptimizedViews() async throws {
        print("=== Testing Performance Optimized Views ===")

        let result = try await client.withConnection { conn in
            // Create a large dataset for performance testing
            _ = try await conn.simpleQuery("""
                CREATE TEMPORARY TABLE large_dataset (
                    id SERIAL PRIMARY KEY,
                    category TEXT,
                    value1 INTEGER,
                    value2 NUMERIC,
                    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    status TEXT DEFAULT 'active'
                )
            """)

            // Generate test data
            for i in 1...1000 {
                let category = ["A", "B", "C", "D", "E"][i % 5]
                _ = try await conn.query("""
                    INSERT INTO large_dataset (category, value1, value2, status)
                    VALUES ($1, $2, $3, $4)
                """, binds: [
                    PGData(string: category),
                    PGData(int32: Int32(i)),
                    PGData(double: Double(Double(i) * 1.5)),
                    PGData(string: i % 3 == 0 ? "active" : "inactive")
                ])
            }

            // Create indexed view for performance
            _ = try await conn.simpleQuery("""
                CREATE OR REPLACE VIEW filtered_dataset AS
                SELECT id, category, value1, value2, timestamp, status
                FROM large_dataset
                WHERE status = 'active'
                  AND value1 > 500
            """)

            // Create aggregate view
            _ = try await conn.simpleQuery("""
                CREATE OR REPLACE VIEW aggregate_dataset AS
                SELECT
                    category,
                    COUNT(*) as row_count,
                    SUM(value1) as sum_value1,
                    AVG(value2) as avg_value2,
                    MIN(value1) as min_value1,
                    MAX(value1) as max_value1,
                    MIN(timestamp) as earliest_timestamp,
                    MAX(timestamp) as latest_timestamp
                FROM large_dataset
                WHERE status = 'active'
                GROUP BY category
            """)

            // Test view performance with different queries
            let filteredRows = try await conn.query("""
                EXPLAIN (FORMAT JSON) SELECT * FROM filtered_dataset WHERE category = 'A' LIMIT 100
            """)

            var explainPlans: [String] = []
            for try await (plan) in filteredRows.decode(String.self) {
                explainPlans.append(plan)
            }

            let aggregateRows = try await conn.query("""
                SELECT * FROM aggregate_dataset WHERE category = 'A'
            """)

            var aggregates: [(String, Int32, Int64, Double, Int32, Int32, String, String)] = []
            for try await (category, rowCount, sumVal, avgVal, minVal, maxVal, earliest, latest) in aggregateRows.decode((String, Int32, Int64, Double, Int32, Int32, String, String).self) {
                aggregates.append((category, rowCount, sumVal, avgVal, minVal, maxVal, earliest, latest))
                print("Aggregate: Category=\(category), Count=\(rowCount), Sum=\(sumVal), Avg=\(avgVal), Min=\(minVal), Max=\(maxVal)")
            }

            // Test view update
            let beforeUpdate = try await conn.query("""
                SELECT COUNT(*)::text FROM aggregate_dataset
            """)

            var beforeCount = 0
            for try await (countStr) in beforeUpdate.decode(String.self) {
                if let intVal = Int(countStr) {
                    beforeCount = intVal
                }
                break
            }

            // Update base table
            _ = try await conn.query("""
                UPDATE large_dataset SET status = 'inactive' WHERE value1 < 100
            """)

            // Test if view reflects changes (materialized vs regular view difference)
            let afterUpdate = try await conn.query("""
                SELECT COUNT(*)::text as new_count FROM aggregate_dataset WHERE status = 'active'
            """)

            var afterCount = 0
            for try await (countStr) in afterUpdate.decode(String.self) {
                if let intVal = Int(countStr) {
                    afterCount = intVal
                }
                break
            }

            // Create index on base table to improve view performance
            _ = try await conn.simpleQuery("CREATE INDEX idx_dataset_category_status ON large_dataset(category, status)")
            _ = try await conn.simpleQuery("CREATE INDEX idx_dataset_value1 ON large_dataset(value1)")

            // Test query performance with index
            let indexedRows = try await conn.query("""
                EXPLAIN (FORMAT JSON) SELECT COUNT(*) FROM filtered_dataset WHERE category = 'A' AND value1 > 1000
            """)

            var indexedPlans: [String] = []
            for try await (plan) in indexedRows.decode(String.self) {
                indexedPlans.append(plan)
            }

            // Clean up
            _ = try await conn.simpleQuery("DROP VIEW IF EXISTS aggregate_dataset")
            _ = try await conn.simpleQuery("DROP VIEW IF EXISTS filtered_dataset")
            _ = try await conn.simpleQuery("DROP TABLE IF EXISTS large_dataset")

            return (explainPlans.count, aggregates.count, beforeCount, afterCount, indexedPlans.count)
        }

        XCTAssertEqual(result.0, 1, "Should have one explain plan for filtered view")
        XCTAssertEqual(result.1, 1, "Should have one aggregate result")
        XCTAssertGreaterThan(result.3, result.4, "Count should decrease after updates")
        XCTAssertEqual(result.5, 1, "Should have one explain plan for indexed query")
        print("✓ Performance optimized views test passed")
    }
}