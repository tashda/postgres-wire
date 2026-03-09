import Foundation

// MARK: - Column Definition

public struct PostgresColumnDefinition {
    public let name: String
    public let dataType: String
    public let nullable: Bool
    public let defaultValue: String?
    public let primaryKey: Bool
    public let unique: Bool

    public init(
        name: String,
        dataType: String,
        nullable: Bool = true,
        defaultValue: String? = nil,
        primaryKey: Bool = false,
        unique: Bool = false
    ) {
        self.name = name
        self.dataType = dataType
        self.nullable = nullable
        self.defaultValue = defaultValue
        self.primaryKey = primaryKey
        self.unique = unique
    }
}

// MARK: - Common Data Types

public extension PostgresColumnDefinition {
    // Numeric types
    static func integer(name: String, nullable: Bool = true, defaultValue: Int? = nil) -> PostgresColumnDefinition {
        return PostgresColumnDefinition(
            name: name,
            dataType: "INTEGER",
            nullable: nullable,
            defaultValue: defaultValue.map { String($0) }
        )
    }

    static func bigInt(name: String, nullable: Bool = true, defaultValue: Int? = nil) -> PostgresColumnDefinition {
        return PostgresColumnDefinition(
            name: name,
            dataType: "BIGINT",
            nullable: nullable,
            defaultValue: defaultValue.map { String($0) }
        )
    }

    static func serial(name: String, primaryKey: Bool = false) -> PostgresColumnDefinition {
        return PostgresColumnDefinition(
            name: name,
            dataType: "SERIAL",
            nullable: false,
            primaryKey: primaryKey,
            unique: false
        )
    }

    static func bigSerial(name: String, primaryKey: Bool = false) -> PostgresColumnDefinition {
        return PostgresColumnDefinition(
            name: name,
            dataType: "BIGSERIAL",
            nullable: false,
            primaryKey: primaryKey,
            unique: false
        )
    }

    static func decimal(name: String, precision: Int = 10, scale: Int = 0, nullable: Bool = true) -> PostgresColumnDefinition {
        return PostgresColumnDefinition(
            name: name,
            dataType: "DECIMAL(\(precision),\(scale))",
            nullable: nullable
        )
    }

    static func real(name: String, nullable: Bool = true) -> PostgresColumnDefinition {
        return PostgresColumnDefinition(
            name: name,
            dataType: "REAL",
            nullable: nullable
        )
    }

    static func double(name: String, nullable: Bool = true) -> PostgresColumnDefinition {
        return PostgresColumnDefinition(
            name: name,
            dataType: "DOUBLE PRECISION",
            nullable: nullable
        )
    }

    // Text types
    static func text(name: String, nullable: Bool = true, defaultValue: String? = nil) -> PostgresColumnDefinition {
        return PostgresColumnDefinition(
            name: name,
            dataType: "TEXT",
            nullable: nullable,
            defaultValue: defaultValue.map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" }
        )
    }

    static func varchar(name: String, length: Int = 255, nullable: Bool = true, defaultValue: String? = nil) -> PostgresColumnDefinition {
        return PostgresColumnDefinition(
            name: name,
            dataType: "VARCHAR(\(length))",
            nullable: nullable,
            defaultValue: defaultValue.map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" }
        )
    }

    static func char(name: String, length: Int = 1, nullable: Bool = true, defaultValue: String? = nil) -> PostgresColumnDefinition {
        return PostgresColumnDefinition(
            name: name,
            dataType: "CHAR(\(length))",
            nullable: nullable,
            defaultValue: defaultValue.map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" }
        )
    }

    // Boolean type
    static func boolean(name: String, nullable: Bool = true, defaultValue: Bool? = nil) -> PostgresColumnDefinition {
        return PostgresColumnDefinition(
            name: name,
            dataType: "BOOLEAN",
            nullable: nullable,
            defaultValue: defaultValue.map { $0 ? "TRUE" : "FALSE" }
        )
    }

    // Date/Time types
    static func timestamp(name: String, nullable: Bool = true, defaultValue: String? = nil) -> PostgresColumnDefinition {
        return PostgresColumnDefinition(
            name: name,
            dataType: "TIMESTAMP",
            nullable: nullable,
            defaultValue: defaultValue ?? "CURRENT_TIMESTAMP"
        )
    }

    static func timestampWithTimeZone(name: String, nullable: Bool = true, defaultValue: String? = nil) -> PostgresColumnDefinition {
        return PostgresColumnDefinition(
            name: name,
            dataType: "TIMESTAMPTZ",
            nullable: nullable,
            defaultValue: defaultValue ?? "CURRENT_TIMESTAMP"
        )
    }

    static func date(name: String, nullable: Bool = true, defaultValue: String? = nil) -> PostgresColumnDefinition {
        return PostgresColumnDefinition(
            name: name,
            dataType: "DATE",
            nullable: nullable,
            defaultValue: defaultValue ?? "CURRENT_DATE"
        )
    }

    static func time(name: String, nullable: Bool = true, defaultValue: String? = nil) -> PostgresColumnDefinition {
        return PostgresColumnDefinition(
            name: name,
            dataType: "TIME",
            nullable: nullable,
            defaultValue: defaultValue ?? "CURRENT_TIME"
        )
    }

    static func timeWithTimeZone(name: String, nullable: Bool = true, defaultValue: String? = nil) -> PostgresColumnDefinition {
        return PostgresColumnDefinition(
            name: name,
            dataType: "TIMETZ",
            nullable: nullable,
            defaultValue: defaultValue ?? "CURRENT_TIME"
        )
    }

    // JSON types
    static func json(name: String, nullable: Bool = true) -> PostgresColumnDefinition {
        return PostgresColumnDefinition(
            name: name,
            dataType: "JSON",
            nullable: nullable
        )
    }

