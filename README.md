# PostgresWire & PostgresKit

A high-performance, SwiftNIO-based PostgreSQL client library for Swift, providing both low-level wire protocol access and high-level ergonomic APIs for application development.

## Overview

- **PostgresWire**: A thin, focused wrapper over Vapor's `PostgresNIO`, exposing a minimal interface for connections, queries, and streaming. It is designed to be easily testable and extremely fast.
- **PostgresKit**: Built on top of `PostgresWire`, this module provides a higher-level client with connection abstractions, statement caching, metadata utilities, and ergonomic APIs suitable for modern Swift applications.

## Features

- **High Performance**: Built directly on `SwiftNIO` and `PostgresNIO`.
- **Async/Await**: Modern Swift concurrency support throughout the API.
- **Statement Caching**: Simple LRU cache for prepared statements to optimize repeated queries.
- **Execution Options**: Fine-grained control over query execution, including server-side cursor thresholds and fetch baselines.
- **Metadata Utilities**: Helpers to list databases, schemas, tables, and object definitions natively in Swift.
- **Independent**: Clean API surface completely independent of any specific web framework.

## Installation

Add `postgres-wire` to your `Package.swift` dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/YOUR_GITHUB_USERNAME/postgres-wire.git", from: "1.0.0")
]
```

Add the products you need to your targets:

```swift
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "PostgresKit", package: "postgres-wire")
            // Or just PostgresWire if you only need the low-level client
        ]
    )
]
```

## Usage

### High-Level API (PostgresKit)

PostgresKit provides an ergonomic interface for querying your database with modern concurrency:

```swift
import PostgresKit

// 1. Configure the connection
let config = PostgresConfiguration(
    host: "localhost",
    port: 5432,
    username: "postgres",
    password: "password",
    database: "my_db",
    tls: .disable
)

// 2. Connect
let client = try await PostgresClient.connect(configuration: config)

// 3. Query
let rows = try await client.query("SELECT id, name FROM users WHERE active = \\(true)")
for try await row in rows {
    let id: Int = try row.decode(column: "id")
    let name: String = try row.decode(column: "name")
    print("User: \\(id) - \\(name)")
}
```

### Low-Level API (PostgresWire)

PostgresWire is available if you need granular control over the execution protocol:

```swift
import PostgresWire

let options = PostgresExecutionOptions(
    mode: .auto,               // or .simple, .cursor
    cursorThreshold: 25_000,   // LIMIT ≤ 25k → use simple
    fetchBaseline: 4_096,      // baseline cursor fetch
    fetchRampMultiplier: 24,
    fetchRampMax: 524_288,
    progressThrottleMs: 120
)

let client = try await PostgresWireClient.connect(configuration: config)
let rows = try await client.query(
    WireQuery(sql: "SELECT * FROM public.fixture LIMIT 10000;"),
    options: options
)
```

## Documentation

Comprehensive documentation can be generated using Swift-DocC:

```bash
swift package generate-documentation
```

## License

This project is licensed under the Apache 2.0 License. See the [LICENSE.txt](LICENSE.txt) file for details.
