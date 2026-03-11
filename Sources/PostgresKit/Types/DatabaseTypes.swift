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
