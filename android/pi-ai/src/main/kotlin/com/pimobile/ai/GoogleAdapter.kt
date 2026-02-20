package com.pimobile.ai

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.serialization.json.*
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.BufferedReader

class GoogleAdapter(private val httpClient: OkHttpClient) : ProtocolAdapter {

    private val json = Json { ignoreUnknownKeys = true }

    override fun buildRequest(context: Context, model: ModelDefinition, apiKey: String): Request {
        val body = buildJsonObject {
            putJsonArray("contents") {
                for (msg in context.messages) {
                    when {
                        msg.toolResults != null -> {
                            addJsonObject {
                                put("role", "user")
                                putJsonArray("parts") {
                                    for (result in msg.toolResults) {
                                        addJsonObject {
                                            putJsonObject("functionResponse") {
                                                put("name", result.toolCallId)
                                                putJsonObject("response") {
                                                    put("result", result.output)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        msg.role == Role.ASSISTANT -> {
                            addJsonObject {
                                put("role", "model")
                                putJsonArray("parts") {
                                    val textContent = when (val c = msg.content) {
                                        is MessageContent.Text -> c.text
                                        is MessageContent.Blocks -> c.blocks.filterIsInstance<ContentBlock.Text>()
                                            .joinToString("") { it.text }
                                    }
                                    if (textContent.isNotEmpty()) {
                                        addJsonObject { put("text", textContent) }
                                    }
                                    if (msg.toolCalls != null) {
                                        for (call in msg.toolCalls) {
                                            addJsonObject {
                                                putJsonObject("functionCall") {
                                                    put("name", call.name)
                                                    put("args", json.parseToJsonElement(call.arguments))
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        else -> {
                            addJsonObject {
                                put("role", "user")
                                putJsonArray("parts") {
                                    when (val c = msg.content) {
                                        is MessageContent.Text -> {
                                            addJsonObject { put("text", c.text) }
                                        }
                                        is MessageContent.Blocks -> {
                                            for (block in c.blocks) {
                                                when (block) {
                                                    is ContentBlock.Text -> addJsonObject {
                                                        put("text", block.text)
                                                    }
                                                    is ContentBlock.Image -> addJsonObject {
                                                        putJsonObject("inlineData") {
                                                            put("mimeType", block.mimeType)
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

            putJsonObject("systemInstruction") {
                putJsonArray("parts") {
                    addJsonObject { put("text", context.systemPrompt) }
                }
            }

            putJsonObject("generationConfig") {
                context.temperature?.let { put("temperature", it) }
                context.maxTokens?.let { put("maxOutputTokens", it) }
            }

            if (!context.tools.isNullOrEmpty()) {
                putJsonArray("tools") {
                    addJsonObject {
                        putJsonArray("functionDeclarations") {
                            for (tool in context.tools) {
                                addJsonObject {
                                    put("name", tool.name)
                                    put("description", tool.description)
                                    put("parameters", tool.parameters)
                                }
                            }
                        }
                    }
                }
            }
        }

        val url = "${model.baseUrl}/v1beta/models/${model.id}:streamGenerateContent?alt=sse&key=$apiKey"

        return Request.Builder()
            .url(url)
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
        var toolCallCounter = 0

        try {
            var line: String?
            while (reader.readLine().also { line = it } != null) {
                val data = line ?: continue
                if (!data.startsWith("data: ")) continue
                val payload = data.removePrefix("data: ").trim()
                if (payload.isEmpty()) continue

                try {
                    val obj = json.parseToJsonElement(payload).jsonObject

                    val candidates = obj["candidates"]?.jsonArray
                    if (candidates != null && candidates.isNotEmpty()) {
                        val content = candidates[0].jsonObject["content"]?.jsonObject
                        val parts = content?.get("parts")?.jsonArray

                        if (parts != null) {
                            for (part in parts) {
                                val partObj = part.jsonObject
                                val text = partObj["text"]?.jsonPrimitive?.contentOrNull
                                if (text != null) {
                                    emit(StreamEvent.TextDelta(text))
                                }

                                val functionCall = partObj["functionCall"]?.jsonObject
                                if (functionCall != null) {
                                    val name = functionCall["name"]?.jsonPrimitive?.contentOrNull ?: ""
                                    val args = functionCall["args"]?.jsonObject?.toString() ?: "{}"
                                    val callId = "google_call_${toolCallCounter++}"
                                    emit(StreamEvent.ToolCallStart(callId, name))
                                    emit(StreamEvent.ToolCallDelta(callId, args))
                                    emit(StreamEvent.ToolCallEnd(callId))
                                }
                            }
                        }

                        val finishReason = candidates[0].jsonObject["finishReason"]?.jsonPrimitive?.contentOrNull
                        if (finishReason == "STOP" || finishReason == "MAX_TOKENS") {
                            // Will emit Done after usage
                        }
                    }

                    val usageMetadata = obj["usageMetadata"]?.jsonObject
                    if (usageMetadata != null) {
                        val inputTokens = usageMetadata["promptTokenCount"]?.jsonPrimitive?.intOrNull ?: 0
                        val outputTokens = usageMetadata["candidatesTokenCount"]?.jsonPrimitive?.intOrNull ?: 0
                        emit(StreamEvent.Usage(inputTokens, outputTokens))
                    }
                } catch (e: Exception) {
                    // Skip malformed data
                }
            }

            emit(StreamEvent.Done)
        } finally {
            reader.close()
            response.close()
        }
    }
}
