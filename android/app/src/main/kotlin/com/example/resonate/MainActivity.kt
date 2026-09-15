package com.Aetherion.Resonate

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.media.audiofx.BassBoost
import android.media.audiofx.EnvironmentalReverb
import android.media.audiofx.Virtualizer
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import android.provider.MediaStore
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

class MainActivity : AudioServiceActivity() {
    private val channelName = "com.example.resonate/media_store"
    private val effectsChannelName = "com.example.resonate/audio_effects"
    private val permissionRequestCode = 6167
    private val folderRequestCode = 6168
    private val notificationPermissionRequestCode = 6169
    private val diagnosticFileRequestCode = 6170
    private var permissionResult: MethodChannel.Result? = null
    private var folderResult: MethodChannel.Result? = null
    private var notificationPermissionResult: MethodChannel.Result? = null
    private var diagnosticFileResult: MethodChannel.Result? = null
    private var pendingDiagnosticBytes: ByteArray? = null
    private var pendingDiagnosticMime: String = "application/json"
    private var effectSessionId: Int = 0
    private var bassBoost: BassBoost? = null
    private var virtualizer: Virtualizer? = null
    private var reverb: EnvironmentalReverb? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestAudioPermission" -> requestAudioPermission(result)
                "requestNotificationPermission" -> requestNotificationPermission(result)
                "getSystemVolume" -> getSystemVolume(result)
                "setSystemVolume" -> setSystemVolume(call.argument<Double>("value") ?: 1.0, result)
                "pickFolder" -> pickFolder(result)
                "saveDiagnosticReport" -> saveDiagnosticReport(call.argument<String>("fileName") ?: "resonate-diagnostics.json", call.argument<ByteArray>("bytes") ?: ByteArray(0), result)
                "scanAudio" -> result.success(scanAudio(call.argument<List<String>>("folders") ?: emptyList(), call.argument<Int>("minimumDurationMs") ?: 30000))
                "getAudioSize" -> result.success(getAudioSize(call.argument<List<String>>("folders") ?: emptyList()))
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, effectsChannelName).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "attachToSession" -> { attachEffects(call.argument<Int>("sessionId") ?: 0); result.success(true) }
                    "setBassBoost" -> { bassBoost?.setStrength((call.argument<Int>("strength") ?: 0).coerceIn(0, 1000).toShort()); result.success(true) }
                    "setVirtualizer" -> { virtualizer?.setStrength((call.argument<Int>("strength") ?: 0).coerceIn(0, 1000).toShort()); result.success(true) }
                    "setReverb" -> { reverb?.reverbLevel = (call.argument<Int>("strength") ?: 0).coerceIn(-900, 1000).toShort(); result.success(true) }
                    "release" -> { releaseEffects(); result.success(true) }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) { result.error("AUDIO_EFFECT_ERROR", e.message, null) }
        }
    }

    private fun attachEffects(sessionId: Int) {
        if (sessionId <= 0 || sessionId == effectSessionId) return
        releaseEffects(); effectSessionId = sessionId
        try { bassBoost = BassBoost(0, sessionId).apply { enabled = true } } catch (_: Exception) { bassBoost = null }
        try { virtualizer = Virtualizer(0, sessionId).apply { enabled = true } } catch (_: Exception) { virtualizer = null }
        try { reverb = EnvironmentalReverb(0, sessionId).apply { enabled = true } } catch (_: Exception) { reverb = null }
    }

    private fun releaseEffects() {
        try { bassBoost?.release() } catch (_: Exception) { }
        try { virtualizer?.release() } catch (_: Exception) { }
        try { reverb?.release() } catch (_: Exception) { }
        bassBoost = null; virtualizer = null; reverb = null; effectSessionId = 0
    }

    private fun audioPermission(): String = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_AUDIO else Manifest.permission.READ_EXTERNAL_STORAGE
    private fun hasAudioPermission(): Boolean = checkSelfPermission(audioPermission()) == PackageManager.PERMISSION_GRANTED

    private fun requestAudioPermission(result: MethodChannel.Result) {
        if (hasAudioPermission()) { result.success(true); return }
        permissionResult = result; requestPermissions(arrayOf(audioPermission()), permissionRequestCode)
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33 || checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) { result.success(true); return }
        notificationPermissionResult = result; requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), notificationPermissionRequestCode)
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
        try { contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) } catch (_: Exception) { }
        val documentId = DocumentsContract.getTreeDocumentId(uri)
        val name = documentId.substringAfter(':').trim('/').substringAfterLast('/').ifBlank { "Device storage" }
        result.success(mapOf("uri" to uri.toString(), "name" to name))
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        when (requestCode) {
            permissionRequestCode -> { permissionResult?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED); permissionResult = null }
            notificationPermissionRequestCode -> { notificationPermissionResult?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED); notificationPermissionResult = null }
        }
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
        return prefixes.any { prefix -> normalized.contains("/$prefix") || normalized.startsWith(prefix) }
    }

    private fun projection(includeSize: Boolean = false): MutableList<String> {
        val fields = mutableListOf(MediaStore.Audio.Media._ID, MediaStore.Audio.Media.TITLE, MediaStore.Audio.Media.ARTIST, MediaStore.Audio.Media.ALBUM, MediaStore.Audio.Media.DURATION, MediaStore.Audio.Media.DATE_ADDED, MediaStore.Audio.Media.MIME_TYPE)
        if (includeSize) fields.add(MediaStore.Audio.Media.SIZE)
        if (Build.VERSION.SDK_INT >= 29) fields.add(MediaStore.Audio.Media.RELATIVE_PATH)
        if (Build.VERSION.SDK_INT <= 28) fields.add(MediaStore.Audio.Media.DATA)
        return fields
    }

    private fun querySelectedAudio(folders: List<String>, includeSize: Boolean = false): Long {
        if (!hasAudioPermission()) return 0L
        val prefixes = selectedPrefixes(folders)
        val restrict = folders.isNotEmpty()
        if (restrict && prefixes.isEmpty()) return 0L
        var total = 0L
        contentResolver.query(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, projection(includeSize).toTypedArray(), null, null, "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE ASC")?.use { cursor ->
            val mime = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.MIME_TYPE)
            val size = if (includeSize) cursor.getColumnIndex(MediaStore.Audio.Media.SIZE) else -1
            val relative = if (Build.VERSION.SDK_INT >= 29) cursor.getColumnIndex(MediaStore.Audio.Media.RELATIVE_PATH) else -1
            val data = if (Build.VERSION.SDK_INT <= 28) cursor.getColumnIndex(MediaStore.Audio.Media.DATA) else -1
            while (cursor.moveToNext()) {
                if (!(cursor.getString(mime) ?: "").startsWith("audio/")) continue
                if (restrict && !isInSelectedFolder(if (relative >= 0) cursor.getString(relative) else null, if (data >= 0) cursor.getString(data) else null, prefixes)) continue
                if (includeSize && size >= 0) total += cursor.getLong(size)
            }
        }
        return total
    }

    private fun scanAudio(folders: List<String>, minimumDurationMs: Int): List<Map<String, Any?>> {
        if (!hasAudioPermission()) return emptyList()
        val prefixes = selectedPrefixes(folders)
        val restrict = folders.isNotEmpty()
        if (restrict && prefixes.isEmpty()) return emptyList()
        val songs = mutableListOf<Map<String, Any?>>()
        val collection = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        contentResolver.query(collection, projection().toTypedArray(), null, null, "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE ASC")?.use { cursor ->
            val id = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val title = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artist = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val album = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val duration = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            val dateAdded = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_ADDED)
            val mime = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.MIME_TYPE)
            val relative = if (Build.VERSION.SDK_INT >= 29) cursor.getColumnIndex(MediaStore.Audio.Media.RELATIVE_PATH) else -1
            val data = if (Build.VERSION.SDK_INT <= 28) cursor.getColumnIndex(MediaStore.Audio.Media.DATA) else -1
            while (cursor.moveToNext()) {
                if (!(cursor.getString(mime) ?: "").startsWith("audio/")) continue
                if (restrict && !isInSelectedFolder(if (relative >= 0) cursor.getString(relative) else null, if (data >= 0) cursor.getString(data) else null, prefixes)) continue
                if (cursor.getLong(duration) < minimumDurationMs.toLong()) continue
                val mediaId = cursor.getLong(id)
                songs.add(mapOf("filePath" to ContentUris.withAppendedId(collection, mediaId).toString(), "title" to cursor.getString(title), "artist" to cursor.getString(artist), "album" to cursor.getString(album), "duration" to cursor.getLong(duration), "dateAdded" to cursor.getLong(dateAdded)))
            }
        }
        return songs
    }

    private fun getAudioSize(folders: List<String>): Long = querySelectedAudio(folders, includeSize = true)
    override fun onDestroy() { releaseEffects(); super.onDestroy() }
}
