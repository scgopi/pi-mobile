package com.pimobile.app.ui.components

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pimobile.agent.DiffHunk
import com.pimobile.agent.DiffLineType
import com.pimobile.agent.ToolResultDetails
import com.pimobile.app.ui.theme.ErrorColor
import com.pimobile.app.ui.theme.ErrorDarkColor

@Composable
fun FileViewer(
    details: ToolResultDetails.File,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(8.dp),
        color = if (isSystemInDarkTheme()) Color(0xFF1E1E2E) else Color(0xFFF8F8F8),
        tonalElevation = 1.dp
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    text = details.path,
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.primary
                )
                details.language?.let { lang ->
                    Text(
                        text = lang,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)
                    )
                }
            }
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = details.content,
                fontFamily = FontFamily.Monospace,
                fontSize = 12.sp,
                lineHeight = 18.sp,
                modifier = Modifier
                    .horizontalScroll(rememberScrollState())
                    .heightIn(max = 300.dp)
                    .verticalScroll(rememberScrollState())
            )
        }
    }
}

@Composable
fun DiffViewer(
    details: ToolResultDetails.Diff,
    modifier: Modifier = Modifier
) {
    val isDark = isSystemInDarkTheme()

    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(8.dp),
        color = if (isDark) Color(0xFF1E1E2E) else Color(0xFFF8F8F8),
        tonalElevation = 1.dp
    ) {
        Column(
            modifier = Modifier
                .padding(12.dp)
                .horizontalScroll(rememberScrollState())
        ) {
            Text(
                text = details.path,
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier.padding(bottom = 8.dp)
            )

            for (hunk in details.hunks) {
                DiffHunkView(hunk = hunk, isDark = isDark)
                Spacer(modifier = Modifier.height(4.dp))
            }
        }
    }
}

@Composable
private fun DiffHunkView(hunk: DiffHunk, isDark: Boolean) {
    Column {
        Text(
            text = "@@ -${hunk.startLineOld},${hunk.countOld} +${hunk.startLineNew},${hunk.countNew} @@",
            fontFamily = FontFamily.Monospace,
            fontSize = 11.sp,
            color = MaterialTheme.colorScheme.primary.copy(alpha = 0.7f)
        )
        for (line in hunk.lines) {
            val (prefix, bgColor) = when (line.type) {
                DiffLineType.ADD -> "+" to (if (isDark) Color(0xFF1A3A1A) else Color(0xFFE6FFE6))
                DiffLineType.REMOVE -> "-" to (if (isDark) Color(0xFF3A1A1A) else Color(0xFFFFE6E6))
                DiffLineType.CONTEXT -> " " to Color.Transparent
            }
            Surface(
                color = bgColor,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(
                    text = "$prefix${line.content}",
                    fontFamily = FontFamily.Monospace,
                    fontSize = 12.sp,
                    lineHeight = 18.sp,
                    modifier = Modifier.padding(horizontal = 4.dp)
                )
            }
        }
    }
}

@Composable
fun TableViewer(
    details: ToolResultDetails.Table,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(8.dp),
        tonalElevation = 1.dp
    ) {
        Column(
            modifier = Modifier
                .padding(8.dp)
                .horizontalScroll(rememberScrollState())
        ) {
            Row(modifier = Modifier.padding(bottom = 4.dp)) {
                for (col in details.columns) {
                    Text(
                        text = col,
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.widthIn(min = 80.dp).padding(horizontal = 8.dp)
                    )
                }
            }
            HorizontalDivider()
            for (row in details.rows) {
                Row(modifier = Modifier.padding(vertical = 2.dp)) {
                    for (cell in row) {
                        Text(
                            text = cell,
                            style = MaterialTheme.typography.bodySmall,
                            fontFamily = FontFamily.Monospace,
                            fontSize = 11.sp,
                            modifier = Modifier.widthIn(min = 80.dp).padding(horizontal = 8.dp)
                        )
                    }
                }
            }
        }
    }
}

@Composable
fun ErrorCard(
    details: ToolResultDetails.Error,
    modifier: Modifier = Modifier
) {
    val isDark = isSystemInDarkTheme()

    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(8.dp),
        color = if (isDark) ErrorDarkColor else ErrorColor
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            Text(
                text = "Error",
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.error
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = details.message,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurface
            )
            details.code?.let { code ->
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = "Code: $code",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)
                )
            }
        }
    }
}
