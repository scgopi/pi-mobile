package com.pimobile.app.repository

import com.pimobile.agent.AgentEvent
import com.pimobile.agent.AgentLoop
import com.pimobile.agent.Tool
import com.pimobile.ai.*
import com.pimobile.extensions.ExtensionRegistry
import com.pimobile.session.SessionRepository
import com.pimobile.tools.BuiltInTools
import kotlinx.coroutines.flow.Flow
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

class AgentRepository(
    private val agentLoop: AgentLoop,
    private val sessionRepository: SessionRepository,
    private val extensionRegistry: ExtensionRegistry,
    private val apiKeyRepository: ApiKeyRepository,
    private val tools: List<Tool>
) {
    private val json = Json { ignoreUnknownKeys = true; prettyPrint = false }

    suspend fun sendMessage(
        sessionId: String,
        userMessage: String,
        model: ModelDefinition,
        systemPrompt: String,
        existingMessages: List<Message>
    ): Flow<AgentEvent> {
        val apiKey = apiKeyRepository.getApiKey(model.provider)
            ?: throw IllegalStateException("No API key configured for provider: ${model.provider}")

        // For Azure, override the model's baseUrl with the user-configured endpoint
        val resolvedModel = if (model.provider == "azure" || model.protocol == WireProtocol.AZURE) {
            val endpoint = apiKeyRepository.getSetting("azure", "endpoint")
            if (!endpoint.isNullOrBlank()) {
                model.copy(baseUrl = endpoint)
            } else {
                model
            }
        } else {
            model
        }

        val allTools = tools + extensionRegistry.aggregateTools()

        val context = Context(
            systemPrompt = systemPrompt,
            messages = existingMessages.toMutableList().apply {
                add(Message(
                    role = Role.USER,
                    content = MessageContent.Text(userMessage)
                ))
            },
            temperature = 0.7,
            maxTokens = resolvedModel.maxOutputTokens
        )

        val modifiedContext = extensionRegistry.dispatchBeforeRequest(context)

        sessionRepository.addEntry(
            sessionId = sessionId,
            parentId = null,
            type = "message",
            data = json.encodeToString(
                mapOf("role" to "user", "content" to userMessage)
            )
        )

        return agentLoop.run(resolvedModel, modifiedContext, allTools, apiKey)
    }

    suspend fun saveAssistantMessage(sessionId: String, content: String, thinking: String?) {
        val data = buildMap<String, String> {
            put("role", "assistant")
            put("content", content)
            if (thinking != null) put("thinking", thinking)
        }
        sessionRepository.addEntry(
            sessionId = sessionId,
            parentId = null,
            type = "message",
            data = json.encodeToString(data)
        )
    }

    suspend fun saveToolCall(sessionId: String, toolName: String, input: String, output: String) {
        val data = mapOf(
            "tool" to toolName,
            "input" to input,
            "output" to output
        )
        sessionRepository.addEntry(
            sessionId = sessionId,
            parentId = null,
            type = "tool_call",
            data = json.encodeToString(data)
        )
    }
}
