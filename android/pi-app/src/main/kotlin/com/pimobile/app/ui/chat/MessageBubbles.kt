package com.pimobile.app.ui.chat

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.pimobile.app.ui.theme.*

@Composable
fun UserBubble(text: String, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(start = 48.dp, end = 16.dp, top = 4.dp, bottom = 4.dp),
        horizontalArrangement = Arrangement.End
    ) {
        Surface(
            shape = RoundedCornerShape(20.dp, 20.dp, 4.dp, 20.dp),
            color = UserBubbleColor,
            tonalElevation = 0.dp
        ) {
            Text(
                text = text,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp),
                color = Color.White,
                style = MaterialTheme.typography.bodyLarge
            )
        }
    }
}

@Composable
fun AssistantBubble(
    text: String,
    thinking: String? = null,
    modifier: Modifier = Modifier
) {
    val isDark = isSystemInDarkTheme()
    val bubbleColor = if (isDark) AssistantBubbleDarkColor else AssistantBubbleColor

    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(start = 16.dp, end = 48.dp, top = 4.dp, bottom = 4.dp)
    ) {
        if (!thinking.isNullOrEmpty()) {
            Surface(
                shape = RoundedCornerShape(12.dp),
                color = if (isDark) Color(0xFF1A1A2E) else Color(0xFFEDE7F6),
                modifier = Modifier.padding(bottom = 4.dp)
            ) {
                Column(modifier = Modifier.padding(12.dp)) {
                    Text(
                        text = "Thinking",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.primary
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = thinking,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
                    )
                }
            }
        }

        if (text.isNotEmpty()) {
            Surface(
                shape = RoundedCornerShape(20.dp, 20.dp, 20.dp, 4.dp),
                color = bubbleColor,
                tonalElevation = 1.dp
            ) {
                StreamingMarkdown(
                    text = text,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp)
                )
            }
        }
    }
}
