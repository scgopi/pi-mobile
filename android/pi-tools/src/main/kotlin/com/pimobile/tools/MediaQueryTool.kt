package com.pimobile.tools

import android.content.ContentResolver
import android.graphics.BitmapFactory
import android.media.ExifInterface
import android.net.Uri
import android.provider.MediaStore
import com.pimobile.agent.AgentToolResult
import com.pimobile.agent.Tool
import com.pimobile.agent.ToolResultDetails
import kotlinx.serialization.json.*
import android.util.Base64
import java.io.ByteArrayOutputStream

class MediaQueryTool(private val contentResolver: ContentResolver) : Tool {

    override val name = "media_query"
    override val description = "Query device media (images, video, audio, documents). Supports listing, reading images as base64, and EXIF metadata."
    override val parametersSchema = buildJsonObject {
        put("type", "object")
        putJsonObject("properties") {
            putJsonObject("action") {
                put("type", "string")
                putJsonArray("enum") { add("list"); add("read"); add("metadata") }
                put("description", "Action: list media, read image as base64, or get metadata")
            }
            putJsonObject("mediaType") {
                put("type", "string")
                putJsonArray("enum") { add("images"); add("video"); add("audio"); add("documents") }
                put("description", "Type of media to query")
            }
            putJsonObject("uri") {
                put("type", "string")
                put("description", "Content URI for read/metadata actions")
            }
            putJsonObject("mimeType") {
                put("type", "string")
                put("description", "Filter by MIME type")
            }
            putJsonObject("searchText") {
                put("type", "string")
                put("description", "Search by display name")
            }
            putJsonObject("limit") {
                put("type", "integer")
                put("description", "Max results (default 50)")
            }
        }
        putJsonArray("required") { add("action") }
    }

    override suspend fun execute(input: JsonObject): AgentToolResult {
        val action = input["action"]?.jsonPrimitive?.contentOrNull
            ?: return AgentToolResult("", "Error: 'action' is required", isError = true)

        return try {
            when (action) {
                "list" -> listMedia(input)
                "read" -> readMedia(input)
                "metadata" -> getMetadata(input)
                else -> AgentToolResult("", "Error: Unknown action '$action'", isError = true)
            }
        } catch (e: Exception) {
            AgentToolResult("", "Media query error: ${e.message}", isError = true)
        }
    }

    private fun listMedia(input: JsonObject): AgentToolResult {
        val mediaType = input["mediaType"]?.jsonPrimitive?.contentOrNull ?: "images"
        val mimeTypeFilter = input["mimeType"]?.jsonPrimitive?.contentOrNull
        val searchText = input["searchText"]?.jsonPrimitive?.contentOrNull
        val limit = input["limit"]?.jsonPrimitive?.intOrNull ?: 50

        val (contentUri, projection) = when (mediaType) {
            "images" -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI to arrayOf(
                MediaStore.Images.Media._ID,
                MediaStore.Images.Media.DISPLAY_NAME,
                MediaStore.Images.Media.DATE_ADDED,
                MediaStore.Images.Media.SIZE,
                MediaStore.Images.Media.MIME_TYPE
            )
            "video" -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI to arrayOf(
                MediaStore.Video.Media._ID,
                MediaStore.Video.Media.DISPLAY_NAME,
                MediaStore.Video.Media.DATE_ADDED,
                MediaStore.Video.Media.SIZE,
                MediaStore.Video.Media.MIME_TYPE
            )
            "audio" -> MediaStore.Audio.Media.EXTERNAL_CONTENT_URI to arrayOf(
                MediaStore.Audio.Media._ID,
                MediaStore.Audio.Media.DISPLAY_NAME,
                MediaStore.Audio.Media.DATE_ADDED,
                MediaStore.Audio.Media.SIZE,
                MediaStore.Audio.Media.MIME_TYPE
            )
            "documents" -> MediaStore.Files.getContentUri("external") to arrayOf(
                MediaStore.Files.FileColumns._ID,
                MediaStore.Files.FileColumns.DISPLAY_NAME,
                MediaStore.Files.FileColumns.DATE_ADDED,
                MediaStore.Files.FileColumns.SIZE,
                MediaStore.Files.FileColumns.MIME_TYPE
            )
            else -> return AgentToolResult("", "Error: Unknown media type '$mediaType'", isError = true)
        }

        val selection = buildString {
            val conditions = mutableListOf<String>()
            if (mimeTypeFilter != null) {
                conditions.add("${MediaStore.MediaColumns.MIME_TYPE} = ?")
            }
            if (searchText != null) {
                conditions.add("${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ?")
            }
            append(conditions.joinToString(" AND "))
        }.ifEmpty { null }

        val selectionArgs = buildList {
            if (mimeTypeFilter != null) add(mimeTypeFilter)
            if (searchText != null) add("%$searchText%")
        }.toTypedArray().ifEmpty { null }

        val sortOrder = "${MediaStore.MediaColumns.DATE_ADDED} DESC LIMIT $limit"

        val cursor = contentResolver.query(contentUri, projection, selection, selectionArgs, sortOrder)
            ?: return AgentToolResult("", "Error: Query returned null cursor", isError = true)

        val columns = listOf("URI", "Name", "Date", "Size", "Type")
        val rows = mutableListOf<List<String>>()

        cursor.use {
            while (it.moveToNext()) {
                val id = it.getLong(0)
                val name = it.getString(1) ?: "unknown"
                val date = it.getLong(2)
                val size = it.getLong(3)
                val mime = it.getString(4) ?: "unknown"
                val uri = Uri.withAppendedPath(contentUri, id.toString()).toString()

                rows.add(listOf(uri, name, formatDate(date), formatSize(size), mime))
            }
        }

        val output = buildString {
            appendLine("Media: $mediaType (${rows.size} results)")
            for (row in rows) {
                appendLine("${row[1]} | ${row[4]} | ${row[3]} | ${row[2]}")
                appendLine("  URI: ${row[0]}")
            }
        }

        return AgentToolResult("", output, ToolResultDetails.Table(columns, rows))
    }

