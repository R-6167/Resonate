package com.Aetherion.Resonate

import android.app.Activity
import android.content.ContentUris
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.MediaStore
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Owns MediaStore queries and recursive Storage Access Framework scans.
 * Folder picking and persisted permission grants remain in MainActivity because
 * they depend on activity-result lifecycle callbacks.
 */
internal class FolderScanHandler(
    private val activity: Activity,
    private val hasAudioPermission: () -> Boolean,
) {
    private val folderScanExecutor = Executors.newSingleThreadExecutor()

        private fun selectedPrefixes(folders: List<String>): Set<String> = folders.mapNotNull { value ->
            try {
                val id = DocumentsContract.getTreeDocumentId(Uri.parse(value))
                val path = id.substringAfter(':', "").trim('/')
                if (path.isEmpty()) "" else "$path/"
            } catch (_: Exception) { null }
        }.toSet()
    
        private fun isInSelectedFolder(relativePath: String?, dataPath: String?, prefixes: Set<String>): Boolean {
            if (prefixes.isEmpty()) return false
            if (prefixes.contains("")) return true
            val relative = (relativePath ?: "").trim('/') + "/"
            if (prefixes.any { relative.startsWith(it) || it.startsWith(relative) }) return true
            val absolute = dataPath ?: return false
            val normalized = absolute.replace('\\', '/').trim('/') + "/"
            return prefixes.any { p ->
                val needle = p.trim('/')
                needle.isNotEmpty() && (normalized.contains("/$needle/") || normalized.endsWith("/$needle") || normalized.contains(needle))
            }
        }
    
        private fun querySelectedAudio(folders: List<String>, minimumDurationMs: Int = 0, includeSize: Boolean = false, includeNonMusic: Boolean = false): Any {
            if (!hasAudioPermission()) return if (includeSize) 0L else emptyList<Map<String, Any?>>()
            val prefixes = selectedPrefixes(folders)
            if (prefixes.isEmpty() && folders.isNotEmpty()) return if (includeSize) 0L else emptyList<Map<String, Any?>>()
            // RELATIVE_PATH was added in Android 10 (API 29). Including it in
            // the projection on Android 7/8 makes MediaStore queries fail before
            // any tracks are returned, even though mode-folder playback can work.
            // Keep the older DATA column as the compatibility fallback.
            val projectionColumns = mutableListOf(
                MediaStore.Audio.Media._ID,
                MediaStore.Audio.Media.TITLE,
                MediaStore.Audio.Media.ARTIST,
                MediaStore.Audio.Media.ALBUM,
                MediaStore.Audio.Media.DURATION,
                MediaStore.Audio.Media.DATE_ADDED,
                MediaStore.Audio.Media.SIZE,
                MediaStore.Audio.Media.DATA,
            )
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                projectionColumns.add(MediaStore.Audio.Media.RELATIVE_PATH)
            }
            val projection = projectionColumns.toTypedArray()
            val selection = StringBuilder(if (includeNonMusic && folders.isNotEmpty()) "1=1" else "${MediaStore.Audio.Media.IS_MUSIC} != 0")
            if (minimumDurationMs > 0) selection.append(" AND ${MediaStore.Audio.Media.DURATION} >= ?")
            val selectionArgs = if (minimumDurationMs > 0) arrayOf(minimumDurationMs.toString()) else null
            val songs = mutableListOf<Map<String, Any?>>()
            var totalSize = 0L
            activity.contentResolver.query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                projection,
                selection.toString(),
                selectionArgs,
                "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE ASC",
            )?.use { cursor ->
                val idCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
                val titleCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
                val artistCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
                val albumCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
                val durationCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
                val dateCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_ADDED)
                val sizeCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.SIZE)
                val dataCol = cursor.getColumnIndex(MediaStore.Audio.Media.DATA)
                val relativeCol = cursor.getColumnIndex(MediaStore.Audio.Media.RELATIVE_PATH)
                while (cursor.moveToNext()) {
                    val relativePath = if (relativeCol >= 0) cursor.getString(relativeCol) else null
                    val dataPath = if (dataCol >= 0) cursor.getString(dataCol) else null
                    if (folders.isNotEmpty() && !isInSelectedFolder(relativePath, dataPath, prefixes)) continue
                    val size = cursor.getLong(sizeCol)
                    if (includeSize) { totalSize += size; continue }
                    val id = cursor.getLong(idCol)
                    val contentUri = ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id).toString()
                    songs.add(
                        mapOf(
                            "filePath" to contentUri,
                            "title" to (cursor.getString(titleCol) ?: "Unknown Title"),
                            "artist" to (cursor.getString(artistCol) ?: "Unknown Artist"),
                            "album" to (cursor.getString(albumCol) ?: "Unknown Album"),
                            "duration" to cursor.getLong(durationCol),
                            "dateAdded" to cursor.getLong(dateCol),
                            "size" to size,
                        )
                    )
                }
            }
            return if (includeSize) totalSize else songs
        }
    
        /**
         * Scan the selected SAF tree directly. MediaStore can omit audiobook formats
         * (notably .m4b) or files that have not been indexed yet, so Mode folders must
         * not depend on READ_MEDIA_AUDIO or IS_MUSIC classification.
         */
        fun scanModeFolderAsync(folderUri: String, result: MethodChannel.Result) {
            folderScanExecutor.execute {
                try {
                    val songs = scanModeFolder(folderUri)
                    activity.runOnUiThread { result.success(songs) }
                } catch (e: Exception) {
                    android.util.Log.w("ResonateModes", "Mode folder scan failed", e)
                    activity.runOnUiThread {
                        result.error("MODE_FOLDER_SCAN_FAILED", e.message ?: "Unable to scan selected folder", null)
                    }
                }
            }
        }
    
        private fun scanModeFolder(folderUri: String): List<Map<String, Any?>> {
            if (folderUri.isBlank()) return emptyList()
            val treeUri = Uri.parse(folderUri)
            val hasReadGrant = activity.contentResolver.persistedUriPermissions.any {
                it.uri == treeUri && it.isReadPermission
            }
            if (!hasReadGrant) {
                throw SecurityException(
                    "Saved access to this folder has expired. Remove it and select the folder again."
                )
            }
            val rootDocumentId = DocumentsContract.getTreeDocumentId(treeUri)
            val results = mutableListOf<Map<String, Any?>>()
            val visited = mutableSetOf<String>()
            val audioExtensions = setOf(
                "aac", "aif", "aiff", "alac", "amr", "ape", "flac", "m4a",
                "m4b", "m4p", "mid", "midi", "mp3", "oga", "ogg", "opus",
                "wav", "wma", "3ga"
            )
            fun visit(documentId: String, depth: Int) {
                if (depth > 32 || !visited.add(documentId)) return
                val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, documentId)
                val cursor = activity.contentResolver.query(
                    childrenUri,
                    arrayOf(
                        DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                        DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                        DocumentsContract.Document.COLUMN_MIME_TYPE,
                    ),
                    null,
                    null,
                    null,
                ) ?: throw IllegalStateException(
                    "Storage provider returned no listing for selected folder: $documentId"
                )
                cursor.use {
                    val idColumn = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
                    val nameColumn = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                    val mimeColumn = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)
                    if (idColumn < 0 || nameColumn < 0 || mimeColumn < 0) {
                        throw IllegalStateException("Storage provider returned an unreadable folder listing")
                    }
                    while (cursor.moveToNext()) {
                        val childId = cursor.getString(idColumn) ?: continue
                        val name = cursor.getString(nameColumn) ?: "Unknown Title"
                        val mime = cursor.getString(mimeColumn) ?: ""
                        if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                            visit(childId, depth + 1)
                            continue
                        }
                        val extension = name.substringAfterLast('.', "").lowercase()
                        if (!mime.startsWith("audio/") && extension !in audioExtensions) continue
                        val fileUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, childId)
                        var title = name.substringBeforeLast('.', name).ifBlank { "Unknown Title" }
                        var artist = "Unknown Artist"
                        var album = "Unknown Album"
                        var durationMs = 0L
                        val metadata = MediaMetadataRetriever()
                        try {
                            metadata.setDataSource(activity, fileUri)
                            title = metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE)
                                ?.takeIf { it.isNotBlank() } ?: title
                            artist = metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST)
                                ?.takeIf { it.isNotBlank() } ?: artist
                            album = metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUM)
                                ?.takeIf { it.isNotBlank() } ?: album
                            durationMs = metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                                ?.toLongOrNull() ?: 0L
                        } catch (e: Exception) {
                            android.util.Log.d("ResonateModes", "Metadata unavailable for $name", e)
                        } finally {
                            try { metadata.release() } catch (_: Exception) {}
                        }
                        results.add(
                            mapOf(
                                "filePath" to fileUri.toString(),
                                "title" to title,
                                "artist" to artist,
                                "album" to album,
                                "duration" to durationMs,
                                "dateAdded" to 0L,
                            )
                        )
                    }
                }
            }
            visit(rootDocumentId, 0)
            return results
        }
    
        fun scanAudio(folders: List<String>, minimumDurationMs: Int, includeNonMusic: Boolean = false): List<Map<String, Any?>> =
            @Suppress("UNCHECKED_CAST")
            (querySelectedAudio(folders, minimumDurationMs, includeSize = false, includeNonMusic = includeNonMusic) as List<Map<String, Any?>>)
    
        fun getAudioSize(folders: List<String>): Long =
            querySelectedAudio(folders, includeSize = true) as Long

    fun release() {
        folderScanExecutor.shutdownNow()
    }
}
