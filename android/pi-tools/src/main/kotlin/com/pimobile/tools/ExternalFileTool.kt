package com.pimobile.tools

import android.util.Base64
import android.webkit.MimeTypeMap
import com.pimobile.agent.AgentToolResult
import com.pimobile.agent.Tool
import com.pimobile.agent.ToolResultDetails
import kotlinx.serialization.json.*
import java.text.SimpleDateFormat
import java.util.*

class ExternalFileTool : Tool {

    override val name = "file_access"

    override val description = """Access files outside the app sandbox via the system file picker \
(local storage, Google Drive, etc.). Actions:
- "pick": Show file picker UI for user to select files or directories. Returns bookmark_id values for subsequent access. \
Use content_types to filter (e.g. ["image"], ["pdf"], ["folder"]).
- "export": Show save dialog to export text content as a new file at a user-chosen location.
- "read": Read file contents using bookmark_id (and optional path for files within a picked directory). \
Text files return numbered lines; images/binary return base64.
- "write": Write text content to a file using bookmark_id (and optional path).
- "list": List directory contents using a bookmark_id. Returns file names you can use as path in read/write/info.
- "info": Get detailed metadata using bookmark_id (and optional path). Returns size, dates, type.
- "grants": List all saved bookmark_id grants with validity status.
- "revoke": Remove a saved bookmark_id grant.
Typical flow: "pick" a directory to get bookmark_id, "list" it to see files, then "read" with bookmark_id + path. \
Or "pick" individual files and "read" them directly by bookmark_id."""

    override val parametersSchema = buildJsonObject {
        put("type", "object")
        putJsonArray("required") { add("action") }
        putJsonObject("properties") {
            putJsonObject("action") {
                put("type", "string")
                put("description", "Action to perform. Required.")
                putJsonArray("enum") {
                    add("pick"); add("export"); add("read"); add("write")
                    add("list"); add("info"); add("grants"); add("revoke")
                }
            }
            putJsonObject("content_types") {
                put("type", "array")
                put("description", "(pick) File types to allow. Friendly names: 'image', 'pdf', 'text', 'video', 'audio', 'folder', 'any', 'json', 'csv', 'archive', 'source_code'. Also accepts MIME types (e.g. 'image/jpeg') or file extensions (e.g. 'kt'). Defaults to ['any'].")
                putJsonObject("items") { put("type", "string") }
            }
            putJsonObject("multiple") {
                put("type", "boolean")
                put("description", "(pick) Allow selecting multiple files. Defaults to false.")
            }
            putJsonObject("bookmark_id") {
                put("type", "string")
                put("description", "(read, write, list, info, revoke) Bookmark ID obtained from a previous 'pick' result.")
            }
            putJsonObject("path") {
                put("type", "string")
                put("description", "(read, write, info) Relative path within a bookmarked directory. Use file names from 'list' results. Not needed when bookmark_id points to a file directly.")
            }
            putJsonObject("content") {
                put("type", "string")
                put("description", "(write, export) Text content to write or export as a file.")
            }
            putJsonObject("filename") {
                put("type", "string")
                put("description", "(export) Suggested filename for the exported file. Defaults to 'export.txt'.")
            }
            putJsonObject("start_line") {
                put("type", "integer")
                put("description", "(read) Starting line number (1-indexed) for text files. Optional.")
            }
            putJsonObject("end_line") {
                put("type", "integer")
                put("description", "(read) Ending line number (inclusive) for text files. Optional.")
            }
            putJsonObject("recursive") {
                put("type", "boolean")
                put("description", "(list) List directory recursively. Defaults to false.")
            }
            putJsonObject("pattern") {
                put("type", "string")
                put("description", "(list) Glob pattern to filter results (e.g. '*.kt', '**/*.json').")
            }
        }
    }

