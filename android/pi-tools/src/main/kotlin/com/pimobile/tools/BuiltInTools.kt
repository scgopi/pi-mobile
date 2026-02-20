package com.pimobile.tools

import android.content.Context
import com.pimobile.agent.Tool
import java.io.File

object BuiltInTools {
    fun create(context: Context, sandboxDir: File): List<Tool> = listOf(
        ReadFileTool(context.contentResolver, sandboxDir),
        WriteFileTool(sandboxDir),
        EditFileTool(sandboxDir),
        ListFilesTool(sandboxDir),
        SqliteQueryTool(),
        HttpRequestTool(),
        MediaQueryTool(context.contentResolver),
        ExternalFileTool()
    )
}
