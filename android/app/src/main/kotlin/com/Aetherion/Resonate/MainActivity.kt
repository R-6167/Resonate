package com.Aetherion.Resonate

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.media.audiofx.BassBoost
import android.media.audiofx.DynamicsProcessing
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
    private val channelName = "com.aetherion.resonate/media_store"
    private val effectsChannelName = "com.aetherion.resonate/audio_effects"
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
    /** Resonate multi-band software-style EQ via DynamicsProcessing (API 28+). */
    private var resonateDsp: DynamicsProcessing? = null
    private var resonateDspBandCount: Int = 0
    private var resonateDspEnabled: Boolean = true

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
                    "attachToSession" -> {
                        attachEffects(call.argument<Int>("sessionId") ?: 0)
                        result.success(true)
                    }
                    "setBassBoost" -> {
                        val s = (call.argument<Int>("strength") ?: 0).coerceIn(0, 1000)
                        if (s > 0) ensureBassBoost()?.setStrength(s.toShort())
                        result.success(true)
                    }
                    "setVirtualizer" -> {
                        val s = (call.argument<Int>("strength") ?: 0).coerceIn(0, 1000)
                        if (s > 0) ensureVirtualizer()?.setStrength(s.toShort())
                        result.success(true)
                    }
                    "setReverb" -> {
                        val s = (call.argument<Int>("strength") ?: 0).coerceIn(-900, 1000)
                        if (s != 0) ensureReverb()?.reverbLevel = s.toShort()
                        result.success(true)
                    }
                    "attachResonateDsp" -> {
                        val sessionId = call.argument<Int>("sessionId") ?: 0
                        val ok = attachResonateDsp(sessionId)
                        result.success(
                            mapOf(
                                "ok" to ok,
                                "bandCount" to resonateDspBandCount,
                                "api" to Build.VERSION.SDK_INT,
                                "engine" to "ResonateDSP/v1-native-dp",
                            )
                        )
                    }
                    "setResonateEqBands" -> {
                        val centers = call.argument<List<Double>>("centersHz") ?: emptyList()
                        val gains = call.argument<List<Double>>("gainsDb") ?: emptyList()
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        result.success(setResonateEqBands(centers, gains, enabled))
                    }
                    "setResonateDspEnabled" -> {
                        resonateDspEnabled = call.argument<Boolean>("enabled") ?: true
                        try {
                            resonateDsp?.enabled = resonateDspEnabled
                        } catch (_: Exception) {
                        }
                        result.success(true)
                    }
                    "release" -> {
                        releaseEffects()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) { result.error("AUDIO_EFFECT_ERROR", e.message, null) }
        }
    }

    private fun attachEffects(sessionId: Int) {
        // CRITICAL: do not create BassBoost/Virtualizer/Reverb/DynamicsProcessing here.
        // Eager AudioEffect construction on first play kills the Activity on many OEMs
        // while ExoPlayer continues ("Resonate keeps stopping" + audio still playing).
        if (sessionId <= 0) return
        effectSessionId = sessionId
    }

    private fun ensureBassBoost(): BassBoost? {
        if (effectSessionId <= 0) return null
        if (bassBoost != null) return bassBoost
        return try {
            BassBoost(0, effectSessionId).also {
                it.enabled = true
                bassBoost = it
            }
        } catch (_: Throwable) {
            bassBoost = null
            null
        }
    }

    private fun ensureVirtualizer(): Virtualizer? {
        if (effectSessionId <= 0) return null
        if (virtualizer != null) return virtualizer
        return try {
            Virtualizer(0, effectSessionId).also {
                it.enabled = true
                virtualizer = it
            }
        } catch (_: Throwable) {
            virtualizer = null
            null
        }
    }

    private fun ensureReverb(): EnvironmentalReverb? {
        if (effectSessionId <= 0) return null
        if (reverb != null) return reverb
        return try {
            EnvironmentalReverb(0, effectSessionId).also {
                it.enabled = true
                reverb = it
            }
        } catch (_: Throwable) {
            reverb = null
            null
        }
    }

    /**
     * Resonate multi-band EQ using [DynamicsProcessing] pre-EQ (API 28+).
     * Band count is negotiated with the platform (often 5–32); Dart maps 31 studio
     * centers onto whatever the device accepts.
     */
    private fun attachResonateDsp(sessionId: Int): Boolean {
        // Temporarily disabled: DynamicsProcessing on session shared with just_audio
        // Equalizer caused Activity death on first play for some devices.
        resonateDspBandCount = 0
        return false
        if (sessionId <= 0) return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            resonateDspBandCount = 0
            return false
        }
        // Try modest band counts first — 31 crashes some OEM audio stacks.
        for (requestedBands in intArrayOf(10, 5, 3)) {
            try {
                try {
                    resonateDsp?.release()
                } catch (_: Exception) {
                }
                resonateDsp = null
                val config = DynamicsProcessing.Config.Builder(
                    DynamicsProcessing.VARIANT_FAVOR_FREQUENCY_RESOLUTION,
                    /*channelCount=*/1,
                    /*preEqInUse=*/true,
                    requestedBands,
                    /*mbcInUse=*/false,
                    /*mbcBandCount=*/0,
                    /*postEqInUse=*/false,
                    /*postEqBandCount=*/0,
                    /*limiterInUse=*/false,
                ).build()
                val dp = DynamicsProcessing(0, sessionId, config)
                dp.enabled = resonateDspEnabled
                val preEq = dp.getPreEqByChannelIndex(0)
                if (preEq.bandCount <= 0) {
                    try {
                        dp.release()
                    } catch (_: Exception) {
                    }
                    continue
                }
                resonateDsp = dp
                resonateDspBandCount = preEq.bandCount
                return true
            } catch (_: Exception) {
                resonateDsp = null
                resonateDspBandCount = 0
            } catch (_: Throwable) {
                // Catch Errors too — some OEM failures are not Exception subclasses.
                resonateDsp = null
                resonateDspBandCount = 0
            }
        }
        return false
    }

    private fun setResonateEqBands(
        centersHz: List<Double>,
        gainsDb: List<Double>,
        enabled: Boolean,
    ): Boolean {
        val dp = resonateDsp ?: return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return false
        try {
            resonateDspEnabled = enabled
            dp.enabled = enabled
            if (!enabled || resonateDspBandCount <= 0) return true
            val preEq = dp.getPreEqByChannelIndex(0)
            val n = preEq.bandCount.coerceAtMost(resonateDspBandCount)
            for (i in 0 until n) {
                val hz = if (i < centersHz.size) centersHz[i].toFloat() else preEq.getBand(i).cutoffFrequency
                val db = if (i < gainsDb.size) gainsDb[i].toFloat().coerceIn(-12f, 12f) else 0f
                // DynamicsProcessing EqBand: cutoffFrequency + gain
                val band = DynamicsProcessing.EqBand(true, hz, db)
                preEq.setBand(i, band)
            }
            dp.setPreEqAllChannelsTo(preEq)
            return true
        } catch (_: Exception) {
            return false
        }
    }

    private fun releaseEffects() {
        try {
            bassBoost?.release()
        } catch (_: Exception) {
        }
        try {
            virtualizer?.release()
        } catch (_: Exception) {
        }
        try {
            reverb?.release()
        } catch (_: Exception) {
        }
        try {
            resonateDsp?.release()
        } catch (_: Exception) {
        }
        bassBoost = null
        virtualizer = null
        reverb = null
        resonateDsp = null
        resonateDspBandCount = 0
        effectSessionId = 0
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
        return prefixes.any { p ->
            val needle = p.trim('/')
            needle.isNotEmpty() && (normalized.contains("/$needle/") || normalized.endsWith("/$needle") || normalized.contains(needle))
        }
    }

    private fun querySelectedAudio(folders: List<String>, minimumDurationMs: Int = 0, includeSize: Boolean = false): Any {
        if (!hasAudioPermission()) return if (includeSize) 0L else emptyList<Map<String, Any?>>()
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
        val selection = StringBuilder("${MediaStore.Audio.Media.IS_MUSIC} != 0")
        if (minimumDurationMs > 0) selection.append(" AND ${MediaStore.Audio.Media.DURATION} >= $minimumDurationMs")
        val songs = mutableListOf<Map<String, Any?>>()
        var totalSize = 0L
        contentResolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            projection,
            selection.toString(),
            null,
            "${MediaStore.Audio.Media.DATE_ADDED} DESC",
        )?.use { cursor ->
            val idIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val titleIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artistIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val albumIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val durationIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            val dateIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_ADDED)
            val sizeIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.SIZE)
            val dataIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
            val relativeIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.RELATIVE_PATH)
            while (cursor.moveToNext()) {
                val relative = if (relativeIdx >= 0) cursor.getString(relativeIdx) else null
                val dataPath = if (dataIdx >= 0) cursor.getString(dataIdx) else null
                if (folders.isNotEmpty() && !isInSelectedFolder(relative, dataPath, prefixes)) continue
                val id = cursor.getLong(idIdx)
                val size = if (sizeIdx >= 0) cursor.getLong(sizeIdx) else 0L
                if (includeSize) {
                    totalSize += size
                    continue
                }
                val contentUri = ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id)
                songs.add(
                    mapOf(
                        "filePath" to contentUri.toString(),
                        "title" to (cursor.getString(titleIdx) ?: "Unknown Title"),
                        "artist" to (cursor.getString(artistIdx) ?: "Unknown Artist"),
                        "album" to (cursor.getString(albumIdx) ?: "Unknown Album"),
                        "duration" to cursor.getLong(durationIdx),
                        "dateAdded" to cursor.getLong(dateIdx),
                        "size" to size,
                    )
                )
            }
        }
        return if (includeSize) totalSize else songs
    }

    private fun scanAudio(folders: List<String>, minimumDurationMs: Int): List<Map<String, Any?>> =
        @Suppress("UNCHECKED_CAST")
        (querySelectedAudio(folders, minimumDurationMs, includeSize = false) as List<Map<String, Any?>>)

    private fun getAudioSize(folders: List<String>): Long = querySelectedAudio(folders, includeSize = true) as Long
    override fun onDestroy() { releaseEffects(); super.onDestroy() }
}
