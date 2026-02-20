package com.pimobile.ai

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.serialization.json.*
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.BufferedReader

class AnthropicAdapter(private val httpClient: OkHttpClient) : ProtocolAdapter {

    private val json = Json { ignoreUnknownKeys = true }

    override fun buildRequest(context: Context, model: ModelDefinition, apiKey: String): Request {
        val body = buildJsonObject {
            put("model", model.id)
            put("max_tokens", context.maxTokens ?: model.maxOutputTokens)
            put("stream", true)

            put("system", context.systemPrompt)

            putJsonArray("messages") {
                for (msg in context.messages) {
                    when {
                        msg.toolResults != null -> {
                            addJsonObject {
                                put("role", "user")
                                putJsonArray("content") {
                                    for (result in msg.toolResults) {
                                        addJsonObject {
                                            put("type", "tool_result")
                                            put("tool_use_id", result.toolCallId)
                                            put("content", result.output)
                                            if (result.isError) {
                                                put("is_error", true)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        msg.role == Role.ASSISTANT -> {
                            addJsonObject {
                                put("role", "assistant")
                                putJsonArray("content") {
                                    if (msg.thinking != null) {
                                        addJsonObject {
                                            put("type", "thinking")
                                            put("thinking", msg.thinking)
                                        }
                                    }
                                    val textContent = when (val c = msg.content) {
                                        is MessageContent.Text -> c.text
                                        is MessageContent.Blocks -> c.blocks.filterIsInstance<ContentBlock.Text>()
                                            .joinToString("") { it.text }
                                    }
                                    if (textContent.isNotEmpty()) {
                                        addJsonObject {
                                            put("type", "text")
                                            put("text", textContent)
                                        }
                                    }
                                    if (msg.toolCalls != null) {
                                        for (call in msg.toolCalls) {
                                            addJsonObject {
                                                put("type", "tool_use")
                                                put("id", call.id)
                                                put("name", call.name)
                                                put("input", json.parseToJsonElement(call.arguments))
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        else -> {
                            addJsonObject {
                                put("role", msg.role.name.lowercase())
                                when (val c = msg.content) {
                                    is MessageContent.Text -> put("content", c.text)
                                    is MessageContent.Blocks -> {
                                        putJsonArray("content") {
                                            for (block in c.blocks) {
                                                when (block) {
                                                    is ContentBlock.Text -> addJsonObject {
                                                        put("type", "text")
                                                        put("text", block.text)
                                                    }
                                                    is ContentBlock.Image -> addJsonObject {
                                                        put("type", "image")
                                                        putJsonObject("source") {
                                                            put("type", "base64")
                                                            put("media_type", block.mimeType)
                                                            put("data", block.base64)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            if (!context.tools.isNullOrEmpty()) {
                putJsonArray("tools") {
                    for (tool in context.tools) {
                        addJsonObject {
                            put("name", tool.name)
                            put("description", tool.description)
                            put("input_schema", tool.parameters)
                        }
                    }
                }
            }

            context.temperature?.let { put("temperature", it) }
        }

        return Request.Builder()
            .url("${model.baseUrl}/v1/messages")
            .addHeader("x-api-key", apiKey)
            .addHeader("anthropic-version", "2023-06-01")
            .addHeader("Content-Type", "application/json")
            .post(body.toString().toRequestBody("application/json".toMediaType()))
            .build()
    }

    override fun parseStreamEvents(response: Response): Flow<StreamEvent> = flow {
        val source = response.body?.source() ?: run {
            emit(StreamEvent.Error("Empty response body"))
            return@flow
        }

        val reader = BufferedReader(source.inputStream().reader())
        var currentEventType: String? = null
        var currentBlockType: String? = null
        var currentBlockId: String? = null

        try {
            var line: String?
            while (reader.readLine().also { line = it } != null) {
                val data = line ?: continue

                if (data.startsWith("event: ")) {
                    currentEventType = data.removePrefix("event: ").trim()
                    continue
                }

                if (!data.startsWith("data: ")) continue
                val payload = data.removePrefix("data: ").trim()
                if (payload.isEmpty()) continue

                try {
                    val obj = json.parseToJsonElement(payload).jsonObject

                    when (currentEventType) {
                        "message_start" -> {
                            val message = obj["message"]?.jsonObject
                            val usage = message?.get("usage")?.jsonObject
                            if (usage != null) {
                                val inputTokens = usage["input_tokens"]?.jsonPrimitive?.intOrNull ?: 0
                                emit(StreamEvent.Usage(inputTokens, 0))
                            }
                        }
                        "content_block_start" -> {
                            val contentBlock = obj["content_block"]?.jsonObject
                            val blockType = contentBlock?.get("type")?.jsonPrimitive?.contentOrNull
                            currentBlockType = blockType
                            when (blockType) {
                                "tool_use" -> {
                                    val id = contentBlock["id"]?.jsonPrimitive?.contentOrNull ?: ""
                                    val name = contentBlock["name"]?.jsonPrimitive?.contentOrNull ?: ""
                                    currentBlockId = id
                                    emit(StreamEvent.ToolCallStart(id, name))
                                }
                                "thinking" -> {
                                    currentBlockId = null
                                }
                                "text" -> {
                                    currentBlockId = null
                                }
                            }
                        }
                        "content_block_delta" -> {
                            val delta = obj["delta"]?.jsonObject
                            val deltaType = delta?.get("type")?.jsonPrimitive?.contentOrNull
                            when (deltaType) {
                                "text_delta" -> {
                                    val text = delta["text"]?.jsonPrimitive?.contentOrNull
                                    if (text != null) {
                                        emit(StreamEvent.TextDelta(text))
                                    }
                                }
                                "thinking_delta" -> {
                                    val thinking = delta["thinking"]?.jsonPrimitive?.contentOrNull
                                    if (thinking != null) {
                                        emit(StreamEvent.ThinkingDelta(thinking))
                                    }
                                }
                                "input_json_delta" -> {
                                    val partialJson = delta["partial_json"]?.jsonPrimitive?.contentOrNull
                                    if (partialJson != null && currentBlockId != null) {
                                        emit(StreamEvent.ToolCallDelta(currentBlockId!!, partialJson))
                                    }
                                }
                            }
                        }
                        "content_block_stop" -> {
                            if (currentBlockType == "tool_use" && currentBlockId != null) {
                                emit(StreamEvent.ToolCallEnd(currentBlockId!!))
                            }
                            currentBlockType = null
                            currentBlockId = null
                        }
                        "message_delta" -> {
                            val delta = obj["delta"]?.jsonObject
                            val usage = obj["usage"]?.jsonObject
                            if (usage != null) {
                                val outputTokens = usage["output_tokens"]?.jsonPrimitive?.intOrNull ?: 0
                                emit(StreamEvent.Usage(0, outputTokens))
                            }
                        }
                        "message_stop" -> {
                            emit(StreamEvent.Done)
                        }
                        "error" -> {
                            val error = obj["error"]?.jsonObject
                            val message = error?.get("message")?.jsonPrimitive?.contentOrNull ?: "Unknown error"
                            emit(StreamEvent.Error(message))
                        }
                    }
                } catch (e: Exception) {
                    // Skip malformed data
                }

                currentEventType = null
            }
        } finally {
            reader.close()
            response.close()
        }
    }
}
