package com.pimobile.extensions

import com.pimobile.agent.Tool
import com.pimobile.ai.Context
import com.pimobile.ai.Message

class ExtensionRegistry {

    private val extensions = mutableMapOf<String, PiExtension>()

    fun register(extension: PiExtension) {
        extensions[extension.id] = extension
    }

    fun unregister(extensionId: String) {
        extensions.remove(extensionId)
    }

    fun getExtension(extensionId: String): PiExtension? {
        return extensions[extensionId]
    }

    fun allExtensions(): List<PiExtension> {
        return extensions.values.toList()
    }

    fun aggregateTools(): List<Tool> {
        return extensions.values.flatMap { it.getTools() }
    }

    suspend fun dispatchSessionStart(sessionId: String) {
        for (ext in extensions.values) {
            try {
                ext.onSessionStart(sessionId)
            } catch (e: Exception) {
                // Log but don't fail
            }
        }
    }

    suspend fun dispatchSessionEnd(sessionId: String) {
        for (ext in extensions.values) {
            try {
                ext.onSessionEnd(sessionId)
            } catch (e: Exception) {
                // Log but don't fail
            }
        }
    }

    suspend fun dispatchBeforeRequest(context: Context): Context {
        var ctx = context
        for (ext in extensions.values) {
            try {
                ctx = ext.onBeforeRequest(ctx)
            } catch (e: Exception) {
                // Log but don't fail
            }
        }
        return ctx
    }

    suspend fun dispatchAfterResponse(message: Message): Message {
        var msg = message
        for (ext in extensions.values) {
            try {
                msg = ext.onAfterResponse(msg)
            } catch (e: Exception) {
                // Log but don't fail
            }
        }
        return msg
    }

    suspend fun activateAll() {
        for (ext in extensions.values) {
            try {
                ext.onActivate()
            } catch (e: Exception) {
                // Log but don't fail
            }
        }
    }

    suspend fun deactivateAll() {
        for (ext in extensions.values) {
            try {
                ext.onDeactivate()
            } catch (e: Exception) {
                // Log but don't fail
            }
        }
    }
}
