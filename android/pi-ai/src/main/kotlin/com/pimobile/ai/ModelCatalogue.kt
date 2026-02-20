package com.pimobile.ai

import kotlinx.serialization.json.*

class ModelCatalogue {
    private val models = mutableMapOf<String, ModelDefinition>()

    private val json = Json { ignoreUnknownKeys = true }

    /**
     * Load from the nested catalogue format:
     * { "providers": { "<provider>": { "defaultBaseUrl": "...", "protocol": "...", "models": { "<id>": { ... } } } } }
     */
    fun loadFromJson(jsonString: String) {
        val root = json.parseToJsonElement(jsonString).jsonObject
        val providers = root["providers"]?.jsonObject ?: return

        for ((providerKey, providerValue) in providers) {
            val providerObj = providerValue.jsonObject
            val defaultBaseUrl = providerObj["defaultBaseUrl"]?.jsonPrimitive?.contentOrNull ?: continue
            val protocolStr = providerObj["protocol"]?.jsonPrimitive?.contentOrNull ?: continue
            val protocol = try { json.decodeFromJsonElement<WireProtocol>(JsonPrimitive(protocolStr)) } catch (_: Exception) { continue }
            val modelsObj = providerObj["models"]?.jsonObject ?: continue

            for ((modelId, modelValue) in modelsObj) {
                val modelObj = modelValue.jsonObject
                val name = modelObj["name"]?.jsonPrimitive?.contentOrNull ?: continue
                val contextWindow = modelObj["contextWindow"]?.jsonPrimitive?.intOrNull ?: continue
                val maxOutputTokens = modelObj["maxOutputTokens"]?.jsonPrimitive?.intOrNull ?: continue
                val inputCost = modelObj["inputCostPer1M"]?.jsonPrimitive?.doubleOrNull ?: 0.0
                val outputCost = modelObj["outputCostPer1M"]?.jsonPrimitive?.doubleOrNull ?: 0.0
                val capsObj = modelObj["capabilities"]?.jsonObject
                val baseUrl = modelObj["baseUrl"]?.jsonPrimitive?.contentOrNull ?: defaultBaseUrl

                val capabilities = ModelCapabilities(
                    vision = capsObj?.get("vision")?.jsonPrimitive?.booleanOrNull ?: false,
                    toolUse = capsObj?.get("toolUse")?.jsonPrimitive?.booleanOrNull ?: false,
                    streaming = capsObj?.get("streaming")?.jsonPrimitive?.booleanOrNull ?: true,
                    reasoning = capsObj?.get("reasoning")?.jsonPrimitive?.booleanOrNull ?: false
                )

                val definition = ModelDefinition(
                    id = modelId,
                    name = name,
                    provider = providerKey,
                    protocol = protocol,
                    baseUrl = baseUrl,
                    contextWindow = contextWindow,
                    maxOutputTokens = maxOutputTokens,
                    inputCostPer1M = inputCost,
                    outputCostPer1M = outputCost,
                    capabilities = capabilities
                )

                models["$providerKey/$modelId"] = definition
            }
        }
    }

    fun get(provider: String, id: String): ModelDefinition? {
        return models["$provider/$id"]
    }

    fun getByProvider(provider: String): List<ModelDefinition> {
        return models.values.filter { it.provider == provider }
    }

    fun allModels(): List<ModelDefinition> {
        return models.values.toList()
    }

    fun allProviders(): List<String> {
        return models.values.map { it.provider }.distinct()
    }
}
