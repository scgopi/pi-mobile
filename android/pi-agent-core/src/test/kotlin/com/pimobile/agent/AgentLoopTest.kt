package com.pimobile.agent

import com.pimobile.ai.*
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

class AgentLoopTest {

    private val testModel = ModelDefinition(
        id = "test-model",
        name = "Test",
        provider = "test",
        protocol = WireProtocol.OPENAI_COMPLETIONS,
        baseUrl = "http://localhost",
        contextWindow = 4096,
        maxOutputTokens = 1024,
        inputCostPer1M = 0.0,
        outputCostPer1M = 0.0
    )

    @Test
    fun `text-only response emits AssistantMessage and Done`() = runTest {
        val llmClient = mockk<LlmClient>()
        every { llmClient.stream(any(), any(), any()) } returns flowOf(
            StreamEvent.TextDelta("Hello "),
            StreamEvent.TextDelta("world"),
            StreamEvent.Done
        )

        val loop = AgentLoop(llmClient)
        val context = Context(
            systemPrompt = "test",
            messages = mutableListOf(Message(Role.USER, MessageContent.Text("Hi")))
        )

        val events = loop.run(testModel, context, emptyList(), "test-key").toList()

        val assistantMessages = events.filterIsInstance<AgentEvent.AssistantMessage>()
        assertEquals(1, assistantMessages.size)
        assertEquals("Hello world", assistantMessages[0].content)

        val doneEvents = events.filterIsInstance<AgentEvent.Done>()
        assertEquals(1, doneEvents.size)
    }

    @Test
    fun `unknown tool returns error result`() = runTest {
        val llmClient = mockk<LlmClient>()

        // First call: LLM requests an unknown tool
        val firstResponse = flowOf(
            StreamEvent.ToolCallStart("tc-1", "unknown_tool"),
            StreamEvent.ToolCallDelta("tc-1", "{}"),
            StreamEvent.ToolCallEnd("tc-1"),
            StreamEvent.Done
        )
        // Second call: LLM responds with text only to end the loop
        val secondResponse = flowOf(
            StreamEvent.TextDelta("ok"),
            StreamEvent.Done
        )

        var callCount = 0
        every { llmClient.stream(any(), any(), any()) } answers {
            callCount++
            if (callCount == 1) firstResponse else secondResponse
        }

        val loop = AgentLoop(llmClient)
        val context = Context(
            systemPrompt = "test",
            messages = mutableListOf(Message(Role.USER, MessageContent.Text("Use a tool")))
        )

        val events = loop.run(testModel, context, emptyList(), "test-key").toList()

        val toolCompleted = events.filterIsInstance<AgentEvent.ToolCallCompleted>()
        assertEquals(1, toolCompleted.size)
        assertTrue(toolCompleted[0].result.isError)
        assertTrue(toolCompleted[0].result.output.contains("Unknown tool"))
    }
}
