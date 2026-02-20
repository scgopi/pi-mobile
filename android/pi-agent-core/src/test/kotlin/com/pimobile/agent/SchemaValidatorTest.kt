package com.pimobile.agent

import kotlinx.serialization.json.*
import org.junit.Test
import org.junit.Assert.*

class SchemaValidatorTest {

    @Test
    fun `valid object passes validation`() {
        val schema = buildJsonObject {
            put("type", "object")
            putJsonObject("properties") {
                putJsonObject("name") { put("type", "string") }
                putJsonObject("age") { put("type", "integer") }
            }
            putJsonArray("required") { add("name") }
        }

        val input = buildJsonObject {
            put("name", "Alice")
            put("age", 30)
        }

        val result = SchemaValidator.validate(schema, input)
        assertTrue(result.isValid)
        assertTrue(result.errors.isEmpty())
    }

    @Test
    fun `missing required field fails validation`() {
        val schema = buildJsonObject {
            put("type", "object")
            putJsonObject("properties") {
                putJsonObject("name") { put("type", "string") }
            }
            putJsonArray("required") { add("name") }
        }

        val input = buildJsonObject { }

        val result = SchemaValidator.validate(schema, input)
        assertFalse(result.isValid)
        assertTrue(result.errors.isNotEmpty())
    }

    @Test
    fun `wrong type fails validation`() {
        val schema = buildJsonObject {
            put("type", "object")
            putJsonObject("properties") {
                putJsonObject("age") { put("type", "integer") }
            }
            putJsonArray("required") { add("age") }
        }

        val input = buildJsonObject {
            put("age", "not a number")
        }

        val result = SchemaValidator.validate(schema, input)
        assertFalse(result.isValid)
        assertTrue(result.errors.isNotEmpty())
    }
}
