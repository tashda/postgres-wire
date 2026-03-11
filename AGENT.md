# PostgresWire & PostgresKit — Agent Guide

## Project Identity

A Swift 6.2 library providing a layered PostgreSQL client built on top of Vapor's `PostgresNIO` and `SwiftNIO`. Two library targets: **PostgresWire** (low-level wire protocol with streaming) and **PostgresKit** (high-level ergonomic API with DDL/DML/introspection/security).

## Architecture

```
┌─────────────────────────────────────────────┐
│  Consumer Application                       │
├─────────────────────────────────────────────┤
│  PostgresKit (high-level)                   │
│  ├── Connection/   — Client, pool, cache    │
│  ├── Execution/    — Query, DML, COPY, tx   │
│  ├── Introspection/— Schema discovery       │
│  ├── Schema/       — DDL operations         │
│  ├── Security/     — Roles, privileges      │
│  ├── Maintenance/  — VACUUM, ANALYZE        │
│  └── Types/        — Errors, encodable, etc │
├─────────────────────────────────────────────┤
│  PostgresWire (low-level)                   │
│  ├── Core/         — WireClient, WireTypes  │
│  └── Streaming/    — DataStream, Formatter  │
├─────────────────────────────────────────────┤
│  PostgresNIO (Vapor) — wire protocol        │
│  SwiftNIO           — async I/O             │
└─────────────────────────────────────────────┘
```

### Layer Boundaries
- **PostgresWire** wraps `PostgresNIO` and exposes: connections, raw queries, streaming with formatting/progress, cursor-based pagination. It re-exports `PostgresNIO`.
- **PostgresKit** wraps `PostgresWire` and adds: statement caching (LRU), DDL builders, DML helpers, introspection, role management, notifications, bulk copy, error enrichment. It re-exports `PostgresWire` (and thus `PostgresNIO`).
- Consumer code should only import `PostgresKit` unless low-level streaming control is needed.

### Key Types
| Type | Role |
|------|------|
| `PostgresDatabaseClient` | Primary entry point. Owns wire client + prepared statement registry. |
| `PostgresDatabaseConnection` | Per-connection wrapper with caching. Obtained via `withConnection`. |
| `PostgresWireClient` | Low-level connection pool + query execution. |
| `PostgresDataStream` | Actor managing streaming rows with formatting/progress. |
| `PostgresFormatterEngine` | Actor formatting raw bytes into display strings by OID. |
| `PostgresError` | Rich error type with SQL state, constraint detection, debugging. |

## Conventions

### Swift
- **Swift 6.2**, strict concurrency. All public types are `Sendable`.
- Actors for mutable shared state (`PreparedRegistry`, `PreparedServerCache`, `PostgresDataStream`, `PostgresFormatterEngine`).
- `async/await` everywhere — no completion handlers.
- Minimum deployment: **macOS 13**.
- `@_exported import` for transitive dependencies in `Exports.swift`.

### File Organization
- One logical concern per file. Max ~500 lines (enforced by refactoring).
- Subdirectories group by domain: `Connection/`, `Execution/`, `Introspection/`, `Schema/`, `Security/`, `Maintenance/`, `Types/`, `Core/`, `Streaming/`.
- Naming: PascalCase types, files named after primary type they contain.
- Extensions on `PostgresDatabaseClient` or `PostgresDatabaseConnection` are grouped by domain file (e.g., `TableOperations.swift` extends the connection with table DDL methods).

### Error Handling
- `PostgresError` wraps `PSQLError` from PostgresNIO with user-friendly messages.
- `executeWithEnhancedError` static method wraps any throwing closure.
- Constraint violation helpers: `isUniqueViolation`, `isForeignKeyViolation`, `isConstraintViolation`.
- `PostgresErrorDebugInfo` provides detailed debugging context.

### Logging & Metrics
- `apple/swift-log` — all client instances carry a Logger.
- `apple/swift-metrics` — available in PostgresKit for performance tracking.

## Building & Testing

### Prerequisites
- Swift 6.2+
- Docker Desktop (for integration tests)

### Commands
```bash
swift build                           # Build both targets
swift test --filter PostgresWireTests # Unit tests only (no DB needed)
swift test --filter PostgresKitTests  # Integration tests (needs DB)
./test-all-postgres-versions.sh       # Test against PG 14-18 + latest
```

### Docker Integration Testing
Set `USE_DOCKER=1` to auto-manage a Docker PostgreSQL container:
1. `PostgresDockerManager` starts a container with the specified `POSTGRES_VERSION`.
2. Loads `Tests/PostgresKitTests/Support/SampleData.sql` into the database.
3. Overrides `POSTGRES_*` env vars to point at the container.
4. Container auto-stops via `atexit`.

### Environment Variables
| Variable | Default | Notes |
|----------|---------|-------|
| `POSTGRES_HOST` | `127.0.0.1` | |
| `POSTGRES_PORT` | `5432` (or `54321` for Docker) | |
| `POSTGRES_USERNAME` | `postgres` | |
| `POSTGRES_PASSWORD` | `postgres` | |
| `POSTGRES_DATABASE` | `postgres` | |
| `POSTGRES_TLS` | `false` | |
| `USE_DOCKER` | unset | Set to `1` for Docker testing |
| `POSTGRES_VERSION` | `latest` | Docker image tag |

