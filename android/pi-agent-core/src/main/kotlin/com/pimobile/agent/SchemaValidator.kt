package com.pimobile.agent

import com.networknt.schema.JsonSchemaFactory
import com.networknt.schema.SpecVersion
import kotlinx.serialization.json.JsonObject

data class ValidationResult(
    val isValid: Boolean,
    val errors: List<String> = emptyList()
)

object SchemaValidator {

    private val factory = JsonSchemaFactory.getInstance(SpecVersion.VersionFlag.V7)

    fun validate(schema: JsonObject, input: JsonObject): ValidationResult {
        return try {
            val jsonSchema = factory.getSchema(schema.toString())
            val objectMapper = com.fasterxml.jackson.databind.ObjectMapper()
            val node = objectMapper.readTree(input.toString())
            val errors = jsonSchema.validate(node)

            if (errors.isEmpty()) {
                ValidationResult(isValid = true)
            } else {
                ValidationResult(
                    isValid = false,
                    errors = errors.map { it.message }
                )
            }
        } catch (e: Exception) {
            ValidationResult(
                isValid = false,
                errors = listOf("Schema validation error: ${e.message}")
            )
        }
    }
}
