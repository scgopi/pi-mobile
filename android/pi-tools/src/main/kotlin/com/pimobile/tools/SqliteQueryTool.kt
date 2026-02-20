package com.pimobile.tools

import android.database.sqlite.SQLiteDatabase
import com.pimobile.agent.AgentToolResult
import com.pimobile.agent.Tool
import com.pimobile.agent.ToolResultDetails
import kotlinx.serialization.json.*

class SqliteQueryTool : Tool {

    override val name = "sqlite_query"
    override val description = "Execute SQL queries against a SQLite database. Supports SELECT queries, mutations, and schema introspection."
    override val parametersSchema = buildJsonObject {
        put("type", "object")
        putJsonObject("properties") {
            putJsonObject("database") {
                put("type", "string")
                put("description", "Path to the SQLite database file")
            }
            putJsonObject("query") {
                put("type", "string")
                put("description", "SQL query to execute")
            }
            putJsonObject("params") {
                put("type", "array")
                putJsonObject("items") { put("type", "string") }
                put("description", "Query parameters for parameterized queries")
            }
        }
        putJsonArray("required") { add("database"); add("query") }
    }

    override suspend fun execute(input: JsonObject): AgentToolResult {
        val dbPath = input["database"]?.jsonPrimitive?.contentOrNull
            ?: return AgentToolResult("", "Error: 'database' is required", isError = true)
        val query = input["query"]?.jsonPrimitive?.contentOrNull
            ?: return AgentToolResult("", "Error: 'query' is required", isError = true)
        val params = input["params"]?.jsonArray?.map {
            it.jsonPrimitive.contentOrNull ?: ""
        }?.toTypedArray() ?: emptyArray()

        var db: SQLiteDatabase? = null
        return try {
            db = SQLiteDatabase.openOrCreateDatabase(dbPath, null)
            val trimmedQuery = query.trim().uppercase()

            if (trimmedQuery.startsWith("SELECT") ||
                trimmedQuery.startsWith("PRAGMA") ||
                trimmedQuery.startsWith("WITH")
            ) {
                executeSelect(db, query, params)
            } else {
                executeMutation(db, query, params)
            }
        } catch (e: Exception) {
            AgentToolResult("", "SQLite error: ${e.message}", isError = true)
        } finally {
            db?.close()
        }
    }

    private fun executeSelect(db: SQLiteDatabase, query: String, params: Array<String>): AgentToolResult {
        val cursor = db.rawQuery(query, params)
        return try {
            val columns = (0 until cursor.columnCount).map { cursor.getColumnName(it) }
            val rows = mutableListOf<List<String>>()

            while (cursor.moveToNext()) {
                val row = (0 until cursor.columnCount).map { idx ->
                    when (cursor.getType(idx)) {
                        android.database.Cursor.FIELD_TYPE_NULL -> "NULL"
                        android.database.Cursor.FIELD_TYPE_INTEGER -> cursor.getLong(idx).toString()
                        android.database.Cursor.FIELD_TYPE_FLOAT -> cursor.getDouble(idx).toString()
                        android.database.Cursor.FIELD_TYPE_BLOB -> "[BLOB ${cursor.getBlob(idx).size} bytes]"
                        else -> cursor.getString(idx) ?: "NULL"
                    }
                }
                rows.add(row)
            }

            val output = buildString {
                appendLine("Columns: ${columns.joinToString(", ")}")
                appendLine("Rows: ${rows.size}")
                appendLine()
                if (rows.isNotEmpty()) {
                    val widths = columns.indices.map { col ->
                        maxOf(
                            columns[col].length,
                            rows.maxOfOrNull { it[col].length } ?: 0
                        )
                    }
                    appendLine(columns.mapIndexed { i, c -> c.padEnd(widths[i]) }.joinToString(" | "))
                    appendLine(widths.joinToString("-+-") { "-".repeat(it) })
                    for (row in rows) {
                        appendLine(row.mapIndexed { i, v -> v.padEnd(widths[i]) }.joinToString(" | "))
                    }
                }
            }

            AgentToolResult("", output, ToolResultDetails.Table(columns, rows))
        } finally {
            cursor.close()
        }
    }

    private fun executeMutation(db: SQLiteDatabase, query: String, params: Array<String>): AgentToolResult {
        db.execSQL(query, params)
        val cursor = db.rawQuery("SELECT changes()", null)
        val changes = if (cursor.moveToFirst()) cursor.getLong(0) else 0
        cursor.close()
        return AgentToolResult("", "Query executed successfully. Rows affected: $changes")
    }
}
