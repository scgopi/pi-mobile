import Foundation
import GRDB
import Combine

public final class SessionRepository: Sendable {
    private let database: SessionDatabase

    public init(database: SessionDatabase) {
        self.database = database
    }

    // MARK: - Session Operations

    public func createSession(_ session: Session) throws {
        try database.queue.write { db in
            try session.insert(db)
        }
    }

    public func updateSession(_ session: Session) throws {
        try database.queue.write { db in
            try session.update(db)
        }
    }

    public func getSession(id: String) throws -> Session? {
        try database.queue.read { db in
            try Session.fetchOne(db, key: id)
        }
    }

    public func listSessions() throws -> [Session] {
        try database.queue.read { db in
            try Session
                .order(Session.Columns.updatedAt.desc)
                .fetchAll(db)
        }
    }

    public func deleteSession(id: String) throws {
        try database.queue.write { db in
            _ = try Session.deleteOne(db, key: id)
        }
    }

    // MARK: - Entry Operations

    public func addEntry(_ entry: Entry) throws {
        try database.queue.write { db in
            try entry.insert(db)
            // Update session's updated_at
            try db.execute(
                sql: "UPDATE sessions SET updated_at = ? WHERE id = ?",
                arguments: [entry.createdAt, entry.sessionId]
            )
        }
    }

    public func getEntry(id: String) throws -> Entry? {
        try database.queue.read { db in
            try Entry.fetchOne(db, key: id)
        }
    }

    /// Walk the DAG from a leaf entry to the root using a recursive CTE.
    public func getBranch(leafId: String) throws -> [Entry] {
        try database.queue.read { db in
            let sql = """
                WITH RECURSIVE branch AS (
                    SELECT * FROM entries WHERE id = ?
                    UNION ALL
                    SELECT e.* FROM entries e
                    INNER JOIN branch b ON e.id = b.parent_id
                )
                SELECT * FROM branch ORDER BY created_at ASC
                """
            return try Entry.fetchAll(db, sql: sql, arguments: [leafId])
        }
    }

    /// Find all leaf entries (entries with no children) for a session.
    public func listBranches(sessionId: String) throws -> [BranchInfo] {
        try database.queue.read { db in
            let sql = """
                SELECT e.id as leaf_id, e.content as last_content, e.created_at as last_updated,
                    (WITH RECURSIVE branch AS (
                        SELECT id, parent_id FROM entries WHERE id = e.id
                        UNION ALL
                        SELECT en.id, en.parent_id FROM entries en
                        INNER JOIN branch b ON en.id = b.parent_id
                    )
                    SELECT COUNT(*) FROM branch) as entry_count
                FROM entries e
                WHERE e.session_id = ?
                AND NOT EXISTS (
                    SELECT 1 FROM entries child WHERE child.parent_id = e.id
                )
                ORDER BY e.created_at DESC
                """

            let rows = try Row.fetchAll(db, sql: sql, arguments: [sessionId])
            return rows.map { row in
                BranchInfo(
                    leafId: row["leaf_id"],
                    entryCount: row["entry_count"],
                    lastContent: row["last_content"],
                    lastUpdated: row["last_updated"]
                )
            }
        }
    }

    /// Get entries for a branch starting from a new parent (switch branch).
    /// Returns the path from root to the specified entry.
    public func switchBranch(toLeafId leafId: String) throws -> [Entry] {
        return try getBranch(leafId: leafId)
    }

    /// Get all entries for a session (flat, ordered by creation time).
    public func allEntries(sessionId: String) throws -> [Entry] {
        try database.queue.read { db in
            try Entry
                .filter(Entry.Columns.sessionId == sessionId)
                .order(Entry.Columns.createdAt.asc)
                .fetchAll(db)
        }
    }

    /// Get the latest leaf entry for a session.
    public func latestLeaf(sessionId: String) throws -> Entry? {
        try database.queue.read { db in
            let sql = """
                SELECT e.* FROM entries e
                WHERE e.session_id = ?
                AND NOT EXISTS (
                    SELECT 1 FROM entries child WHERE child.parent_id = e.id
                )
                ORDER BY e.created_at DESC
                LIMIT 1
                """
            return try Entry.fetchOne(db, sql: sql, arguments: [sessionId])
        }
    }

    // MARK: - Reactive Observation

    /// Observe the session list for changes using GRDB's ValueObservation.
    public func observeSessions() -> ValueObservation<ValueReducers.Fetch<[Session]>> {
        ValueObservation.tracking { db in
            try Session
                .order(Session.Columns.updatedAt.desc)
                .fetchAll(db)
        }
    }

    /// Observe entries for a specific session.
    public func observeEntries(sessionId: String) -> ValueObservation<ValueReducers.Fetch<[Entry]>> {
        ValueObservation.tracking { db in
            try Entry
                .filter(Entry.Columns.sessionId == sessionId)
                .order(Entry.Columns.createdAt.asc)
                .fetchAll(db)
        }
    }
}
