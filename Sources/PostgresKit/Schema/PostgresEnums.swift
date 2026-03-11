import Foundation

/// PostgreSQL privilege types.
public enum PostgresPrivilege: String, Sendable {
    case select = "SELECT"
    case insert = "INSERT"
    case update = "UPDATE"
    case delete = "DELETE"
    case truncate = "TRUNCATE"
    case references = "REFERENCES"
    case trigger = "TRIGGER"
    case create = "CREATE"
    case connect = "CONNECT"
    case temporary = "TEMPORARY"
    case execute = "EXECUTE"
    case usage = "USAGE"
    case all = "ALL"
}

/// PostgreSQL foreign key actions.
public enum PostgresForeignKeyAction: String, Sendable {
    case cascade = "CASCADE"
    case restrict = "RESTRICT"
    case setNull = "SET NULL"
    case setDefault = "SET DEFAULT"
    case noAction = "NO ACTION"
}

/// PostgreSQL transaction isolation levels.
public enum PostgresIsolationLevel: String, Sendable {
    case readCommitted = "READ COMMITTED"
    case repeatableRead = "REPEATABLE READ"
    case serializable = "SERIALIZABLE"
}

/// PostgreSQL constraint types.
public enum PostgresConstraintType: Sendable {
    case primaryKey
    case foreignKey
    case unique
    case check
    case notNull
    case exclusion
}

/// PostgreSQL tablespace types.
public enum PostgresTablespace: Sendable {
    case pgDefault
    case pgGlobal
    case custom(String)
}

/// PostgreSQL collation support.
public enum PostgresCollation: Sendable {
    case `default`
    case defaultWithLocale(String)
    case binary
    case c
    case posix
    case custom(String)
}
