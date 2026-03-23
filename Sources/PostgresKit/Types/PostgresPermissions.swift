import Foundation

/// Represents the current role's effective permissions on a PostgreSQL server.
///
/// Fetched once at connection time via ``PostgresSecurityClient/currentPermissions()``
/// and cached on the connection session. The single query uses `pg_roles` and
/// `has_database_privilege()`, both available on PostgreSQL 12+.
public struct PostgresPermissions: Sendable, Equatable {

    // MARK: - Role Attributes

    /// The role has superuser privileges (full control).
    public let isSuperuser: Bool
    /// The role can create other roles.
    public let canCreateRole: Bool
    /// The role can create databases.
    public let canCreateDB: Bool
    /// The role can log in (is a login role, not a group role).
    public let canLogin: Bool
    /// The role can initiate streaming replication.
    public let isReplication: Bool
    /// The role bypasses row-level security policies.
    public let bypassRLS: Bool

    // MARK: - Database-Level Privileges

    /// The role has CREATE privilege on the current database.
    public let canCreateInCurrentDB: Bool

    // MARK: - Init

    public init(
        isSuperuser: Bool,
        canCreateRole: Bool,
        canCreateDB: Bool,
        canLogin: Bool,
        isReplication: Bool,
        bypassRLS: Bool,
        canCreateInCurrentDB: Bool
    ) {
        self.isSuperuser = isSuperuser
        self.canCreateRole = canCreateRole
        self.canCreateDB = canCreateDB
        self.canLogin = canLogin
        self.isReplication = isReplication
        self.bypassRLS = bypassRLS
        self.canCreateInCurrentDB = canCreateInCurrentDB
    }

    // MARK: - Convenience

    /// Can create, alter, or drop roles.
    public var canManageRoles: Bool { isSuperuser || canCreateRole }

    /// Can create new databases.
    public var canManageDatabases: Bool { isSuperuser || canCreateDB }

    /// Can install or drop extensions (superuser only).
    public var canManageExtensions: Bool { isSuperuser }

    /// Can run VACUUM FULL (requires table ownership or superuser).
    public var canVacuumFull: Bool { isSuperuser }

    /// Can run REINDEX on system catalogs (superuser only).
    public var canReindexSystem: Bool { isSuperuser }

    /// Can terminate other backends (superuser or pg_signal_backend role).
    public var canTerminateBackends: Bool { isSuperuser }

    /// Can create schemas in the current database.
    public var canCreateSchemas: Bool { isSuperuser || canCreateInCurrentDB }
}
