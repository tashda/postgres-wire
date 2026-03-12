import Foundation
import PostgresWire

/// High-level schema and object discovery.
public extension PostgresDatabaseClient {
    /// List all databases that are not templates.
    func listDatabases() async throws -> [String] {
        var names: [String] = []
        let rows = try await simpleQuery("SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname")
        for try await name in rows.decode(String.self) { names.append(name) }
        return names
    }

    /// Check if the current user has superuser privileges.
    func checkSuperuser() async throws -> Bool {
        let sql = "SELECT rolsuper FROM pg_roles WHERE rolname = current_user"
        let rows = try await simpleQuery(sql)
        for try await isSuper in rows.decode(Bool.self) {
            return isSuper
        }
        return false
    }

    /// List all user schemas.
    func listSchemas() async throws -> [PostgresSchemaInfo] {
        let sql = """
            SELECT n.nspname, r.rolname
            FROM pg_catalog.pg_namespace n
            JOIN pg_catalog.pg_roles r ON n.nspowner = r.oid
            WHERE n.nspname !~ '^pg_' AND n.nspname != 'information_schema'
            ORDER BY n.nspname
            """
        var results: [PostgresSchemaInfo] = []
        let rows = try await simpleQuery(sql)
        for try await v in rows.decode((String, String).self) {
            results.append(PostgresSchemaInfo(name: v.0, owner: v.1))
        }
        return results
    }

    /// List tables and views within a schema.
    func listTablesAndViews(schema: String) async throws -> [SchemaObject] {
        let sql = """
            SELECT table_schema, table_name, table_type
            FROM information_schema.tables
            WHERE table_schema = $1
            ORDER BY table_name
            """
        return try await withConnection { conn in
            let rows = try await conn.queryPreparedRows(sql, binds: [toPGData(value: schema)])
            var objects: [SchemaObject] = []
            for row in rows {
                let (s, n, t) = try row.decode((String, String, String).self)
                let kind: SchemaObjectKind
                switch t.uppercased() {
                case "BASE TABLE": kind = .table
                case "VIEW": kind = .view
                default: kind = .table
                }
                objects.append(SchemaObject(schema: s, name: n, kind: kind))
            }
            return objects
        }
    }

    /// List columns for a specific table or view.
    func listColumns(schema: String, table: String) async throws -> [PostgresColumnInfo] {
        let sql = """
            SELECT column_name, data_type, is_nullable, column_default
            FROM information_schema.columns
            WHERE table_schema = $1 AND table_name = $2
            ORDER BY ordinal_position
            """
        return try await withConnection { conn in
            let rows = try await conn.queryPreparedRows(sql, binds: [toPGData(value: schema), toPGData(value: table)])
            var out: [PostgresColumnInfo] = []
            for row in rows {
                let (name, dataType, nullable, defaultValue) = try row.decode((String, String, String, String?).self)
                out.append(PostgresColumnInfo(name: name, dataType: dataType, isNullable: nullable.uppercased() == "YES", defaultValue: defaultValue))
            }
            return out
        }
    }

    /// Fetch all column details for all tables in a schema.
    func columnsByTable(schema: String) async throws -> [String: [PostgresColumnDetail]] {
        struct ColRec { let name: String; let type: String; let nullable: Bool; let maxLength: Int?; let ordinal: Int }
        
        let results = try await withConnection { conn in
            var columnsByTable: [String: [ColRec]] = [:]
            var primaryKeysByTable: [String: Set<String>] = [:]
            var foreignKeysByTable: [String: [String: PostgresColumnDetail.ForeignKeyRef]] = [:]

            // Standard columns
            let colSql = """
                SELECT table_name, column_name, data_type, is_nullable::text,
                       character_maximum_length::text, ordinal_position::text
                FROM information_schema.columns
                WHERE table_schema = $1
                ORDER BY table_name, ordinal_position
                """
            let colRows = try await conn.queryPreparedRows(colSql, binds: [toPGData(value: schema)])
            for row in colRows {
                let (table, column, dataType, nullableText, maxLenText, ordinalText) = try row.decode((String, String, String, String, String?, String).self)
                let isNullable = nullableText.uppercased() == "YES" || nullableText.uppercased() == "TRUE" || nullableText == "1"
                let maxLen = maxLenText.flatMap { Int($0) }
                let ordinal = Int(ordinalText) ?? 0
                columnsByTable[table, default: []].append(ColRec(name: column, type: dataType, nullable: isNullable, maxLength: maxLen, ordinal: ordinal))
            }

            // Primary keys
            let pkSql = """
                SELECT tc.table_name, kcu.column_name
                FROM information_schema.table_constraints AS tc
                JOIN information_schema.key_column_usage AS kcu
                  ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
                WHERE tc.constraint_type = 'PRIMARY KEY' AND tc.table_schema = $1
                """
            let pkRows = try await conn.queryPreparedRows(pkSql, binds: [toPGData(value: schema)])
            for row in pkRows {
                let (table, column) = try row.decode((String, String).self)
                primaryKeysByTable[table, default: []].insert(column)
            }

            // Foreign keys
            let fkSql = """
                SELECT cls.relname AS table_name, att.attname AS column_name,
                       nsp_ref.nspname AS ref_schema, cls_ref.relname AS ref_table,
                       att_ref.attname AS ref_column, con.conname AS constraint_name
                FROM pg_constraint con
                JOIN pg_class cls ON cls.oid = con.conrelid
                JOIN pg_namespace nsp ON nsp.oid = cls.relnamespace
                JOIN pg_class cls_ref ON cls_ref.oid = con.confrelid
                JOIN pg_namespace nsp_ref ON nsp_ref.oid = cls_ref.relnamespace
                JOIN LATERAL generate_subscripts(con.conkey, 1) AS idx(pos) ON TRUE
                JOIN pg_attribute att ON att.attrelid = con.conrelid AND att.attnum = con.conkey[idx.pos]
                JOIN pg_attribute att_ref ON att_ref.attrelid = con.confrelid AND att_ref.attnum = con.confkey[idx.pos]
                WHERE con.contype = 'f' AND nsp.nspname = $1
                ORDER BY cls.relname, idx.pos
                """
            let fkRows = try await conn.queryPreparedRows(fkSql, binds: [toPGData(value: schema)])
            for row in fkRows {
                let (table, column, refSchema, refTable, refColumn, conname) = try row.decode((String, String, String, String, String, String).self)
                foreignKeysByTable[table, default: [:]][column] = PostgresColumnDetail.ForeignKeyRef(constraintName: conname, referencedSchema: refSchema, referencedTable: refTable, referencedColumn: refColumn)
            }

            // Materialized views
            let matSql = """
                SELECT c.relname, a.attname, pg_catalog.format_type(a.atttypid, a.atttypmod),
                       (NOT a.attnotnull)::text, a.attnum::text
                FROM pg_attribute a
                JOIN pg_class c ON c.oid = a.attrelid
                JOIN pg_namespace n ON n.oid = c.relnamespace
                WHERE n.nspname = $1 AND c.relkind = 'm' AND a.attnum > 0 AND NOT a.attisdropped
                ORDER BY c.relname, a.attnum
                """
            let matRows = try await conn.queryPreparedRows(matSql, binds: [toPGData(value: schema)])
            for row in matRows {
                let (table, column, dataType, nullableText, ordinalText) = try row.decode((String, String, String, String, String).self)
                let isNullable = nullableText.uppercased().hasPrefix("T") || nullableText == "1"
                let ordinal = Int(ordinalText) ?? 0
                columnsByTable[table, default: []].append(ColRec(name: column, type: dataType, nullable: isNullable, maxLength: nil, ordinal: ordinal))
            }
            
            return (columnsByTable, primaryKeysByTable, foreignKeysByTable)
        }

        var result: [String: [PostgresColumnDetail]] = [:]
        for (table, recs) in results.0 {
            let pkset = results.1[table] ?? []
            let fks = results.2[table] ?? [:]
            result[table] = recs.sorted { $0.ordinal < $1.ordinal }.map { r in
                PostgresColumnDetail(name: r.name, dataType: r.type, isNullable: r.nullable, maxLength: r.maxLength, isPrimaryKey: pkset.contains(r.name), foreignKey: fks[r.name])
            }
        }
        return result
    }

