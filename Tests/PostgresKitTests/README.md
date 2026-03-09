# PostgresKit Comprehensive Test Suite

This directory contains comprehensive tests for the PostgreSQL wire protocol client, covering all aspects of the library's functionality including connection management, data types, transactions, streaming, metadata operations, and error handling.

## Test Organization

### Core Test Files

1. **PostgresClientComprehensiveTests.swift**
   - Core client functionality tests
   - All PostgreSQL data types support
   - Query execution and parameter binding
   - Basic transaction operations
   - Notification handling
   - Large dataset handling

2. **ConnectionManagementTests.swift**
   - Connection lifecycle management
   - Pool configuration and reuse
   - TLS/SSL connectivity
   - Error handling and recovery
   - Concurrent connection usage
   - Connection resilience testing

3. **TransactionConcurrencyTests.swift**
   - Transaction isolation levels
   - Savepoint operations
   - Concurrent transaction handling
   - Deadlock scenarios
   - Performance under load
   - Transaction edge cases

4. **StreamingAPITests.swift**
   - Real-time data streaming
   - Cursor-based streaming
   - Configuration options
   - Memory management
   - Formatting strategies
   - Performance optimization

5. **MetadataAPITests.swift**
   - Schema introspection
   - Table and view metadata
   - Constraint and index information
   - Comment retrieval
   - Role and extension listing
   - Performance considerations

6. **TestSuiteRunner.swift**
   - Test orchestration and reporting
   - Configuration validation
   - Environment setup
   - Result aggregation
   - Report generation

## Test Coverage

### Functional Areas

- **✅ Connection Management**
  - Basic connectivity
  - Connection pooling
  - TLS/SSL support
  - Error handling
  - Connection recovery
  - Multiple concurrent connections

- **✅ Data Types**
  - All PostgreSQL native types
  - NULL value handling
  - Binary data (BYTEA)
  - Large objects
  - Arrays and composite types
  - JSON/JSONB
  - UUIDs
  - Temporal types
  - Network types

- **✅ Query Execution**
  - Simple queries
  - Parameterized queries
  - Prepared statements
  - Batch operations
  - Statement caching
  - Multiple result sets

- **✅ Transactions**
  - Basic transaction control
  - Savepoints
  - Isolation levels
  - Concurrent transactions
  - Deadlock detection
  - Performance optimization

- **✅ Streaming API**
  - Real-time result streaming
  - Cursor-based operations
  - Memory management
  - Configuration options
  - Formatting strategies
  - Performance tuning

- **✅ Metadata Operations**
  - Schema introspection
  - Table and view metadata
  - Constraint information
  - Index details
  - Comment retrieval
  - Role and extension data

### Testing Scenarios

- **✅ Happy Path Testing**
  - Normal operation scenarios
  - Expected behavior verification
  - Performance benchmarks

- **✅ Error Handling**
  - Invalid credentials
  - Connection failures
  - Query errors
  - Constraint violations
  - Network issues

- **✅ Edge Cases**
  - Empty result sets
  - NULL values
  - Special characters
  - Large data volumes
  - Timeout scenarios

- **✅ Concurrency Testing**
  - Multiple simultaneous connections
  - Concurrent query execution
  - Parallel transactions
  - Thread safety
  - Resource contention

- **✅ Performance Testing**
  - Large dataset handling
  - Memory usage optimization
  - Query execution speed
  - Streaming efficiency
  - Connection pool performance

## Environment Configuration

### Required Environment Variables

```bash
# Basic connection configuration
export PGKIT_HOST=localhost
export PGKIT_PORT=5432
export PGKIT_DATABASE=postgres
export PGKIT_USERNAME=postgres
export PGKIT_PASSWORD=your_password

# Optional configuration
export PGKIT_TLS=false
export PGKIT_APPLICATION_NAME=PostgresKitTests
```

### Optional Test Configuration

```bash
# Test execution options
export PGKIT_TEST_TIMEOUT=300
export PGKIT_ENABLE_PERF_TESTS=true
export PGKIT_ENABLE_STRESS_TESTS=false
export PGKIT_PARALLEL_TESTS=true

# Logging configuration
export LOG_LEVEL=INFO
```

## Running Tests

### Prerequisites

1. PostgreSQL server running and accessible
2. Test database with appropriate permissions
3. Swift testing environment set up
4. Required environment variables configured

### Running Individual Test Files

