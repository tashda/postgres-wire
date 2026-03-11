import Foundation
import PostgresWire

/// High-level database introspection and property discovery.
public extension PostgresDatabaseClient {
    /// Fetch comprehensive properties for a specific database.
    func fetchDatabaseProperties(name: String) async throws -> PostgresDatabaseProperties {
        let sql = """
            SELECT
                d.oid::text,
                d.datname,
                pg_catalog.pg_get_userbyid(d.datdba) AS owner,
                pg_catalog.pg_encoding_to_char(d.encoding) AS encoding,
                d.datcollate AS collation,
                d.datctype AS ctype,
                COALESCE(d.daticulocale, '') AS icu_locale,
                d.datconnlimit::text AS connection_limit,
                d.datistemplate::text AS is_template,
                d.datallowconn::text AS allow_connections,
                COALESCE(t.spcname, 'pg_default') AS tablespace,
                pg_catalog.pg_database_size(d.datname)::text AS size_bytes,
                (SELECT count(*)::text FROM pg_catalog.pg_stat_activity WHERE datname = d.datname) AS active_connections,
                COALESCE(pg_catalog.shobj_description(d.oid, 'pg_database'), '') AS description,
                COALESCE(d.datacl::text, '') AS acl
            FROM pg_catalog.pg_database d
            LEFT JOIN pg_catalog.pg_tablespace t ON t.oid = d.dattablespace
            WHERE d.datname = \(quoteLiteral(name))
            """

        let rows = try await simpleQuery(sql)
        var props: PostgresDatabaseProperties?
        for try await v in rows.decode((String, String, String, String, String, String, String, String, String, String, String, String, String, String, String).self) {
            props = PostgresDatabaseProperties(
                oid: v.0, name: v.1, owner: v.2, encoding: v.3, collation: v.4, ctype: v.5,
                icuLocale: v.6.isEmpty ? nil : v.6,
                connectionLimit: Int(v.7) ?? -1,
                isTemplate: v.8 == "t" || v.8 == "true",
                allowConnections: v.9 == "t" || v.9 == "true",
                tablespace: v.10,
                sizeBytes: Int64(v.11) ?? 0,
                activeConnections: Int(v.12) ?? 0,
                description: v.13.isEmpty ? nil : v.13,
                acl: v.14.isEmpty ? nil : v.14
            )
        }

        guard let result = props else {
            throw PostgresError.protocolError("Database '\(name)' not found")
        }
        return result
    }

    /// Fetch database-level configuration parameters.
    func fetchDatabaseParameters(databaseOid: String) async throws -> [PostgresDatabaseParameter] {
        let sql = """
            SELECT unnest(setconfig)::text AS setting
            FROM pg_catalog.pg_db_role_setting
            WHERE setdatabase = \(databaseOid)::oid AND setrole = 0
            """
        var params: [PostgresDatabaseParameter] = []
        let rows = try await simpleQuery(sql)
        for try await setting in rows.decode(String.self) {
            let parts = setting.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                params.append(PostgresDatabaseParameter(name: String(parts[0]), value: String(parts[1])))
            }
        }
        return params
    }

    /// List all available tablespaces.
    func listTablespaces() async throws -> [String] {
        var names: [String] = []
        let rows = try await simpleQuery("SELECT spcname FROM pg_catalog.pg_tablespace ORDER BY spcname")
        for try await name in rows.decode(String.self) { names.append(name) }
        return names
    }
}
