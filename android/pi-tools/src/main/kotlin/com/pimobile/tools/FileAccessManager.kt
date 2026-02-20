package com.pimobile.tools

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.webkit.MimeTypeMap
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.documentfile.provider.DocumentFile
import kotlinx.coroutines.CompletableDeferred
import java.lang.ref.WeakReference
import java.text.SimpleDateFormat
import java.util.*

// MARK: - Data Types

data class PickedFileInfo(
    val bookmarkId: String,
    val name: String,
    val isDirectory: Boolean,
    val size: Long?,
    val mimeType: String?,
    val lastModified: Long?
)

data class DirectoryEntry(
    val name: String,
    val isDirectory: Boolean,
    val size: Long?,
    val mimeType: String?,
    val lastModified: Long?
)

data class GrantInfo(
    val id: String,
    val name: String?,
    val isValid: Boolean
)

// MARK: - FileAccessManager

class FileAccessManager private constructor() {

    companion object {
        val instance = FileAccessManager()
        private const val PREFS_KEY = "com.pi.fileAccessBookmarks"
        private const val BOOKMARKS_KEY = "bookmarks"
    }

    private var activityRef: WeakReference<ComponentActivity>? = null
    private var prefs: SharedPreferences? = null

    // Activity result launchers
    private var openDocumentLauncher: ActivityResultLauncher<Array<String>>? = null
    private var openMultipleDocumentsLauncher: ActivityResultLauncher<Array<String>>? = null
    private var openDocumentTreeLauncher: ActivityResultLauncher<Uri?>? = null
    private var createDocumentLauncher: ActivityResultLauncher<String>? = null

    // CompletableDeferreds for bridging callbacks to coroutines
    private var openDocumentDeferred: CompletableDeferred<Uri?>? = null
    private var openMultipleDocumentsDeferred: CompletableDeferred<List<Uri>>? = null
    private var openDocumentTreeDeferred: CompletableDeferred<Uri?>? = null
    private var createDocumentDeferred: CompletableDeferred<Uri?>? = null

    // Stored MIME types for the current pick operation
    private var pendingMimeTypes: Array<String>? = null

    /**
     * Must be called in Activity.onCreate() before the Activity reaches STARTED state.
     * Registers all ActivityResultLaunchers.
     */
    fun configure(activity: ComponentActivity) {
        activityRef = WeakReference(activity)
        prefs = activity.getSharedPreferences(PREFS_KEY, Context.MODE_PRIVATE)

        openDocumentLauncher = activity.registerForActivityResult(
            ActivityResultContracts.OpenDocument()
        ) { uri ->
            openDocumentDeferred?.complete(uri)
            openDocumentDeferred = null
        }

        openMultipleDocumentsLauncher = activity.registerForActivityResult(
            ActivityResultContracts.OpenMultipleDocuments()
        ) { uris ->
            openMultipleDocumentsDeferred?.complete(uris)
            openMultipleDocumentsDeferred = null
        }

        openDocumentTreeLauncher = activity.registerForActivityResult(
            ActivityResultContracts.OpenDocumentTree()
        ) { uri ->
            openDocumentTreeDeferred?.complete(uri)
            openDocumentTreeDeferred = null
        }

        createDocumentLauncher = activity.registerForActivityResult(
            ActivityResultContracts.CreateDocument("*/*")
        ) { uri ->
            createDocumentDeferred?.complete(uri)
            createDocumentDeferred = null
        }
    }

    // MARK: - Bookmark Persistence

    private fun loadBookmarks(): MutableMap<String, String> {
        val stored = prefs?.getString(BOOKMARKS_KEY, null) ?: return mutableMapOf()
        val map = mutableMapOf<String, String>()
        // Format: id1\nuri1\nid2\nuri2\n...
        val lines = stored.split("\n")
        var i = 0
        while (i + 1 < lines.size) {
            val id = lines[i]
            val uri = lines[i + 1]
            if (id.isNotEmpty() && uri.isNotEmpty()) {
                map[id] = uri
            }
            i += 2
        }
        return map
    }

