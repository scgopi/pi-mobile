package com.pimobile.agent

import com.pimobile.ai.*
import kotlinx.coroutines.flow.*
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject

class AgentLoop(private val llmClient: LlmClient) {

    private val json = Json { ignoreUnknownKeys = true }

    fun run(
        model: ModelDefinition,
        context: Context,
        tools: List<Tool>,
        apiKey: String
    ): Flow<AgentEvent> = flow {
        val toolDefs = tools.map {
            ToolDefinition(
                name = it.name,
                description = it.description,
                parameters = it.parametersSchema
            )
        }
        val ctxWithTools = context.copy(tools = toolDefs)

        var loopCount = 0
        val maxLoops = 50

        while (loopCount < maxLoops) {
            loopCount++

            val response = collectStreamedResponse(model, ctxWithTools, apiKey)

            emit(AgentEvent.AssistantMessage(
                content = response.textContent,
                thinking = response.thinking
            ))

            if (response.toolCalls.isNullOrEmpty()) {
                emit(AgentEvent.Done)
                break
            }

            val results = mutableListOf<ToolResult>()
            for (call in response.toolCalls) {
                emit(AgentEvent.ToolCallStarted(call.name, call.input))
                val result = executeTool(call, tools)
                results.add(ToolResult(call.id, result.output, result.isError))
                emit(AgentEvent.ToolCallCompleted(call.name, result))
            }

            ctxWithTools.messages.add(Message(
                role = Role.ASSISTANT,
                content = MessageContent.Text(response.textContent),
                toolCalls = response.toolCalls,
                thinking = response.thinking
            ))
            ctxWithTools.messages.add(Message(
                role = Role.USER,
                content = MessageContent.Text(""),
                toolResults = results
            ))
        }

        if (loopCount >= maxLoops) {
            emit(AgentEvent.Error("Agent loop exceeded maximum iterations ($maxLoops)"))
            emit(AgentEvent.Done)
        }
    }

    private suspend fun FlowCollector<AgentEvent>.collectStreamedResponse(
        model: ModelDefinition,
        context: Context,
        apiKey: String
    ): CollectedResponse {
        val textBuilder = StringBuilder()
        val thinkingBuilder = StringBuilder()
        val toolCalls = mutableMapOf<String, ToolCallAccumulator>()
        var hasThinking = false

        llmClient.stream(model, context, apiKey).collect { event ->
            when (event) {
                is StreamEvent.TextDelta -> {
                    textBuilder.append(event.delta)
                    emit(AgentEvent.StreamDelta(event.delta))
                }
                is StreamEvent.ThinkingDelta -> {
                    thinkingBuilder.append(event.delta)
                    hasThinking = true
                    emit(AgentEvent.ThinkingDelta(event.delta))
                }
                is StreamEvent.ToolCallStart -> {
                    toolCalls[event.id] = ToolCallAccumulator(event.id, event.name, StringBuilder())
                }
                is StreamEvent.ToolCallDelta -> {
                    toolCalls[event.id]?.arguments?.append(event.argumentsDelta)
                }
                is StreamEvent.ToolCallEnd -> {
                    // Tool call finalized
                }
                is StreamEvent.Usage -> {
                    emit(AgentEvent.UsageUpdate(event.inputTokens, event.outputTokens))
                }
                is StreamEvent.Error -> {
                    emit(AgentEvent.Error(event.message))
                }
                is StreamEvent.Done -> {
                    // Stream complete
                }
            }
        }

        val completedToolCalls = if (toolCalls.isNotEmpty()) {
            toolCalls.values.map { acc ->
                ToolCall(
                    id = acc.id,
                    name = acc.name,
                    arguments = acc.arguments.toString().ifBlank { "{}" }
                )
            }
        } else null

        return CollectedResponse(
            textContent = textBuilder.toString(),
            thinking = if (hasThinking) thinkingBuilder.toString() else null,
            toolCalls = completedToolCalls
        )
    }

    private suspend fun executeTool(call: ToolCall, tools: List<Tool>): AgentToolResult {
        val tool = tools.find { it.name == call.name }
            ?: return AgentToolResult(call.id, "Error: Unknown tool '${call.name}'", isError = true)

        val validation = SchemaValidator.validate(tool.parametersSchema, call.input)
        if (!validation.isValid) {
            return AgentToolResult(
                call.id,
                "Validation error: ${validation.errors.joinToString()}",
                isError = true
            )
        }

        return try {
            tool.execute(call.input).copy(toolCallId = call.id)
        } catch (e: Exception) {
            AgentToolResult(
                call.id,
                "Tool error: ${e.message}",
                ToolResultDetails.Error(e.message ?: "", null),
                true
            )
        }
    }
}

private data class ToolCallAccumulator(
    val id: String,
    val name: String,
    val arguments: StringBuilder
)

private data class CollectedResponse(
    val textContent: String,
    val thinking: String?,
    val toolCalls: List<ToolCall>?
)
