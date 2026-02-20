package com.pimobile.ai

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import okhttp3.OkHttpClient
import java.util.concurrent.TimeUnit

class LlmClient(
    private val httpClient: OkHttpClient = OkHttpClient.Builder()
        .readTimeout(120, TimeUnit.SECONDS)
        .connectTimeout(30, TimeUnit.SECONDS)
        .build()
) {
    private val adapters = mapOf(
        WireProtocol.OPENAI_COMPLETIONS to OpenAICompletionsAdapter(httpClient),
        WireProtocol.OPENAI_RESPONSES to OpenAIResponsesAdapter(httpClient),
        WireProtocol.ANTHROPIC to AnthropicAdapter(httpClient),
        WireProtocol.GOOGLE to GoogleAdapter(httpClient),
        WireProtocol.AZURE to AzureOpenAIAdapter(httpClient)
    )

    fun stream(model: ModelDefinition, context: Context, apiKey: String): Flow<StreamEvent> = flow {
        val adapter = adapters[model.protocol]
            ?: throw IllegalArgumentException("Unsupported protocol: ${model.protocol}")

        val request = adapter.buildRequest(context, model, apiKey)
        val response = httpClient.newCall(request).execute()

        if (!response.isSuccessful) {
            val errorBody = response.body?.string() ?: "Unknown error"
            emit(StreamEvent.Error("HTTP ${response.code}: $errorBody"))
            response.close()
            return@flow
        }

        val eventFlow = adapter.parseStreamEvents(response)
        eventFlow.collect { event -> emit(event) }
    }.flowOn(Dispatchers.IO)
}
