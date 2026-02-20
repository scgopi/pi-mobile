package com.pimobile.tools

import android.content.ContentResolver
import android.net.Uri
import com.pimobile.agent.AgentToolResult
import com.pimobile.agent.Tool
import com.pimobile.agent.ToolResultDetails
import kotlinx.serialization.json.*
import java.io.File
import android.util.Base64

class ReadFileTool(
    private val contentResolver: ContentResolver,
    private val sandboxDir: File
) : Tool {

    override val name = "read_file"
    override val description = "Read the contents of a file. Supports sandbox paths and content:// URIs. For images, returns base64-encoded data."
    override val parametersSchema = buildJsonObject {
        put("type", "object")
        putJsonObject("properties") {
            putJsonObject("path") {
                put("type", "string")
                put("description", "File path (sandbox-relative) or content:// URI")
            }
            putJsonObject("startLine") {
                put("type", "integer")
                put("description", "Starting line number (1-based, optional)")
            }
            putJsonObject("endLine") {
                put("type", "integer")
                put("description", "Ending line number (1-based, inclusive, optional)")
            }
        }
        putJsonArray("required") { add("path") }
    }

    private val imageExtensions = setOf("jpg", "jpeg", "png", "gif", "webp", "bmp")

    private val extensionToLanguage = mapOf(
        "kt" to "kotlin", "java" to "java", "py" to "python", "js" to "javascript",
        "ts" to "typescript", "json" to "json", "xml" to "xml", "html" to "html",
        "css" to "css", "md" to "markdown", "yaml" to "yaml", "yml" to "yaml",
        "sh" to "bash", "sql" to "sql", "swift" to "swift", "rs" to "rust",
        "go" to "go", "rb" to "ruby", "c" to "c", "cpp" to "cpp", "h" to "c",
        "gradle" to "groovy", "toml" to "toml", "txt" to "text"
    )

    override suspend fun execute(input: JsonObject): AgentToolResult {
        val path = input["path"]?.jsonPrimitive?.contentOrNull
            ?: return AgentToolResult("", "Error: 'path' is required", isError = true)

        val startLine = input["startLine"]?.jsonPrimitive?.intOrNull
        val endLine = input["endLine"]?.jsonPrimitive?.intOrNull

        return try {
            if (path.startsWith("content://")) {
                readContentUri(path, startLine, endLine)
            } else {
                readSandboxFile(path, startLine, endLine)
            }
        } catch (e: Exception) {
            AgentToolResult("", "Error reading file: ${e.message}", isError = true)
        }
    }

    private fun readSandboxFile(path: String, startLine: Int?, endLine: Int?): AgentToolResult {
        val file = File(sandboxDir, path).canonicalFile
        if (!file.canonicalPath.startsWith(sandboxDir.canonicalPath)) {
            return AgentToolResult("", "Error: Path is outside sandbox", isError = true)
        }

        if (!file.exists()) {
            return AgentToolResult("", "Error: File not found: $path", isError = true)
        }

        val extension = file.extension.lowercase()

        if (extension in imageExtensions) {
            val bytes = file.readBytes()
            val base64 = Base64.encodeToString(bytes, Base64.NO_WRAP)
            val mimeType = when (extension) {
                "jpg", "jpeg" -> "image/jpeg"
                "png" -> "image/png"
                "gif" -> "image/gif"
                "webp" -> "image/webp"
                "bmp" -> "image/bmp"
                else -> "application/octet-stream"
            }
            return AgentToolResult(
                "",
                "[Image: ${file.name}, ${bytes.size} bytes, $mimeType]\nbase64:$base64"
            )
        }

        val lines = file.readLines()
        val language = extensionToLanguage[extension]

        val start = (startLine ?: 1).coerceAtLeast(1)
        val end = (endLine ?: lines.size).coerceAtMost(lines.size)

        val numberedLines = lines.subList(start - 1, end).mapIndexed { index, line ->
            "${start + index}: $line"
        }

        val content = numberedLines.joinToString("\n")
        val header = "File: $path (${lines.size} lines total, showing $start-$end)"

        return AgentToolResult(
            "",
            "$header\n$content",
            ToolResultDetails.File(path, content, language)
        )
    }

    private fun readContentUri(uriString: String, startLine: Int?, endLine: Int?): AgentToolResult {
        val uri = Uri.parse(uriString)
        val inputStream = contentResolver.openInputStream(uri)
            ?: return AgentToolResult("", "Error: Cannot open URI: $uriString", isError = true)

        val content = inputStream.bufferedReader().use { it.readText() }
        val lines = content.lines()

        val start = (startLine ?: 1).coerceAtLeast(1)
        val end = (endLine ?: lines.size).coerceAtMost(lines.size)

        val numberedLines = lines.subList(start - 1, end).mapIndexed { index, line ->
            "${start + index}: $line"
        }

        val result = numberedLines.joinToString("\n")
        return AgentToolResult(
            "",
            "URI: $uriString (${lines.size} lines total, showing $start-$end)\n$result"
        )
    }
}