### Test Plans (Xcode)
- **`PostgresIntegration.xctestplan`** — Primary test plan. Multi-version matrix (PG 14, 15, 16, 17, 18) with Docker env vars. Runs both `PostgresWireTests` and `PostgresKitTests`.
- **`TestPlanComprehensive.xctestplan`** — Single-version (PG 16) comprehensive run. `PostgresKitTests` only, random execution order.

### CI/CD (GitHub Actions)
- **`test.yml`**: Build → Unit tests (PostgresWireTests) → Integration tests matrix (PG 14-18 + latest).
- **`documentation.yml`**: DocC generation and GitHub Pages deployment on main push.

## Test Architecture

### Base Class
`PostgresKitTestCase` — XCTestCase subclass that:
1. Loads `.env` via `TestEnv.loadDotEnv()` in `class setUp()`.
2. Starts Docker container via `PostgresDockerManager` if `USE_DOCKER=1` in `setUp() async throws`.

All PostgresKitTests should inherit from `PostgresKitTestCase`.

### Test Categories
| Category | Files | What's Tested |
|----------|-------|---------------|
| Connection | BasicTests, DebugConnectionTests | Connect, pool, reuse, TLS |
| Query | BasicTests, DecodingTests, SimpleInsertTest | SELECT, INSERT, parameterized queries |
| DDL | DDLTests, ComprehensiveTableTests, ComprehensiveIndexTests, ComprehensiveConstraintTests | CREATE/ALTER/DROP tables, indexes, constraints |
| DML | AdvancedClientTests, BulkCopyTests | INSERT/UPDATE/DELETE, COPY, TRUNCATE |
| Transactions | TransactionDebugTests, BasicTests | BEGIN/COMMIT/ROLLBACK, savepoints, isolation |
| Metadata | MetadataFullTests, MetadataIntegrationTests | Introspection, schema discovery |
| Security | UserManagementTests | Roles, privileges, membership |
| Errors | ErrorHandling*, PostgresError*, EnhancedError* | Error conversion, constraint detection |
| Notifications | NotificationsTests | LISTEN/NOTIFY, async streams |
| Streaming | BasicTests, AdvancedClientTests | Streaming queries, cursor pagination |
| Sequences | SimpleSequenceTest | CREATE/nextval/currval/setval |
| Admin | AdminTests | VACUUM, ANALYZE, REINDEX, server config |
| Cache | LRUCacheTests, StatementCacheTests, ServerPrepareKeyTests | LRU eviction, statement caching |
| Formatting | PostgresFormatterEngineTests, StreamingDataTypeTests | OID formatting, type mapping |
| Config | PostgresStreamConfigurationTests, PostgresStreamUpdateTests, PostgresExecutionOptionsTests | Stream config, update events |

## Sample Data (`SampleData.sql`)

Comprehensive fixture in `Tests/PostgresKitTests/Support/SampleData.sql` covering:
- 40+ PostgreSQL data types across dedicated type tables (numeric, text, temporal, JSON, array, network, geometric, binary, range, full-text, special)
- Custom types: enums (`mood`, `priority_level`, `order_status`), composite (`address_type`), domains (`positive_integer`, `email_address`, `percentage`)
- Extensions: `uuid-ossp`, `hstore`, `ltree`, `citext`
- 4 schemas: `public`, `app`, `audit`, `archive`
- Realistic relational model: users, profiles, posts, tags, comments (threaded), orders, order items
- Triggers: `updated_at`, search vector, tag count, audit logging
- Functions: PL/pgSQL and pure SQL (table-returning, JSONB manipulation)
- Views and materialized views with indexes
- Sequences with options (START, INCREMENT, CYCLE)
- Roles and permissions: `test_readonly`, `test_readwrite`, `test_app_user`
- Boundary data: min/max values, NULLs, empty strings, Unicode, special characters

## Design Analysis & Recommendations

### Strengths
1. **Clean layer separation** — PostgresWire vs PostgresKit is well-defined.
2. **File size discipline** — No files over 500 lines in source (largest: `WireClient.swift` at 455).
3. **Domain-organized directories** — Easy to find functionality.
4. **Strict concurrency** — Actors where needed, Sendable throughout.
5. **Docker testing pipeline** — Multi-version CI is excellent.

### Areas for Improvement
1. **Test file sizes** — `ComprehensiveConstraintTests.swift` is 1,408 lines. Should be split by constraint type.
2. **Sample data is trivially small** — Only covers TEXT, SERIAL, BOOLEAN, TIMESTAMPTZ. Needs ALL 40+ PostgreSQL types.
3. **No data type round-trip tests** — Missing systematic encode→insert→select→decode tests for every supported type (JSONB, arrays, UUID, network types, geometric, date/time variants, etc.).
4. **No trigger/function test fixtures** — The schema supports creating triggers/functions but the sample data has none to introspect.
5. **No permission test fixtures** — No test roles or privilege grants in sample data.
6. **Missing test areas**: Full-text search (tsvector/tsquery), range types, composite types, domain types, partitioned tables, materialized view refresh, EXPLAIN plans, connection timeout/retry, TLS connections, large objects.
7. **Inconsistent test base class usage** — Some tests may not inherit from `PostgresKitTestCase`.
