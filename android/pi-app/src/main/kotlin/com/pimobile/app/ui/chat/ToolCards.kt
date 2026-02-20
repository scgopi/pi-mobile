package com.pimobile.app.ui.chat

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pimobile.agent.AgentToolResult
import com.pimobile.app.ui.theme.*
import kotlinx.serialization.json.JsonObject

@Composable
fun ToolCallCard(
    name: String,
    input: JsonObject,
    result: AgentToolResult?,
    modifier: Modifier = Modifier
) {
    val isDark = isSystemInDarkTheme()
    var expanded by remember { mutableStateOf(false) }

    Surface(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp)
            .clickable { expanded = !expanded },
        shape = RoundedCornerShape(12.dp),
        color = if (isDark) ToolCardDarkColor else ToolCardColor,
        tonalElevation = 1.dp
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(
                    text = if (result == null) "\u23F3" else if (result.isError) "\u274C" else "\u2705",
                    fontSize = 16.sp
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = name,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold
                )
                Spacer(modifier = Modifier.weight(1f))
                Text(
                    text = if (expanded) "\u25B2" else "\u25BC",
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)
                )
            }

            AnimatedVisibility(visible = expanded) {
                Column(modifier = Modifier.padding(top = 8.dp)) {
                    Text(
                        text = "Input:",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.primary
                    )
                    Text(
                        text = input.toString().take(500),
                        style = MaterialTheme.typography.bodySmall,
                        fontFamily = FontFamily.Monospace,
                        fontSize = 11.sp,
                        modifier = Modifier.padding(top = 4.dp)
                    )

                    if (result != null) {
                        Spacer(modifier = Modifier.height(8.dp))
                        ToolResultCard(result = result)
                    }
                }
            }

            if (!expanded && result != null) {
                Text(
                    text = result.output.take(80) + if (result.output.length > 80) "..." else "",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
                    modifier = Modifier.padding(top = 4.dp),
                    maxLines = 1
                )
            }
        }
    }
}

@Composable
fun ToolResultCard(
    result: AgentToolResult,
    modifier: Modifier = Modifier
) {
    val isDark = isSystemInDarkTheme()

    Column(modifier = modifier) {
        Text(
            text = if (result.isError) "Error:" else "Output:",
            style = MaterialTheme.typography.labelSmall,
            color = if (result.isError) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary
        )

        Surface(
            shape = RoundedCornerShape(8.dp),
            color = if (result.isError) {
                if (isDark) ErrorDarkColor else ErrorColor
            } else {
                MaterialTheme.colorScheme.surface
            },
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 4.dp)
        ) {
            Text(
                text = result.output.take(1000),
                style = MaterialTheme.typography.bodySmall,
                fontFamily = FontFamily.Monospace,
                fontSize = 11.sp,
                modifier = Modifier.padding(8.dp)
            )
        }
    }
}
