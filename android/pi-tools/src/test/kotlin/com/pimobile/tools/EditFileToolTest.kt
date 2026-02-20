package com.pimobile.tools

import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.io.File

class EditFileToolTest {

    private lateinit var sandboxDir: File
    private lateinit var tool: EditFileTool

    @Before
    fun setUp() {
        sandboxDir = File(System.getProperty("java.io.tmpdir"), "edit_test_${System.nanoTime()}")
        sandboxDir.mkdirs()
        tool = EditFileTool(sandboxDir)
    }

    @After
    fun tearDown() {
        sandboxDir.deleteRecursively()
    }

    @Test
    fun `successful edit returns applied message`() = runTest {
        val testFile = File(sandboxDir, "hello.txt")
        testFile.writeText("Hello World")

        val input = buildJsonObject {
            put("path", "hello.txt")
            putJsonArray("edits") {
                addJsonObject {
                    put("search", "World")
                    put("replace", "Kotlin")
                }
            }
        }

        val result = tool.execute(input)
        assertFalse(result.isError)
        assertTrue(result.output.contains("Applied 1 edit"))
        assertEquals("Hello Kotlin", testFile.readText())
    }

    @Test
    fun `search string not found returns error`() = runTest {
        val testFile = File(sandboxDir, "hello.txt")
        testFile.writeText("Hello World")

        val input = buildJsonObject {
            put("path", "hello.txt")
            putJsonArray("edits") {
                addJsonObject {
                    put("search", "Nonexistent")
                    put("replace", "Replaced")
                }
            }
        }

        val result = tool.execute(input)
        assertTrue(result.isError)
        assertTrue(result.output.contains("not found"))
    }

    @Test
    fun `duplicate search string returns error`() = runTest {
        val testFile = File(sandboxDir, "repeat.txt")
        testFile.writeText("foo bar foo")

        val input = buildJsonObject {
            put("path", "repeat.txt")
            putJsonArray("edits") {
                addJsonObject {
                    put("search", "foo")
                    put("replace", "baz")
                }
            }
        }

        val result = tool.execute(input)
        assertTrue(result.isError)
        assertTrue(result.output.contains("2 times"))
    }
}
