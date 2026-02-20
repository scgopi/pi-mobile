package com.pimobile.tools

import android.content.ContentResolver
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.io.File

class ReadFileToolTest {

    private lateinit var sandboxDir: File
    private lateinit var tool: ReadFileTool
    private val contentResolver: ContentResolver = mockk()

    @Before
    fun setUp() {
        sandboxDir = File(System.getProperty("java.io.tmpdir"), "sandbox_test_${System.nanoTime()}")
        sandboxDir.mkdirs()
        tool = ReadFileTool(contentResolver, sandboxDir)
    }

    @After
    fun tearDown() {
        sandboxDir.deleteRecursively()
    }

    @Test
    fun `reads sandbox file successfully`() = runTest {
        val testFile = File(sandboxDir, "test.txt")
        testFile.writeText("line1\nline2\nline3")

        val input = buildJsonObject { put("path", "test.txt") }
        val result = tool.execute(input)

        assertFalse(result.isError)
        assertTrue(result.output.contains("line1"))
        assertTrue(result.output.contains("line2"))
        assertTrue(result.output.contains("line3"))
    }

    @Test
    fun `rejects path outside sandbox`() = runTest {
        val input = buildJsonObject { put("path", "../secret") }
        val result = tool.execute(input)

        assertTrue(result.isError)
        assertTrue(result.output.contains("outside sandbox"))
    }

    @Test
    fun `returns error for file not found`() = runTest {
        val input = buildJsonObject { put("path", "nonexistent.txt") }
        val result = tool.execute(input)

        assertTrue(result.isError)
        assertTrue(result.output.contains("File not found"))
    }
}
