package com.pimobile.agent

import com.pimobile.ai.*
import kotlinx.serialization.json.JsonObject

interface Tool {
    val name: String
    val description: String
    val parametersSchema: JsonObject
    suspend fun execute(input: JsonObject): AgentToolResult
}

data class AgentToolResult(
    val toolCallId: String,
    val output: String,
    val details: ToolResultDetails? = null,
    val isError: Boolean = false
)

sealed class ToolResultDetails {
    data class File(val path: String, val content: String, val language: String? = null) : ToolResultDetails()
    data class Diff(val path: String, val hunks: List<DiffHunk>) : ToolResultDetails()
    data class Table(val columns: List<String>, val rows: List<List<String>>) : ToolResultDetails()
    data class Error(val message: String, val code: String? = null) : ToolResultDetails()
}

data class DiffHunk(
    val startLineOld: Int,
    val countOld: Int,
    val startLineNew: Int,
    val countNew: Int,
    val lines: List<DiffLine>
)

data class DiffLine(val type: DiffLineType, val content: String)

enum class DiffLineType { CONTEXT, ADD, REMOVE }

sealed class AgentEvent {
    data class StreamDelta(val delta: String) : AgentEvent()
    data class ThinkingDelta(val delta: String) : AgentEvent()
    data class AssistantMessage(val content: String, val thinking: String? = null) : AgentEvent()
    data class ToolCallStarted(val name: String, val input: JsonObject) : AgentEvent()
    data class ToolCallCompleted(val name: String, val result: AgentToolResult) : AgentEvent()
    data class UsageUpdate(val inputTokens: Int, val outputTokens: Int) : AgentEvent()
    data class Error(val message: String) : AgentEvent()
    data object Done : AgentEvent()
}