    override suspend fun execute(input: JsonObject): AgentToolResult {
        val action = input["action"]?.jsonPrimitive?.contentOrNull ?: ""

        return when (action) {
            "pick" -> handlePick(input)
            "export" -> handleExport(input)
            "read" -> handleRead(input)
            "write" -> handleWrite(input)
            "list" -> handleList(input)
            "info" -> handleInfo(input)
            "grants" -> handleGrants()
            "revoke" -> handleRevoke(input)
            else -> AgentToolResult(
                "",
                "Error: Unknown action '$action'. Use: pick, export, read, write, list, info, grants, revoke.",
                isError = true
            )
        }
    }

    // MARK: - Pick

    private suspend fun handlePick(input: JsonObject): AgentToolResult {
        val typeNames = input["content_types"]?.jsonArray?.mapNotNull { it.jsonPrimitive.contentOrNull } ?: listOf("any")
        val multiple = input["multiple"]?.jsonPrimitive?.booleanOrNull ?: false

        val isDirectory = typeNames.any { it.lowercase() == "folder" || it.lowercase() == "directory" }
        val mimeTypes = if (isDirectory) emptyList() else resolveMimeTypes(typeNames)

        val results = FileAccessManager.instance.pickFiles(
            mimeTypes = mimeTypes,
            multiple = multiple,
            isDirectory = isDirectory
        )

        if (results == null) {
            return AgentToolResult(
                "",
                "File picker was cancelled or unavailable. Ensure FileAccessManager.configure(activity) was called at app startup."
            )
        }

        if (results.isEmpty()) {
            return AgentToolResult("", "No files were selected.")
        }

        val isoFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US)
        isoFormat.timeZone = TimeZone.getTimeZone("UTC")

        val columns = listOf("Bookmark ID", "Name", "Type", "Size", "Modified")
        val rows = results.map { file ->
            listOf(
                file.bookmarkId,
                file.name,
                if (file.isDirectory) "directory" else (file.mimeType ?: "unknown"),
                file.size?.let { formatFileSize(it) } ?: "-",
                file.lastModified?.let { isoFormat.format(Date(it)) } ?: "-"
            )
        }

        val header = columns.joinToString(" | ")
        val rowsStr = rows.joinToString("\n") { it.joinToString(" | ") }
        val output = "${results.size} file(s) selected:\n$header\n$rowsStr"