```bash
# Run all comprehensive tests
swift test --filter PostgresClientComprehensiveTests

# Run specific test categories
swift test --filter ConnectionManagementTests
swift test --filter TransactionConcurrencyTests
swift test --filter StreamingAPITests
swift test --filter MetadataAPITests
```

### Running Test Suite with Runner

```swift
import XCTest
@testable import PostgresKit

// Example of using the test suite runner
let runner = TestSuiteRunner()

// Validate configuration
let validation = runner.validateConfiguration()
if !validation.isValid {
    print("Configuration issues: \(validation.issues)")
}
if validation.hasWarnings {
    print("Configuration warnings: \(validation.warnings)")
}

// Setup environment and run tests
try await runner.setupTestEnvironment()
let report = try await runner.runAllTests()
await runner.cleanupTestEnvironment()

// Generate reports
print(report.generateReport())
print(report.exportToJSON())
```

### Test Categories by Priority

#### Priority 1: Core Functionality
- Basic connectivity
- Simple query execution
- Data type support
- Error handling

#### Priority 2: Advanced Features
- Transaction management
- Streaming API
- Connection pooling
- Metadata operations

#### Priority 3: Performance and Stress
- Large dataset handling
- Concurrency testing
- Memory management
- Performance optimization

## Test Data Management

### Temporary Objects
Tests create and use temporary database objects:
- Temporary tables: `TEMPORARY TABLE test_*`
- Temporary schemas: `CREATE SCHEMA IF NOT EXISTS metadata_test_schema`
- Test data: Automatically cleaned up after each test

### Cleanup Strategy
- Use temporary tables where possible (automatically cleaned up at session end)
- Explicit cleanup in tearDown methods
- Transaction rollback for test isolation
- Connection pooling with proper resource cleanup

## Performance Benchmarks

### Metrics Tracked
- Query execution time
- Connection establishment time
- Memory usage patterns
- Streaming throughput
- Transaction throughput

### Benchmark Tests
- Large dataset streaming (10,000+ rows)
- High concurrency (20+ connections)
- Batch insert performance
- Memory management efficiency

## Continuous Integration

### CI Configuration
```yaml
# Example GitHub Actions workflow
name: PostgresKit Tests
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: test_db
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
    - uses: actions/checkout@v3
    - name: Setup Swift
      uses: swift-actions/setup-swift@v1
    - name: Run Tests
      env:
        PGKIT_HOST: localhost
        PGKIT_PORT: 5432
        PGKIT_DATABASE: test_db
        PGKIT_USERNAME: postgres
        PGKIT_PASSWORD: postgres
      run: swift test --filter PostgresKitTests
```

### Test Requirements
- PostgreSQL 12+ for full feature support
- Swift 5.7+ for async/await support
- Sufficient resources for stress testing (4GB+ RAM recommended)

## Debugging and Troubleshooting

### Common Issues

1. **Connection Failures**
   - Verify PostgreSQL is running
   - Check network connectivity
   - Validate credentials
   - Confirm database exists

2. **Permission Errors**
   - Ensure user has CREATE TEMPORARY TABLE permission
   - Check schema access rights
   - Verify connection limits

3. **Test Timeouts**
   - Increase `PGKIT_TEST_TIMEOUT`
   - Check server performance
   - Reduce concurrent test count

4. **Memory Issues**
   - Monitor memory usage during large dataset tests
   - Adjust streaming configuration
   - Consider reducing dataset size

### Debug Logging

Enable detailed logging:
```swift
let logger = Logger(label: "test-debug")
logger.logLevel = .trace
```

### Test Isolation

Each test should:
- Use unique table names where possible
- Clean up created objects
- Use transactions for data isolation
- Avoid side effects on other tests

## Contributing

### Adding New Tests

1. Follow naming conventions: `test<Feature><Scenario>`
2. Use appropriate test category
3. Include setup and cleanup
4. Document expected behavior
5. Handle errors appropriately

### Test Coverage Requirements

- New features must have comprehensive tests
- Edge cases should be covered
- Error conditions must be tested
- Performance impact should be measured

### Code Review Checklist

- [ ] Test names are descriptive
- [ ] Proper error handling
- [ ] Resource cleanup
- [ ] Documentation added
- [ ] Performance considerations
- [ ] Thread safety verified

## Reports and Analytics

### Test Report Formats
- Console output
- JSON export
- HTML dashboard (future)
- Performance metrics (future)

### Key Metrics
- Pass rate by category
- Execution time trends
- Memory usage patterns
- Error frequency analysis

This comprehensive test suite ensures the PostgreSQL wire protocol client maintains high quality, reliability, and performance across all supported use cases and scenarios.