package com.pimobile.ai

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.serialization.json.*
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.BufferedReader

/**
 * Adapter for Azure OpenAI Service.
 *
 * Azure uses the same wire format as OpenAI Responses API but with:
 * - `baseUrl` as the full endpoint URL (e.g. `https://{resource}.cognitiveservices.azure.com/openai/responses?api-version=2025-04-01-preview`)
 * - `api-key` header instead of `Authorization: Bearer`
 */
class AzureOpenAIAdapter(private val httpClient: OkHttpClient) : ProtocolAdapter {

    private val json = Json { ignoreUnknownKeys = true }

    override fun buildRequest(context: Context, model: ModelDefinition, apiKey: String): Request {
        val body = buildJsonObject {
            put("model", model.id)
            put("stream", true)

            putJsonArray("input") {
                addJsonObject {
                    put("role", "system")
                    putJsonArray("content") {
                        addJsonObject {
                            put("type", "input_text")
                            put("text", context.systemPrompt)
                        }
                    }
                }
                for (msg in context.messages) {
                    when {
                        msg.toolResults != null -> {
                            for (result in msg.toolResults) {
                                addJsonObject {
                                    put("type", "function_call_output")
                                    put("call_id", result.toolCallId)
                                    put("output", result.output)
                                }
                            }
                        }
                        msg.role == Role.ASSISTANT && msg.toolCalls != null -> {
                            val textContent = when (val c = msg.content) {
                                is MessageContent.Text -> c.text
                                is MessageContent.Blocks -> c.blocks.filterIsInstance<ContentBlock.Text>()
                                    .joinToString("") { it.text }
                            }
                            if (textContent.isNotEmpty()) {
                                addJsonObject {
                                    put("role", "assistant")
                                    putJsonArray("content") {
                                        addJsonObject {
                                            put("type", "output_text")
                                            put("text", textContent)
                                        }
                                    }
                                }
                            }
                            for (call in msg.toolCalls) {
                                addJsonObject {
                                    put("type", "function_call")
                                    put("call_id", call.id)
                                    put("name", call.name)
                                    put("arguments", call.arguments)
                                    put("status", "completed")
                                }
                            }
                        }
                        else -> {
                            addJsonObject {
                                put("role", msg.role.name.lowercase())
                                putJsonArray("content") {
                                    when (val c = msg.content) {
                                        is MessageContent.Text -> addJsonObject {
                                            put("type", "input_text")
                                            put("text", c.text)
                                        }
                                        is MessageContent.Blocks -> {
                                            for (block in c.blocks) {
                                                when (block) {
                                                    is ContentBlock.Text -> addJsonObject {
                                                        put("type", "input_text")
                                                        put("text", block.text)
                                                    }
                                                    is ContentBlock.Image -> addJsonObject {
                                                        put("type", "input_image")
                                                        putJsonObject("image") {
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
                            put("type", "function")
                            put("name", tool.name)
                            put("description", tool.description)
                            put("parameters", tool.parameters)
                        }
                    }
                }
            }

            if (!model.capabilities.reasoning) {
                context.temperature?.let { put("temperature", it) }
            }
            context.maxTokens?.let { put("max_output_tokens", it) }
        }

        // Azure: use baseUrl as full endpoint, api-key header instead of Bearer
        return Request.Builder()
            .url(model.baseUrl)
            .addHeader("api-key", apiKey)
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
        val activeToolCalls = mutableMapOf<String, String>()

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
                        "response.output_text.delta" -> {
                            val delta = obj["delta"]?.jsonPrimitive?.contentOrNull
                            if (delta != null) {
                                emit(StreamEvent.TextDelta(delta))
                            }
                        }
                        "response.function_call_arguments.delta" -> {
                            val delta = obj["delta"]?.jsonPrimitive?.contentOrNull
                            val itemId = obj["item_id"]?.jsonPrimitive?.contentOrNull ?: ""
                            if (delta != null) {
                                emit(StreamEvent.ToolCallDelta(itemId, delta))
                            }
                        }
                        "response.output_item.added" -> {
                            val item = obj["item"]?.jsonObject
                            if (item != null && item["type"]?.jsonPrimitive?.contentOrNull == "function_call") {
                                // Use item "id" (fc_ prefix) — matches "item_id" in delta events
                                val itemId = item["id"]?.jsonPrimitive?.contentOrNull ?: item["call_id"]?.jsonPrimitive?.contentOrNull ?: ""
                                val name = item["name"]?.jsonPrimitive?.contentOrNull ?: ""
                                activeToolCalls[itemId] = name
                                emit(StreamEvent.ToolCallStart(itemId, name))
                            }
                        }
                        "response.output_item.done" -> {
                            val item = obj["item"]?.jsonObject
                            if (item != null && item["type"]?.jsonPrimitive?.contentOrNull == "function_call") {
                                val itemId = item["id"]?.jsonPrimitive?.contentOrNull ?: item["call_id"]?.jsonPrimitive?.contentOrNull ?: ""
                                emit(StreamEvent.ToolCallEnd(itemId))
                                activeToolCalls.remove(itemId)
                            }
                        }
                        "response.completed" -> {
                            val resp = obj["response"]?.jsonObject
                            val usage = resp?.get("usage")?.jsonObject
                            if (usage != null) {
                                val inputTokens = usage["input_tokens"]?.jsonPrimitive?.intOrNull ?: 0
                                val outputTokens = usage["output_tokens"]?.jsonPrimitive?.intOrNull ?: 0
                                emit(StreamEvent.Usage(inputTokens, outputTokens))
                            }
                            emit(StreamEvent.Done)
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
