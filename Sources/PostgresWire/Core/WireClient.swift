import Foundation
import Logging
import NIOConcurrencyHelpers
import NIOCore
import NIOPosix
import NIOSSL
import PostgresNIO

public struct PostgresWireConfiguration: Sendable {
    public var host: String
    public var port: Int
    public var username: String
    public var password: String?
    public var database: String?
    public var useTLS: Bool
    public var applicationName: String?
    /// TCP connect timeout in seconds. Defaults to 10.
    public var connectTimeout: Int

    public init(
        host: String,
        port: Int = 5432,
        username: String,
        password: String?,
        database: String? = nil,
        useTLS: Bool = false,
        applicationName: String? = nil,
        connectTimeout: Int = 10
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.database = database
        self.useTLS = useTLS
        self.applicationName = applicationName
        self.connectTimeout = connectTimeout
    }
}

public final class PostgresWireClient: @unchecked Sendable {
    private let client: PostgresClient
    private let runTask: Task<Void, Never>
    private let logger: Logger

    private init(client: PostgresClient, logger: Logger) {
        self.client = client
        self.logger = logger
        self.runTask = Task.detached { await client.run() }
    }

    deinit {
        runTask.cancel()
    }

    public static func connect(
        configuration: PostgresWireConfiguration,
        logger: Logger = .init(label: "postgres-wire")
    ) async throws -> PostgresWireClient {
        // Phase 0: Pre-resolve hostname. This gives immediate feedback for
        // typos and non-existent hosts instead of hanging until timeout.
        try await resolveHostname(configuration.host, port: configuration.port)

        // Phase 1: Eager validation with a direct (non-pooled) connection.
        // This gives us immediate feedback: wrong credentials return an auth
        // error right away instead of the pool retrying until timeout.
        let connTLS: PostgresConnection.Configuration.TLS
        if configuration.useTLS {
            let sslContext = try NIOSSLContext(configuration: .makeClientConfiguration())
            connTLS = .require(sslContext)
        } else {
            connTLS = .disable
        }

        var probeConfig = PostgresConnection.Configuration(
            host: configuration.host,
            port: configuration.port,
            username: configuration.username,
            password: configuration.password,
            database: configuration.database ?? "postgres",
            tls: connTLS
        )
        probeConfig.options.connectTimeout = .seconds(Int64(configuration.connectTimeout))

        // Race the probe against a hard timeout. NIO's connectTimeout may not
        // fire reliably on macOS (NIOTSConnectionBootstrap / Network.framework),
        // so we enforce our own deadline. We use a continuation so we can return
        // immediately when either the probe or the timer fires — we do NOT wait
        // for the NIO connection to finish if the timer wins.
        let finalProbeConfig = probeConfig
        let timeoutNanos = UInt64(configuration.connectTimeout) * 1_000_000_000
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            // Connect task
            group.addTask {
                let probe = try await PostgresConnection.connect(
                    configuration: finalProbeConfig,
                    id: 0,
                    logger: logger
                )
                try? await probe.close()
            }
            
            // Timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanos)
                throw IOError(errnoCode: 60, reason: "connect timeout")
            }
            
