import Foundation
import Logging
import PostgresWire

public struct PostgresConnectionClient: Sendable {
    internal let client: PostgresClient
    init(client: PostgresClient) { self.client = client }

    /// Borrow a single connection for multi-step operations (e.g., transactions).
    public func withConnection<T>(
        _ body: @Sendable (PostgresConnection) async throws -> T
    ) async throws -> T {
        try await client.withConnection(body)
    }
}

public struct PostgresAdminClient: Sendable {
    internal let client: PostgresClient
    init(client: PostgresClient) { self.client = client }
}

public struct PostgresAgentClient: Sendable {
    internal let client: PostgresClient
    init(client: PostgresClient) { self.client = client }

    public func snapshot(options: PostgresActivityOptions = .init()) async throws -> PostgresActivitySnapshot {
        try await client.wire.activity.snapshot(options: options)
    }

    public func streamSnapshots(every seconds: TimeInterval = 5.0, options: PostgresActivityOptions = .init()) -> AsyncThrowingStream<PostgresActivitySnapshot, Error> {
        client.wire.activity.streamSnapshots(every: seconds, options: options)
    }
}

public struct PostgresIntrospectionClient: Sendable {
    internal let client: PostgresClient
    init(client: PostgresClient) { self.client = client }
}

public struct PostgresSecurityClient: Sendable {
    internal let client: PostgresClient
    init(client: PostgresClient) { self.client = client }
}

public struct PostgresNotifierClient: Sendable {
    internal let client: PostgresClient
    init(client: PostgresClient) { self.client = client }

    public func notify(channel: String, payload: String? = nil) async throws {
        try await client.notifierActor.notify(channel: channel, payload: payload)
    }

    public func listen(channels: [String]) async throws {
        try await client.notifierActor.listen(channels: channels)
    }

    public func unlisten(channel: String) async throws {
        try await client.notifierActor.unlisten(channel: channel)
    }

    public func notifications(for channel: String) async -> AsyncStream<PostgresNotification> {
        await client.notifierActor.notifications(for: channel)
    }
}

extension PostgresClient {
    public var connection: PostgresConnectionClient { .init(client: self) }
    public var admin: PostgresAdminClient { .init(client: self) }
    public var agent: PostgresAgentClient { .init(client: self) }
    public var introspection: PostgresIntrospectionClient { .init(client: self) }
    public var security: PostgresSecurityClient { .init(client: self) }
    public var notifier: PostgresNotifierClient { .init(client: self) }
}