    private fun persistBookmarks(bookmarks: Map<String, String>) {
        val sb = StringBuilder()
        for ((id, uri) in bookmarks) {
            sb.append(id).append("\n").append(uri).append("\n")
        }
        prefs?.edit()?.putString(BOOKMARKS_KEY, sb.toString())?.apply()
    }

    private fun storeBookmark(uri: Uri, name: String): String {
        val activity = activityRef?.get() ?: return ""
        val id = UUID.randomUUID().toString()

        // Take persistable permission
        try {
            val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            activity.contentResolver.takePersistableUriPermission(uri, flags)
        } catch (_: SecurityException) {
            // Read-only grant
            try {
                activity.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            } catch (_: SecurityException) {
                // No persistable permission available
            }
        }

        val bookmarks = loadBookmarks()
        bookmarks[id] = uri.toString()
        persistBookmarks(bookmarks)
        return id
    }

    private fun resolveBookmark(id: String): Uri? {
        val bookmarks = loadBookmarks()
        val uriString = bookmarks[id] ?: return null
        return Uri.parse(uriString)
    }

    // MARK: - Pick Files

    /**
     * Show the SAF file picker. Returns a list of picked files with bookmark IDs.
     * For directory picks, pass mimeTypes = listOf("folder").
     */
    suspend fun pickFiles(
        mimeTypes: List<String>,
        multiple: Boolean,
        isDirectory: Boolean
    ): List<PickedFileInfo>? {
        val activity = activityRef?.get() ?: return null

        if (isDirectory) {
            // Directory pick via OpenDocumentTree
            val deferred = CompletableDeferred<Uri?>()
            openDocumentTreeDeferred = deferred
            openDocumentTreeLauncher?.launch(null) ?: return null
            val uri = deferred.await() ?: return null

            val docFile = DocumentFile.fromTreeUri(activity, uri) ?: return null
            val bookmarkId = storeBookmark(uri, docFile.name ?: "folder")

            return listOf(
                PickedFileInfo(
                    bookmarkId = bookmarkId,
                    name = docFile.name ?: "folder",
                    isDirectory = true,
                    size = null,
                    mimeType = null,
                    lastModified = docFile.lastModified().takeIf { it > 0 }
                )
            )
        }

        val mimeArray = if (mimeTypes.isEmpty()) arrayOf("*/*") else mimeTypes.toTypedArray()

        if (multiple) {
            val deferred = CompletableDeferred<List<Uri>>()
            openMultipleDocumentsDeferred = deferred
            openMultipleDocumentsLauncher?.launch(mimeArray) ?: return null
            val uris = deferred.await()
            if (uris.isEmpty()) return null

            return uris.mapNotNull { uri -> buildPickedFileInfo(activity, uri) }
        } else {
            val deferred = CompletableDeferred<Uri?>()
            openDocumentDeferred = deferred
            openDocumentLauncher?.launch(mimeArray) ?: return null
            val uri = deferred.await() ?: return null

            val info = buildPickedFileInfo(activity, uri) ?: return null
            return listOf(info)
        }
    }

    private fun buildPickedFileInfo(activity: ComponentActivity, uri: Uri): PickedFileInfo? {
        val docFile = DocumentFile.fromSingleUri(activity, uri) ?: return null
        val bookmarkId = storeBookmark(uri, docFile.name ?: "file")

        return PickedFileInfo(
            bookmarkId = bookmarkId,
            name = docFile.name ?: "file",
            isDirectory = docFile.isDirectory,
            size = docFile.length().takeIf { it > 0 },
            mimeType = docFile.type,
            lastModified = docFile.lastModified().takeIf { it > 0 }
        )
    }

    // MARK: - Export File

