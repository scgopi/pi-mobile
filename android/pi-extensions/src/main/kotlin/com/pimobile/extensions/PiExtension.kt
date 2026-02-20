package com.pimobile.extensions

import com.pimobile.agent.Tool
import com.pimobile.ai.Context
import com.pimobile.ai.Message

interface PiExtension {
    val id: String
    val name: String
    val version: String

    fun getTools(): List<Tool>

    suspend fun onSessionStart(sessionId: String) {}
    suspend fun onSessionEnd(sessionId: String) {}
    suspend fun onBeforeRequest(context: Context): Context = context
    suspend fun onAfterResponse(message: Message): Message = message
    suspend fun onActivate() {}
    suspend fun onDeactivate() {}
}
