package com.pimobile.tools

import com.pimobile.agent.AgentToolResult
import com.pimobile.agent.Tool
import kotlinx.serialization.json.*
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody

class HttpRequestTool : Tool {

    override val name = "http_request"
    override val description = "Make an HTTP request. Supports GET, POST, PUT, PATCH, DELETE methods with headers and body."
    override val parametersSchema = buildJsonObject {
        put("type", "object")
        putJsonObject("properties") {
            putJsonObject("method") {
                put("type", "string")
                putJsonArray("enum") { add("GET"); add("POST"); add("PUT"); add("PATCH"); add("DELETE"); add("HEAD") }
                put("description", "HTTP method")
            }
            putJsonObject("url") {
                put("type", "string")
                put("description", "Request URL")
            }
            putJsonObject("headers") {
                put("type", "object")
                putJsonObject("additionalProperties") { put("type", "string") }
                put("description", "Request headers")
            }
            putJsonObject("body") {
                put("type", "string")
                put("description", "Request body (for POST, PUT, PATCH)")
            }
            putJsonObject("contentType") {
                put("type", "string")
                put("description", "Content-Type header (default: application/json)")
            }
        }
        putJsonArray("required") { add("method"); add("url") }
    }

    private val client = OkHttpClient.Builder()
        .followRedirects(true)
        .followSslRedirects(true)
        .build()

    private val maxBodySize = 100 * 1024 // 100KB

    override suspend fun execute(input: JsonObject): AgentToolResult {
        val method = input["method"]?.jsonPrimitive?.contentOrNull?.uppercase()
            ?: return AgentToolResult("", "Error: 'method' is required", isError = true)
        val url = input["url"]?.jsonPrimitive?.contentOrNull
            ?: return AgentToolResult("", "Error: 'url' is required", isError = true)
        val headers = input["headers"]?.jsonObject
        val body = input["body"]?.jsonPrimitive?.contentOrNull
        val contentType = input["contentType"]?.jsonPrimitive?.contentOrNull ?: "application/json"

        return try {
            val requestBuilder = Request.Builder().url(url)

            headers?.forEach { (key, value) ->
                val headerValue = value.jsonPrimitive.contentOrNull ?: return@forEach
                requestBuilder.addHeader(key, headerValue)
            }

            val requestBody = when (method) {
                "GET", "HEAD" -> null
                else -> (body ?: "").toRequestBody(contentType.toMediaType())
            }

            requestBuilder.method(method, requestBody)
            val request = requestBuilder.build()
            val response = client.newCall(request).execute()

            val responseBody = response.body?.let { respBody ->
                val bytes = respBody.bytes()
                if (bytes.size > maxBodySize) {
                    String(bytes, 0, maxBodySize, Charsets.UTF_8) + "\n... [truncated at 100KB]"
                } else {
                    String(bytes, Charsets.UTF_8)
                }
            } ?: ""

            val importantHeaders = listOf(
                "content-type", "content-length", "location", "set-cookie",
                "x-request-id", "retry-after", "www-authenticate"
            )
            val responseHeaders = response.headers.toMultimap()
                .filterKeys { it.lowercase() in importantHeaders }
                .map { (key, values) -> "$key: ${values.joinToString(", ")}" }
                .joinToString("\n")

            val output = buildString {
                appendLine("HTTP ${response.code} ${response.message}")
                if (responseHeaders.isNotEmpty()) {
                    appendLine(responseHeaders)
                }
                appendLine()
                append(responseBody)
            }

            response.close()
            AgentToolResult("", output)
        } catch (e: Exception) {
            AgentToolResult("", "HTTP request error: ${e.message}", isError = true)
        }
    }
}