    /// List installed PostgreSQL extensions.
    func listExtensions() async throws -> [PostgresExtensionInfo] {
        let sql = """
            SELECT e.extname, n.nspname AS schema, e.extversion, e.extrelocatable
            FROM pg_extension e
            JOIN pg_namespace n ON n.oid = e.extnamespace
            ORDER BY e.extname
            """
        var out: [PostgresExtensionInfo] = []
        let rows = try await simpleQuery(sql)
        for try await (name, schema, version, reloc) in rows.decode((String, String, String, Bool).self) {
            out.append(PostgresExtensionInfo(name: name, schema: schema, version: version, relocatable: reloc))
        }
        return out
    }

    /// List all available PostgreSQL extensions (installed or not).
    func listAvailableExtensions() async throws -> [PostgresAvailableExtensionInfo] {
        let sql = """
            SELECT name, default_version, installed_version, comment
            FROM pg_available_extensions
            ORDER BY name
            """
        var out: [PostgresAvailableExtensionInfo] = []
        let rows = try await simpleQuery(sql)
        for try await (name, defVer, instVer, comment) in rows.decode((String, String, String?, String?).self) {
            out.append(PostgresAvailableExtensionInfo(name: name, defaultVersion: defVer, installedVersion: instVer, comment: comment))
        }
        return out
    }

    /// List all objects (tables, functions, types) owned by an extension.
    func listExtensionObjects(_ extensionName: String) async throws -> [PostgresExtensionObject] {
        let sql = """
            SELECT 
                n.nspname as schema,
                obj.objname as name,
                obj.objtype as type
            FROM (
                -- Tables, Views, Sequences, etc
                SELECT c.relnamespace, c.relname as objname, 
                       CASE c.relkind 
                         WHEN 'r' THEN 'TABLE' 
                         WHEN 'v' THEN 'VIEW' 
                         WHEN 'm' THEN 'MATERIALIZED VIEW' 
                         WHEN 'i' THEN 'INDEX' 
                         WHEN 'S' THEN 'SEQUENCE' 
                         ELSE 'OTHER' 
                       END as objtype,
                       c.oid
                FROM pg_class c
                UNION ALL
                -- Functions / Procedures
                SELECT p.pronamespace, p.proname, 'FUNCTION', p.oid
                FROM pg_proc p
                UNION ALL
                -- Types
                SELECT t.typnamespace, t.typname, 'TYPE', t.oid
                FROM pg_type t
            ) obj
            JOIN pg_depend d ON d.objid = obj.oid
            JOIN pg_extension e ON e.oid = d.refobjid
            JOIN pg_namespace n ON n.oid = obj.relnamespace
            WHERE d.refclassid = 'pg_extension'::regclass
              AND e.extname = $1
            ORDER BY n.nspname, obj.objname
            """
        var out: [PostgresExtensionObject] = []
        let rows = try await queryPreparedRows(sql, binds: [toPGData(value: extensionName)])
        for row in rows {
            let (schema, name, type) = try row.decode((String, String, String).self)
            out.append(PostgresExtensionObject(schema: schema, name: name, type: type))
        }
        return out
    }
}