            // Wait for the first one to finish or fail
            try await group.next()
            group.cancelAll()
        }

        // Phase 2: Probe succeeded — create the pool-based client for ongoing use.
        let poolTLS: PostgresClient.Configuration.TLS = configuration.useTLS
            ? .require(.makeClientConfiguration())
            : .disable

        var clientConfig = PostgresClient.Configuration(
            host: configuration.host,
            port: configuration.port,
            username: configuration.username,
            password: configuration.password,
            database: configuration.database ?? "postgres",
            tls: poolTLS
        )
        clientConfig.options.connectTimeout = .seconds(Int64(configuration.connectTimeout))

        let client = PostgresClient(configuration: clientConfig, backgroundLogger: logger)
        return PostgresWireClient(client: client, logger: logger)
    }

    public func close() {
        runTask.cancel()
    }

    public func withConnection<T>(
        _ operation: (WireConnection) async throws -> T
    ) async throws -> T {
        try await client.withConnection { connection in
            try await operation(WireConnection(connection))
        }
    }

    public func query(_ query: WireQuery, logger: Logger? = nil) async throws -> WireRowSequence {
        try await client.query(query.asPostgresQuery(), logger: logger ?? self.logger)
    }

    public func query(
        _ query: WireQuery,
        options: PostgresExecutionOptions?,
        logger: Logger? = nil
    ) async throws -> WireRowSequence {
        // Advisory surface for now; forwards to existing path.
        _ = options
        return try await self.query(query, logger: logger)
    }

    // MARK: - Streaming API

    /// Execute a query with streaming and formatting
    public func streamQuery(
        _ sql: String,
        configuration: PostgresStreamConfiguration = .default,
        onUpdate: @escaping @Sendable (PostgresStreamUpdate) async -> Void,
        logger: Logger? = nil
    ) async throws -> PostgresStreamResult {
        let effectiveLogger = logger ?? self.logger
        let operationStart = Date().timeIntervalSinceReferenceDate

        effectiveLogger.info("Starting streaming query: \(sql.prefix(100))")

        // Create data stream with formatting capabilities
        let dataStream = PostgresDataStream(
            configuration: configuration,
            logger: effectiveLogger,
            operationStart: operationStart
        )

        do {
            // Execute query using existing query mechanism
            let wireQuery = WireQuery(sql: sql)
            let rowSequence = try await client.query(wireQuery.asPostgresQuery(), logger: effectiveLogger)

            // Process rows with streaming and formatting
            var processedRowCount = 0
            var lastSentRowCount = 0
            var lastProgressUpdate = operationStart

            for try await row in rowSequence {
                await dataStream.appendRow(row)
                processedRowCount += 1

                // Send progress updates based on configuration
                let now = Date().timeIntervalSinceReferenceDate
                let timeSinceLastUpdate = now - lastProgressUpdate
                let shouldUpdateByTime = timeSinceLastUpdate >= configuration.progressThrottle
                let shouldUpdateByCount = processedRowCount % configuration.liveCounterFrequency == 0

                if shouldUpdateByTime || shouldUpdateByCount {
                    await sendProgressUpdate(
                        dataStream: dataStream,
                        lastSentRowCount: lastSentRowCount,
                        onUpdate: onUpdate,
                        logger: effectiveLogger
                    )
                    lastSentRowCount = processedRowCount
                    lastProgressUpdate = now
                }

                // Check for cancellation
                if Task.isCancelled {
                    await dataStream.cancel()
                    throw CancellationError()
                }
            }

            // Mark streaming as complete
            await dataStream.complete()

            // Send final update
            let finalMetrics = await dataStream.getMetrics()
            let finalUpdate = PostgresStreamUpdate.completion(
                columns: await getColumnsFromStream(dataStream),
                totalRowCount: await dataStream.getLiveRowCount(),
                metrics: finalMetrics
            )

            await onUpdate(finalUpdate)

            let result = PostgresStreamResult(
                columns: await getColumnsFromStream(dataStream),
                totalRowCount: await dataStream.getLiveRowCount(),
                metrics: finalMetrics
            )

            effectiveLogger.info("Streaming query completed: \(processedRowCount) rows in \(String(format: "%.3f", finalMetrics.totalElapsed))s")

            return result

        } catch {
            // Handle errors
            await dataStream.fail(with: error)

            let errorUpdate = PostgresStreamUpdate.error(
                columns: await getColumnsFromStream(dataStream),
                totalRowCount: await dataStream.getLiveRowCount(),
                error: error
            )

            await onUpdate(errorUpdate)
            throw error
        }
    }

    /// Execute a streaming query with automatic cursor management for large result sets
    public func streamQueryWithCursor(
        _ sql: String,
        configuration: PostgresStreamConfiguration = .default,
        onUpdate: @escaping @Sendable (PostgresStreamUpdate) async -> Void,
        logger: Logger? = nil
    ) async throws -> PostgresStreamResult {
        let effectiveLogger = logger ?? self.logger
        let operationStart = Date().timeIntervalSinceReferenceDate

        effectiveLogger.info("Starting cursor streaming query: \(sql.prefix(100))")

        return try await withConnection { connection in
            let dataStream = PostgresDataStream(
                configuration: configuration,
                logger: effectiveLogger,
                operationStart: operationStart
            )

            let cursorName = "pgstream_cur_" + String(UUID().uuidString.prefix(8))

            do {
                // Begin transaction and declare cursor
                _ = try await connection.query(WireQuery(sql: "BEGIN"), logger: effectiveLogger)
                _ = try await connection.query(WireQuery(sql: "DECLARE \(cursorName) NO SCROLL CURSOR FOR \(sql)"), logger: effectiveLogger)

                var fetchSize = configuration.initialPreviewRows
                var totalFetched = 0
                var lastSentRowCount = 0
                var lastProgressUpdate = operationStart

                fetchLoop: while true {
                    let fetchSQL = "FETCH FORWARD \(fetchSize) FROM \(cursorName)"
                    let rows = try await connection.query(WireQuery(sql: fetchSQL), logger: effectiveLogger)

                    var fetchedThisRound = 0
                    for try await row in rows {
                        await dataStream.appendRow(row)
                        fetchedThisRound += 1
                        totalFetched += 1
                    }

                    // If no rows fetched, we're done
                    if fetchedThisRound == 0 {
                        break fetchLoop
                    }

                    // Update fetch size based on configuration
                    if totalFetched >= configuration.initialPreviewRows {
                        fetchSize = configuration.streamingFetchSize
                    }

                    // Send progress updates
                    let now = Date().timeIntervalSinceReferenceDate
                    let timeSinceLastUpdate = now - lastProgressUpdate
                    let shouldUpdateByTime = timeSinceLastUpdate >= configuration.progressThrottle
                    let shouldUpdateByCount = totalFetched % configuration.liveCounterFrequency == 0

                    if shouldUpdateByTime || shouldUpdateByCount {
                        await sendProgressUpdate(
                            dataStream: dataStream,
                            lastSentRowCount: lastSentRowCount,
                            onUpdate: onUpdate,
                            logger: effectiveLogger
                        )
                        lastSentRowCount = totalFetched
                        lastProgressUpdate = now
                    }

                    // Check for cancellation
                    if Task.isCancelled {
                        await dataStream.cancel()
                        throw CancellationError()
                    }
                }

                // Close cursor and transaction
                _ = try await connection.query(WireQuery(sql: "CLOSE \(cursorName)"), logger: effectiveLogger)
                _ = try await connection.query(WireQuery(sql: "COMMIT"), logger: effectiveLogger)

                // Mark streaming as complete
                await dataStream.complete()

                // Send final update
                let finalMetrics = await dataStream.getMetrics()
                let finalUpdate = PostgresStreamUpdate.completion(
                    columns: await getColumnsFromStream(dataStream),
                    totalRowCount: await dataStream.getLiveRowCount(),
                    metrics: finalMetrics
                )

                await onUpdate(finalUpdate)

                let result = PostgresStreamResult(
                    columns: await getColumnsFromStream(dataStream),
                    totalRowCount: await dataStream.getLiveRowCount(),
                    metrics: finalMetrics
                )

                effectiveLogger.info("Cursor streaming query completed: \(totalFetched) rows in \(String(format: "%.3f", finalMetrics.totalElapsed))s")

                return result

            } catch {
                // Clean up cursor and transaction on error
                _ = try? await connection.query(WireQuery(sql: "CLOSE \(cursorName)"), logger: effectiveLogger)
                _ = try? await connection.query(WireQuery(sql: "ROLLBACK"), logger: effectiveLogger)

                await dataStream.fail(with: error)

                let errorUpdate = PostgresStreamUpdate.error(
                    columns: await getColumnsFromStream(dataStream),
                    totalRowCount: await dataStream.getLiveRowCount(),
                    error: error
                )

                await onUpdate(errorUpdate)
                throw error
            }
        }
    }

    // MARK: - Private Helper Methods

    private func sendProgressUpdate(
        dataStream: PostgresDataStream,
        lastSentRowCount: Int,
        onUpdate: @escaping @Sendable (PostgresStreamUpdate) async -> Void,
        logger: Logger
    ) async {
        let rowCount = await dataStream.getLiveRowCount()
        let metrics = await dataStream.getMetrics()
        let columns = await getColumnsFromStream(dataStream)

        // Send only NEW rows since last update for incremental updates
        let newRowsRange = lastSentRowCount..<rowCount
        let newFormattedRows = await dataStream.getFormattedRows(in: newRowsRange)

        // Get raw rows for deferred formatting
        let newRawRows = await dataStream.getRawRows(in: newRowsRange)

        let update = PostgresStreamUpdate(
            columns: columns,
            appendedRows: newFormattedRows, // Send only new rows
            rawRows: newRawRows, // Send raw rows for deferred formatting
            totalRowCount: rowCount,
            metrics: metrics,
            rowRange: newRowsRange
        )

        await onUpdate(update)
    }

    private func getColumnsFromStream(_ dataStream: PostgresDataStream) async -> [ColumnInfo] {
        return await dataStream.columns
    }
}

// MARK: - DNS Pre-Resolution

extension PostgresWireClient {
    /// Resolve hostname before attempting a connection. Fails immediately for
    /// non-existent hosts, typos, and invalid addresses — no need to wait for
    /// the TCP connect timeout.
    private static func resolveHostname(_ host: String, port: Int) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var hints = addrinfo()
                #if canImport(Darwin)
                hints.ai_socktype = SOCK_STREAM
                #else
                hints.ai_socktype = Int32(SOCK_STREAM.rawValue)
                #endif
                hints.ai_family = AF_UNSPEC

                var result: UnsafeMutablePointer<addrinfo>?
                let status = getaddrinfo(host, String(port), &hints, &result)
                if let result {
                    freeaddrinfo(result)
                }

                if status != 0 {
                    continuation.resume(throwing: DNSResolutionError(host: host))
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

/// Error thrown when DNS resolution fails for a hostname.
struct DNSResolutionError: Error, LocalizedError {
    let host: String

    var errorDescription: String? {
        "Could not resolve hostname '\(host)'. Check the server address."
    }
}
