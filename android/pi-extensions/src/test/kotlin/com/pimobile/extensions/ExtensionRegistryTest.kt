package com.pimobile.extensions

import com.pimobile.agent.AgentToolResult
import com.pimobile.agent.Tool
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

class ExtensionRegistryTest {

    private lateinit var registry: ExtensionRegistry

    @Before
    fun setUp() {
        registry = ExtensionRegistry()
    }

    @Test
    fun `register and retrieve extension`() {
        val ext = TestExtension("ext-1")
        registry.register(ext)
        assertEquals(ext, registry.getExtension("ext-1"))
    }

    @Test
    fun `unregister removes extension`() {
        val ext = TestExtension("ext-1")
        registry.register(ext)
        registry.unregister("ext-1")
        assertNull(registry.getExtension("ext-1"))
    }

    @Test
    fun `aggregateTools merges tools from all extensions`() {
        val tool1 = createTestTool("tool_a")
        val tool2 = createTestTool("tool_b")
        val ext1 = TestExtension("ext-1").apply { toolsList.add(tool1) }
        val ext2 = TestExtension("ext-2").apply { toolsList.add(tool2) }

        registry.register(ext1)
        registry.register(ext2)

        val tools = registry.aggregateTools()
        assertEquals(2, tools.size)
        assertTrue(tools.any { it.name == "tool_a" })
        assertTrue(tools.any { it.name == "tool_b" })
    }

    @Test
    fun `activateAll calls onActivate on all extensions`() = runTest {
        val ext1 = TestExtension("ext-1")
        val ext2 = TestExtension("ext-2")
        registry.register(ext1)
        registry.register(ext2)

        registry.activateAll()

        assertTrue(ext1.activateCalled)
        assertTrue(ext2.activateCalled)
    }

    @Test
    fun `deactivateAll calls onDeactivate on all extensions`() = runTest {
        val ext1 = TestExtension("ext-1")
        val ext2 = TestExtension("ext-2")
        registry.register(ext1)
        registry.register(ext2)

        registry.deactivateAll()

        assertTrue(ext1.deactivateCalled)
        assertTrue(ext2.deactivateCalled)
    }

    private fun createTestTool(toolName: String): Tool {
        return object : Tool {
            override val name = toolName
            override val description = "Test tool $toolName"
            override val parametersSchema = buildJsonObject { put("type", "object") }
            override suspend fun execute(input: JsonObject) = AgentToolResult("", "ok")
        }
    }
}

private class TestExtension(
    override val id: String,
    override val name: String = "Test",
    override val version: String = "1.0"
) : PiExtension {
    val toolsList = mutableListOf<Tool>()
    var activateCalled = false
    var deactivateCalled = false

    override fun getTools() = toolsList
    override suspend fun onActivate() { activateCalled = true }
    override suspend fun onDeactivate() { deactivateCalled = true }
}