    static func jsonb(name: String, nullable: Bool = true) -> PostgresColumnDefinition {
        return PostgresColumnDefinition(
            name: name,
            dataType: "JSONB",
            nullable: nullable
        )
    }

    // Binary types
    static func bytea(name: String, nullable: Bool = true) -> PostgresColumnDefinition {
        return PostgresColumnDefinition(
            name: name,
            dataType: "BYTEA",
            nullable: nullable
        )
    }

    // UUID type
    static func uuid(name: String, nullable: Bool = true, defaultValue: String? = nil) -> PostgresColumnDefinition {
        return PostgresColumnDefinition(
            name: name,
            dataType: "UUID",
            nullable: nullable,
            defaultValue: defaultValue ?? "gen_random_uuid()"
        )
    }

    // Array types
    static func array(name: String, elementType: String, nullable: Bool = true) -> PostgresColumnDefinition {
        return PostgresColumnDefinition(
            name: name,
            dataType: "\(elementType)[]",
            nullable: nullable
        )
    }

    // Network types
    static func inet(name: String, nullable: Bool = true) -> PostgresColumnDefinition {
        return PostgresColumnDefinition(
            name: name,
            dataType: "INET",
            nullable: nullable
        )
    }

    static func cidr(name: String, nullable: Bool = true) -> PostgresColumnDefinition {
        return PostgresColumnDefinition(
            name: name,
            dataType: "CIDR",
            nullable: nullable
        )
    }

    static func macaddr(name: String, nullable: Bool = true) -> PostgresColumnDefinition {
        return PostgresColumnDefinition(
            name: name,
            dataType: "MACADDR",
            nullable: nullable
        )
    }

    // Custom enum type
    static func enumType(name: String, typeName: String, nullable: Bool = true, defaultValue: String? = nil) -> PostgresColumnDefinition {
        return PostgresColumnDefinition(
            name: name,
            dataType: typeName,
            nullable: nullable,
            defaultValue: defaultValue.map { "'\($0)'" }
        )
    }
}

// MARK: - PostgreSQL Enums

/// PostgreSQL privilege types
public enum PostgresPrivilege: String {
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

/// PostgreSQL foreign key actions
public enum PostgresForeignKeyAction: String {
    case cascade = "CASCADE"
    case restrict = "RESTRICT"
    case setNull = "SET NULL"
    case setDefault = "SET DEFAULT"
    case noAction = "NO ACTION"
}

/// PostgreSQL transaction isolation levels
public enum PostgresIsolationLevel: String {
    case readCommitted = "READ COMMITTED"
    case repeatableRead = "REPEATABLE READ"
    case serializable = "SERIALIZABLE"
}

/// PostgreSQL constraint types
public enum PostgresConstraintType {
    case primaryKey
    case foreignKey
    case unique
    case check
    case notNull
    case exclusion
}

/// PostgreSQL trigger events
public enum PostgresTriggerEvent: String {
    case before = "BEFORE"
    case after = "AFTER"
    case insteadOf = "INSTEAD OF"
}

/// PostgreSQL trigger operations
public enum PostgresTriggerOperation: String {
    case insert = "INSERT"
    case update = "UPDATE"
    case delete = "DELETE"
    case truncate = "TRUNCATE"
}

/// PostgreSQL index types
public enum PostgresIndexType {
    case btree
    case hash
    case gist
    case gin
    case brin
}

/// PostgreSQL tablespace types
public enum PostgresTablespace {
    case pgDefault
    case pgGlobal
    case custom(String)
}

/// PostgreSQL collation support
public enum PostgresCollation {
    case `default`
    case defaultWithLocale(String) // default with locale
    case binary
    case c
    case posix
    case custom(String)
}

/// PostgreSQL function parameter mode
public enum PostgresFunctionMode {
    case `in`
    case `out`
    case `inout`
}

/// PostgreSQL function language
public enum PostgresFunctionLanguage: String {
    case sql = "SQL"
    case plpgsql = "PLPGSQL"
    case plpython = "PLPYTHONU"
    case plperl = "PLPERLU"
    case pltcl = "PLTCL"
}

/// PostgreSQL function security
public enum PostgresFunctionSecurity {
    case definer
    case invoker
}

/// PostgreSQL function parameter definition
public struct PostgresFunctionParameter {
    public let name: String
    public let dataType: String
    public let mode: PostgresFunctionMode
    public let defaultValue: String?

    public init(
        name: String,
        dataType: String,
        mode: PostgresFunctionMode = .`in`,
        defaultValue: String? = nil
    ) {
        self.name = name
        self.dataType = dataType
        self.mode = mode
        self.defaultValue = defaultValue
    }
}

/// PostgreSQL index column definition
public struct PostgresIndexColumn {
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

/// PostgreSQL index column order
public enum PostgresIndexOrder: String {
    case asc = "ASC"
    case desc = "DESC"
}

/// PostgreSQL index NULLS order
public enum PostgresIndexNullsOrder: String {
    case first = "FIRST"
    case last = "LAST"
}

/// PostgreSQL trigger forEach option
public enum PostgresTriggerForEach: String {
    case row = "ROW"
    case statement = "STATEMENT"
}

/// PostgreSQL lock modes
public enum PostgresLockMode: String {
    case accessShare = "ACCESS SHARE"
    case rowShare = "ROW SHARE"
    case rowExclusive = "ROW EXCLUSIVE"
    case shareUpdateExclusive = "SHARE UPDATE EXCLUSIVE"
    case share = "SHARE"
    case shareRowExclusive = "SHARE ROW EXCLUSIVE"
    case exclusive = "EXCLUSIVE"
    case accessExclusive = "ACCESS EXCLUSIVE"
}