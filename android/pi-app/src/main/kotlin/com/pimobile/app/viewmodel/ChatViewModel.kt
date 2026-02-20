package com.pimobile.app.viewmodel

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.pimobile.agent.AgentEvent
import com.pimobile.agent.AgentToolResult
import com.pimobile.ai.*
import com.pimobile.app.PiMobileApp
import com.pimobile.app.repository.AgentRepository
import com.pimobile.app.repository.ApiKeyRepository
import com.pimobile.tools.BuiltInTools
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.contentOrNull

data class ChatUiState(
    val sessionId: String? = null,
    val messages: List<ChatMessage> = emptyList(),
    val isStreaming: Boolean = false,
    val currentStreamText: String = "",
    val currentThinkingText: String = "",
    val activeToolCalls: List<ActiveToolCall> = emptyList(),
    val selectedModel: ModelDefinition? = null,
    val inputTokens: Int = 0,
    val outputTokens: Int = 0,
    val error: String? = null
)

sealed class ChatMessage {
    data class User(val text: String) : ChatMessage()
    data class Assistant(val text: String, val thinking: String? = null) : ChatMessage()
    data class ToolCallMsg(val name: String, val input: JsonObject, val result: AgentToolResult? = null) : ChatMessage()
    data class ErrorMsg(val message: String) : ChatMessage()
}

data class ActiveToolCall(val name: String, val input: JsonObject)

class ChatViewModel(application: Application) : AndroidViewModel(application) {

    private val app = application as PiMobileApp

    private val apiKeyRepository = ApiKeyRepository(application)
    private val sandboxDir = application.getExternalFilesDir("sandbox")
        ?: application.filesDir.resolve("sandbox").also { it.mkdirs() }
    private val tools = BuiltInTools.create(application, sandboxDir)
    private val agentRepository = AgentRepository(
        agentLoop = app.agentLoop,
        sessionRepository = app.sessionRepository,
        extensionRegistry = app.extensionRegistry,
        apiKeyRepository = apiKeyRepository,
        tools = tools
    )

    private val _uiState = MutableStateFlow(ChatUiState())
    val uiState: StateFlow<ChatUiState> = _uiState.asStateFlow()

    private var streamingJob: Job? = null
    private val conversationMessages = mutableListOf<Message>()

    fun initSession(sessionId: String) {
        // Restore last selected model from preferences
        val defaultProvider = apiKeyRepository.getDefaultProvider()
        val defaultModelId = apiKeyRepository.getDefaultModel()
        if (defaultProvider != null && defaultModelId != null) {
            val saved = app.modelCatalogue.get(defaultProvider, defaultModelId)
            if (saved != null) {
                _uiState.update { it.copy(selectedModel = saved) }
            }
        }

        if (sessionId == "new") {
            viewModelScope.launch {
                val session = app.sessionRepository.createSession(title = "New Chat")
                _uiState.update { it.copy(sessionId = session.id) }
            }
        } else {
            _uiState.update { it.copy(sessionId = sessionId) }
            loadExistingSession(sessionId)
        }
    }

    private fun loadExistingSession(sessionId: String) {
        viewModelScope.launch {
            val session = app.sessionRepository.getSession(sessionId) ?: return@launch
            val leafId = session.leafId
            if (leafId != null) {
                val entries = app.sessionRepository.getBranch(leafId)
                val messages = entries.mapNotNull { entry ->
                    when (entry.type) {
                        "message" -> {
                            val data = Json.parseToJsonElement(entry.data).jsonObject
                            val role = data["role"]?.jsonPrimitive?.contentOrNull
                            val content = data["content"]?.jsonPrimitive?.contentOrNull ?: ""
                            when (role) {
                                "user" -> ChatMessage.User(content)
                                "assistant" -> ChatMessage.Assistant(content)
                                else -> null
                            }
                        }
                        else -> null
                    }
                }
                _uiState.update { it.copy(messages = messages) }
            }
        }
    }

    fun setModel(model: ModelDefinition) {
        _uiState.update { it.copy(selectedModel = model) }
        apiKeyRepository.setDefaultProvider(model.provider)
        apiKeyRepository.setDefaultModel(model.id)
    }

