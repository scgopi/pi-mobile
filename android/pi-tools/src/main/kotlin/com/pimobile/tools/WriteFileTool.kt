package com.pimobile.tools

import com.pimobile.agent.AgentToolResult
import com.pimobile.agent.Tool
import kotlinx.serialization.json.*
import java.io.File

class WriteFileTool(private val sandboxDir: File) : Tool {

    override val name = "write_file"
    override val description = "Write content to a file in the sandbox directory. Creates parent directories if needed."
    override val parametersSchema = buildJsonObject {
        put("type", "object")
        putJsonObject("properties") {
            putJsonObject("path") {
                put("type", "string")
                put("description", "File path relative to sandbox directory")
            }
            putJsonObject("content") {
                put("type", "string")
                put("description", "Content to write to the file")
            }
        }
        putJsonArray("required") { add("path"); add("content") }
    }

    override suspend fun execute(input: JsonObject): AgentToolResult {
        val path = input["path"]?.jsonPrimitive?.contentOrNull
            ?: return AgentToolResult("", "Error: 'path' is required", isError = true)
        val content = input["content"]?.jsonPrimitive?.contentOrNull
            ?: return AgentToolResult("", "Error: 'content' is required", isError = true)

        return try {
            val file = File(sandboxDir, path).canonicalFile
            if (!file.canonicalPath.startsWith(sandboxDir.canonicalPath)) {
                return AgentToolResult("", "Error: Path is outside sandbox", isError = true)
            }

            file.parentFile?.mkdirs()
            file.writeText(content)

            val bytes = file.length()
            AgentToolResult("", "Successfully wrote $bytes bytes to $path")
        } catch (e: Exception) {
            AgentToolResult("", "Error writing file: ${e.message}", isError = true)
        }
    }
}
