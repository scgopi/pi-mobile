package com.pimobile.ai

import kotlinx.serialization.json.*
import org.junit.Test
import org.junit.Assert.*

class TypesTest {

    private val json = Json { ignoreUnknownKeys = true }

    @Test
    fun `WireProtocol serializes to serial name`() {
        val encoded = json.encodeToString(WireProtocol.serializer(), WireProtocol.OPENAI_COMPLETIONS)
        assertEquals("\"openai-completions\"", encoded)
    }

    @Test
    fun `WireProtocol deserializes from serial name`() {
        val decoded = json.decodeFromString(WireProtocol.serializer(), "\"openai-completions\"")
        assertEquals(WireProtocol.OPENAI_COMPLETIONS, decoded)
    }

    @Test
    fun `ModelCapabilities has correct defaults`() {
        val caps = ModelCapabilities()
        assertFalse(caps.vision)
        assertFalse(caps.toolUse)
        assertTrue(caps.streaming)
        assertFalse(caps.reasoning)
    }

    @Test
    fun `ContentBlock Text serialization round-trip`() {
        val original = ContentBlock.Text("hello world")
        val encoded = json.encodeToString(ContentBlock.serializer(), original)
        val decoded = json.decodeFromString(ContentBlock.serializer(), encoded)
        assertEquals(original, decoded)
    }

    @Test
    fun `MessageContent Text serialization round-trip`() {
        val original = MessageContent.Text("hello")
        val encoded = json.encodeToString(MessageContent.serializer(), original)
        val decoded = json.decodeFromString(MessageContent.serializer(), encoded)
        assertEquals(original, decoded)
    }

    @Test
    fun `ToolCall input parses arguments to JsonObject`() {
        val toolCall = ToolCall("tc-1", "read_file", """{"path":"test.txt","startLine":1}""")
        val input = toolCall.input
        assertEquals("test.txt", input["path"]?.jsonPrimitive?.content)
        assertEquals(1, input["startLine"]?.jsonPrimitive?.int)
    }
}
