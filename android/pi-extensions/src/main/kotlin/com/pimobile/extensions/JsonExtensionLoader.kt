package com.pimobile.extensions

import com.pimobile.agent.AgentToolResult
import com.pimobile.agent.Tool
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.*

@Serializable
data class JsonToolSpec(
    val name: String,
    val description: String,
    val parameters: JsonObject,
    val outputTemplate: String? = null
)

@Serializable
data class JsonExtensionSpec(
    val id: String,
    val name: String,
    val version: String,
    val tools: List<JsonToolSpec>
)

class JsonExtensionLoader {

    private val json = Json { ignoreUnknownKeys = true }

    fun loadFromJson(jsonString: String): PiExtension {
        val spec = json.decodeFromString<JsonExtensionSpec>(jsonString)
        return JsonBackedExtension(spec)
    }

    fun loadMultipleFromJson(jsonString: String): List<PiExtension> {
        val specs = json.decodeFromString<List<JsonExtensionSpec>>(jsonString)
        return specs.map { JsonBackedExtension(it) }
    }
}

private class JsonBackedExtension(private val spec: JsonExtensionSpec) : PiExtension {
    override val id: String = spec.id
    override val name: String = spec.name
    override val version: String = spec.version

    override fun getTools(): List<Tool> {
        return spec.tools.map { toolSpec ->
            JsonBackedTool(toolSpec)
        }
    }
}

private class JsonBackedTool(private val spec: JsonToolSpec) : Tool {
    override val name: String = spec.name
    override val description: String = spec.description
    override val parametersSchema: JsonObject = spec.parameters

    override suspend fun execute(input: JsonObject): AgentToolResult {
        val template = spec.outputTemplate
        if (template != null) {
            var output: String = template
            for ((key, value) in input) {
                val replacement = when (value) {
                    is JsonPrimitive -> value.contentOrNull ?: value.toString()
                    else -> value.toString()
                }
                output = output.replace("{{$key}}", replacement)
            }
            return AgentToolResult(
                toolCallId = "",
                output = output
            )
        }

        return AgentToolResult(
            toolCallId = "",
            output = "Tool '${spec.name}' executed with input: $input"
        )
    }
}
