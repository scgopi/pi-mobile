package com.pimobile.ai

import kotlinx.coroutines.flow.Flow
import okhttp3.Request
import okhttp3.Response

interface ProtocolAdapter {
    fun buildRequest(context: Context, model: ModelDefinition, apiKey: String): Request
    fun parseStreamEvents(response: Response): Flow<StreamEvent>
}
