import Foundation
import Logging

public struct PostgresPoolConfiguration: Sendable {
    public var minimum: Int
    public var maximum: Int
    public var idleTimeoutSeconds: Int

    public init(minimum: Int = 0, maximum: Int = 8, idleTimeoutSeconds: Int = 30) {
        self.minimum = minimum
        self.maximum = maximum
        self.idleTimeoutSeconds = idleTimeoutSeconds
    }
}

public struct PostgresConfiguration: Sendable {
    public var host: String
    public var port: Int
    public var database: String
    public var username: String
    public var password: String?
    public var sslMode: PostgresSSLMode
    /// Path to a PEM-encoded root CA certificate file for verify-ca / verify-full modes.
    public var sslRootCertPath: String?
    public var applicationName: String?
    public var pool: PostgresPoolConfiguration
    /// TCP connect timeout in seconds. Defaults to 10.
    public var connectTimeout: Int

    /// Whether TLS is enabled (any mode other than `disable`).
    public var useTLS: Bool { sslMode != .disable }

    public init(
        host: String,
        port: Int = 5432,
        database: String = "postgres",
        username: String,
        password: String?,
        sslMode: PostgresSSLMode = .disable,
        sslRootCertPath: String? = nil,
        applicationName: String? = nil,
        pool: PostgresPoolConfiguration = .init(),
        connectTimeout: Int = 10
    ) {
        self.host = host
        self.port = port
        self.database = database
        self.username = username
        self.password = password
        self.sslMode = sslMode
        self.sslRootCertPath = sslRootCertPath
        self.applicationName = applicationName
        self.pool = pool
        self.connectTimeout = connectTimeout
    }

    /// Backward-compatible initializer using a simple `useTLS` boolean.
    public init(
        host: String,
        port: Int = 5432,
        database: String = "postgres",
        username: String,
        password: String?,
        useTLS: Bool,
        applicationName: String? = nil,
        pool: PostgresPoolConfiguration = .init(),
        connectTimeout: Int = 10
    ) {
        self.init(
            host: host,
            port: port,
            database: database,
            username: username,
            password: password,
            sslMode: useTLS ? .require : .disable,
            applicationName: applicationName,
            pool: pool,
            connectTimeout: connectTimeout
        )
    }
}

extension PostgresConfiguration {
    public func makeWireConfiguration() -> PostgresWireConfiguration {
        .init(
            host: host,
            port: port,
            username: username,
            password: password,
            database: database,
            sslMode: sslMode,
            sslRootCertPath: sslRootCertPath,
            applicationName: applicationName,
            connectTimeout: connectTimeout
        )
    }
}

