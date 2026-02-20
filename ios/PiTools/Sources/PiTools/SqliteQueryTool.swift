import Foundation
import SQLite3
import PiAgentCore
import PiAI

public struct SqliteQueryTool: Tool, Sendable {
    public let name = "sqlite_query"
    public let description = "Execute SQL queries against a SQLite database. Returns tabular results for SELECT queries and row counts for mutations. Supports schema introspection."

    public init() {}

    public var parametersSchema: JSONValue {
        .object([
            "type": .string("object"),
            "required": .array([.string("database"), .string("query")]),
            "properties": .object([
                "database": .object([
                    "type": .string("string"),
                    "description": .string("Path to the SQLite database file"),
                ]),
                "query": .object([
                    "type": .string("string"),
                    "description": .string("SQL query to execute"),
                ]),
            ]),
        ])
    }

    public func execute(input: JSONValue) async throws -> AgentToolResult {
        guard let dbPath = input["database"]?.stringValue else {
            return AgentToolResult(output: "Error: 'database' parameter is required", isError: true)
        }
        guard let query = input["query"]?.stringValue else {
            return AgentToolResult(output: "Error: 'query' parameter is required", isError: true)
        }

        var db: OpaquePointer?
        let rc = sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        guard rc == SQLITE_OK, let db = db else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            sqlite3_close(db)
            return AgentToolResult(output: "Error opening database: \(msg)", isError: true)
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        let prepareRc = sqlite3_prepare_v2(db, query, -1, &stmt, nil)
        guard prepareRc == SQLITE_OK, let stmt = stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            return AgentToolResult(output: "SQL prepare error: \(msg)", isError: true)
        }
        defer { sqlite3_finalize(stmt) }

        let columnCount = sqlite3_column_count(stmt)
        let isSelect = query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().hasPrefix("SELECT")
            || query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().hasPrefix("PRAGMA")
            || query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().hasPrefix("WITH")

        if isSelect && columnCount > 0 {
            // Read column names
            var columns: [String] = []
            for i in 0..<columnCount {
                let colName = sqlite3_column_name(stmt, i).map { String(cString: $0) } ?? "col\(i)"
                columns.append(colName)
            }

            // Read rows
            var rows: [[String]] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                var row: [String] = []
                for i in 0..<columnCount {
                    let type = sqlite3_column_type(stmt, i)
                    let value: String
                    switch type {
                    case SQLITE_NULL:
                        value = "NULL"
                    case SQLITE_INTEGER:
                        value = String(sqlite3_column_int64(stmt, i))
                    case SQLITE_FLOAT:
                        value = String(sqlite3_column_double(stmt, i))
                    case SQLITE_TEXT:
                        value = String(cString: sqlite3_column_text(stmt, i))
                    case SQLITE_BLOB:
                        let bytes = sqlite3_column_bytes(stmt, i)
                        value = "[BLOB: \(bytes) bytes]"
                    default:
                        value = "?"
                    }
                    row.append(value)
                }
                rows.append(row)
            }

            // Format as table
            let header = columns.joined(separator: " | ")
            let separator = columns.map { String(repeating: "-", count: max($0.count, 4)) }.joined(separator: "-+-")
            let rowsStr = rows.map { $0.joined(separator: " | ") }.joined(separator: "\n")
            let output = "\(header)\n\(separator)\n\(rowsStr)\n\n\(rows.count) row(s)"

            return AgentToolResult(
                output: output,
                details: .table(columns: columns, rows: rows)
            )
        } else {
            // Execute mutation
            let stepRc = sqlite3_step(stmt)
            if stepRc != SQLITE_DONE && stepRc != SQLITE_ROW {
                let msg = String(cString: sqlite3_errmsg(db))
                return AgentToolResult(output: "SQL execution error: \(msg)", isError: true)
            }

            let changes = sqlite3_changes(db)
            return AgentToolResult(output: "Query executed successfully. \(changes) row(s) affected.")
        }
    }
}
