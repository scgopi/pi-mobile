package com.pimobile.ai

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.serialization.json.*
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.BufferedReader

class OpenAICompletionsAdapter(private val httpClient: OkHttpClient) : ProtocolAdapter {

    private val json = Json { ignoreUnknownKeys = true }

    override fun buildRequest(context: Context, model: ModelDefinition, apiKey: String): Request {
        val body = buildJsonObject {
            put("model", model.id)
            put("stream", true)

            putJsonArray("messages") {
                addJsonObject {
                    put("role", "system")
                    put("content", context.systemPrompt)
                }
                for (msg in context.messages) {
                    when {
                        msg.toolResults != null -> {
                            for (result in msg.toolResults) {
                                addJsonObject {
                                    put("role", "tool")
                                    put("tool_call_id", result.toolCallId)
                                    put("content", result.output)
                                }
                            }
                        }
                        msg.role == Role.ASSISTANT && msg.toolCalls != null -> {
                            addJsonObject {
                                put("role", "assistant")
                                val textContent = when (val c = msg.content) {
                                    is MessageContent.Text -> c.text
                                    is MessageContent.Blocks -> c.blocks.filterIsInstance<ContentBlock.Text>()
                                        .joinToString("") { it.text }
                                }
                                if (textContent.isNotEmpty()) {
                                    put("content", textContent)
                                } else {
                                    put("content", JsonNull)
                                }
                                putJsonArray("tool_calls") {
                                    for (call in msg.toolCalls) {
                                        addJsonObject {
                                            put("id", call.id)
                                            put("type", "function")
                                            putJsonObject("function") {
                                                put("name", call.name)
                                                put("arguments", call.arguments)
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
                                                        put("type", "image_url")
                                                        putJsonObject("image_url") {
                                                            put("url", "data:${block.mimeType};base64,${block.base64}")
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
                            put("type", "function")
                            putJsonObject("function") {
                                put("name", tool.name)
                                put("description", tool.description)
                                put("parameters", tool.parameters)
                            }
                        }
                    }
                }
            }

            context.temperature?.let { put("temperature", it) }

            val isCerebras = model.provider.lowercase().contains("cerebras")
            val isMistral = model.provider.lowercase().contains("mistral")

            if (context.maxTokens != null) {
                if (isMistral) {
                    put("max_tokens", context.maxTokens)
                } else {
                    put("max_completion_tokens", context.maxTokens)
                }
            }

            if (!isCerebras) {
                put("stream_options", buildJsonObject { put("include_usage", true) })
            }
        }

        return Request.Builder()
            .url("${model.baseUrl}/v1/chat/completions")
            .addHeader("Authorization", "Bearer $apiKey")
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

        try {
            var line: String?
            while (reader.readLine().also { line = it } != null) {
                val data = line ?: continue
                if (!data.startsWith("data: ")) continue
                val payload = data.removePrefix("data: ").trim()
                if (payload == "[DONE]") {
                    emit(StreamEvent.Done)
                    break
                }

                try {
                    val obj = json.parseToJsonElement(payload).jsonObject

                    val usage = obj["usage"]?.jsonObject
                    if (usage != null) {
                        val inputTokens = usage["prompt_tokens"]?.jsonPrimitive?.intOrNull ?: 0
                        val outputTokens = usage["completion_tokens"]?.jsonPrimitive?.intOrNull ?: 0
                        if (inputTokens > 0 || outputTokens > 0) {
                            emit(StreamEvent.Usage(inputTokens, outputTokens))
                        }
                    }

                    val choices = obj["choices"]?.jsonArray ?: continue
                    if (choices.isEmpty()) continue

                    val delta = choices[0].jsonObject["delta"]?.jsonObject ?: continue

                    val content = delta["content"]?.jsonPrimitive?.contentOrNull
                    if (content != null) {
                        emit(StreamEvent.TextDelta(content))
                    }

                    val toolCalls = delta["tool_calls"]?.jsonArray
                    if (toolCalls != null) {
                        for (tc in toolCalls) {
                            val tcObj = tc.jsonObject
                            val function = tcObj["function"]?.jsonObject
                            val tcId = tcObj["id"]?.jsonPrimitive?.contentOrNull
                            val tcName = function?.get("name")?.jsonPrimitive?.contentOrNull
                            val tcArgs = function?.get("arguments")?.jsonPrimitive?.contentOrNull

                            if (tcId != null && tcName != null) {
                                emit(StreamEvent.ToolCallStart(tcId, tcName))
                            }
                            if (tcArgs != null) {
                                val id = tcId ?: ""
                                emit(StreamEvent.ToolCallDelta(id, tcArgs))
                            }
                        }
                    }
                } catch (e: Exception) {
                    // Skip malformed chunks
                }
            }
        } finally {
            reader.close()
            response.close()
        }
    }
}
