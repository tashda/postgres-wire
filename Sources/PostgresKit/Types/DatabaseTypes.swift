import Foundation

/// Comprehensive database properties.
public struct PostgresDatabaseProperties: Sendable {
    public let oid: String
    public let name: String
    public let owner: String
    public let encoding: String
    public let collation: String
    public let ctype: String
    public let icuLocale: String?
    public let connectionLimit: Int
    public let isTemplate: Bool
    public let allowConnections: Bool
    public let tablespace: String
    public let sizeBytes: Int64
    public let activeConnections: Int
    public let description: String?
    public let acl: String?

    public init(
        oid: String,
        name: String,
        owner: String,
        encoding: String,
        collation: String,
        ctype: String,
        icuLocale: String?,
        connectionLimit: Int,
        isTemplate: Bool,
        allowConnections: Bool,
        tablespace: String,
        sizeBytes: Int64,
        activeConnections: Int,
        description: String?,
        acl: String?
    ) {
        self.oid = oid
        self.name = name
        self.owner = owner
        self.encoding = encoding
        self.collation = collation
        self.ctype = ctype
        self.icuLocale = icuLocale
        self.connectionLimit = connectionLimit
        self.isTemplate = isTemplate
        self.allowConnections = allowConnections
        self.tablespace = tablespace
        self.sizeBytes = sizeBytes
        self.activeConnections = activeConnections
        self.description = description
        self.acl = acl
    }
}

/// A configuration parameter for a database or role.
public struct PostgresDatabaseParameter: Sendable {
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

/// A single privilege entry within a PostgreSQL ACL.
public struct PostgresACLPrivilege: Sendable, Equatable {
    /// The privilege type.
    public let privilege: PostgresPrivilege
    /// Whether the grantee can grant this privilege to others.
    public let withGrantOption: Bool

    public init(privilege: PostgresPrivilege, withGrantOption: Bool = false) {
        self.privilege = privilege
        self.withGrantOption = withGrantOption
    }
}

/// A parsed entry from a PostgreSQL ACL string (e.g. from `datacl`, `relacl`, `defaclacl`).
///
/// PostgreSQL ACL format: `grantee=privileges/grantor`
/// Privilege letters: `a`=INSERT, `r`=SELECT, `w`=UPDATE, `d`=DELETE, `D`=TRUNCATE,
/// `x`=REFERENCES, `t`=TRIGGER, `X`=EXECUTE, `U`=USAGE, `C`=CREATE, `c`=CONNECT,
/// `T`=TEMPORARY. A `*` after a letter indicates WITH GRANT OPTION.
/// Empty grantee means PUBLIC.
public struct PostgresACLEntry: Sendable, Equatable {
    /// The role receiving the privileges. Empty string means PUBLIC.
    public let grantee: String
    /// The role that granted the privileges.
    public let grantor: String
    /// The individual privileges granted.
    public let privileges: [PostgresACLPrivilege]

    public init(grantee: String, grantor: String, privileges: [PostgresACLPrivilege]) {
        self.grantee = grantee
        self.grantor = grantor
        self.privileges = privileges
    }

    /// Parse a PostgreSQL ACL string into structured entries.
    ///
    /// Input format: `{grantee=privs/grantor,grantee2=privs/grantor,...}`
    /// or individual entries without braces.
    public static func parse(acl: String) -> [PostgresACLEntry] {
        let trimmed = acl.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
        guard !trimmed.isEmpty else { return [] }

        var entries: [PostgresACLEntry] = []
        for item in splitACLItems(trimmed) {
            if let entry = parseEntry(item) {
                entries.append(entry)
            }
        }
        return entries
    }

