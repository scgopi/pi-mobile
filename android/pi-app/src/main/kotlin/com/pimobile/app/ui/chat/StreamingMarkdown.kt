package com.pimobile.app.ui.chat

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun StreamingMarkdown(
    text: String,
    modifier: Modifier = Modifier,
    isStreaming: Boolean = false
) {
    val annotated = parseMarkdown(text, isStreaming)
    Text(
        text = annotated,
        modifier = modifier,
        style = MaterialTheme.typography.bodyLarge
    )
}

private fun parseMarkdown(text: String, isStreaming: Boolean): AnnotatedString {
    return buildAnnotatedString {
        val lines = text.lines()
        for ((lineIndex, line) in lines.withIndex()) {
            when {
                line.startsWith("### ") -> {
                    withStyle(SpanStyle(fontWeight = FontWeight.Bold, fontSize = 16.sp)) {
                        append(line.removePrefix("### "))
                    }
                }
                line.startsWith("## ") -> {
                    withStyle(SpanStyle(fontWeight = FontWeight.Bold, fontSize = 18.sp)) {
                        append(line.removePrefix("## "))
                    }
                }
                line.startsWith("# ") -> {
                    withStyle(SpanStyle(fontWeight = FontWeight.Bold, fontSize = 20.sp)) {
                        append(line.removePrefix("# "))
                    }
                }
                line.startsWith("```") -> {
                    withStyle(SpanStyle(fontFamily = FontFamily.Monospace, fontSize = 13.sp)) {
                        append(line)
                    }
                }
                else -> {
                    parseInlineMarkdown(this, line)
                }
            }
            if (lineIndex < lines.size - 1) {
                append("\n")
            }
        }

        if (isStreaming) {
            withStyle(SpanStyle(fontWeight = FontWeight.Bold)) {
                append("\u2588")
            }
        }
    }
}

private fun parseInlineMarkdown(builder: AnnotatedString.Builder, text: String) {
    var i = 0
    while (i < text.length) {
        when {
            text.startsWith("**", i) -> {
                val end = text.indexOf("**", i + 2)
                if (end > 0) {
                    builder.withStyle(SpanStyle(fontWeight = FontWeight.Bold)) {
                        append(text.substring(i + 2, end))
                    }
                    i = end + 2
                } else {
                    builder.append(text[i])
                    i++
                }
            }
            text.startsWith("*", i) && (i == 0 || text[i - 1] != '*') -> {
                val end = text.indexOf("*", i + 1)
                if (end > 0 && !text.startsWith("**", end)) {
                    builder.withStyle(SpanStyle(fontStyle = FontStyle.Italic)) {
                        append(text.substring(i + 1, end))
                    }
                    i = end + 1
                } else {
                    builder.append(text[i])
                    i++
                }
            }
            text.startsWith("`", i) && !text.startsWith("```", i) -> {
                val end = text.indexOf("`", i + 1)
                if (end > 0) {
                    builder.withStyle(SpanStyle(fontFamily = FontFamily.Monospace, fontSize = 13.sp)) {
                        append(text.substring(i + 1, end))
                    }
                    i = end + 1
                } else {
                    builder.append(text[i])
                    i++
                }
            }
            else -> {
                builder.append(text[i])
                i++
            }
        }
    }
}
