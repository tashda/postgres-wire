import PostgresWire

/// High-level schema summary discovery.
public extension PostgresDatabaseClient {
    /// Type of an object in the schema summary.
    enum SummaryObjectType: String, Sendable {
        case table = "BASE TABLE"
        case view = "VIEW"
        case materializedView = "MATERIALIZED VIEW"
        case function = "FUNCTION"
        case trigger = "TRIGGER"
    }

    /// A summary of a schema's contents.
    struct SchemaSummary: Sendable {

        public struct Object: Sendable {
            public let name: String
            public let type: SummaryObjectType
            public let columns: [PostgresColumnDetail]
            public let triggerAction: String?
            public let triggerTable: String?

            public init(name: String, type: SummaryObjectType, columns: [PostgresColumnDetail], triggerAction: String?, triggerTable: String?) {
                self.name = name
                self.type = type
                self.columns = columns
                self.triggerAction = triggerAction
                self.triggerTable = triggerTable
            }
        }
        public let schema: String
        public let objects: [Object]

        public init(schema: String, objects: [Object]) {
            self.schema = schema
            self.objects = objects
        }
    }

    /// Generate a summary of all objects within a schema.
    func schemaSummary(
        schema: String,
        progress: (@Sendable (SummaryObjectType, Int, Int) async -> Void)? = nil
    ) async throws -> SchemaSummary {
        let columnsByObject = try await columnsByTable(schema: schema)

        // Tables and views
        let tableSQL = """
            SELECT table_name, table_type FROM information_schema.tables
            WHERE table_schema = $1 AND table_type IN ('BASE TABLE', 'VIEW')
            ORDER BY table_type, table_name
            """
        let tableRows = try await withConnection { conn in
            try await conn.queryPreparedRows(tableSQL, binds: [toPGData(value: schema)])
        }
        var entries: [(String, SummaryObjectType)] = []
        for row in tableRows {
            let (name, rawType) = try row.decode((String, String).self)
            entries.append((name, rawType.uppercased() == "VIEW" ? .view : .table))
        }

        // Materialized views
        let matRows = try await withConnection { conn in
            try await conn.queryPreparedRows("SELECT matviewname FROM pg_matviews WHERE schemaname = $1 ORDER BY matviewname", binds: [toPGData(value: schema)])
        }
        let matNames: [String] = try matRows.map { try $0.decode(String.self) }

        // Functions
        let fnRows = try await withConnection { conn in
            try await conn.queryPreparedRows("SELECT routine_name FROM information_schema.routines WHERE specific_schema = $1 AND routine_type = 'FUNCTION' ORDER BY routine_name", binds: [toPGData(value: schema)])
        }
        let functionNames: [String] = try fnRows.map { try $0.decode(String.self) }

        // Triggers
        let trigSQL = """
            SELECT trigger_name, action_timing, event_manipulation, event_object_table
            FROM information_schema.triggers WHERE trigger_schema = $1 ORDER BY trigger_name
            """
        let trigRows = try await withConnection { conn in
            try await conn.queryPreparedRows(trigSQL, binds: [toPGData(value: schema)])
        }
        var triggerEntries: [(String, String, String, String)] = []
        for row in trigRows { triggerEntries.append(try row.decode((String, String, String, String).self)) }

        let total = max(entries.count + matNames.count + functionNames.count + triggerEntries.count, 1)
        var processed = 0
        var objects: [SchemaSummary.Object] = []

        for (name, type) in entries {
            processed += 1
            if let progress { await progress(type, processed, total) }
            objects.append(.init(name: name, type: type, columns: columnsByObject[name] ?? [], triggerAction: nil, triggerTable: nil))
        }

        for name in matNames {
            processed += 1
            if let progress { await progress(.materializedView, processed, total) }
            objects.append(.init(name: name, type: .materializedView, columns: columnsByObject[name] ?? [], triggerAction: nil, triggerTable: nil))
        }

        for name in functionNames {
            processed += 1
            if let progress { await progress(.function, processed, total) }
            objects.append(.init(name: name, type: .function, columns: [], triggerAction: nil, triggerTable: nil))
        }

        for (name, timing, action, table) in triggerEntries {
            processed += 1
            if let progress { await progress(.trigger, processed, total) }
            let actionDisplay = "\(timing.uppercased()) \(action.uppercased())".trimmingCharacters(in: .whitespaces)
            objects.append(.init(name: name, type: .trigger, columns: [], triggerAction: actionDisplay, triggerTable: "\(schema).\(table)"))
        }

        return SchemaSummary(schema: schema, objects: objects)
    }
}
