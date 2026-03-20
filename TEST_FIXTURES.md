# Test Fixture Policy

`postgres-wire` owns the canonical PostgreSQL integration fixture model.

## Rules

- Fixtures always run through `bootstrap`, `validate`, and `repair/recreate`.
- Validation is mandatory on every run, even when a Docker container is reused.
- Ambient long-lived containers are never trusted without validation.
- Fixture failures must be reported as fixture/bootstrap failures, not as driver regressions.

## Canonical Fixture

- Engine: PostgreSQL Docker container
- Seeded database: package-owned `SampleData.sql`
- Entry points:
  - library: `ensurePostgresTestFixture()`
  - CLI: `swift run --package-path . postgres-test-fixture`

## Workflow Expectations

- CI may reuse containers for speed.
- Reused containers must be revalidated.
- If validation fails, the fixture must be repaired or recreated automatically before tests proceed.
