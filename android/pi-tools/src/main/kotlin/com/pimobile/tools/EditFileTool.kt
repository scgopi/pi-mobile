package com.pimobile.tools

import com.pimobile.agent.*
import kotlinx.serialization.json.*
import java.io.File

class EditFileTool(private val sandboxDir: File) : Tool {

    override val name = "edit_file"
    override val description = "Apply search/replace edits to a file. Each edit specifies an exact string to find and its replacement."
    override val parametersSchema = buildJsonObject {
        put("type", "object")
        putJsonObject("properties") {
            putJsonObject("path") {
                put("type", "string")
                put("description", "File path relative to sandbox directory")
            }
            putJsonObject("edits") {
                put("type", "array")
                putJsonObject("items") {
                    put("type", "object")
                    putJsonObject("properties") {
                        putJsonObject("search") {
                            put("type", "string")
                            put("description", "Exact text to search for")
                        }
                        putJsonObject("replace") {
                            put("type", "string")
                            put("description", "Text to replace with")
                        }
                    }
                    putJsonArray("required") { add("search"); add("replace") }
                }
            }
        }
        putJsonArray("required") { add("path"); add("edits") }
    }

    override suspend fun execute(input: JsonObject): AgentToolResult {
        val path = input["path"]?.jsonPrimitive?.contentOrNull
            ?: return AgentToolResult("", "Error: 'path' is required", isError = true)
        val editsArray = input["edits"]?.jsonArray
            ?: return AgentToolResult("", "Error: 'edits' is required", isError = true)

        return try {
            val file = File(sandboxDir, path).canonicalFile
            if (!file.canonicalPath.startsWith(sandboxDir.canonicalPath)) {
                return AgentToolResult("", "Error: Path is outside sandbox", isError = true)
            }
            if (!file.exists()) {
                return AgentToolResult("", "Error: File not found: $path", isError = true)
            }

            val originalContent = file.readText()
            var currentContent = originalContent
            val appliedEdits = mutableListOf<String>()

            for (editJson in editsArray) {
                val editObj = editJson.jsonObject
                val search = editObj["search"]?.jsonPrimitive?.contentOrNull ?: continue
                val replace = editObj["replace"]?.jsonPrimitive?.contentOrNull ?: continue

                val occurrences = countOccurrences(currentContent, search)
                when {
                    occurrences == 0 -> {
                        return AgentToolResult(
                            "",
                            "Error: Search string not found in file:\n$search",
                            isError = true
                        )
                    }
                    occurrences > 1 -> {
                        return AgentToolResult(
                            "",
                            "Error: Search string found $occurrences times (must be unique):\n$search",
                            isError = true
                        )
                    }
                }

                currentContent = currentContent.replaceFirst(search, replace)
                appliedEdits.add("- Replaced ${search.length} chars with ${replace.length} chars")
            }

            file.writeText(currentContent)

            val hunks = generateDiffHunks(originalContent, currentContent)
            val diffText = formatUnifiedDiff(path, hunks)

            AgentToolResult(
                "",
                "Applied ${appliedEdits.size} edit(s) to $path\n$diffText",
                ToolResultDetails.Diff(path, hunks)
            )
        } catch (e: Exception) {
            AgentToolResult("", "Error editing file: ${e.message}", isError = true)
        }
    }

    private fun countOccurrences(text: String, search: String): Int {
        var count = 0
        var index = 0
        while (true) {
            index = text.indexOf(search, index)
            if (index == -1) break
            count++
            index += search.length
        }
        return count
    }

    private fun generateDiffHunks(original: String, modified: String): List<DiffHunk> {
        val oldLines = original.lines()
        val newLines = modified.lines()
        val hunks = mutableListOf<DiffHunk>()

        var i = 0
        var j = 0
        while (i < oldLines.size || j < newLines.size) {
            if (i < oldLines.size && j < newLines.size && oldLines[i] == newLines[j]) {
                i++
                j++
                continue
            }

            val hunkStartOld = i
            val hunkStartNew = j
            val lines = mutableListOf<DiffLine>()

            val contextStart = maxOf(0, i - 3)
            for (c in contextStart until i) {
                lines.add(DiffLine(DiffLineType.CONTEXT, oldLines[c]))
            }

            while (i < oldLines.size && (j >= newLines.size || oldLines[i] != newLines.getOrNull(j))) {
                lines.add(DiffLine(DiffLineType.REMOVE, oldLines[i]))
                i++
            }
            while (j < newLines.size && (i >= oldLines.size || newLines[j] != oldLines.getOrNull(i))) {
                lines.add(DiffLine(DiffLineType.ADD, newLines[j]))
                j++
            }

            val contextEnd = minOf(oldLines.size, i + 3)
            for (c in i until contextEnd) {
                if (c < oldLines.size) {
                    lines.add(DiffLine(DiffLineType.CONTEXT, oldLines[c]))
                }
            }

            val removedCount = lines.count { it.type == DiffLineType.REMOVE } +
                    lines.count { it.type == DiffLineType.CONTEXT }
            val addedCount = lines.count { it.type == DiffLineType.ADD } +
                    lines.count { it.type == DiffLineType.CONTEXT }

            hunks.add(DiffHunk(
                startLineOld = hunkStartOld + 1,
                countOld = removedCount,
                startLineNew = hunkStartNew + 1,
                countNew = addedCount,
                lines = lines
            ))

            i = contextEnd
            j += (contextEnd - hunkStartOld) - lines.count { it.type == DiffLineType.REMOVE } +
                    lines.count { it.type == DiffLineType.ADD }
            break
        }

        return hunks
    }

    private fun formatUnifiedDiff(path: String, hunks: List<DiffHunk>): String {
        val sb = StringBuilder()
        sb.appendLine("--- a/$path")
        sb.appendLine("+++ b/$path")
        for (hunk in hunks) {
            sb.appendLine("@@ -${hunk.startLineOld},${hunk.countOld} +${hunk.startLineNew},${hunk.countNew} @@")
            for (line in hunk.lines) {
                val prefix = when (line.type) {
                    DiffLineType.CONTEXT -> " "
                    DiffLineType.ADD -> "+"
                    DiffLineType.REMOVE -> "-"
                }
                sb.appendLine("$prefix${line.content}")
            }
        }
        return sb.toString()
    }
}
