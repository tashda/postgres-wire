import Foundation

/// PostgreSQL lock modes.
public enum PostgresLockMode: String, Sendable {
    case accessShare = "ACCESS SHARE"
    case rowShare = "ROW SHARE"
    case rowExclusive = "ROW EXCLUSIVE"
    case shareUpdateExclusive = "SHARE UPDATE EXCLUSIVE"
    case share = "SHARE"
    case shareRowExclusive = "SHARE ROW EXCLUSIVE"
    case exclusive = "EXCLUSIVE"
    case accessExclusive = "ACCESS EXCLUSIVE"
}