    /// Split ACL string respecting quoted identifiers.
    private static func splitACLItems(_ str: String) -> [String] {
        var items: [String] = []
        var current = ""
        var inQuotes = false
        for ch in str {
            if ch == "\"" {
                inQuotes.toggle()
                current.append(ch)
            } else if ch == "," && !inQuotes {
                items.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { items.append(current) }
        return items
    }

    /// Parse a single ACL entry like `grantee=arwdDxt/grantor` or `"quoted name"=r/grantor`.
    private static func parseEntry(_ entry: String) -> PostgresACLEntry? {
        guard let eqIndex = entry.lastIndex(of: "=") else { return nil }

        let rawGrantee = String(entry[entry.startIndex..<eqIndex])
        let rest = String(entry[entry.index(after: eqIndex)...])

        guard let slashIndex = rest.lastIndex(of: "/") else { return nil }

        let privsStr = String(rest[rest.startIndex..<slashIndex])
        let rawGrantor = String(rest[rest.index(after: slashIndex)...])

        let grantee = rawGrantee.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        let grantor = rawGrantor.trimmingCharacters(in: CharacterSet(charactersIn: "\""))

        let privileges = parsePrivileges(privsStr)
        return PostgresACLEntry(grantee: grantee, grantor: grantor, privileges: privileges)
    }

    private static let privilegeMap: [Character: PostgresPrivilege] = [
        "a": .insert, "r": .select, "w": .update, "d": .delete,
        "D": .truncate, "x": .references, "t": .trigger,
        "X": .execute, "U": .usage, "C": .create, "c": .connect,
        "T": .temporary,
    ]

    private static func parsePrivileges(_ str: String) -> [PostgresACLPrivilege] {
        var result: [PostgresACLPrivilege] = []
        let arr = Array(str)
        var i = 0
        while i < arr.count {
            if let priv = privilegeMap[arr[i]] {
                let withGrant = (i + 1 < arr.count && arr[i + 1] == "*")
                result.append(PostgresACLPrivilege(privilege: priv, withGrantOption: withGrant))
                if withGrant { i += 1 }
            }
            i += 1
        }
        return result
    }
}

/// A default privilege entry from `pg_default_acl`.
public struct PostgresDefaultPrivilege: Sendable {
    /// Schema name, or empty for global defaults.
    public let schema: String
    /// The role that owns the default privilege rule.
    public let owner: String
    /// The object type this default applies to.
    public let objectType: PostgresObjectType
    /// The role receiving the privileges.
    public let grantee: String
    /// The privileges granted by default.
    public let privileges: [PostgresACLPrivilege]

    public init(schema: String, owner: String, objectType: PostgresObjectType, grantee: String, privileges: [PostgresACLPrivilege]) {
        self.schema = schema
        self.owner = owner
        self.objectType = objectType
        self.grantee = grantee
        self.privileges = privileges
    }
}

/// Describes a PostgreSQL server setting.
public struct PostgresSettingDefinition: Sendable {
    /// Parameter name (e.g. "work_mem", "statement_timeout").
    public let name: String
    /// Data type: "bool", "enum", "integer", "real", or "string".
    public let vartype: String
    /// Minimum value for numeric types, empty for others.
    public let minVal: String
    /// Maximum value for numeric types, empty for others.
    public let maxVal: String
    /// Allowed values for enum types, empty array for others.
    public let enumVals: [String]
    /// Current server-wide default (boot_val).
    public let bootVal: String
    /// Unit (e.g. "kB", "ms", "s", "min"), empty if unitless.
    public let unit: String
    /// Short description of the parameter.
    public let shortDesc: String
    /// The context in which this setting can be changed ("user" or "superuser").
    public let context: String
    /// Category for grouping (e.g. "Query Tuning / Planner Cost Constants").
    public let category: String

    public init(
        name: String, vartype: String, minVal: String, maxVal: String,
        enumVals: [String], bootVal: String, unit: String,
        shortDesc: String, context: String, category: String
    ) {
        self.name = name
        self.vartype = vartype
        self.minVal = minVal
        self.maxVal = maxVal
        self.enumVals = enumVals
        self.bootVal = bootVal
        self.unit = unit
        self.shortDesc = shortDesc
        self.context = context
        self.category = category
    }
}