    fun sendMessage(text: String) {
        val model = _uiState.value.selectedModel ?: return
        val sessionId = _uiState.value.sessionId ?: return

        _uiState.update { state ->
            state.copy(
                messages = state.messages + ChatMessage.User(text),
                isStreaming = true,
                currentStreamText = "",
                currentThinkingText = "",
                error = null
            )
        }

        streamingJob = viewModelScope.launch {
            try {
                val eventFlow = agentRepository.sendMessage(
                    sessionId = sessionId,
                    userMessage = text,
                    model = model,
                    systemPrompt = "You are Pi, a helpful AI assistant on a mobile device. You can use tools to help the user with tasks involving files, databases, web requests, and device media.",
                    existingMessages = conversationMessages.toList()
                )

                val textBuilder = StringBuilder()
                val thinkingBuilder = StringBuilder()

                eventFlow.collect { event ->
                    when (event) {
                        is AgentEvent.StreamDelta -> {
                            textBuilder.append(event.delta)
                            _uiState.update { it.copy(currentStreamText = textBuilder.toString()) }
                        }
                        is AgentEvent.ThinkingDelta -> {
                            thinkingBuilder.append(event.delta)
                            _uiState.update { it.copy(currentThinkingText = thinkingBuilder.toString()) }
                        }
                        is AgentEvent.AssistantMessage -> {
                            val msg = ChatMessage.Assistant(event.content, event.thinking)
                            _uiState.update { state ->
                                state.copy(
                                    messages = state.messages + msg,
                                    currentStreamText = "",
                                    currentThinkingText = ""
                                )
                            }
                            conversationMessages.add(Message(
                                role = Role.ASSISTANT,
                                content = MessageContent.Text(event.content),
                                thinking = event.thinking
                            ))
                            agentRepository.saveAssistantMessage(sessionId, event.content, event.thinking)
                            textBuilder.clear()
                            thinkingBuilder.clear()
                        }
                        is AgentEvent.ToolCallStarted -> {
                            _uiState.update { state ->
                                state.copy(
                                    messages = state.messages + ChatMessage.ToolCallMsg(event.name, event.input),
                                    activeToolCalls = state.activeToolCalls + ActiveToolCall(event.name, event.input)
                                )
                            }
                        }
                        is AgentEvent.ToolCallCompleted -> {
                            _uiState.update { state ->
                                val updatedMessages = state.messages.toMutableList()
                                val idx = updatedMessages.indexOfLast {
                                    it is ChatMessage.ToolCallMsg && it.name == event.name && it.result == null
                                }
                                if (idx >= 0) {
                                    val existing = updatedMessages[idx] as ChatMessage.ToolCallMsg
                                    updatedMessages[idx] = existing.copy(result = event.result)
                                }
                                state.copy(
                                    messages = updatedMessages,
                                    activeToolCalls = state.activeToolCalls.filter { it.name != event.name }
                                )
                            }
                            agentRepository.saveToolCall(
                                sessionId, event.name,
                                event.result.toolCallId,
                                event.result.output
                            )
                        }
                        is AgentEvent.UsageUpdate -> {
                            _uiState.update { state ->
                                state.copy(
                                    inputTokens = state.inputTokens + event.inputTokens,
                                    outputTokens = state.outputTokens + event.outputTokens
                                )
                            }
                        }
                        is AgentEvent.Error -> {
                            _uiState.update { state ->
                                state.copy(
                                    messages = state.messages + ChatMessage.ErrorMsg(event.message),
                                    error = event.message
                                )
                            }
                        }
                        is AgentEvent.Done -> {
                            _uiState.update { it.copy(isStreaming = false) }
                        }
                    }
                }

                conversationMessages.add(Message(
                    role = Role.USER,
                    content = MessageContent.Text(text)
                ))
            } catch (e: Exception) {
                _uiState.update { state ->
                    state.copy(
                        isStreaming = false,
                        error = e.message,
                        messages = state.messages + ChatMessage.ErrorMsg(e.message ?: "Unknown error")
                    )
                }
            }
        }
    }

    fun cancelStreaming() {
        streamingJob?.cancel()
        _uiState.update { it.copy(isStreaming = false) }
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }
}
