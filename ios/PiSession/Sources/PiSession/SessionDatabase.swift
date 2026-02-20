import Foundation
import GRDB

public final class SessionDatabase: Sendable {
    private let dbQueue: DatabaseQueue

    public init(path: String? = nil) throws {
        if let path = path {
            var config = Configuration()
            config.prepareDatabase { db in
                // Enable WAL mode for better concurrent performance
                try db.execute(sql: "PRAGMA journal_mode = WAL")
                try db.execute(sql: "PRAGMA synchronous = NORMAL")
                try db.execute(sql: "PRAGMA foreign_keys = ON")
            }
            dbQueue = try DatabaseQueue(path: path, configuration: config)
        } else {
            // In-memory database for testing
            dbQueue = try DatabaseQueue()
        }

        try migrate()
    }

    public var queue: DatabaseQueue { dbQueue }

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_create_tables") { db in
            // Sessions table
            try db.create(table: "sessions", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("model_provider", .text).notNull()
                t.column("model_id", .text).notNull()
                t.column("system_prompt", .text).notNull().defaults(to: "")
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }

            // Entries table (DAG nodes)
            try db.create(table: "entries", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("session_id", .text).notNull()
                    .references("sessions", onDelete: .cascade)
                t.column("parent_id", .text)
                    .references("entries", onDelete: .setNull)
                t.column("role", .text).notNull()
                t.column("content", .text).notNull()
                t.column("tool_calls", .text)
                t.column("tool_results", .text)
                t.column("thinking", .text)
                t.column("input_tokens", .integer).notNull().defaults(to: 0)
                t.column("output_tokens", .integer).notNull().defaults(to: 0)
                t.column("created_at", .datetime).notNull()
            }

            // Indexes
            try db.create(indexOn: "entries", columns: ["session_id"])
            try db.create(indexOn: "entries", columns: ["parent_id"])
            try db.create(indexOn: "sessions", columns: ["updated_at"])
        }

        try migrator.migrate(dbQueue)
    }
}
