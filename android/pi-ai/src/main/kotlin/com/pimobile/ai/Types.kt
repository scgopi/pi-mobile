package com.pimobile.ai

import kotlinx.serialization.*
import kotlinx.serialization.json.*

@Serializable
enum class WireProtocol {
    @SerialName("openai-completions") OPENAI_COMPLETIONS,
    @SerialName("openai-responses") OPENAI_RESPONSES,
    @SerialName("anthropic") ANTHROPIC,
    @SerialName("google") GOOGLE,
    @SerialName("azure") AZURE
}

@Serializable
data class ModelCapabilities(
    val vision: Boolean = false,
    val toolUse: Boolean = false,
    val streaming: Boolean = true,
    val reasoning: Boolean = false
)

@Serializable
data class ModelDefinition(
    val id: String,
    val name: String,
    val provider: String,
    val protocol: WireProtocol,
    val baseUrl: String,
    val contextWindow: Int,
    val maxOutputTokens: Int,
    val inputCostPer1M: Double,
    val outputCostPer1M: Double,
    val capabilities: ModelCapabilities = ModelCapabilities()
)

@Serializable
enum class Role {
    @SerialName("user") USER,
    @SerialName("assistant") ASSISTANT,
    @SerialName("system") SYSTEM
}

@Serializable
sealed class ContentBlock {
    @Serializable
    @SerialName("text")
    data class Text(val text: String) : ContentBlock()

    @Serializable
    @SerialName("image")
    data class Image(val base64: String, val mimeType: String) : ContentBlock()
}

@Serializable
sealed class MessageContent {
    @Serializable
    @SerialName("text")
    data class Text(val text: String) : MessageContent()

    @Serializable
    @SerialName("blocks")
    data class Blocks(val blocks: List<ContentBlock>) : MessageContent()
}

@Serializable
data class ToolDefinition(
    val name: String,
    val description: String,
    val parameters: JsonObject
)

@Serializable
data class ToolCall(
    val id: String,
    val name: String,
    val arguments: String
) {
    val input: JsonObject
        get() = Json.parseToJsonElement(arguments).jsonObject
}

@Serializable
data class ToolResult(
    val toolCallId: String,
    val output: String,
    val isError: Boolean = false
)

@Serializable
data class Message(
    val role: Role,
    val content: MessageContent,
    val toolCalls: List<ToolCall>? = null,
    val toolResults: List<ToolResult>? = null,
    val thinking: String? = null
)

data class Context(
    val systemPrompt: String,
    val messages: MutableList<Message>,
    val tools: List<ToolDefinition>? = null,
    val temperature: Double? = null,
    val maxTokens: Int? = null
)

sealed class StreamEvent {
    data class TextDelta(val delta: String) : StreamEvent()
    data class ThinkingDelta(val delta: String) : StreamEvent()
    data class ToolCallStart(val id: String, val name: String) : StreamEvent()
    data class ToolCallDelta(val id: String, val argumentsDelta: String) : StreamEvent()
    data class ToolCallEnd(val id: String) : StreamEvent()
    data class Usage(val inputTokens: Int, val outputTokens: Int) : StreamEvent()
    data object Done : StreamEvent()
    data class Error(val message: String) : StreamEvent()
}