    /**
     * Show the SAF save dialog to export data as a new file.
     */
    suspend fun exportFile(filename: String, data: ByteArray): Boolean {
        val activity = activityRef?.get() ?: return false

        val deferred = CompletableDeferred<Uri?>()
        createDocumentDeferred = deferred
        createDocumentLauncher?.launch(filename) ?: return false
        val uri = deferred.await() ?: return false

        return try {
            activity.contentResolver.openOutputStream(uri)?.use { stream ->
                stream.write(data)
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    // MARK: - Read File Data

    /**
     * Read file data using a persisted bookmark ID.
     * If subpath is provided, navigates within a tree URI.
     */
    fun readFileData(bookmarkId: String, subpath: String? = null): ByteArray? {
        val activity = activityRef?.get() ?: return null
        val uri = resolveBookmark(bookmarkId) ?: return null

        val targetUri = if (!subpath.isNullOrEmpty()) {
            resolveSubpath(activity, uri, subpath) ?: return null
        } else {
            uri
        }

        return try {
            activity.contentResolver.openInputStream(targetUri)?.use { it.readBytes() }
        } catch (_: Exception) {
            null
        }
    }

    // MARK: - Write File Data

    /**
     * Write data to a file using a persisted bookmark ID.
     * If subpath is provided, writes to a file within a tree URI.
     */
    fun writeFileData(bookmarkId: String, data: ByteArray, subpath: String? = null): Boolean {
        val activity = activityRef?.get() ?: return false
        val uri = resolveBookmark(bookmarkId) ?: return false

        val targetUri = if (!subpath.isNullOrEmpty()) {
            resolveSubpathForWrite(activity, uri, subpath) ?: return false
        } else {
            uri
        }

        return try {
            activity.contentResolver.openOutputStream(targetUri, "wt")?.use { stream ->
                stream.write(data)
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    // MARK: - List Directory

    /**
     * List contents of a directory bookmark.
     */
    fun listDirectory(bookmarkId: String, recursive: Boolean): List<DirectoryEntry>? {
        val activity = activityRef?.get() ?: return null
        val uri = resolveBookmark(bookmarkId) ?: return null
        val treeDoc = DocumentFile.fromTreeUri(activity, uri) ?: return null

        if (!treeDoc.isDirectory) return null

        val entries = mutableListOf<DirectoryEntry>()
        if (recursive) {
            listRecursive(treeDoc, "", entries)
        } else {
            for (child in treeDoc.listFiles()) {
                entries.add(
                    DirectoryEntry(
                        name = child.name ?: continue,
                        isDirectory = child.isDirectory,
                        size = child.length().takeIf { it > 0 },
                        mimeType = child.type,
                        lastModified = child.lastModified().takeIf { it > 0 }
                    )
                )
            }
        }

        return entries.sortedWith(compareBy<DirectoryEntry> { !it.isDirectory }.thenBy { it.name })
    }

    private fun listRecursive(dir: DocumentFile, prefix: String, entries: MutableList<DirectoryEntry>) {
        for (child in dir.listFiles()) {
            val name = child.name ?: continue
            val relativeName = if (prefix.isEmpty()) name else "$prefix/$name"

            entries.add(
                DirectoryEntry(
                    name = relativeName,
                    isDirectory = child.isDirectory,
                    size = child.length().takeIf { it > 0 },
                    mimeType = child.type,
                    lastModified = child.lastModified().takeIf { it > 0 }
                )
            )

            if (child.isDirectory) {
                listRecursive(child, relativeName, entries)
            }
        }
    }

    // MARK: - File Info

    /**
     * Get metadata for a bookmarked file or a file within a bookmarked directory.
     */
    fun fileInfo(bookmarkId: String, subpath: String? = null): Map<String, String>? {
        val activity = activityRef?.get() ?: return null
        val uri = resolveBookmark(bookmarkId) ?: return null

        val docFile = if (!subpath.isNullOrEmpty()) {
            val treeDoc = DocumentFile.fromTreeUri(activity, uri) ?: return null
            navigateToChild(treeDoc, subpath) ?: return null
        } else {
            // Try as tree first, fall back to single
            DocumentFile.fromTreeUri(activity, uri)
                ?: DocumentFile.fromSingleUri(activity, uri)
                ?: return null
        }

        val isoFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US)
        isoFormat.timeZone = TimeZone.getTimeZone("UTC")

        val info = mutableMapOf<String, String>()
        info["name"] = docFile.name ?: "unknown"
        info["path"] = docFile.uri.toString()
        info["is_directory"] = if (docFile.isDirectory) "yes" else "no"
        val size = docFile.length()
        if (size > 0) info["size_bytes"] = size.toString()
        docFile.type?.let { info["mime_type"] = it }
        val modified = docFile.lastModified()
        if (modified > 0) info["last_modified"] = isoFormat.format(Date(modified))

        return info
    }

    // MARK: - Grants Management

    /**
     * List all stored bookmark grants with validity info.
     */
    fun listGrants(): List<GrantInfo> {
        val activity = activityRef?.get() ?: return emptyList()
        val bookmarks = loadBookmarks()
        val persistedUris = activity.contentResolver.persistedUriPermissions.map { it.uri.toString() }.toSet()

        return bookmarks.map { (id, uriString) ->
            val uri = Uri.parse(uriString)
            val docFile = try {
                DocumentFile.fromTreeUri(activity, uri)
                    ?: DocumentFile.fromSingleUri(activity, uri)
            } catch (_: Exception) { null }

            GrantInfo(
                id = id,
                name = docFile?.name,
                isValid = uriString in persistedUris
            )
        }.sortedBy { it.name ?: "" }
    }

    /**
     * Remove a bookmark and release its persistable URI permission.
     */
    fun revokeGrant(id: String): Boolean {
        val activity = activityRef?.get() ?: return false
        val bookmarks = loadBookmarks()
        val uriString = bookmarks.remove(id) ?: return false
        persistBookmarks(bookmarks)

        // Release persistable permission
        try {
            val uri = Uri.parse(uriString)
            val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            activity.contentResolver.releasePersistableUriPermission(uri, flags)
        } catch (_: SecurityException) {
            // Permission may already be released
        }

        return true
    }

    // MARK: - File Name Helper

    /**
     * Get the display name for a bookmarked file.
     */
    fun fileName(bookmarkId: String, subpath: String? = null): String? {
        val activity = activityRef?.get() ?: return null
        if (!subpath.isNullOrEmpty()) {
            return subpath.substringAfterLast("/")
        }
        val uri = resolveBookmark(bookmarkId) ?: return null
        val docFile = DocumentFile.fromTreeUri(activity, uri)
            ?: DocumentFile.fromSingleUri(activity, uri)
            ?: return null
        return docFile.name
    }

    // MARK: - Subpath Resolution

    /**
     * Navigate a tree URI to find a child at the given relative path.
     */
    private fun navigateToChild(treeDoc: DocumentFile, subpath: String): DocumentFile? {
        val components = subpath.split("/").filter { it.isNotEmpty() }
        var current = treeDoc
        for (component in components) {
            current = current.findFile(component) ?: return null
        }
        return current
    }

    /**
     * Resolve a subpath within a tree URI for reading.
     */
    private fun resolveSubpath(activity: ComponentActivity, treeUri: Uri, subpath: String): Uri? {
        val treeDoc = DocumentFile.fromTreeUri(activity, treeUri) ?: return null
        val child = navigateToChild(treeDoc, subpath) ?: return null
        return child.uri
    }

    /**
     * Resolve a subpath within a tree URI for writing.
     * Creates parent directories and the file if they don't exist.
     */
    private fun resolveSubpathForWrite(activity: ComponentActivity, treeUri: Uri, subpath: String): Uri? {
        val treeDoc = DocumentFile.fromTreeUri(activity, treeUri) ?: return null
        val components = subpath.split("/").filter { it.isNotEmpty() }
        if (components.isEmpty()) return null

        var current = treeDoc

        // Navigate/create directories for all but the last component
        for (i in 0 until components.size - 1) {
            val dirName = components[i]
            val existing = current.findFile(dirName)
            current = if (existing != null && existing.isDirectory) {
                existing
            } else {
                current.createDirectory(dirName) ?: return null
            }
        }

        // Find or create the file
        val fileName = components.last()
        val existing = current.findFile(fileName)
        if (existing != null && !existing.isDirectory) {
            return existing.uri
        }

        val ext = fileName.substringAfterLast(".", "")
        val mimeType = if (ext.isNotEmpty()) {
            MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "application/octet-stream"
        } else {
            "application/octet-stream"
        }

        val created = current.createFile(mimeType, fileName) ?: return null
        return created.uri
    }
}
