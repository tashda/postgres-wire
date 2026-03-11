import Foundation

/// PostgreSQL trigger events.
public enum PostgresTriggerEvent: String, Sendable {
    case before = "BEFORE"
    case after = "AFTER"
    case insteadOf = "INSTEAD OF"
}

/// PostgreSQL trigger operations.
public enum PostgresTriggerOperation: String, Sendable {
    case insert = "INSERT"
    case update = "UPDATE"
    case delete = "DELETE"
    case truncate = "TRUNCATE"
}

/// PostgreSQL trigger forEach option.
public enum PostgresTriggerForEach: String, Sendable {
    case row = "ROW"
    case statement = "STATEMENT"
}
