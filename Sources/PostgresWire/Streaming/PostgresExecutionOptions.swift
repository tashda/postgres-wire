import Foundation

public enum PostgresExecutionMode: Sendable, Equatable {
    case auto
    case simple
    case cursor
}

public struct PostgresExecutionOptions: Sendable, Equatable {
    public var mode: PostgresExecutionMode
    public var cursorThreshold: Int?
    public var fetchBaseline: Int?
    public var fetchRampMultiplier: Int?
    public var fetchRampMax: Int?
    public var progressThrottleMs: Int?

    public init(
        mode: PostgresExecutionMode = .auto,
        cursorThreshold: Int? = nil,
        fetchBaseline: Int? = nil,
        fetchRampMultiplier: Int? = nil,
        fetchRampMax: Int? = nil,
        progressThrottleMs: Int? = nil
    ) {
        self.mode = mode
        self.cursorThreshold = cursorThreshold
        self.fetchBaseline = fetchBaseline
        self.fetchRampMultiplier = fetchRampMultiplier
        self.fetchRampMax = fetchRampMax
        self.progressThrottleMs = progressThrottleMs
    }
}