    private fun readMedia(input: JsonObject): AgentToolResult {
        val uriString = input["uri"]?.jsonPrimitive?.contentOrNull
            ?: return AgentToolResult("", "Error: 'uri' is required for read action", isError = true)

        val uri = Uri.parse(uriString)
        val inputStream = contentResolver.openInputStream(uri)
            ?: return AgentToolResult("", "Error: Cannot open URI: $uriString", isError = true)

        val bitmap = BitmapFactory.decodeStream(inputStream)
        inputStream.close()

        if (bitmap == null) {
            return AgentToolResult("", "Error: Could not decode image from URI", isError = true)
        }

        val outputStream = ByteArrayOutputStream()
        bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 85, outputStream)
        val base64 = Base64.encodeToString(outputStream.toByteArray(), Base64.NO_WRAP)
        bitmap.recycle()

        return AgentToolResult(
            "",
            "[Image: ${bitmap.width}x${bitmap.height}]\nbase64:$base64"
        )
    }

    private fun getMetadata(input: JsonObject): AgentToolResult {
        val uriString = input["uri"]?.jsonPrimitive?.contentOrNull
            ?: return AgentToolResult("", "Error: 'uri' is required for metadata action", isError = true)

        val uri = Uri.parse(uriString)
        val inputStream = contentResolver.openInputStream(uri)
            ?: return AgentToolResult("", "Error: Cannot open URI: $uriString", isError = true)

        val exif = ExifInterface(inputStream)
        inputStream.close()

        val tags = listOf(
            "DateTime" to ExifInterface.TAG_DATETIME,
            "Make" to ExifInterface.TAG_MAKE,
            "Model" to ExifInterface.TAG_MODEL,
            "Orientation" to ExifInterface.TAG_ORIENTATION,
            "ExposureTime" to ExifInterface.TAG_EXPOSURE_TIME,
            "FNumber" to ExifInterface.TAG_F_NUMBER,
            "ISO" to "ISOSpeedRatings",
            "FocalLength" to ExifInterface.TAG_FOCAL_LENGTH,
            "ImageWidth" to ExifInterface.TAG_IMAGE_WIDTH,
            "ImageHeight" to ExifInterface.TAG_IMAGE_LENGTH,
            "GPSLatitude" to ExifInterface.TAG_GPS_LATITUDE,
            "GPSLongitude" to ExifInterface.TAG_GPS_LONGITUDE,
            "WhiteBalance" to ExifInterface.TAG_WHITE_BALANCE,
            "Flash" to ExifInterface.TAG_FLASH
        )

        val output = buildString {
            appendLine("EXIF Metadata for: $uriString")
            appendLine()
            for ((label, tag) in tags) {
                val value = exif.getAttribute(tag)
                if (value != null) {
                    appendLine("$label: $value")
                }
            }

            val lat = exif.getAttribute(ExifInterface.TAG_GPS_LATITUDE)
            val lon = exif.getAttribute(ExifInterface.TAG_GPS_LONGITUDE)
            val latRef = exif.getAttribute(ExifInterface.TAG_GPS_LATITUDE_REF)
            val lonRef = exif.getAttribute(ExifInterface.TAG_GPS_LONGITUDE_REF)
            if (lat != null && lon != null) {
                appendLine("GPS Coordinates: $lat $latRef, $lon $lonRef")
            }
        }

        return AgentToolResult("", output)
    }

    private fun formatDate(epochSeconds: Long): String {
        val sdf = java.text.SimpleDateFormat("yyyy-MM-dd HH:mm", java.util.Locale.US)
        return sdf.format(java.util.Date(epochSeconds * 1000))
    }

    private fun formatSize(bytes: Long): String {
        return when {
            bytes < 1024 -> "${bytes}B"
            bytes < 1024 * 1024 -> "${bytes / 1024}KB"
            bytes < 1024 * 1024 * 1024 -> "${bytes / (1024 * 1024)}MB"
            else -> "${bytes / (1024 * 1024 * 1024)}GB"
        }
    }
}
