package com.pimobile.tools

import com.pimobile.agent.AgentToolResult
import com.pimobile.agent.Tool
import com.pimobile.agent.ToolResultDetails
import kotlinx.serialization.json.*
import java.io.File
import java.nio.file.FileSystems
import java.nio.file.Files
import java.text.SimpleDateFormat
import java.util.*
import kotlin.streams.toList

class ListFilesTool(private val sandboxDir: File) : Tool {

    override val name = "list_files"
    override val description = "List directory contents. Supports glob patterns and recursive listing."
    override val parametersSchema = buildJsonObject {
        put("type", "object")
        putJsonObject("properties") {
            putJsonObject("path") {
                put("type", "string")
                put("description", "Directory path relative to sandbox (defaults to root)")
            }
            putJsonObject("glob") {
                put("type", "string")
                put("description", "Glob pattern to filter files (e.g., '*.kt', '**/*.json')")
            }
            putJsonObject("recursive") {
                put("type", "boolean")
                put("description", "List recursively (default: false)")
            }
        }
    }

    private val dateFormat = SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US)

    override suspend fun execute(input: JsonObject): AgentToolResult {
        val path = input["path"]?.jsonPrimitive?.contentOrNull ?: ""
        val glob = input["glob"]?.jsonPrimitive?.contentOrNull
        val recursive = input["recursive"]?.jsonPrimitive?.booleanOrNull ?: false

        return try {
            val dir = File(sandboxDir, path).canonicalFile
            if (!dir.canonicalPath.startsWith(sandboxDir.canonicalPath)) {
                return AgentToolResult("", "Error: Path is outside sandbox", isError = true)
            }
            if (!dir.exists()) {
                return AgentToolResult("", "Error: Directory not found: $path", isError = true)
            }
            if (!dir.isDirectory) {
                return AgentToolResult("", "Error: Not a directory: $path", isError = true)
            }

            val entries = if (recursive) {
                Files.walk(dir.toPath()).toList().drop(1).map { it.toFile() }
            } else {
                dir.listFiles()?.toList() ?: emptyList()
            }

            val filtered = if (glob != null) {
                val matcher = FileSystems.getDefault().getPathMatcher("glob:$glob")
                entries.filter { matcher.matches(dir.toPath().relativize(it.toPath())) }
            } else {
                entries
            }

            val sorted = filtered.sortedWith(compareBy<File> { !it.isDirectory }.thenBy { it.name })

            val columns = listOf("Name", "Size", "Modified", "Type")
            val rows = sorted.map { file ->
                val relativePath = sandboxDir.toPath().relativize(file.toPath()).toString()
                val size = if (file.isDirectory) "-" else formatSize(file.length())
                val modified = dateFormat.format(Date(file.lastModified()))
                val type = if (file.isDirectory) "dir" else file.extension.ifEmpty { "file" }
                listOf(relativePath, size, modified, type)
            }

            val output = buildString {
                appendLine("Directory: ${if (path.isEmpty()) "/" else path} (${sorted.size} items)")
                appendLine()
                for (row in rows) {
                    val typeIndicator = if (row[3] == "dir") "/" else ""
                    appendLine("${row[0]}$typeIndicator  ${row[1]}  ${row[2]}")
                }
            }

            AgentToolResult(
                "",
                output,
                ToolResultDetails.Table(columns, rows)
            )
        } catch (e: Exception) {
            AgentToolResult("", "Error listing files: ${e.message}", isError = true)
        }
    }

    private fun formatSize(bytes: Long): String {
        return when {
            bytes < 1024 -> "${bytes}B"
            bytes < 1024 * 1024 -> "${bytes / 1024}KB"
            bytes < 1024 * 1024 * 1024 -> "${bytes / (1024 * 1024)}MB"
            else -> "${bytes / (1024 * 1024 * 1024)}GB"
        }
    }
}
