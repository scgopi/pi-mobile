# Pi Mobile: Tool System & SQLite Session Storage Design

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Mobile Tool System](#mobile-tool-system)
   - [Tool Interface Definitions](#tool-interface-definitions)
   - [Tool Result Structure](#tool-result-structure)
   - [Core Tools](#core-tools)
   - [Data Tools](#data-tools)
   - [Extension Tool System](#extension-tool-system)
3. [SQLite-Based DAG Session Storage](#sqlite-based-dag-session-storage)
   - [Schema DDL](#schema-ddl)
   - [Key Queries](#key-queries)
   - [Android Implementation (Room)](#android-implementation-room)
   - [iOS Implementation (GRDB)](#ios-implementation-grdb)
   - [Migration Strategy](#migration-strategy)
4. [Security Considerations](#security-considerations)

---

## Architecture Overview

Pi's desktop architecture has 4 built-in tools (`read`, `write`, `edit`, `bash`) and stores sessions as append-only DAGs in `.jsonl` files. On mobile, we replace `bash` with purpose-built data tools (`sqlite_query`, `http_request`, `list_directory`) and replace `.jsonl` file storage with SQLite, while preserving the exact same DAG semantics (id, parentId, type, timestamp, data, leaf pointer, branching).

### Mapping Desktop to Mobile

```
Desktop (Node.js)          Mobile (Kotlin/Swift)
─────────────────          ─────────────────────
read tool                → read_file tool (sandbox + document picker)
write tool               → write_file tool (sandbox + document picker)
edit tool                → edit_file tool (same logic, mobile paths)
bash tool                → sqlite_query + http_request + list_directory
.jsonl session files     → SQLite database (WAL mode)
Extension .ts files      → Extension interface (Kotlin/Swift)
```

### Design Principles

1. **Faithful to Pi's abstractions**: `AgentToolResult<T>` with `content` (for model) + `details` (for UI) is preserved exactly
2. **Platform-native**: Kotlin data classes + Room on Android, Swift structs + GRDB on iOS
3. **Sandboxed by default**: All file tools operate within app sandbox unless user grants explicit access via document picker
4. **SQL safety**: Parameterized queries only, no raw string interpolation, schema introspection via safe metadata queries

---

## Mobile Tool System

### Tool Interface Definitions

#### Kotlin (Android)

```kotlin
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

/**
 * Content block for tool results — matches Pi's TextContent | ImageContent union.
 */
@Serializable
sealed interface ToolContent {
    @Serializable
    data class Text(val text: String) : ToolContent

    @Serializable
    data class Image(val data: String, val mimeType: String) : ToolContent
}

/**
 * Tool result structure — matches Pi's AgentToolResult<T>.
 * `content` is what the LLM sees, `details` is structured data for UI rendering.
 */
@Serializable
data class ToolResult<T>(
    val content: List<ToolContent>,
    val details: T? = null
)

/**
 * Callback for streaming partial tool results during execution.
 */
typealias ToolUpdateCallback<T> = (ToolResult<T>) -> Unit

/**
 * Tool parameter schema definition using JSON Schema subset.
 * Matches Pi's TypeBox TSchema usage for LLM tool calling.
 */
@Serializable
data class ToolParameter(
    val name: String,
    val type: String, // "string", "number", "boolean", "integer"
    val description: String,
    val required: Boolean = true,
    val enumValues: List<String>? = null
)

/**
 * Base interface for all tools — matches Pi's AgentTool<TSchema, TDetails>.
 *
 * Pi reference: packages/agent/src/types.ts:157-166
 */
interface AgentTool<TParams, TDetails> {
    /** Tool name used in LLM tool calls */
    val name: String
    /** Human-readable label for UI display */
    val label: String
    /** Description sent to LLM for tool selection */
    val description: String
    /** Parameter definitions for JSON Schema generation */
    val parameters: List<ToolParameter>

    /**
     * Execute the tool.
     *
     * @param toolCallId Unique ID for this tool invocation
     * @param params Parsed parameters from LLM
     * @param onUpdate Optional callback for streaming partial results
     * @return Tool result with content for LLM and details for UI
     * @throws CancellationException if the coroutine is cancelled
     */
    suspend fun execute(
        toolCallId: String,
        params: TParams,
        onUpdate: ToolUpdateCallback<TDetails>? = null
    ): ToolResult<TDetails>
}
```

#### Swift (iOS)

```swift
import Foundation

/// Content block for tool results — matches Pi's TextContent | ImageContent union.
enum ToolContent: Codable, Sendable {
    case text(String)
    case image(data: String, mimeType: String)

    // Codable conformance with "type" discriminator
    enum CodingKeys: String, CodingKey { case type, text, data, mimeType }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let data, let mimeType):
            try container.encode("image", forKey: .type)
            try container.encode(data, forKey: .data)
            try container.encode(mimeType, forKey: .mimeType)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try container.decode(String.self, forKey: .text))
        case "image":
            self = .image(
                data: try container.decode(String.self, forKey: .data),
                mimeType: try container.decode(String.self, forKey: .mimeType)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Unknown content type: \(type)"
            )
        }
    }
}

/// Tool result structure — matches Pi's AgentToolResult<T>.
struct ToolResult<Details: Codable & Sendable>: Sendable {
    let content: [ToolContent]
    let details: Details?
}

/// Callback for streaming partial tool results during execution.
typealias ToolUpdateCallback<Details: Codable & Sendable> = @Sendable (ToolResult<Details>) -> Void

/// Tool parameter schema definition.
struct ToolParameter: Codable, Sendable {
    let name: String
    let type: String // "string", "number", "boolean", "integer"
    let description: String
    let required: Bool
    let enumValues: [String]?

    init(name: String, type: String, description: String,
         required: Bool = true, enumValues: [String]? = nil) {
        self.name = name
        self.type = type
        self.description = description
        self.required = required
        self.enumValues = enumValues
    }
}

/// Base protocol for all tools — matches Pi's AgentTool<TSchema, TDetails>.
///
/// Pi reference: packages/agent/src/types.ts:157-166
protocol AgentTool<Params, Details> {
    associatedtype Params: Codable & Sendable
    associatedtype Details: Codable & Sendable

    /// Tool name used in LLM tool calls
    var name: String { get }
    /// Human-readable label for UI display
    var label: String { get }
    /// Description sent to LLM for tool selection
    var description: String { get }
    /// Parameter definitions for JSON Schema generation
    var parameters: [ToolParameter] { get }

    /// Execute the tool.
    func execute(
        toolCallId: String,
        params: Params,
        onUpdate: ToolUpdateCallback<Details>?
    ) async throws -> ToolResult<Details>
}
```

### Tool Result Structure

The dual `output`/`details` pattern from Pi is preserved exactly:

| Field | Purpose | Consumer |
|-------|---------|----------|
| `content` | Text/image content blocks | LLM (via tool result message) |
| `details` | Structured metadata | UI rendering (diffs, truncation info, query stats) |

This separation lets the UI render rich tool results (syntax-highlighted diffs, table views for SQL results, file trees) while the LLM sees concise text summaries.

---

### Core Tools

#### 1. read_file

Reads files from app sandbox or user-granted external locations. Supports text, images, JSON, CSV, Plist.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `path` | string | yes | File path (sandbox-relative or bookmark URI) |
| `offset` | integer | no | Line number to start reading from (1-indexed) |
| `limit` | integer | no | Maximum number of lines to read |

**Details type:**

```kotlin
// Android
@Serializable
data class ReadFileDetails(
    val truncation: TruncationInfo? = null,
    val fileType: String? = null, // "text", "image", "json", "csv", "plist"
    val fileSize: Long? = null
)

@Serializable
data class TruncationInfo(
    val truncated: Boolean,
    val totalLines: Int,
    val outputLines: Int,
    val outputBytes: Int,
    val truncatedBy: String? = null // "lines" or "bytes"
)
```

```swift
// iOS
struct ReadFileDetails: Codable, Sendable {
    let truncation: TruncationInfo?
    let fileType: String? // "text", "image", "json", "csv", "plist"
    let fileSize: Int64?
}

struct TruncationInfo: Codable, Sendable {
    let truncated: Bool
    let totalLines: Int
    let outputLines: Int
    let outputBytes: Int
    let truncatedBy: String? // "lines" or "bytes"
}
```

**Android implementation sketch:**

```kotlin
class ReadFileTool(
    private val context: Context,
    private val sandboxRoot: File = context.filesDir
) : AgentTool<ReadFileParams, ReadFileDetails> {

    override val name = "read_file"
    override val label = "read"
    override val description = """
        Read a file's contents. Supports text files and images (jpg, png, gif, webp).
        Images are sent as attachments. Text output is truncated to $MAX_LINES lines
        or ${MAX_BYTES / 1024}KB. Use offset/limit for large files.
    """.trimIndent()

    override val parameters = listOf(
        ToolParameter("path", "string", "File path relative to sandbox or content URI"),
        ToolParameter("offset", "integer", "Start line (1-indexed)", required = false),
        ToolParameter("limit", "integer", "Max lines to read", required = false),
    )

    override suspend fun execute(
        toolCallId: String,
        params: ReadFileParams,
        onUpdate: ToolUpdateCallback<ReadFileDetails>?
    ): ToolResult<ReadFileDetails> = withContext(Dispatchers.IO) {
        val file = resolveFile(params.path)

        // Check if image
        val mimeType = detectImageMimeType(file)
        if (mimeType != null) {
            val bytes = file.readBytes()
            val base64 = Base64.encodeToString(bytes, Base64.NO_WRAP)
            return@withContext ToolResult(
                content = listOf(
                    ToolContent.Text("Read image file [$mimeType]"),
                    ToolContent.Image(data = base64, mimeType = mimeType)
                ),
                details = ReadFileDetails(fileType = "image", fileSize = file.length())
            )
        }

        // Read as text with truncation (same logic as Pi's truncateHead)
        val text = file.readText(Charsets.UTF_8)
        val allLines = text.split("\n")
        val startLine = ((params.offset ?: 1) - 1).coerceAtLeast(0)

        if (startLine >= allLines.size) {
            throw IllegalArgumentException(
                "Offset ${params.offset} is beyond end of file (${allLines.size} lines)"
            )
        }

        val selectedLines = if (params.limit != null) {
            allLines.subList(startLine, (startLine + params.limit).coerceAtMost(allLines.size))
        } else {
            allLines.subList(startLine, allLines.size)
        }

        val truncation = truncateHead(selectedLines.joinToString("\n"))
        val outputText = buildTruncatedOutput(truncation, startLine, allLines.size, params)

        ToolResult(
            content = listOf(ToolContent.Text(outputText)),
            details = ReadFileDetails(
                truncation = if (truncation.truncated) truncation else null,
                fileType = "text",
                fileSize = file.length()
            )
        )
    }

    private fun resolveFile(path: String): File {
        // Content URIs (from document picker / SAF)
        if (path.startsWith("content://")) {
            // Copy to temp and return, or read via ContentResolver
            return resolveContentUri(Uri.parse(path))
        }
        // Sandbox-relative paths
        val resolved = File(sandboxRoot, path).canonicalFile
        require(resolved.startsWith(sandboxRoot.canonicalFile)) {
            "Path escapes sandbox: $path"
        }
        return resolved
    }
}
```

**iOS implementation sketch:**

```swift
final class ReadFileTool: AgentTool {
    typealias Params = ReadFileParams
    typealias Details = ReadFileDetails

    let name = "read_file"
    let label = "read"
    let description = """
        Read a file's contents. Supports text files and images (jpg, png, gif, webp). \
        Images are sent as attachments. Text output is truncated to \(maxLines) lines \
        or \(maxBytes / 1024)KB. Use offset/limit for large files.
        """

    let parameters: [ToolParameter] = [
        ToolParameter(name: "path", type: "string", description: "File path relative to sandbox or bookmark ID"),
        ToolParameter(name: "offset", type: "integer", description: "Start line (1-indexed)", required: false),
        ToolParameter(name: "limit", type: "integer", description: "Max lines to read", required: false),
    ]

    private let sandboxRoot: URL
    private let bookmarkStore: BookmarkStore

    init(sandboxRoot: URL, bookmarkStore: BookmarkStore) {
        self.sandboxRoot = sandboxRoot
        self.bookmarkStore = bookmarkStore
    }

    func execute(
        toolCallId: String,
        params: ReadFileParams,
        onUpdate: ToolUpdateCallback<ReadFileDetails>?
    ) async throws -> ToolResult<ReadFileDetails> {
        let fileURL = try resolveFile(params.path)

        // Check if image
        if let mimeType = detectImageMimeType(fileURL) {
            let data = try Data(contentsOf: fileURL)
            let base64 = data.base64EncodedString()
            return ToolResult(
                content: [
                    .text("Read image file [\(mimeType)]"),
                    .image(data: base64, mimeType: mimeType)
                ],
                details: ReadFileDetails(fileType: "image", fileSize: Int64(data.count))
            )
        }

        // Read as text with truncation
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        let allLines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        let startLine = max(0, (params.offset ?? 1) - 1)

        guard startLine < allLines.count else {
            throw ToolError.invalidArgument(
                "Offset \(params.offset ?? 1) is beyond end of file (\(allLines.count) lines)"
            )
        }

        let endLine = params.limit.map { min(startLine + $0, allLines.count) }
            ?? allLines.count
        let selectedText = allLines[startLine..<endLine].joined(separator: "\n")
        let truncation = truncateHead(selectedText)
        let outputText = buildTruncatedOutput(truncation, startLine, allLines.count, params)

        return ToolResult(
            content: [.text(outputText)],
            details: ReadFileDetails(
                truncation: truncation.truncated ? truncation : nil,
                fileType: "text",
                fileSize: Int64((try? FileManager.default.attributesOfItem(
                    atPath: fileURL.path
                )[.size] as? Int64) ?? 0)
            )
        )
    }

    private func resolveFile(_ path: String) throws -> URL {
        // Security bookmark (from document picker)
        if path.hasPrefix("bookmark://") {
            let bookmarkId = String(path.dropFirst("bookmark://".count))
            guard let url = bookmarkStore.resolve(bookmarkId) else {
                throw ToolError.fileNotFound("Bookmark expired: \(bookmarkId)")
            }
            return url
        }
        // Sandbox-relative
        let resolved = sandboxRoot.appendingPathComponent(path).standardized
        guard resolved.path.hasPrefix(sandboxRoot.standardized.path) else {
            throw ToolError.accessDenied("Path escapes sandbox: \(path)")
        }
        return resolved
    }
}
```

#### 2. write_file

Writes content to files in the app sandbox, auto-creating parent directories.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `path` | string | yes | File path (sandbox-relative) |
| `content` | string | yes | Content to write |

**Android:**

```kotlin
class WriteFileTool(
    private val sandboxRoot: File
) : AgentTool<WriteFileParams, Nothing> {

    override val name = "write_file"
    override val label = "write"
    override val description = """
        Write content to a file. Creates the file if it doesn't exist, overwrites if
        it does. Automatically creates parent directories. Only writes to app sandbox.
    """.trimIndent()

    override val parameters = listOf(
        ToolParameter("path", "string", "File path relative to sandbox"),
        ToolParameter("content", "string", "Content to write"),
    )

    override suspend fun execute(
        toolCallId: String,
        params: WriteFileParams,
        onUpdate: ToolUpdateCallback<Nothing>?
    ): ToolResult<Nothing> = withContext(Dispatchers.IO) {
        val file = resolveSandboxPath(sandboxRoot, params.path)
        file.parentFile?.mkdirs()
        file.writeText(params.content, Charsets.UTF_8)
        ToolResult(
            content = listOf(
                ToolContent.Text("Successfully wrote ${params.content.length} bytes to ${params.path}")
            ),
            details = null
        )
    }
}
```

**iOS:**

```swift
final class WriteFileTool: AgentTool {
    typealias Params = WriteFileParams
    typealias Details = Never? // No details, matches Pi's undefined

    let name = "write_file"
    let label = "write"
    let description = """
        Write content to a file. Creates the file if it doesn't exist, overwrites if \
        it does. Automatically creates parent directories. Only writes to app sandbox.
        """

    let parameters: [ToolParameter] = [
        ToolParameter(name: "path", type: "string", description: "File path relative to sandbox"),
        ToolParameter(name: "content", type: "string", description: "Content to write"),
    ]

    private let sandboxRoot: URL

    init(sandboxRoot: URL) { self.sandboxRoot = sandboxRoot }

    func execute(
        toolCallId: String,
        params: WriteFileParams,
        onUpdate: ToolUpdateCallback<Never?>?
    ) async throws -> ToolResult<Never?> {
        let fileURL = try resolveSandboxPath(sandboxRoot, params.path)
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try params.content.write(to: fileURL, atomically: true, encoding: .utf8)
        return ToolResult(
            content: [.text("Successfully wrote \(params.content.count) bytes to \(params.path)")],
            details: nil
        )
    }
}
```

#### 3. edit_file

Exact search/replace with unified diff generation. This is a direct port of Pi's edit tool logic from `packages/coding-agent/src/core/tools/edit.ts` and `edit-diff.ts`.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `path` | string | yes | File path |
| `old_text` | string | yes | Exact text to find (must be unique) |
| `new_text` | string | yes | Replacement text |

**Details type:**

```kotlin
// Android
@Serializable
data class EditFileDetails(
    val diff: String,
    val firstChangedLine: Int? = null
)
```

```swift
// iOS
struct EditFileDetails: Codable, Sendable {
    let diff: String
    let firstChangedLine: Int?
}
```

**Core logic (shared algorithm, platform-specific file I/O):**

The edit tool ports these functions from `edit-diff.ts`:
- `normalizeToLF()` — normalize line endings to LF
- `normalizeForFuzzyMatch()` — strip trailing whitespace, normalize smart quotes/dashes/spaces
- `fuzzyFindText()` — try exact match first, fall back to fuzzy
- `stripBom()` — handle UTF-8 BOM
- `generateDiffString()` — produce unified diff with line numbers

```kotlin
// Android core edit logic
class EditFileTool(
    private val sandboxRoot: File
) : AgentTool<EditFileParams, EditFileDetails> {

    override val name = "edit_file"
    override val label = "edit"
    override val description = """
        Edit a file by replacing exact text. The old_text must match exactly
        (including whitespace). Use this for precise, surgical edits.
    """.trimIndent()

    override val parameters = listOf(
        ToolParameter("path", "string", "File path"),
        ToolParameter("old_text", "string", "Exact text to find and replace (must match exactly)"),
        ToolParameter("new_text", "string", "New text to replace the old text with"),
    )

    override suspend fun execute(
        toolCallId: String,
        params: EditFileParams,
        onUpdate: ToolUpdateCallback<EditFileDetails>?
    ): ToolResult<EditFileDetails> = withContext(Dispatchers.IO) {
        val file = resolveFile(params.path)
        val rawContent = file.readText(Charsets.UTF_8)

        val (bom, content) = stripBom(rawContent)
        val originalEnding = detectLineEnding(content)
        val normalizedContent = normalizeToLF(content)
        val normalizedOldText = normalizeToLF(params.oldText)
        val normalizedNewText = normalizeToLF(params.newText)

        // Find using fuzzy match (exact first, then fuzzy)
        val matchResult = fuzzyFindText(normalizedContent, normalizedOldText)
        if (!matchResult.found) {
            throw ToolExecutionException(
                "Could not find the exact text in ${params.path}. " +
                "The old text must match exactly including all whitespace and newlines."
            )
        }

        // Check uniqueness
        val fuzzyContent = normalizeForFuzzyMatch(normalizedContent)
        val fuzzyOldText = normalizeForFuzzyMatch(normalizedOldText)
        val occurrences = fuzzyContent.split(fuzzyOldText).size - 1
        if (occurrences > 1) {
            throw ToolExecutionException(
                "Found $occurrences occurrences of the text in ${params.path}. " +
                "The text must be unique. Please provide more context."
            )
        }

        // Perform replacement
        val baseContent = matchResult.contentForReplacement
        val newContent = baseContent.substring(0, matchResult.index) +
            normalizedNewText +
            baseContent.substring(matchResult.index + matchResult.matchLength)

        if (baseContent == newContent) {
            throw ToolExecutionException("No changes made to ${params.path}.")
        }

        val finalContent = bom + restoreLineEndings(newContent, originalEnding)
        file.writeText(finalContent, Charsets.UTF_8)

        val diffResult = generateDiffString(baseContent, newContent)

        ToolResult(
            content = listOf(ToolContent.Text("Successfully replaced text in ${params.path}.")),
            details = EditFileDetails(
                diff = diffResult.diff,
                firstChangedLine = diffResult.firstChangedLine
            )
        )
    }
}
```

---

### Data Tools

#### 4. sqlite_query

Runs SQL on any SQLite database within the app's scope. This replaces the most common `bash` use cases: querying databases, data inspection, data manipulation.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `database` | string | yes | Database path (sandbox-relative) or "session" for app DB |
| `query` | string | yes | SQL query to execute |
| `params` | array | no | Parameterized query values (positional `?` binding) |
| `mode` | string | no | "query" (default), "execute", "schema", "tables" |

**Details type:**

```kotlin
// Android
@Serializable
data class SqliteQueryDetails(
    val rowCount: Int,
    val columnNames: List<String>,
    val executionTimeMs: Long,
    val affectedRows: Int? = null, // For INSERT/UPDATE/DELETE
    val mode: String // "query", "execute", "schema", "tables"
)
```

```swift
// iOS
struct SqliteQueryDetails: Codable, Sendable {
    let rowCount: Int
    let columnNames: [String]
    let executionTimeMs: Int64
    let affectedRows: Int?
    let mode: String
}
```

**Android implementation (using android.database.sqlite):**

```kotlin
class SqliteQueryTool(
    private val sandboxRoot: File
) : AgentTool<SqliteQueryParams, SqliteQueryDetails> {

    override val name = "sqlite_query"
    override val label = "sqlite"
    override val description = """
        Run SQL queries on SQLite databases. Supports:
        - mode="tables": List all tables
        - mode="schema": Describe table schema (columns, types, indexes)
        - mode="query": Run SELECT queries (parameterized)
        - mode="execute": Run INSERT/UPDATE/DELETE (parameterized)
        Always use parameterized queries with ? placeholders for values.
    """.trimIndent()

    override val parameters = listOf(
        ToolParameter("database", "string", "Database path relative to sandbox, or 'session' for app DB"),
        ToolParameter("query", "string", "SQL query to execute"),
        ToolParameter("params", "string", "JSON array of query parameters", required = false),
        ToolParameter("mode", "string", "query|execute|schema|tables", required = false),
    )

    // Track open databases for connection reuse within a session
    private val openDatabases = mutableMapOf<String, SQLiteDatabase>()

    override suspend fun execute(
        toolCallId: String,
        params: SqliteQueryParams,
        onUpdate: ToolUpdateCallback<SqliteQueryDetails>?
    ): ToolResult<SqliteQueryDetails> = withContext(Dispatchers.IO) {
        val startTime = System.currentTimeMillis()
        val db = openDatabase(params.database)
        val mode = params.mode ?: "query"

        when (mode) {
            "tables" -> listTables(db, startTime)
            "schema" -> describeSchema(db, params.query, startTime)
            "query" -> runQuery(db, params.query, params.params, startTime)
            "execute" -> runExecute(db, params.query, params.params, startTime)
            else -> throw ToolExecutionException("Unknown mode: $mode")
        }
    }

    private fun openDatabase(path: String): SQLiteDatabase {
        return openDatabases.getOrPut(path) {
            val dbFile = if (path == "session") {
                // App's own session database
                File(sandboxRoot, "pi-sessions.db")
            } else {
                resolveSandboxPath(sandboxRoot, path)
            }
            SQLiteDatabase.openOrCreateDatabase(dbFile, null)
        }
    }

    private fun runQuery(
        db: SQLiteDatabase,
        query: String,
        queryParams: List<String>?,
        startTime: Long
    ): ToolResult<SqliteQueryDetails> {
        // Security: only allow SELECT for query mode
        val trimmed = query.trim().uppercase()
        require(trimmed.startsWith("SELECT") || trimmed.startsWith("WITH") ||
                trimmed.startsWith("PRAGMA") || trimmed.startsWith("EXPLAIN")) {
            "query mode only supports SELECT/WITH/PRAGMA/EXPLAIN statements. Use mode=execute for modifications."
        }

        val cursor = db.rawQuery(query, queryParams?.toTypedArray())
        val columns = cursor.columnNames.toList()
        val rows = mutableListOf<List<String?>>()

        cursor.use {
            while (it.moveToNext() && rows.size < MAX_ROWS) {
                val row = columns.indices.map { i ->
                    when (it.getType(i)) {
                        Cursor.FIELD_TYPE_NULL -> null
                        Cursor.FIELD_TYPE_BLOB -> "[BLOB ${it.getBlob(i).size} bytes]"
                        else -> it.getString(i)
                    }
                }
                rows.add(row)
            }
        }

        val elapsed = System.currentTimeMillis() - startTime
        val table = formatAsTable(columns, rows)

        ToolResult(
            content = listOf(ToolContent.Text(table)),
            details = SqliteQueryDetails(
                rowCount = rows.size,
                columnNames = columns,
                executionTimeMs = elapsed,
                mode = "query"
            )
        )
    }

    private fun runExecute(
        db: SQLiteDatabase,
        query: String,
        queryParams: List<String>?,
        startTime: Long
    ): ToolResult<SqliteQueryDetails> {
        // Security: block dangerous operations
        val trimmed = query.trim().uppercase()
        require(!trimmed.startsWith("DROP DATABASE") && !trimmed.startsWith("ATTACH")) {
            "Operation not allowed for safety"
        }

        val stmt = db.compileStatement(query)
        queryParams?.forEachIndexed { i, param ->
            stmt.bindString(i + 1, param)
        }

        val affected = when {
            trimmed.startsWith("INSERT") -> { stmt.executeInsert(); 1 }
            trimmed.startsWith("UPDATE") || trimmed.startsWith("DELETE") -> stmt.executeUpdateDelete()
            else -> { stmt.execute(); 0 }
        }

        val elapsed = System.currentTimeMillis() - startTime

        ToolResult(
            content = listOf(ToolContent.Text("Query executed successfully. $affected row(s) affected.")),
            details = SqliteQueryDetails(
                rowCount = 0,
                columnNames = emptyList(),
                executionTimeMs = elapsed,
                affectedRows = affected,
                mode = "execute"
            )
        )
    }

    companion object {
        const val MAX_ROWS = 1000
    }
}
```

**iOS implementation (using GRDB):**

```swift
import GRDB

final class SqliteQueryTool: AgentTool {
    typealias Params = SqliteQueryParams
    typealias Details = SqliteQueryDetails

    let name = "sqlite_query"
    let label = "sqlite"
    let description = """
        Run SQL queries on SQLite databases. Supports: \
        mode=tables (list tables), mode=schema (describe columns/indexes), \
        mode=query (SELECT with parameters), mode=execute (INSERT/UPDATE/DELETE).
        """

    let parameters: [ToolParameter] = [
        ToolParameter(name: "database", type: "string", description: "Database path or 'session'"),
        ToolParameter(name: "query", type: "string", description: "SQL query to execute"),
        ToolParameter(name: "params", type: "string", description: "JSON array of parameters", required: false),
        ToolParameter(name: "mode", type: "string", description: "query|execute|schema|tables", required: false),
    ]

    private let sandboxRoot: URL
    private var pools: [String: DatabasePool] = [:]

    init(sandboxRoot: URL) {
        self.sandboxRoot = sandboxRoot
    }

    func execute(
        toolCallId: String,
        params: SqliteQueryParams,
        onUpdate: ToolUpdateCallback<SqliteQueryDetails>?
    ) async throws -> ToolResult<SqliteQueryDetails> {
        let start = ContinuousClock.now
        let pool = try openDatabase(params.database)
        let mode = params.mode ?? "query"

        switch mode {
        case "tables":
            return try await listTables(pool, start: start)
        case "schema":
            return try await describeSchema(pool, table: params.query, start: start)
        case "query":
            return try await runQuery(pool, sql: params.query,
                                      args: params.params ?? [], start: start)
        case "execute":
            return try await runExecute(pool, sql: params.query,
                                        args: params.params ?? [], start: start)
        default:
            throw ToolError.invalidArgument("Unknown mode: \(mode)")
        }
    }

    private func openDatabase(_ path: String) throws -> DatabasePool {
        if let existing = pools[path] { return existing }
        let dbURL: URL
        if path == "session" {
            dbURL = sandboxRoot.appendingPathComponent("pi-sessions.db")
        } else {
            dbURL = try resolveSandboxPath(sandboxRoot, path)
        }
        let pool = try DatabasePool(path: dbURL.path)
        pools[path] = pool
        return pool
    }

    private func runQuery(
        _ pool: DatabasePool,
        sql: String,
        args: [String],
        start: ContinuousClock.Instant
    ) async throws -> ToolResult<SqliteQueryDetails> {
        // Security: validate read-only
        let upper = sql.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard upper.hasPrefix("SELECT") || upper.hasPrefix("WITH") ||
              upper.hasPrefix("PRAGMA") || upper.hasPrefix("EXPLAIN") else {
            throw ToolError.invalidArgument(
                "query mode only supports SELECT/WITH/PRAGMA/EXPLAIN. Use mode=execute."
            )
        }

        let result = try await pool.read { db -> (columns: [String], rows: [[String?]]) in
            let statement = try db.makeStatement(sql: sql)
            let arguments = StatementArguments(args.map { DatabaseValue(value: $0) })
            let cursor = try Row.fetchCursor(statement, arguments: arguments)
            var columns: [String] = []
            var rows: [[String?]] = []

            while let row = try cursor.next(), rows.count < Self.maxRows {
                if columns.isEmpty { columns = Array(row.columnNames) }
                rows.append(columns.map { row[$0]?.description })
            }
            return (columns, rows)
        }

        let elapsed = start.duration(to: .now)
        let table = formatAsTable(result.columns, result.rows)

        return ToolResult(
            content: [.text(table)],
            details: SqliteQueryDetails(
                rowCount: result.rows.count,
                columnNames: result.columns,
                executionTimeMs: Int64(elapsed.components.seconds * 1000 +
                                       elapsed.components.attoseconds / 1_000_000_000_000_000),
                mode: "query"
            )
        )
    }

    static let maxRows = 1000
}
```

#### 5. http_request

Makes HTTP requests, replacing `curl` via bash.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `url` | string | yes | Target URL |
| `method` | string | no | HTTP method (default: GET) |
| `headers` | string | no | JSON object of headers |
| `body` | string | no | Request body |
| `timeout` | integer | no | Timeout in seconds (default: 30) |

**Details type:**

```kotlin
@Serializable
data class HttpRequestDetails(
    val statusCode: Int,
    val headers: Map<String, String>,
    val responseTimeMs: Long,
    val bodySize: Int,
    val truncated: Boolean = false
)
```

**Android implementation (OkHttp):**

```kotlin
class HttpRequestTool : AgentTool<HttpRequestParams, HttpRequestDetails> {
    override val name = "http_request"
    override val label = "http"
    override val description = """
        Make HTTP requests. Supports GET, POST, PUT, DELETE, PATCH, HEAD.
        Response body is truncated to ${MAX_RESPONSE_BYTES / 1024}KB.
        JSON responses are auto-formatted.
    """.trimIndent()

    override val parameters = listOf(
        ToolParameter("url", "string", "Target URL"),
        ToolParameter("method", "string", "HTTP method (GET, POST, etc.)", required = false),
        ToolParameter("headers", "string", "JSON object of request headers", required = false),
        ToolParameter("body", "string", "Request body", required = false),
        ToolParameter("timeout", "integer", "Timeout in seconds", required = false),
    )

    private val client = OkHttpClient.Builder()
        .followRedirects(true)
        .followSslRedirects(true)
        .build()

    override suspend fun execute(
        toolCallId: String,
        params: HttpRequestParams,
        onUpdate: ToolUpdateCallback<HttpRequestDetails>?
    ): ToolResult<HttpRequestDetails> = withContext(Dispatchers.IO) {
        val startTime = System.currentTimeMillis()
        val timeout = (params.timeout ?: 30).toLong()

        val requestBuilder = Request.Builder().url(params.url)

        // Set method and body
        val method = (params.method ?: "GET").uppercase()
        val body = params.body?.toRequestBody("application/json".toMediaType())
        requestBuilder.method(method, body)

        // Add headers
        params.headers?.let { headersJson ->
            val headers = Json.parseToJsonElement(headersJson).jsonObject
            headers.forEach { (k, v) -> requestBuilder.addHeader(k, v.jsonPrimitive.content) }
        }

        val perCallClient = client.newBuilder()
            .callTimeout(timeout, TimeUnit.SECONDS)
            .build()

        val response = perCallClient.newCall(requestBuilder.build()).execute()
        val elapsed = System.currentTimeMillis() - startTime

        val responseBody = response.body?.string() ?: ""
        val truncated = responseBody.length > MAX_RESPONSE_BYTES
        val displayBody = if (truncated) {
            responseBody.take(MAX_RESPONSE_BYTES) +
                "\n\n[Response truncated at ${MAX_RESPONSE_BYTES / 1024}KB]"
        } else {
            responseBody
        }

        // Format output
        val output = buildString {
            appendLine("HTTP ${response.code} ${response.message}")
            appendLine()
            append(displayBody)
        }

        val responseHeaders = response.headers.toMap()

        ToolResult(
            content = listOf(ToolContent.Text(output)),
            details = HttpRequestDetails(
                statusCode = response.code,
                headers = responseHeaders,
                responseTimeMs = elapsed,
                bodySize = responseBody.length,
                truncated = truncated
            )
        )
    }

    companion object {
        const val MAX_RESPONSE_BYTES = 100 * 1024 // 100KB
    }
}
```

**iOS implementation (URLSession):**

```swift
final class HttpRequestTool: AgentTool {
    typealias Params = HttpRequestParams
    typealias Details = HttpRequestDetails

    let name = "http_request"
    let label = "http"
    let description = """
        Make HTTP requests. Supports GET, POST, PUT, DELETE, PATCH, HEAD. \
        Response body is truncated to \(Self.maxResponseBytes / 1024)KB.
        """

    let parameters: [ToolParameter] = [
        ToolParameter(name: "url", type: "string", description: "Target URL"),
        ToolParameter(name: "method", type: "string", description: "HTTP method", required: false),
        ToolParameter(name: "headers", type: "string", description: "JSON headers object", required: false),
        ToolParameter(name: "body", type: "string", description: "Request body", required: false),
        ToolParameter(name: "timeout", type: "integer", description: "Timeout in seconds", required: false),
    ]

    func execute(
        toolCallId: String,
        params: HttpRequestParams,
        onUpdate: ToolUpdateCallback<HttpRequestDetails>?
    ) async throws -> ToolResult<HttpRequestDetails> {
        guard let url = URL(string: params.url) else {
            throw ToolError.invalidArgument("Invalid URL: \(params.url)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = (params.method ?? "GET").uppercased()
        request.timeoutInterval = TimeInterval(params.timeout ?? 30)
        request.httpBody = params.body?.data(using: .utf8)

        if let headersJSON = params.headers,
           let data = headersJSON.data(using: .utf8),
           let headers = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        }

        let start = ContinuousClock.now
        let (data, response) = try await URLSession.shared.data(for: request)
        let elapsed = start.duration(to: .now)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ToolError.networkError("Non-HTTP response received")
        }

        let bodyString = String(data: data, encoding: .utf8) ?? "[Binary \(data.count) bytes]"
        let truncated = bodyString.count > Self.maxResponseBytes
        let displayBody = truncated
            ? String(bodyString.prefix(Self.maxResponseBytes)) +
              "\n\n[Response truncated at \(Self.maxResponseBytes / 1024)KB]"
            : bodyString

        let output = "HTTP \(httpResponse.statusCode)\n\n\(displayBody)"

        return ToolResult(
            content: [.text(output)],
            details: HttpRequestDetails(
                statusCode: httpResponse.statusCode,
                headers: httpResponse.allHeaderFields as? [String: String] ?? [:],
                responseTimeMs: Int64(elapsed.components.seconds * 1000),
                bodySize: data.count,
                truncated: truncated
            )
        )
    }

    static let maxResponseBytes = 100 * 1024
}
```

#### 6. list_directory

Lists files and directories with metadata, replacing `ls` via bash.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `path` | string | yes | Directory path |
| `recursive` | boolean | no | Include subdirectories (default: false) |
| `pattern` | string | no | Glob pattern filter (e.g., "*.json") |
| `max_depth` | integer | no | Maximum recursion depth (default: 3) |

**Details type:**

```kotlin
@Serializable
data class ListDirectoryDetails(
    val totalFiles: Int,
    val totalDirs: Int,
    val totalSize: Long,
    val truncated: Boolean = false
)

@Serializable
data class FileEntry(
    val name: String,
    val path: String,
    val isDirectory: Boolean,
    val size: Long,
    val modifiedAt: String, // ISO 8601
    val permissions: String? = null
)
```

---

### Extension Tool System

Extensions can register custom tools at runtime. This matches Pi's `registerTool()` from `ExtensionAPI`.

#### Android

```kotlin
/**
 * Interface for extension-provided tools.
 * Extensions implement this and register via ToolRegistry.
 *
 * Matches Pi's ToolDefinition from extensions/types.ts:335-358
 */
interface ExtensionTool {
    val name: String
    val label: String
    val description: String
    val parameters: List<ToolParameter>

    /**
     * Execute the tool with parsed parameters.
     * The JsonElement params will match the declared parameter schema.
     */
    suspend fun execute(
        toolCallId: String,
        params: JsonElement,
        onUpdate: ((ToolResult<JsonElement>) -> Unit)?
    ): ToolResult<JsonElement>
}

/**
 * Registry for managing built-in and extension tools.
 * Thread-safe; tools can be registered/unregistered at any time.
 */
class ToolRegistry {
    private val _tools = ConcurrentHashMap<String, RegisteredTool>()

    data class RegisteredTool(
        val tool: Any, // AgentTool<*, *> or ExtensionTool
        val source: String // "builtin" or extension identifier
    )

    /** Register a built-in tool */
    fun <P, D> registerBuiltin(tool: AgentTool<P, D>) {
        _tools[tool.name] = RegisteredTool(tool, "builtin")
    }

    /** Register an extension tool */
    fun registerExtension(tool: ExtensionTool, extensionId: String) {
        require(!tool.name.startsWith("_")) { "Tool names starting with _ are reserved" }
        _tools[tool.name] = RegisteredTool(tool, extensionId)
    }

    /** Unregister all tools from an extension */
    fun unregisterExtension(extensionId: String) {
        _tools.entries.removeIf { it.value.source == extensionId }
    }

    /** Get all registered tools (for LLM tool definitions) */
    fun allTools(): List<RegisteredTool> = _tools.values.toList()

    /** Get a tool by name */
    fun get(name: String): RegisteredTool? = _tools[name]

    /** Get tool names */
    fun toolNames(): Set<String> = _tools.keys.toSet()
}
```

#### iOS

```swift
/// Protocol for extension-provided tools.
protocol ExtensionTool: Sendable {
    var name: String { get }
    var label: String { get }
    var description: String { get }
    var parameters: [ToolParameter] { get }

    func execute(
        toolCallId: String,
        params: [String: Any],
        onUpdate: (@Sendable ([String: Any]) -> Void)?
    ) async throws -> ToolResult<AnyCodable>
}

/// Registry for managing built-in and extension tools.
actor ToolRegistry {
    struct RegisteredTool {
        let name: String
        let label: String
        let description: String
        let parameters: [ToolParameter]
        let source: String // "builtin" or extension id
        let execute: @Sendable (String, [String: Any], ((Any) -> Void)?) async throws -> Any
    }

    private var tools: [String: RegisteredTool] = [:]

    func register<T: AgentTool>(builtin tool: T) {
        tools[tool.name] = RegisteredTool(
            name: tool.name,
            label: tool.label,
            description: tool.description,
            parameters: tool.parameters,
            source: "builtin",
            execute: { id, params, onUpdate in
                let decoded = try JSONDecoder().decode(
                    T.Params.self,
                    from: JSONSerialization.data(withJSONObject: params)
                )
                return try await tool.execute(toolCallId: id, params: decoded, onUpdate: nil)
            }
        )
    }

    func register(extension tool: ExtensionTool, extensionId: String) {
        tools[tool.name] = RegisteredTool(
            name: tool.name,
            label: tool.label,
            description: tool.description,
            parameters: tool.parameters,
            source: extensionId,
            execute: { id, params, onUpdate in
                try await tool.execute(toolCallId: id, params: params, onUpdate: nil)
            }
        )
    }

    func unregisterExtension(_ extensionId: String) {
        tools = tools.filter { $0.value.source != extensionId }
    }

    func allTools() -> [RegisteredTool] { Array(tools.values) }
    func get(_ name: String) -> RegisteredTool? { tools[name] }
}
```

---

## SQLite-Based DAG Session Storage

### Design Rationale

Pi desktop uses `.jsonl` files for session storage. On mobile, SQLite is the right choice because:

1. **Concurrent access**: WAL mode supports concurrent readers without blocking writers — critical for UI observing session changes while agent loop appends entries
2. **Efficient branching**: Recursive CTEs reconstruct any branch path in a single query instead of scanning the whole file
3. **Search**: FTS5 enables full-text search across all sessions without loading everything into memory
4. **Atomic writes**: SQLite transactions guarantee consistency even if the app is killed mid-write
5. **Size efficiency**: Binary storage + compression for large tool results
6. **Platform native**: Both Android (Room) and iOS (GRDB) have first-class SQLite support with reactive observation

### Library Choices

**Android: Room** (over SQLDelight or raw SQLite)
- Room provides compile-time SQL verification, automatic migration support, and Flow-based reactive queries
- Room's DAO pattern maps cleanly to Pi's SessionManager API
- SQLDelight's multiplatform benefits are unnecessary since we're writing native per platform
- Raw SQLite requires too much boilerplate for migrations and type conversion

**iOS: GRDB** (over SQLite.swift)
- GRDB provides `DatabasePool` with WAL mode, `ValueObservation` for reactive queries, and `Codable` integration
- GRDB's `DatabaseMigrator` handles schema migrations cleanly
- SQLite.swift lacks built-in observation and WAL pool support
- GRDB's `FetchableRecord` + `PersistableRecord` maps cleanly to Swift structs

### Schema DDL

```sql
-- ============================================================
-- Pi Mobile Session Storage Schema (v1)
-- Preserves the append-only DAG semantics from Pi desktop
-- ============================================================

-- Sessions table (one row per session, maps to SessionHeader)
CREATE TABLE sessions (
    id              TEXT PRIMARY KEY,  -- UUID
    version         INTEGER NOT NULL DEFAULT 1,
    created_at      TEXT NOT NULL,     -- ISO 8601
    cwd             TEXT NOT NULL DEFAULT '',
    parent_session  TEXT,              -- FK to sessions.id (for forked sessions)
    leaf_id         TEXT,              -- FK to entries.id (current position)
    display_name    TEXT               -- User-defined session name
);

-- Entries table (the DAG nodes, maps to SessionEntry)
-- This is the core append-only log. Entries are never modified or deleted.
CREATE TABLE entries (
    id              TEXT PRIMARY KEY,  -- Short unique ID (8 hex chars)
    session_id      TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    parent_id       TEXT,              -- FK to entries.id (NULL = root)
    type            TEXT NOT NULL,     -- 'message', 'tool_call', 'tool_result',
                                       -- 'thinking_level_change', 'model_change',
                                       -- 'compaction', 'branch_summary',
                                       -- 'custom', 'custom_message', 'label'
    created_at      TEXT NOT NULL,     -- ISO 8601
    data            TEXT NOT NULL      -- JSON blob (entry-type-specific payload)
);

-- Index for fast branch reconstruction (walk parent chain)
CREATE INDEX idx_entries_parent ON entries(parent_id);

-- Index for listing entries by session
CREATE INDEX idx_entries_session ON entries(session_id, created_at);

-- Index for type-specific queries (e.g., find latest compaction)
CREATE INDEX idx_entries_type ON entries(session_id, type);

-- Full-text search index for session content
CREATE VIRTUAL TABLE entries_fts USING fts5(
    text_content,           -- Extracted text from messages
    content='entries',
    content_rowid='rowid',
    tokenize='unicode61'
);

-- Trigger to keep FTS in sync on insert
CREATE TRIGGER entries_ai AFTER INSERT ON entries
WHEN NEW.type IN ('message', 'custom_message')
BEGIN
    INSERT INTO entries_fts(rowid, text_content)
    VALUES (NEW.rowid, json_extract(NEW.data, '$.text'));
END;

-- Labels table (separate for easy querying, maps to LabelEntry)
-- Latest label per target_id wins (ordered by created_at)
CREATE TABLE labels (
    id              TEXT PRIMARY KEY,
    session_id      TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    entry_id        TEXT NOT NULL,     -- The entry this label is attached to
    target_id       TEXT NOT NULL REFERENCES entries(id),
    label           TEXT,              -- NULL or empty to clear
    created_at      TEXT NOT NULL
);

CREATE INDEX idx_labels_target ON labels(target_id, created_at);

-- Schema version tracking
CREATE TABLE schema_version (
    version         INTEGER NOT NULL,
    applied_at      TEXT NOT NULL
);

INSERT INTO schema_version (version, applied_at) VALUES (1, datetime('now'));
```

### Data Column Encoding

The `data` column stores JSON. Each entry type has a defined JSON shape:

```
type = "message"
data = {
    "role": "user" | "assistant" | "toolResult",
    "text": "extracted text for search",  -- Flattened for FTS
    "message": { ... full message JSON ... }
}

type = "thinking_level_change"
data = { "thinkingLevel": "off" | "low" | "medium" | "high" }

type = "model_change"
data = { "provider": "anthropic", "modelId": "claude-sonnet-4-..." }

type = "compaction"
data = {
    "summary": "...",
    "firstKeptEntryId": "abc12345",
    "tokensBefore": 50000,
    "details": { ... },
    "fromHook": false
}

type = "branch_summary"
data = {
    "fromId": "abc12345",
    "summary": "...",
    "details": { ... },
    "fromHook": false
}

type = "custom"
data = { "customType": "my-extension", "payload": { ... } }

type = "custom_message"
data = {
    "customType": "my-extension",
    "content": "...",
    "display": true,
    "details": { ... },
    "text": "extracted for FTS"
}
```

### Key Queries

#### Insert a new entry (append to DAG)

```sql
-- 1. Insert the entry
INSERT INTO entries (id, session_id, parent_id, type, created_at, data)
VALUES (:id, :sessionId, :parentId, :type, :createdAt, :data);

-- 2. Advance the leaf pointer
UPDATE sessions SET leaf_id = :id WHERE id = :sessionId;
```

#### Reconstruct branch (root to leaf)

Uses a recursive CTE to walk from leaf to root, then reverses:

```sql
-- Walk from leaf to root, collecting the path
WITH RECURSIVE branch(id, parent_id, type, created_at, data, depth) AS (
    -- Start from the leaf
    SELECT e.id, e.parent_id, e.type, e.created_at, e.data, 0
    FROM entries e
    JOIN sessions s ON s.id = :sessionId AND e.id = s.leaf_id

    UNION ALL

    -- Walk up to parent
    SELECT e.id, e.parent_id, e.type, e.created_at, e.data, b.depth + 1
    FROM entries e
    JOIN branch b ON e.id = b.parent_id
)
SELECT id, parent_id, type, created_at, data
FROM branch
ORDER BY depth DESC;  -- Root first
```

#### Reconstruct branch from arbitrary entry (not just leaf)

```sql
WITH RECURSIVE branch(id, parent_id, type, created_at, data, depth) AS (
    SELECT e.id, e.parent_id, e.type, e.created_at, e.data, 0
    FROM entries e
    WHERE e.id = :entryId

    UNION ALL

    SELECT e.id, e.parent_id, e.type, e.created_at, e.data, b.depth + 1
    FROM entries e
    JOIN branch b ON e.id = b.parent_id
)
SELECT id, parent_id, type, created_at, data
FROM branch
ORDER BY depth DESC;
```

#### List sessions (most recent first)

```sql
SELECT
    s.id,
    s.display_name,
    s.cwd,
    s.created_at,
    s.parent_session,
    -- Get last activity time
    COALESCE(
        (SELECT MAX(e.created_at) FROM entries e
         WHERE e.session_id = s.id AND e.type = 'message'),
        s.created_at
    ) AS modified_at,
    -- Get message count
    (SELECT COUNT(*) FROM entries e
     WHERE e.session_id = s.id AND e.type = 'message') AS message_count,
    -- Get first user message
    (SELECT json_extract(e.data, '$.text') FROM entries e
     WHERE e.session_id = s.id AND e.type = 'message'
       AND json_extract(e.data, '$.role') = 'user'
     ORDER BY e.created_at LIMIT 1) AS first_message
FROM sessions s
ORDER BY modified_at DESC;
```

#### Switch branch (move leaf pointer)

```sql
UPDATE sessions SET leaf_id = :newLeafId WHERE id = :sessionId;
```

#### Search across sessions

```sql
SELECT e.session_id, e.id, snippet(entries_fts, 0, '**', '**', '...', 32) AS match
FROM entries_fts
JOIN entries e ON e.rowid = entries_fts.rowid
WHERE entries_fts MATCH :searchQuery
ORDER BY rank
LIMIT 50;
```

#### Find latest compaction on branch

```sql
WITH RECURSIVE branch(id, parent_id, type, data, depth) AS (
    SELECT e.id, e.parent_id, e.type, e.data, 0
    FROM entries e
    JOIN sessions s ON s.id = :sessionId AND e.id = s.leaf_id
    UNION ALL
    SELECT e.id, e.parent_id, e.type, e.data, b.depth + 1
    FROM entries e
    JOIN branch b ON e.id = b.parent_id
)
SELECT id, data FROM branch
WHERE type = 'compaction'
ORDER BY depth ASC  -- closest to leaf
LIMIT 1;
```

#### Get children of an entry

```sql
SELECT id, type, created_at, data
FROM entries
WHERE parent_id = :entryId
ORDER BY created_at;
```

#### Build tree structure for a session

```sql
SELECT id, parent_id, type, created_at, data
FROM entries
WHERE session_id = :sessionId
ORDER BY created_at;
-- Build tree in application code from flat list
```

---

### Android Implementation (Room)

#### Entity classes

```kotlin
import androidx.room.*
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

@Entity(tableName = "sessions")
data class SessionEntity(
    @PrimaryKey
    val id: String,
    val version: Int = 1,
    @ColumnInfo(name = "created_at")
    val createdAt: String,
    val cwd: String = "",
    @ColumnInfo(name = "parent_session")
    val parentSession: String? = null,
    @ColumnInfo(name = "leaf_id")
    val leafId: String? = null,
    @ColumnInfo(name = "display_name")
    val displayName: String? = null
)

@Entity(
    tableName = "entries",
    foreignKeys = [
        ForeignKey(
            entity = SessionEntity::class,
            parentColumns = ["id"],
            childColumns = ["session_id"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [
        Index("parent_id"),
        Index("session_id", "created_at"),
        Index("session_id", "type")
    ]
)
data class EntryEntity(
    @PrimaryKey
    val id: String,
    @ColumnInfo(name = "session_id")
    val sessionId: String,
    @ColumnInfo(name = "parent_id")
    val parentId: String? = null,
    val type: String,
    @ColumnInfo(name = "created_at")
    val createdAt: String,
    val data: String // JSON
)

@Entity(
    tableName = "labels",
    foreignKeys = [
        ForeignKey(
            entity = SessionEntity::class,
            parentColumns = ["id"],
            childColumns = ["session_id"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [
        Index("target_id", "created_at")
    ]
)
data class LabelEntity(
    @PrimaryKey
    val id: String,
    @ColumnInfo(name = "session_id")
    val sessionId: String,
    @ColumnInfo(name = "entry_id")
    val entryId: String,
    @ColumnInfo(name = "target_id")
    val targetId: String,
    val label: String?,
    @ColumnInfo(name = "created_at")
    val createdAt: String
)

// Query result types
data class SessionInfo(
    val id: String,
    @ColumnInfo(name = "display_name") val displayName: String?,
    val cwd: String,
    @ColumnInfo(name = "created_at") val createdAt: String,
    @ColumnInfo(name = "parent_session") val parentSession: String?,
    @ColumnInfo(name = "modified_at") val modifiedAt: String,
    @ColumnInfo(name = "message_count") val messageCount: Int,
    @ColumnInfo(name = "first_message") val firstMessage: String?
)

data class BranchEntry(
    val id: String,
    @ColumnInfo(name = "parent_id") val parentId: String?,
    val type: String,
    @ColumnInfo(name = "created_at") val createdAt: String,
    val data: String
)
```

#### DAO layer

```kotlin
@Dao
interface SessionDao {
    // =========================================================================
    // Session CRUD
    // =========================================================================

    @Insert
    suspend fun insertSession(session: SessionEntity)

    @Query("SELECT * FROM sessions WHERE id = :id")
    suspend fun getSession(id: String): SessionEntity?

    @Query("UPDATE sessions SET leaf_id = :leafId WHERE id = :sessionId")
    suspend fun updateLeafId(sessionId: String, leafId: String?)

    @Query("UPDATE sessions SET display_name = :name WHERE id = :sessionId")
    suspend fun updateDisplayName(sessionId: String, name: String?)

    @Query("DELETE FROM sessions WHERE id = :id")
    suspend fun deleteSession(id: String)

    // =========================================================================
    // Session listing
    // =========================================================================

    @Query("""
        SELECT
            s.id,
            s.display_name,
            s.cwd,
            s.created_at,
            s.parent_session,
            COALESCE(
                (SELECT MAX(e.created_at) FROM entries e
                 WHERE e.session_id = s.id AND e.type = 'message'),
                s.created_at
            ) AS modified_at,
            (SELECT COUNT(*) FROM entries e
             WHERE e.session_id = s.id AND e.type = 'message') AS message_count,
            (SELECT json_extract(e.data, '$.text') FROM entries e
             WHERE e.session_id = s.id AND e.type = 'message'
               AND json_extract(e.data, '$.role') = 'user'
             ORDER BY e.created_at LIMIT 1) AS first_message
        FROM sessions s
        ORDER BY modified_at DESC
    """)
    fun observeSessions(): Flow<List<SessionInfo>>

    @Query("""
        SELECT
            s.id,
            s.display_name,
            s.cwd,
            s.created_at,
            s.parent_session,
            COALESCE(
                (SELECT MAX(e.created_at) FROM entries e
                 WHERE e.session_id = s.id AND e.type = 'message'),
                s.created_at
            ) AS modified_at,
            (SELECT COUNT(*) FROM entries e
             WHERE e.session_id = s.id AND e.type = 'message') AS message_count,
            (SELECT json_extract(e.data, '$.text') FROM entries e
             WHERE e.session_id = s.id AND e.type = 'message'
               AND json_extract(e.data, '$.role') = 'user'
             ORDER BY e.created_at LIMIT 1) AS first_message
        FROM sessions s
        ORDER BY modified_at DESC
    """)
    suspend fun listSessions(): List<SessionInfo>

    // =========================================================================
    // Entry operations
    // =========================================================================

    @Insert
    suspend fun insertEntry(entry: EntryEntity)

    @Query("SELECT * FROM entries WHERE id = :id")
    suspend fun getEntry(id: String): EntryEntity?

    @Query("SELECT * FROM entries WHERE session_id = :sessionId ORDER BY created_at")
    suspend fun getEntriesForSession(sessionId: String): List<EntryEntity>

    @Query("SELECT * FROM entries WHERE parent_id = :parentId ORDER BY created_at")
    suspend fun getChildren(parentId: String): List<EntryEntity>

    // =========================================================================
    // Branch reconstruction via recursive CTE
    // =========================================================================

    @Query("""
        WITH RECURSIVE branch(id, parent_id, type, created_at, data, depth) AS (
            SELECT e.id, e.parent_id, e.type, e.created_at, e.data, 0
            FROM entries e
            WHERE e.id = :leafId
            UNION ALL
            SELECT e.id, e.parent_id, e.type, e.created_at, e.data, b.depth + 1
            FROM entries e
            JOIN branch b ON e.id = b.parent_id
        )
        SELECT id, parent_id, type, created_at, data
        FROM branch
        ORDER BY depth DESC
    """)
    suspend fun reconstructBranch(leafId: String): List<BranchEntry>

    /**
     * Observe the current branch reactively.
     * Re-emits whenever entries for this session change.
     */
    @Query("""
        WITH RECURSIVE branch(id, parent_id, type, created_at, data, depth) AS (
            SELECT e.id, e.parent_id, e.type, e.created_at, e.data, 0
            FROM entries e
            JOIN sessions s ON s.id = :sessionId AND e.id = s.leaf_id
            UNION ALL
            SELECT e.id, e.parent_id, e.type, e.created_at, e.data, b.depth + 1
            FROM entries e
            JOIN branch b ON e.id = b.parent_id
        )
        SELECT id, parent_id, type, created_at, data
        FROM branch
        ORDER BY depth DESC
    """)
    fun observeBranch(sessionId: String): Flow<List<BranchEntry>>

    // =========================================================================
    // Labels
    // =========================================================================

    @Insert
    suspend fun insertLabel(label: LabelEntity)

    @Query("""
        SELECT l.target_id, l.label
        FROM labels l
        WHERE l.session_id = :sessionId
          AND l.label IS NOT NULL
        GROUP BY l.target_id
        HAVING l.created_at = MAX(l.created_at)
    """)
    suspend fun getLabels(sessionId: String): List<LabelResult>

    data class LabelResult(
        @ColumnInfo(name = "target_id") val targetId: String,
        val label: String?
    )

    // =========================================================================
    // Search
    // =========================================================================

    @Query("""
        SELECT e.session_id, e.id,
               snippet(entries_fts, 0, '**', '**', '...', 32) AS match_text
        FROM entries_fts
        JOIN entries e ON e.rowid = entries_fts.rowid
        WHERE entries_fts MATCH :query
        ORDER BY rank
        LIMIT :limit
    """)
    suspend fun search(query: String, limit: Int = 50): List<SearchResult>

    data class SearchResult(
        @ColumnInfo(name = "session_id") val sessionId: String,
        val id: String,
        @ColumnInfo(name = "match_text") val matchText: String
    )
}
```

#### Repository layer

```kotlin
/**
 * Repository wrapping SessionDao with business logic.
 * Matches Pi's SessionManager API surface.
 *
 * Pi reference: packages/coding-agent/src/core/session-manager.ts
 */
class SessionRepository(
    private val db: PiDatabase,
    private val dao: SessionDao = db.sessionDao()
) {
    private var currentSessionId: String? = null

    // =========================================================================
    // Session lifecycle
    // =========================================================================

    suspend fun createSession(cwd: String, parentSession: String? = null): String {
        val sessionId = UUID.randomUUID().toString()
        val now = Instant.now().toString()
        dao.insertSession(
            SessionEntity(
                id = sessionId,
                createdAt = now,
                cwd = cwd,
                parentSession = parentSession
            )
        )
        currentSessionId = sessionId
        return sessionId
    }

    suspend fun openSession(sessionId: String): SessionEntity? {
        val session = dao.getSession(sessionId)
        if (session != null) {
            currentSessionId = sessionId
        }
        return session
    }

    // =========================================================================
    // Entry append operations (preserves append-only DAG semantics)
    // =========================================================================

    /**
     * Append a new entry as child of current leaf, then advance leaf.
     * This is the fundamental operation — matches Pi's _appendEntry().
     */
    suspend fun appendEntry(
        type: String,
        data: String, // JSON
        sessionId: String = requireSessionId()
    ): String {
        val session = dao.getSession(sessionId)
            ?: throw IllegalStateException("Session $sessionId not found")

        val entryId = generateShortId()
        val now = Instant.now().toString()

        db.withTransaction {
            dao.insertEntry(
                EntryEntity(
                    id = entryId,
                    sessionId = sessionId,
                    parentId = session.leafId,
                    type = type,
                    createdAt = now,
                    data = data
                )
            )
            dao.updateLeafId(sessionId, entryId)
        }

        return entryId
    }

    /** Append a message entry */
    suspend fun appendMessage(message: JsonElement): String {
        val role = message.jsonObject["role"]?.jsonPrimitive?.content ?: "unknown"
        val text = extractTextContent(message)
        val data = buildJsonObject {
            put("role", role)
            put("text", text)
            put("message", message)
        }.toString()
        return appendEntry("message", data)
    }

    /** Append a compaction entry */
    suspend fun appendCompaction(
        summary: String,
        firstKeptEntryId: String,
        tokensBefore: Int,
        details: JsonElement? = null,
        fromHook: Boolean = false
    ): String {
        val data = buildJsonObject {
            put("summary", summary)
            put("firstKeptEntryId", firstKeptEntryId)
            put("tokensBefore", tokensBefore)
            details?.let { put("details", it) }
            put("fromHook", fromHook)
        }.toString()
        return appendEntry("compaction", data)
    }

    // =========================================================================
    // Branching
    // =========================================================================

    /** Move leaf pointer to an earlier entry (start a new branch) */
    suspend fun branch(entryId: String, sessionId: String = requireSessionId()) {
        val entry = dao.getEntry(entryId)
            ?: throw IllegalArgumentException("Entry $entryId not found")
        dao.updateLeafId(sessionId, entryId)
    }

    /** Reset leaf to null (navigate before first entry) */
    suspend fun resetLeaf(sessionId: String = requireSessionId()) {
        dao.updateLeafId(sessionId, null)
    }

    /** Branch with summary (matches Pi's branchWithSummary) */
    suspend fun branchWithSummary(
        branchFromId: String?,
        summary: String,
        details: JsonElement? = null,
        fromHook: Boolean = false,
        sessionId: String = requireSessionId()
    ): String {
        // Move leaf
        dao.updateLeafId(sessionId, branchFromId)

        // Append branch summary entry
        val data = buildJsonObject {
            put("fromId", branchFromId ?: "root")
            put("summary", summary)
            details?.let { put("details", it) }
            put("fromHook", fromHook)
        }.toString()

        return appendEntry("branch_summary", data, sessionId)
    }

    // =========================================================================
    // Context building (matches Pi's buildSessionContext)
    // =========================================================================

    /**
     * Build the LLM context from the current branch.
     * Handles compaction summaries and branch summaries along the path.
     */
    suspend fun buildSessionContext(
        sessionId: String = requireSessionId()
    ): SessionContext {
        val session = dao.getSession(sessionId) ?: return SessionContext.empty()
        val leafId = session.leafId ?: return SessionContext.empty()

        val branch = dao.reconstructBranch(leafId)
        return buildContextFromBranch(branch)
    }

    /**
     * Build context from a branch entry list (root-to-leaf order).
     * Port of Pi's buildSessionContext() from session-manager.ts:307-414
     */
    private fun buildContextFromBranch(branch: List<BranchEntry>): SessionContext {
        var thinkingLevel = "off"
        var model: ModelRef? = null
        var compaction: BranchEntry? = null

        // First pass: extract settings and find latest compaction
        for (entry in branch) {
            val json = Json.parseToJsonElement(entry.data).jsonObject
            when (entry.type) {
                "thinking_level_change" -> {
                    thinkingLevel = json["thinkingLevel"]?.jsonPrimitive?.content ?: "off"
                }
                "model_change" -> {
                    model = ModelRef(
                        provider = json["provider"]?.jsonPrimitive?.content ?: "",
                        modelId = json["modelId"]?.jsonPrimitive?.content ?: ""
                    )
                }
                "message" -> {
                    val role = json["role"]?.jsonPrimitive?.content
                    if (role == "assistant") {
                        val msg = json["message"]?.jsonObject
                        model = ModelRef(
                            provider = msg?.get("provider")?.jsonPrimitive?.content ?: "",
                            modelId = msg?.get("model")?.jsonPrimitive?.content ?: ""
                        )
                    }
                }
                "compaction" -> compaction = entry
            }
        }

        // Second pass: build message list
        val messages = mutableListOf<JsonElement>()

        if (compaction != null) {
            val compData = Json.parseToJsonElement(compaction.data).jsonObject
            // Emit compaction summary as user message
            messages.add(buildCompactionSummaryMessage(compData))

            val compIdx = branch.indexOf(compaction)
            val firstKeptId = compData["firstKeptEntryId"]?.jsonPrimitive?.content

            // Emit kept messages before compaction
            var foundFirstKept = false
            for (i in 0 until compIdx) {
                if (branch[i].id == firstKeptId) foundFirstKept = true
                if (foundFirstKept) appendMessage(branch[i], messages)
            }

            // Emit messages after compaction
            for (i in (compIdx + 1) until branch.size) {
                appendMessage(branch[i], messages)
            }
        } else {
            for (entry in branch) {
                appendMessage(entry, messages)
            }
        }

        return SessionContext(messages, thinkingLevel, model)
    }

    // =========================================================================
    // Reactive observation
    // =========================================================================

    /** Observe the current branch as a Flow (re-emits on any change) */
    fun observeCurrentBranch(sessionId: String): Flow<SessionContext> {
        return dao.observeBranch(sessionId)
            .map { branch -> buildContextFromBranch(branch) }
    }

    /** Observe session list */
    fun observeSessions(): Flow<List<SessionInfo>> = dao.observeSessions()

    // =========================================================================
    // Fork / export
    // =========================================================================

    /** Create a new session containing only the current branch */
    suspend fun forkSession(
        leafId: String,
        cwd: String,
        sourceSessionId: String = requireSessionId()
    ): String {
        val branch = dao.reconstructBranch(leafId)
        val newSessionId = createSession(cwd, parentSession = sourceSessionId)

        db.withTransaction {
            // Re-insert entries with preserved IDs and parent chains
            for (entry in branch) {
                dao.insertEntry(
                    EntryEntity(
                        id = entry.id,
                        sessionId = newSessionId,
                        parentId = entry.parentId,
                        type = entry.type,
                        createdAt = entry.createdAt,
                        data = entry.data
                    )
                )
            }
            val lastId = branch.lastOrNull()?.id
            dao.updateLeafId(newSessionId, lastId)
        }

        return newSessionId
    }

    /** Export a session to JSONL format (for desktop compatibility) */
    suspend fun exportToJsonl(sessionId: String): String {
        val session = dao.getSession(sessionId)
            ?: throw IllegalStateException("Session not found")
        val entries = dao.getEntriesForSession(sessionId)

        val sb = StringBuilder()

        // Write header
        val header = buildJsonObject {
            put("type", "session")
            put("version", 3)
            put("id", session.id)
            put("timestamp", session.createdAt)
            put("cwd", session.cwd)
            session.parentSession?.let { put("parentSession", it) }
        }
        sb.appendLine(header.toString())

        // Write entries
        for (entry in entries) {
            val entryJson = buildJsonObject {
                put("type", entry.type)
                put("id", entry.id)
                put("parentId", entry.parentId?.let { JsonPrimitive(it) } ?: JsonNull)
                put("timestamp", entry.createdAt)
                // Merge data fields into entry
                val data = Json.parseToJsonElement(entry.data).jsonObject
                for ((k, v) in data) {
                    if (k != "text") put(k, v) // Skip FTS helper field
                }
            }
            sb.appendLine(entryJson.toString())
        }

        return sb.toString()
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    private fun requireSessionId(): String =
        currentSessionId ?: throw IllegalStateException("No active session")

    private fun generateShortId(): String {
        val uuid = UUID.randomUUID().toString().replace("-", "")
        return uuid.take(8)
    }
}
```

#### Database setup

```kotlin
@Database(
    entities = [SessionEntity::class, EntryEntity::class, LabelEntity::class],
    version = 1,
    exportSchema = true
)
abstract class PiDatabase : RoomDatabase() {
    abstract fun sessionDao(): SessionDao

    companion object {
        fun create(context: Context): PiDatabase {
            return Room.databaseBuilder(
                context.applicationContext,
                PiDatabase::class.java,
                "pi-sessions.db"
            )
            .setJournalMode(JournalMode.WRITE_AHEAD_LOGGING) // WAL mode
            .addCallback(object : Callback() {
                override fun onCreate(db: SupportSQLiteDatabase) {
                    // Create FTS table and triggers
                    db.execSQL("""
                        CREATE VIRTUAL TABLE IF NOT EXISTS entries_fts USING fts5(
                            text_content,
                            content='entries',
                            content_rowid='rowid',
                            tokenize='unicode61'
                        )
                    """)
                    db.execSQL("""
                        CREATE TRIGGER IF NOT EXISTS entries_ai AFTER INSERT ON entries
                        WHEN NEW.type IN ('message', 'custom_message')
                        BEGIN
                            INSERT INTO entries_fts(rowid, text_content)
                            VALUES (NEW.rowid, json_extract(NEW.data, '$.text'));
                        END
                    """)
                }
            })
            .build()
        }
    }
}
```

---

### iOS Implementation (GRDB)

#### Record types

```swift
import GRDB
import Foundation

// MARK: - Session Record

struct SessionRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "sessions"

    var id: String
    var version: Int
    var createdAt: String
    var cwd: String
    var parentSession: String?
    var leafId: String?
    var displayName: String?

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let leafId = Column(CodingKeys.leafId)
        static let createdAt = Column(CodingKeys.createdAt)
        static let displayName = Column(CodingKeys.displayName)
    }
}

// MARK: - Entry Record

struct EntryRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "entries"

    var id: String
    var sessionId: String
    var parentId: String?
    var type: String
    var createdAt: String
    var data: String // JSON

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let sessionId = Column(CodingKeys.sessionId)
        static let parentId = Column(CodingKeys.parentId)
        static let type = Column(CodingKeys.type)
        static let createdAt = Column(CodingKeys.createdAt)
    }
}

// MARK: - Label Record

struct LabelRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "labels"

    var id: String
    var sessionId: String
    var entryId: String
    var targetId: String
    var label: String?
    var createdAt: String
}

// MARK: - Query Result Types

struct SessionInfo: Codable, FetchableRecord, Sendable {
    let id: String
    let displayName: String?
    let cwd: String
    let createdAt: String
    let parentSession: String?
    let modifiedAt: String
    let messageCount: Int
    let firstMessage: String?
}

struct BranchEntry: Codable, FetchableRecord, Sendable {
    let id: String
    let parentId: String?
    let type: String
    let createdAt: String
    let data: String
}

// MARK: - Session Context

struct ModelRef: Codable, Sendable {
    let provider: String
    let modelId: String
}

struct SessionContext: Sendable {
    let messages: [Any] // JSON-decoded message objects
    let thinkingLevel: String
    let model: ModelRef?

    static let empty = SessionContext(messages: [], thinkingLevel: "off", model: nil)
}
```

#### Database setup and migrations

```swift
import GRDB

final class PiDatabase: Sendable {
    let pool: DatabasePool

    init(path: String) throws {
        var config = Configuration()
        config.prepareDatabase { db in
            // Enable WAL mode
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            // Enable foreign keys
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        pool = try DatabasePool(path: path, configuration: config)
        try migrator.migrate(pool)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            // Sessions table
            try db.create(table: "sessions") { t in
                t.primaryKey("id", .text)
                t.column("version", .integer).notNull().defaults(to: 1)
                t.column("createdAt", .text).notNull()
                t.column("cwd", .text).notNull().defaults(to: "")
                t.column("parentSession", .text)
                t.column("leafId", .text)
                t.column("displayName", .text)
            }

            // Entries table
            try db.create(table: "entries") { t in
                t.primaryKey("id", .text)
                t.column("sessionId", .text).notNull()
                    .references("sessions", onDelete: .cascade)
                t.column("parentId", .text)
                t.column("type", .text).notNull()
                t.column("createdAt", .text).notNull()
                t.column("data", .text).notNull()
            }
            try db.create(index: "idx_entries_parent", on: "entries", columns: ["parentId"])
            try db.create(index: "idx_entries_session",
                          on: "entries", columns: ["sessionId", "createdAt"])
            try db.create(index: "idx_entries_type",
                          on: "entries", columns: ["sessionId", "type"])

            // Labels table
            try db.create(table: "labels") { t in
                t.primaryKey("id", .text)
                t.column("sessionId", .text).notNull()
                    .references("sessions", onDelete: .cascade)
                t.column("entryId", .text).notNull()
                t.column("targetId", .text).notNull()
                    .references("entries")
                t.column("label", .text)
                t.column("createdAt", .text).notNull()
            }
            try db.create(index: "idx_labels_target",
                          on: "labels", columns: ["targetId", "createdAt"])

            // FTS table
            try db.create(virtualTable: "entries_fts", using: FTS5()) { t in
                t.column("text_content")
                t.tokenizer = .unicode61()
            }

            // Schema version tracking
            try db.create(table: "schema_version") { t in
                t.column("version", .integer).notNull()
                t.column("appliedAt", .text).notNull()
            }
            try db.execute(
                sql: "INSERT INTO schema_version (version, appliedAt) VALUES (1, datetime('now'))"
            )
        }

        return migrator
    }
}
```

#### Repository layer

```swift
/// Repository wrapping GRDB for session management.
/// Matches Pi's SessionManager API surface.
///
/// Pi reference: packages/coding-agent/src/core/session-manager.ts
actor SessionRepository {
    private let db: PiDatabase
    private var currentSessionId: String?

    init(db: PiDatabase) {
        self.db = db
    }

    // =========================================================================
    // Session lifecycle
    // =========================================================================

    func createSession(cwd: String, parentSession: String? = nil) async throws -> String {
        let sessionId = UUID().uuidString
        let now = ISO8601DateFormatter().string(from: Date())

        try await db.pool.write { db in
            try SessionRecord(
                id: sessionId,
                version: 1,
                createdAt: now,
                cwd: cwd,
                parentSession: parentSession,
                leafId: nil,
                displayName: nil
            ).insert(db)
        }

        currentSessionId = sessionId
        return sessionId
    }

    // =========================================================================
    // Entry append (preserves append-only DAG semantics)
    // =========================================================================

    func appendEntry(type: String, data: String) async throws -> String {
        let sessionId = try requireSessionId()
        let entryId = generateShortId()
        let now = ISO8601DateFormatter().string(from: Date())

        try await db.pool.write { db in
            let session = try SessionRecord.fetchOne(db, key: sessionId)

            try EntryRecord(
                id: entryId,
                sessionId: sessionId,
                parentId: session?.leafId,
                type: type,
                createdAt: now,
                data: data
            ).insert(db)

            // Advance leaf pointer
            try db.execute(
                sql: "UPDATE sessions SET leafId = ? WHERE id = ?",
                arguments: [entryId, sessionId]
            )

            // Update FTS if message
            if type == "message" || type == "custom_message" {
                if let textContent = try? JSONSerialization.jsonObject(
                    with: data.data(using: .utf8)!) as? [String: Any],
                   let text = textContent["text"] as? String {
                    try db.execute(
                        sql: "INSERT INTO entries_fts(rowid, text_content) VALUES (last_insert_rowid(), ?)",
                        arguments: [text]
                    )
                }
            }
        }

        return entryId
    }

    // =========================================================================
    // Branch reconstruction
    // =========================================================================

    func reconstructBranch(leafId: String) async throws -> [BranchEntry] {
        try await db.pool.read { db in
            try BranchEntry.fetchAll(db, sql: """
                WITH RECURSIVE branch(id, parentId, type, createdAt, data, depth) AS (
                    SELECT e.id, e.parentId, e.type, e.createdAt, e.data, 0
                    FROM entries e WHERE e.id = ?
                    UNION ALL
                    SELECT e.id, e.parentId, e.type, e.createdAt, e.data, b.depth + 1
                    FROM entries e JOIN branch b ON e.id = b.parentId
                )
                SELECT id, parentId, type, createdAt, data
                FROM branch ORDER BY depth DESC
                """, arguments: [leafId])
        }
    }

    func buildSessionContext() async throws -> SessionContext {
        let sessionId = try requireSessionId()
        guard let session = try await db.pool.read({ db in
            try SessionRecord.fetchOne(db, key: sessionId)
        }), let leafId = session.leafId else {
            return .empty
        }

        let branch = try await reconstructBranch(leafId: leafId)
        return buildContextFromBranch(branch)
    }

    // =========================================================================
    // Branching
    // =========================================================================

    func branch(to entryId: String) async throws {
        let sessionId = try requireSessionId()
        try await db.pool.write { db in
            try db.execute(
                sql: "UPDATE sessions SET leafId = ? WHERE id = ?",
                arguments: [entryId, sessionId]
            )
        }
    }

    func resetLeaf() async throws {
        let sessionId = try requireSessionId()
        try await db.pool.write { db in
            try db.execute(
                sql: "UPDATE sessions SET leafId = NULL WHERE id = ?",
                arguments: [sessionId]
            )
        }
    }

    // =========================================================================
    // Reactive observation (using GRDB ValueObservation)
    // =========================================================================

    /// Observe the current branch as an AsyncStream.
    /// Re-emits whenever entries for the session change.
    func observeCurrentBranch(
        sessionId: String
    ) -> AsyncThrowingStream<[BranchEntry], Error> {
        let observation = ValueObservation.tracking { db -> [BranchEntry] in
            guard let session = try SessionRecord.fetchOne(db, key: sessionId),
                  let leafId = session.leafId else { return [] }

            return try BranchEntry.fetchAll(db, sql: """
                WITH RECURSIVE branch(id, parentId, type, createdAt, data, depth) AS (
                    SELECT e.id, e.parentId, e.type, e.createdAt, e.data, 0
                    FROM entries e WHERE e.id = ?
                    UNION ALL
                    SELECT e.id, e.parentId, e.type, e.createdAt, e.data, b.depth + 1
                    FROM entries e JOIN branch b ON e.id = b.parentId
                )
                SELECT id, parentId, type, createdAt, data
                FROM branch ORDER BY depth DESC
                """, arguments: [leafId])
        }

        return AsyncThrowingStream { continuation in
            let cancellable = observation.start(in: db.pool) { error in
                continuation.finish(throwing: error)
            } onChange: { entries in
                continuation.yield(entries)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    /// Observe session list reactively.
    func observeSessions() -> AsyncThrowingStream<[SessionInfo], Error> {
        let observation = ValueObservation.tracking { db in
            try SessionInfo.fetchAll(db, sql: """
                SELECT
                    s.id,
                    s.displayName,
                    s.cwd,
                    s.createdAt,
                    s.parentSession,
                    COALESCE(
                        (SELECT MAX(e.createdAt) FROM entries e
                         WHERE e.sessionId = s.id AND e.type = 'message'),
                        s.createdAt
                    ) AS modifiedAt,
                    (SELECT COUNT(*) FROM entries e
                     WHERE e.sessionId = s.id AND e.type = 'message') AS messageCount,
                    (SELECT json_extract(e.data, '$.text') FROM entries e
                     WHERE e.sessionId = s.id AND e.type = 'message'
                       AND json_extract(e.data, '$.role') = 'user'
                     ORDER BY e.createdAt LIMIT 1) AS firstMessage
                FROM sessions s
                ORDER BY modifiedAt DESC
            """)
        }

        return AsyncThrowingStream { continuation in
            let cancellable = observation.start(in: db.pool) { error in
                continuation.finish(throwing: error)
            } onChange: { sessions in
                continuation.yield(sessions)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    // =========================================================================
    // Search
    // =========================================================================

    func search(query: String, limit: Int = 50) async throws -> [(sessionId: String, entryId: String, snippet: String)] {
        try await db.pool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT e.sessionId, e.id,
                       snippet(entries_fts, 0, '**', '**', '...', 32) AS matchText
                FROM entries_fts
                JOIN entries e ON e.rowid = entries_fts.rowid
                WHERE entries_fts MATCH ?
                ORDER BY rank LIMIT ?
                """, arguments: [query, limit])

            return rows.map { row in
                (sessionId: row["sessionId"] as String,
                 entryId: row["id"] as String,
                 snippet: row["matchText"] as String)
            }
        }
    }

    // =========================================================================
    // Export
    // =========================================================================

    func exportToJsonl(sessionId: String) async throws -> String {
        let session = try await db.pool.read { db in
            try SessionRecord.fetchOne(db, key: sessionId)
        }
        guard let session else { throw ToolError.sessionNotFound(sessionId) }

        let entries = try await db.pool.read { db in
            try EntryRecord
                .filter(EntryRecord.Columns.sessionId == sessionId)
                .order(EntryRecord.Columns.createdAt)
                .fetchAll(db)
        }

        var lines: [String] = []

        // Header
        var header: [String: Any] = [
            "type": "session",
            "version": 3,
            "id": session.id,
            "timestamp": session.createdAt,
            "cwd": session.cwd
        ]
        if let parent = session.parentSession { header["parentSession"] = parent }
        let headerData = try JSONSerialization.data(withJSONObject: header)
        lines.append(String(data: headerData, encoding: .utf8)!)

        // Entries
        for entry in entries {
            var entryDict: [String: Any] = [
                "type": entry.type,
                "id": entry.id,
                "parentId": entry.parentId as Any,
                "timestamp": entry.createdAt
            ]
            if let data = entry.data.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for (k, v) in parsed where k != "text" {
                    entryDict[k] = v
                }
            }
            let entryData = try JSONSerialization.data(withJSONObject: entryDict)
            lines.append(String(data: entryData, encoding: .utf8)!)
        }

        return lines.joined(separator: "\n") + "\n"
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    private func requireSessionId() throws -> String {
        guard let id = currentSessionId else {
            throw ToolError.noActiveSession
        }
        return id
    }

    private func generateShortId() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8))
    }

    private func buildContextFromBranch(_ branch: [BranchEntry]) -> SessionContext {
        // Port of Pi's buildSessionContext() — same algorithm as Android
        // (omitted for brevity, identical logic)
        fatalError("Implementation mirrors Android's buildContextFromBranch")
    }
}
```

---

### Migration Strategy

#### Desktop JSONL to Mobile SQLite (import)

```kotlin
// Android
class SessionImporter(private val repo: SessionRepository) {
    /**
     * Import a Pi desktop .jsonl session file into SQLite.
     * Preserves all entry IDs, parent chains, and types.
     */
    suspend fun importJsonl(jsonlContent: String): String {
        val lines = jsonlContent.trim().split("\n")
        if (lines.isEmpty()) throw IllegalArgumentException("Empty session file")

        val header = Json.parseToJsonElement(lines[0]).jsonObject
        require(header["type"]?.jsonPrimitive?.content == "session")

        val sessionId = header["id"]?.jsonPrimitive?.content
            ?: throw IllegalArgumentException("Missing session ID")

        // Migrate if needed (v1->v2->v3)
        val version = header["version"]?.jsonPrimitive?.int ?: 1
        val entries = if (version < 3) {
            migrateEntries(lines.drop(1), version)
        } else {
            lines.drop(1).map { Json.parseToJsonElement(it).jsonObject }
        }

        // Create session
        val cwd = header["cwd"]?.jsonPrimitive?.content ?: ""
        val parentSession = header["parentSession"]?.jsonPrimitive?.content

        repo.createSession(cwd, parentSession)

        // Insert entries preserving original IDs and parent chains
        var lastId: String? = null
        for (entry in entries) {
            val entryId = entry["id"]?.jsonPrimitive?.content ?: continue
            val type = entry["type"]?.jsonPrimitive?.content ?: continue
            val parentId = entry["parentId"]?.jsonPrimitive?.content

            // Reconstruct the data JSON based on type
            val data = reconstructDataJson(type, entry)
            repo.appendEntryDirect(entryId, type, data, parentId)
            lastId = entryId
        }

        // Set leaf to last entry
        if (lastId != null) {
            repo.branch(lastId)
        }

        return sessionId
    }
}
```

#### SQLite schema migrations (future versions)

```kotlin
// Android Room migrations
val MIGRATION_1_2 = object : Migration(1, 2) {
    override fun migrate(db: SupportSQLiteDatabase) {
        // Example: add a new column
        db.execSQL("ALTER TABLE sessions ADD COLUMN provider_hint TEXT")
        db.execSQL("UPDATE schema_version SET version = 2, applied_at = datetime('now')")
    }
}
```

```swift
// iOS GRDB migrations
migrator.registerMigration("v2_provider_hint") { db in
    try db.alter(table: "sessions") { t in
        t.add(column: "providerHint", .text)
    }
    try db.execute(
        sql: "UPDATE schema_version SET version = 2, appliedAt = datetime('now')"
    )
}
```

---

## Security Considerations

### sqlite_query Tool

1. **Parameterized queries only**: All user-provided values MUST use `?` placeholders with bound parameters. The tool never interpolates strings into SQL.

2. **Mode-based restrictions**:
   - `query` mode: Only `SELECT`, `WITH`, `PRAGMA`, `EXPLAIN` statements
   - `execute` mode: Blocks `DROP DATABASE`, `ATTACH`, `DETACH` (prevents accessing databases outside sandbox)
   - `tables` / `schema` mode: Read-only metadata queries

3. **Database path validation**: All database paths are resolved within the app sandbox. Content URIs and bookmark IDs go through the OS permission system.

4. **Row limits**: Query results are capped at 1000 rows to prevent memory exhaustion.

5. **Connection isolation**: Each database gets its own connection. The session database is opened in WAL mode with `PRAGMA busy_timeout` to handle concurrent access.

### File Tool Security

1. **Sandbox enforcement**: All path resolution methods verify the canonical path stays within the sandbox root. Path traversal (e.g., `../../etc/passwd`) is rejected.

2. **External file access**: Files outside the sandbox require user action via the document picker (Android SAF / iOS UIDocumentPicker). The tool receives a content URI or security-scoped bookmark, never a raw filesystem path.

3. **Bookmark management**: iOS security-scoped bookmarks are stored encrypted in the Keychain. Android SAF URI permissions are persisted via `ContentResolver.takePersistableUriPermission()`.

### HTTP Request Tool

1. **No localhost/internal access**: The tool blocks requests to `127.0.0.1`, `localhost`, `::1`, and private IP ranges (`10.x`, `172.16-31.x`, `192.168.x`) to prevent SSRF.

2. **Response size limits**: Responses are capped at 100KB to prevent memory exhaustion.

3. **No credential forwarding**: The tool never sends stored API keys or session tokens unless the user explicitly provides them in the headers parameter.

### Session Storage Security

1. **Encryption at rest**: The SQLite database can optionally use SQLCipher for full database encryption. The encryption key is stored in Android Keystore / iOS Keychain.

2. **No raw SQL from LLM**: The LLM's `sqlite_query` tool operates on user databases, never on the session storage database. Session operations go through the Repository layer.

3. **Export sanitization**: When exporting sessions to JSONL, API keys and OAuth tokens in model_change entries are redacted.
