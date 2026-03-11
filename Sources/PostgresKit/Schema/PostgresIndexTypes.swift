import Foundation

/// PostgreSQL index types.
public enum PostgresIndexType: Sendable {
    case btree
    case hash
    case gist
    case gin
    case brin
}

/// PostgreSQL index column definition.
public struct PostgresIndexColumn: Sendable {
    public let name: String
    public let order: PostgresIndexOrder?
    public let nullsOrder: PostgresIndexNullsOrder?

    public init(
        name: String,
        order: PostgresIndexOrder? = nil,
        nullsOrder: PostgresIndexNullsOrder? = nil
    ) {
        self.name = name
        self.order = order
        self.nullsOrder = nullsOrder
    }
}

/// PostgreSQL index column order.
public enum PostgresIndexOrder: String, Sendable {
    case asc = "ASC"
    case desc = "DESC"
}

/// PostgreSQL index NULLS order.
public enum PostgresIndexNullsOrder: String, Sendable {
    case first = "FIRST"
    case last = "LAST"
}
