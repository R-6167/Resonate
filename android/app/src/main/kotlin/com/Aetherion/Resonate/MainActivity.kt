package com.Aetherion.Resonate

import android.app.Activity
import android.content.ContentUris
import android.content.Intent
import android.media.AudioManager
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.MediaStore
import com.Aetherion.Resonate.media.PermissionHelper
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt
import java.util.concurrent.Executors

class MainActivity : AudioServiceActivity() {
    // Compile-time keep: audio_service looks up the FGS small icon by string.
    // Referencing R.drawable here forces AAPT2 to emit a real resource id.
    @Suppress("unused")
    private val mediaNotificationIconId = R.drawable.ic_stat_resonate

    private val channelName = "com.aetherion.resonate/media_store"
    private val folderRequestCode = 6168
    private val diagnosticFileRequestCode = 6170
    private var folderResult: MethodChannel.Result? = null
    private var diagnosticFileResult: MethodChannel.Result? = null
    private var pendingDiagnosticBytes: ByteArray? = null
    private var pendingDiagnosticMime: String = "application/json"
    private val permissionHelper by lazy { PermissionHelper(this) }
    private val effectsChannelHandler = AudioEffectsChannelHandler()
    private val pcmAnalysisHandler = PcmAnalysisHandler(this)
    private val folderScanExecutor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestAudioPermission" -> permissionHelper.requestAudioPermission(result)
                "requestNotificationPermission" -> permissionHelper.requestNotificationPermission(result)
                "getSystemVolume" -> getSystemVolume(result)
                "setSystemVolume" -> setSystemVolume(call.argument<Double>("value") ?: 1.0, result)
                "pickFolder" -> pickFolder(result)
                "saveDiagnosticReport" -> saveDiagnosticReport(call.argument<String>("fileName") ?: "resonate-diagnostics.json", call.argument<ByteArray>("bytes") ?: ByteArray(0), result)
                "scanAudio" -> result.success(scanAudio(call.argument<List<String>>("folders") ?: emptyList(), call.argument<Int>("minimumDurationMs") ?: 30000, call.argument<Boolean>("includeNonMusic") ?: false))
                "scanModeFolder" -> scanModeFolderAsync(call.argument<String>("folderUri") ?: "", result)
                "getAudioSize" -> result.success(getAudioSize(call.argument<List<String>>("folders") ?: emptyList()))
                "readMediaHead" -> pcmAnalysisHandler.readMediaHead(
                    call.argument<String>("uri") ?: "",
                    call.argument<Int>("maxBytes") ?: (512 * 1024),
                    result,
                )
                "extractPcmWindow" -> pcmAnalysisHandler.extractPcmWindow(
                    call.argument<String>("uri") ?: "",
                    (call.argument<Number>("maxSeconds") ?: 12.0).toDouble(),
                    (call.argument<Number>("startMs") ?: 0).toLong(),
                    result,
                )
                "cancelPcmAnalysis" -> pcmAnalysisHandler.cancel(result)
                else -> result.notImplemented()
            }
        }
        effectsChannelHandler.register(flutterEngine.dartExecutor.binaryMessenger)
    }

    private fun getSystemVolume(result: MethodChannel.Result) {
        try { val audioManager = getSystemService(AUDIO_SERVICE) as AudioManager; result.success(mapOf("current" to audioManager.getStreamVolume(AudioManager.STREAM_MUSIC), "max" to audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC))) }
        catch (e: Exception) { result.error("SYSTEM_VOLUME_ERROR", e.message, null) }
    }

    private fun setSystemVolume(value: Double, result: MethodChannel.Result) {
        try { val audioManager = getSystemService(AUDIO_SERVICE) as AudioManager; val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC); audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, (value.coerceIn(0.0,1.0)*max).roundToInt(), 0); result.success(true) }
        catch (e: Exception) { result.error("SYSTEM_VOLUME_ERROR", e.message, null) }
    }

    private fun pickFolder(result: MethodChannel.Result) {
        folderResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
        }
        startActivityForResult(intent, folderRequestCode)
    }

    private fun saveDiagnosticReport(fileName: String, bytes: ByteArray, result: MethodChannel.Result) {
        if (bytes.isEmpty()) { result.error("EMPTY_REPORT", "Diagnostic report is empty.", null); return }
        diagnosticFileResult = result
        pendingDiagnosticBytes = bytes
        pendingDiagnosticMime = "application/json"
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = pendingDiagnosticMime
            putExtra(Intent.EXTRA_TITLE, if (fileName.endsWith(".json")) fileName else "$fileName.json")
        }
        try { startActivityForResult(intent, diagnosticFileRequestCode) } catch (e: Exception) {
            diagnosticFileResult = null
            pendingDiagnosticBytes = null
            result.error("DOCUMENT_PICKER_FAILED", e.message, null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == diagnosticFileRequestCode) {
            val result = diagnosticFileResult
            diagnosticFileResult = null
            val bytes = pendingDiagnosticBytes
            pendingDiagnosticBytes = null
            if (result == null) return
            if (resultCode != Activity.RESULT_OK || data?.data == null || bytes == null) { result.success(null); return }
            try {
                contentResolver.openOutputStream(data.data!!)?.use { it.write(bytes); it.flush() }
                    ?: throw IllegalStateException("Could not open selected document.")
                result.success(data.data!!.toString())
            } catch (e: Exception) { result.error("SAVE_FAILED", e.message, null) }
            return
        }
        if (requestCode != folderRequestCode) return
        val result = folderResult ?: return; folderResult = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) { result.success(null); return }
        val uri = data.data!!
        val grantFlags = data.flags and
            (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        if (grantFlags and Intent.FLAG_GRANT_READ_URI_PERMISSION == 0) {
            result.error(
                "FOLDER_READ_PERMISSION_MISSING",
                "Android did not grant read access to the selected folder. Please choose it again.",
                null,
            )
            return
        }
        try {
            contentResolver.takePersistableUriPermission(uri, grantFlags)
        } catch (e: Exception) {
            android.util.Log.w("ResonateModes", "Could not persist selected folder access", e)
            result.error(
                "FOLDER_PERMISSION_PERSIST_FAILED",
                "Could not keep access to the selected folder. Please choose it again. ${e.message ?: ""}".trim(),
                null,
            )
            return
        }
        val hasReadGrant = contentResolver.persistedUriPermissions.any {
            it.uri == uri && it.isReadPermission
        }
        if (!hasReadGrant) {
            result.error(
                "FOLDER_PERMISSION_NOT_PERSISTED",
                "Android did not retain access to the selected folder. Please choose it again.",
                null,
            )
            return
        }
        val documentId = DocumentsContract.getTreeDocumentId(uri)
        val name = documentId.substringAfter(':').trim('/').substringAfterLast('/').ifBlank { "Device storage" }
        result.success(mapOf("uri" to uri.toString(), "name" to name))
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        permissionHelper.onRequestPermissionsResult(requestCode, grantResults)
    }

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
        if (!permissionHelper.hasAudioPermission()) return if (includeSize) 0L else emptyList<Map<String, Any?>>()
        val prefixes = selectedPrefixes(folders)
        if (prefixes.isEmpty() && folders.isNotEmpty()) return if (includeSize) 0L else emptyList<Map<String, Any?>>()
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.DATE_ADDED,
            MediaStore.Audio.Media.SIZE,
            MediaStore.Audio.Media.DATA,
            MediaStore.Audio.Media.RELATIVE_PATH,
        )
        val selection = StringBuilder(if (includeNonMusic && folders.isNotEmpty()) "1=1" else "${MediaStore.Audio.Media.IS_MUSIC} != 0")
        if (minimumDurationMs > 0) selection.append(" AND ${MediaStore.Audio.Media.DURATION} >= ?")
        val selectionArgs = if (minimumDurationMs > 0) arrayOf(minimumDurationMs.toString()) else null
        val songs = mutableListOf<Map<String, Any?>>()
        var totalSize = 0L
        contentResolver.query(
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
            val dataCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
            val relativeCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.RELATIVE_PATH)
            while (cursor.moveToNext()) {
                val relativePath = cursor.getString(relativeCol)
                val dataPath = cursor.getString(dataCol)
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
    private fun scanModeFolderAsync(folderUri: String, result: MethodChannel.Result) {
        folderScanExecutor.execute {
            try {
                val songs = scanModeFolder(folderUri)
                runOnUiThread { result.success(songs) }
            } catch (e: Exception) {
                android.util.Log.w("ResonateModes", "Mode folder scan failed", e)
                runOnUiThread {
                    result.error("MODE_FOLDER_SCAN_FAILED", e.message ?: "Unable to scan selected folder", null)
                }
            }
        }
    }

    private fun scanModeFolder(folderUri: String): List<Map<String, Any?>> {
        if (folderUri.isBlank()) return emptyList()
        val treeUri = Uri.parse(folderUri)
        val hasReadGrant = contentResolver.persistedUriPermissions.any {
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
            val cursor = contentResolver.query(
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
                        metadata.setDataSource(this@MainActivity, fileUri)
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

    private fun scanAudio(folders: List<String>, minimumDurationMs: Int, includeNonMusic: Boolean = false): List<Map<String, Any?>> =
        @Suppress("UNCHECKED_CAST")
        (querySelectedAudio(folders, minimumDurationMs, includeSize = false, includeNonMusic = includeNonMusic) as List<Map<String, Any?>>)

    private fun getAudioSize(folders: List<String>): Long =
        querySelectedAudio(folders, includeSize = true) as Long

    override fun onDestroy() {
        effectsChannelHandler.release()
        pcmAnalysisHandler.release()
        super.onDestroy()
    }
}