        return AgentToolResult("", output, ToolResultDetails.Table(columns, rows))
    }

    // MARK: - Export

    private suspend fun handleExport(input: JsonObject): AgentToolResult {
        val content = input["content"]?.jsonPrimitive?.contentOrNull
            ?: return AgentToolResult("", "Error: 'content' is required for export.", isError = true)
        val filename = input["filename"]?.jsonPrimitive?.contentOrNull ?: "export.txt"

        val data = content.toByteArray(Charsets.UTF_8)
        val success = FileAccessManager.instance.exportFile(filename, data)

        return if (success) {
            AgentToolResult("", "Exported '$filename' (${formatFileSize(data.size.toLong())}) successfully.")
        } else {
            AgentToolResult("", "Export was cancelled or failed.")
        }
    }

    // MARK: - Read

    private fun handleRead(input: JsonObject): AgentToolResult {
        val bookmarkId = input["bookmark_id"]?.jsonPrimitive?.contentOrNull
            ?: return AgentToolResult("", "Error: 'bookmark_id' is required for read.", isError = true)

        if (bookmarkId.isEmpty()) {
            return AgentToolResult("", "Error: 'bookmark_id' is required for read.", isError = true)
        }

        val subpath = input["path"]?.jsonPrimitive?.contentOrNull
        val fileName = FileAccessManager.instance.fileName(bookmarkId, subpath) ?: "unknown"

        val data = FileAccessManager.instance.readFileData(bookmarkId, subpath)
            ?: return AgentToolResult(
                "",
                "Error: Could not read file '$fileName'. Bookmark may be invalid or file not found.",
                isError = true
            )

        val ext = fileName.substringAfterLast(".", "").lowercase()
        val displayPath = "external://$bookmarkId/${subpath ?: fileName}"

        // Images — return base64
        if (ext in imageExtensions) {
            val base64 = Base64.encodeToString(data, Base64.NO_WRAP)
            return AgentToolResult(
                "",
                "Image: $fileName (${formatFileSize(data.size.toLong())})",
                ToolResultDetails.File(displayPath, "[base64:$base64]", null)
            )
        }

        // Try text
        val text = try {
            String(data, Charsets.UTF_8)
        } catch (_: Exception) {
            null
        }

        if (text == null || !isLikelyText(data)) {
            // Binary fallback — return base64
            val base64 = Base64.encodeToString(data, Base64.NO_WRAP)
            return AgentToolResult(
                "",
                "Binary file: $fileName (${formatFileSize(data.size.toLong())})",
                ToolResultDetails.File(displayPath, "[base64:$base64]", null)
            )
        }

        val allLines = text.split("\n")
        val startLine = maxOf(1, input["start_line"]?.jsonPrimitive?.intOrNull ?: 1)
        val endLine = minOf(allLines.size, input["end_line"]?.jsonPrimitive?.intOrNull ?: allLines.size)

        if (startLine > endLine) {
            return AgentToolResult("", "Error: Invalid line range $startLine-$endLine", isError = true)
        }

        val selectedLines = allLines.subList(startLine - 1, endLine)
        val numberedContent = buildString {
            for ((index, line) in selectedLines.withIndex()) {
                val lineNum = startLine + index
                append("$lineNum\t$line\n")
            }
        }

        val language = languageForExtension(ext)
        val info = "File: $fileName | Lines: $startLine-$endLine of ${allLines.size} | Size: ${formatFileSize(data.size.toLong())}"

        return AgentToolResult(
            "",
            "$info\n$numberedContent",
            ToolResultDetails.File(displayPath, numberedContent, language)
        )
    }

    // MARK: - Write

    private fun handleWrite(input: JsonObject): AgentToolResult {
        val bookmarkId = input["bookmark_id"]?.jsonPrimitive?.contentOrNull
            ?: return AgentToolResult("", "Error: 'bookmark_id' is required for write.", isError = true)

        if (bookmarkId.isEmpty()) {
            return AgentToolResult("", "Error: 'bookmark_id' is required for write.", isError = true)
        }

        val content = input["content"]?.jsonPrimitive?.contentOrNull
            ?: return AgentToolResult("", "Error: 'content' is required for write.", isError = true)

        val data = content.toByteArray(Charsets.UTF_8)
        val subpath = input["path"]?.jsonPrimitive?.contentOrNull

        val success = FileAccessManager.instance.writeFileData(bookmarkId, data, subpath)

        return if (success) {
            val lineCount = content.split("\n").size
            val fileName = FileAccessManager.instance.fileName(bookmarkId, subpath) ?: "unknown"
            AgentToolResult("", "Wrote ${formatFileSize(data.size.toLong())} ($lineCount lines) to $fileName")
        } else {
            AgentToolResult(
                "",
                "Error: Could not write to file. Bookmark may be invalid, expired, or read-only.",
                isError = true
            )
        }
    }

    // MARK: - List

    private fun handleList(input: JsonObject): AgentToolResult {
        val bookmarkId = input["bookmark_id"]?.jsonPrimitive?.contentOrNull
            ?: return AgentToolResult("", "Error: 'bookmark_id' is required for list.", isError = true)

        if (bookmarkId.isEmpty()) {
            return AgentToolResult("", "Error: 'bookmark_id' is required for list.", isError = true)
        }

        val recursive = input["recursive"]?.jsonPrimitive?.booleanOrNull ?: false
        val pattern = input["pattern"]?.jsonPrimitive?.contentOrNull

        var entries = FileAccessManager.instance.listDirectory(bookmarkId, recursive)
            ?: return AgentToolResult(
                "",
                "Error: Could not list directory. Bookmark may be invalid or not a directory.",
                isError = true
            )

        if (pattern != null) {
            entries = entries.filter { matchesGlob(it.name, pattern) }
        }

        if (entries.isEmpty()) {
            return AgentToolResult("", "Directory is empty or no files match the pattern.")
        }

        val isoFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US)
        isoFormat.timeZone = TimeZone.getTimeZone("UTC")

        val columns = listOf("Name", "Type", "Size", "Content Type", "Modified")
        val rows = entries.map { entry ->
            listOf(
                if (entry.isDirectory) "${entry.name}/" else entry.name,
                if (entry.isDirectory) "dir" else "file",
                entry.size?.let { formatFileSize(it) } ?: "-",
                entry.mimeType ?: "-",
                entry.lastModified?.let { isoFormat.format(Date(it)) } ?: "-"
            )
        }

        val header = columns.joinToString(" | ")
        val rowsStr = rows.joinToString("\n") { it.joinToString(" | ") }
        val output = "${entries.size} entries:\n$header\n$rowsStr"

        return AgentToolResult("", output, ToolResultDetails.Table(columns, rows))
    }

    // MARK: - Info

    private fun handleInfo(input: JsonObject): AgentToolResult {
        val bookmarkId = input["bookmark_id"]?.jsonPrimitive?.contentOrNull
            ?: return AgentToolResult("", "Error: 'bookmark_id' is required for info.", isError = true)

        if (bookmarkId.isEmpty()) {
            return AgentToolResult("", "Error: 'bookmark_id' is required for info.", isError = true)
        }

        val subpath = input["path"]?.jsonPrimitive?.contentOrNull
        val info = FileAccessManager.instance.fileInfo(bookmarkId, subpath)
            ?: return AgentToolResult(
                "",
                "Error: Could not get file info. Bookmark may be invalid or file not found.",
                isError = true
            )

        val lines = info.toSortedMap().map { "${it.key}: ${it.value}" }
        return AgentToolResult("", lines.joinToString("\n"))
    }

    // MARK: - Grants

    private fun handleGrants(): AgentToolResult {
        val grants = FileAccessManager.instance.listGrants()

        if (grants.isEmpty()) {
            return AgentToolResult("", "No file access grants stored.")
        }

        val columns = listOf("Bookmark ID", "Name", "Valid")
        val rows = grants.map { grant ->
            listOf(grant.id, grant.name ?: "(unknown)", if (grant.isValid) "yes" else "no")
        }

        val header = columns.joinToString(" | ")
        val rowsStr = rows.joinToString("\n") { it.joinToString(" | ") }
        val output = "${grants.size} grant(s):\n$header\n$rowsStr"

        return AgentToolResult("", output, ToolResultDetails.Table(columns, rows))
    }

    // MARK: - Revoke

    private fun handleRevoke(input: JsonObject): AgentToolResult {
        val bookmarkId = input["bookmark_id"]?.jsonPrimitive?.contentOrNull
            ?: return AgentToolResult("", "Error: 'bookmark_id' is required for revoke.", isError = true)

        if (bookmarkId.isEmpty()) {
            return AgentToolResult("", "Error: 'bookmark_id' is required for revoke.", isError = true)
        }

        val success = FileAccessManager.instance.revokeGrant(bookmarkId)
        return if (success) {
            AgentToolResult("", "Revoked file access grant $bookmarkId.")
        } else {
            AgentToolResult("", "Error: Bookmark ID not found.", isError = true)
        }
    }

    // MARK: - Helpers

    private val imageExtensions = setOf("png", "jpg", "jpeg", "gif", "bmp", "tiff", "webp", "heic")

    /**
     * Heuristic to check if byte data is likely text (not binary).
     */
    private fun isLikelyText(data: ByteArray): Boolean {
        if (data.isEmpty()) return true
        val checkSize = minOf(data.size, 8192)
        var nullCount = 0
        for (i in 0 until checkSize) {
            if (data[i] == 0.toByte()) nullCount++
        }
        return nullCount == 0
    }

    /**
     * Map friendly content type names and extensions to MIME types for SAF.
     */
    private fun resolveMimeTypes(typeNames: List<String>): List<String> {
        val mimeTypes = mutableListOf<String>()
        for (name in typeNames) {
            when (name.lowercase()) {
                "any", "all" -> mimeTypes.add("*/*")
                "image", "images", "photo", "photos" -> mimeTypes.add("image/*")
                "pdf" -> mimeTypes.add("application/pdf")
                "text", "plaintext" -> mimeTypes.add("text/plain")
                "video", "movie" -> mimeTypes.add("video/*")
                "audio", "music", "sound" -> mimeTypes.add("audio/*")
                "json" -> mimeTypes.add("application/json")
                "xml" -> mimeTypes.add("application/xml")
                "html" -> mimeTypes.add("text/html")
                "csv" -> mimeTypes.add("text/csv")
                "archive", "zip", "compressed" -> mimeTypes.add("application/zip")
                "spreadsheet", "excel" -> mimeTypes.add("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
                "presentation" -> mimeTypes.add("application/vnd.openxmlformats-officedocument.presentationml.presentation")
                "rtf" -> mimeTypes.add("application/rtf")
                "data", "binary" -> mimeTypes.add("application/octet-stream")
                "source_code", "sourcecode", "code" -> mimeTypes.add("text/*")
                "folder", "directory" -> { /* handled separately as isDirectory */ }
                else -> {
                    // If it looks like a MIME type (contains /), pass through
                    if ("/" in name) {
                        mimeTypes.add(name)
                    } else {
                        // Try as file extension
                        val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(name)
                        if (mime != null) {
                            mimeTypes.add(mime)
                        }
                    }
                }
            }
        }
        return if (mimeTypes.isEmpty()) listOf("*/*") else mimeTypes
    }

    private fun formatFileSize(bytes: Long): String {
        if (bytes < 1024) return "$bytes B"
        val kb = bytes.toDouble() / 1024
        if (kb < 1024) return String.format("%.1f KB", kb)
        val mb = kb / 1024
        if (mb < 1024) return String.format("%.1f MB", mb)
        val gb = mb / 1024
        return String.format("%.1f GB", gb)
    }

    private fun languageForExtension(ext: String): String? {
        return when (ext) {
            "swift" -> "swift"
            "kt", "kts" -> "kotlin"
            "java" -> "java"
            "py" -> "python"
            "js" -> "javascript"
            "ts" -> "typescript"
            "rb" -> "ruby"
            "go" -> "go"
            "rs" -> "rust"
            "c", "h" -> "c"
            "cpp", "hpp", "cc" -> "cpp"
            "cs" -> "csharp"
            "json" -> "json"
            "xml" -> "xml"
            "yaml", "yml" -> "yaml"
            "toml" -> "toml"
            "md", "markdown" -> "markdown"
            "html", "htm" -> "html"
            "css" -> "css"
            "sh", "bash", "zsh" -> "shell"
            "sql" -> "sql"
            "txt" -> "plaintext"
            else -> null
        }
    }

    private fun matchesGlob(path: String, pattern: String): Boolean {
        val regex = buildString {
            append("^")
            var i = 0
            while (i < pattern.length) {
                val ch = pattern[i]
                when {
                    ch == '*' -> {
                        if (i + 1 < pattern.length && pattern[i + 1] == '*') {
                            append(".*")
                            i += 2
                            if (i < pattern.length && pattern[i] == '/') {
                                i++
                            }
                            continue
                        } else {
                            append("[^/]*")
                        }
                    }
                    ch == '?' -> append("[^/]")
                    ch == '.' -> append("\\.")
                    else -> append(ch)
                }
                i++
            }
            append("$")
        }
        return Regex(regex).containsMatchIn(path)
    }
}
