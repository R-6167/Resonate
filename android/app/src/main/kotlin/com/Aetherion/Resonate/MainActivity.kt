package com.Aetherion.Resonate

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
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
import java.util.concurrent.Executors

class MainActivity : AudioServiceActivity() {
    // Compile-time keep: audio_service looks up the FGS small icon by string.
    // Referencing R.drawable here forces AAPT2 to emit a real resource id.
    @Suppress("unused")
    private val mediaNotificationIconId = R.drawable.ic_stat_resonate

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
    private val pcmExecutor = Executors.newSingleThreadExecutor()

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
                "readMediaHead" -> readMediaHead(
                    call.argument<String>("uri") ?: "",
                    call.argument<Int>("maxBytes") ?: (512 * 1024),
                    result,
                )
                "extractPcmWindow" -> extractPcmWindow(
                    call.argument<String>("uri") ?: "",
                    (call.argument<Number>("maxSeconds") ?: 12.0).toDouble(),
                    (call.argument<Number>("startMs") ?: 0).toLong(),
                    result,
                )
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

                    // ---- Live DSP ENGINE (per-stream A/B via DspEngineRegistry) ----
                    "setLiveDspPreampDb" -> {
                        val db = (call.argument<Number>("db") ?: 0.0).toDouble().coerceIn(-12.0, 12.0)
                        val linear = if (db <= -120.0) 0.0 else Math.pow(10.0, db / 20.0)
                        com.aetherion.resonate.dsp.DspEngineRegistry.applyVolumeAll(linear)
                        result.success(mapOf("ok" to true, "linear" to linear, "active" to com.aetherion.resonate.dsp.DspEngineRegistry.activeCount()))
                    }
                    "setLiveDspEqBands" -> {
                        val centers = (call.argument<List<Double>>("centersHz") ?: emptyList()).toDoubleArray()
                        val gains = (call.argument<List<Double>>("gainsDb") ?: emptyList()).toDoubleArray()
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        com.aetherion.resonate.dsp.DspEngineRegistry.applyEqBandsAll(
                            if (centers.isEmpty()) null else centers,
                            gains,
                            enabled,
                        )
                        result.success(mapOf("ok" to true, "bands" to gains.size, "active" to com.aetherion.resonate.dsp.DspEngineRegistry.activeCount()))
                    }
                    "setLiveDspSpeakerMode" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        com.aetherion.resonate.dsp.DspEngineRegistry.applySpeakerModeAll(enabled)
                        result.success(mapOf(
                            "ok" to true,
                            "enabled" to enabled,
                            "active" to com.aetherion.resonate.dsp.DspEngineRegistry.activeCount(),
                        ))
                    }
                    "setLiveDspVirtualBass" -> {
                        val amount = (call.argument<Number>("amount") ?: 0.55).toDouble().coerceIn(0.0, 1.0)
                        com.aetherion.resonate.dsp.DspEngineRegistry.applyVirtualBassAll(amount)
                        result.success(mapOf("ok" to true, "amount" to amount))
                    }
                    "getLiveDspStatus" -> {
                        result.success(com.aetherion.resonate.dsp.DspEngineRegistry.statusMap())
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
        // Reconnected: only called when the user enables Native DSP and a session
        // already exists — never from the first-play critical path.
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

    private fun scanAudio(folders: List<String>, minimumDurationMs: Int): List<Map<String, Any?>> =
        @Suppress("UNCHECKED_CAST")
        (querySelectedAudio(folders, minimumDurationMs, includeSize = false) as List<Map<String, Any?>>)

    private fun getAudioSize(folders: List<String>): Long =
        querySelectedAudio(folders, includeSize = true) as Long


    /** Read first N bytes of a content:// or file path (ID3 head scan). */
    private fun readMediaHead(uriString: String, maxBytes: Int, result: MethodChannel.Result) {
        if (uriString.isBlank()) { result.success(null); return }
        pcmExecutor.execute {
            try {
                val uri = Uri.parse(uriString)
                val limit = maxBytes.coerceIn(1024, 2 * 1024 * 1024)
                val bytes = contentResolver.openInputStream(uri)?.use { input ->
                    val buf = ByteArray(limit)
                    var off = 0
                    while (off < limit) {
                        val n = input.read(buf, off, limit - off)
                        if (n <= 0) break
                        off += n
                    }
                    if (off <= 0) null else buf.copyOf(off)
                }
                runOnUiThread { result.success(bytes) }
            } catch (e: Exception) {
                try {
                    val file = java.io.File(uriString)
                    if (file.exists() && file.canRead()) {
                        val limit = maxBytes.coerceIn(1024, 2 * 1024 * 1024)
                        val len = minOf(limit.toLong(), file.length()).toInt()
                        val bytes = file.inputStream().use { stream ->
                            val b = stream.readBytes()
                            if (b.size > len) b.copyOf(len) else b
                        }
                        runOnUiThread { result.success(bytes) }
                        return@execute
                    }
                } catch (_: Exception) {}
                runOnUiThread { result.success(null) }
            }
        }
    }

    /** Decode a short PCM window via MediaExtractor/MediaCodec (MP3/M4A/content://). */
    private fun extractPcmWindow(uriString: String, maxSeconds: Double, startMs: Long, result: MethodChannel.Result) {
        if (uriString.isBlank()) { result.success(null); return }
        pcmExecutor.execute {
            var extractor: MediaExtractor? = null
            var codec: MediaCodec? = null
            try {
                extractor = MediaExtractor()
                val uri = Uri.parse(uriString)
                var opened = false
                try {
                    if (uriString.startsWith("content://") || uriString.startsWith("file://")) {
                        extractor.setDataSource(this@MainActivity, uri, null)
                        opened = true
                    }
                } catch (_: Exception) {}
                if (!opened) {
                    try {
                        contentResolver.openFileDescriptor(uri, "r")?.use { pfd ->
                            extractor.setDataSource(pfd.fileDescriptor)
                            opened = true
                        }
                    } catch (_: Exception) {}
                }
                if (!opened) {
                    try { extractor.setDataSource(uriString); opened = true } catch (_: Exception) {}
                }
                if (!opened) { runOnUiThread { result.success(null) }; return@execute }

                var audioTrack = -1
                var format: MediaFormat? = null
                for (i in 0 until extractor.trackCount) {
                    val f = extractor.getTrackFormat(i)
                    val mime = f.getString(MediaFormat.KEY_MIME) ?: continue
                    if (mime.startsWith("audio/")) { audioTrack = i; format = f; break }
                }
                if (audioTrack < 0 || format == null) { runOnUiThread { result.success(null) }; return@execute }
                extractor.selectTrack(audioTrack)
                if (startMs > 0L) {
                    try {
                        extractor.seekTo(startMs * 1000L, MediaExtractor.SEEK_TO_CLOSEST_SYNC)
                    } catch (_: Exception) {}
                }
                val mime = format.getString(MediaFormat.KEY_MIME) ?: run {
                    runOnUiThread { result.success(null) }; return@execute
                }
                val sampleRate = if (format.containsKey(MediaFormat.KEY_SAMPLE_RATE)) format.getInteger(MediaFormat.KEY_SAMPLE_RATE) else 44100
                val channelCount = if (format.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) format.getInteger(MediaFormat.KEY_CHANNEL_COUNT) else 2
                codec = MediaCodec.createDecoderByType(mime)
                codec.configure(format, null, null, 0)
                codec.start()
                val maxUs = (maxSeconds.coerceIn(4.0, 25.0) * 1_000_000L).toLong()
                val maxPcmBytes = (sampleRate * channelCount * 2 * maxSeconds.coerceIn(4.0, 25.0)).toInt().coerceIn(64 * 1024, 3 * 1024 * 1024)
                val outBytes = java.io.ByteArrayOutputStream(maxPcmBytes.coerceAtMost(512 * 1024))
                val info = MediaCodec.BufferInfo()
                var inputDone = false
                var outputDone = false
                var safety = 0
                while (!outputDone && safety < 800 && outBytes.size() < maxPcmBytes) {
                    safety++
                    if (!inputDone) {
                        val inIndex = codec.dequeueInputBuffer(8000)
                        if (inIndex >= 0) {
                            val inBuf = codec.getInputBuffer(inIndex)
                            if (inBuf != null) {
                                inBuf.clear()
                                val sampleSize = extractor.readSampleData(inBuf, 0)
                                if (sampleSize < 0 || extractor.sampleTime < 0L || extractor.sampleTime > startMs * 1000L + maxUs) {
                                    codec.queueInputBuffer(inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                                    inputDone = true
                                } else {
                                    codec.queueInputBuffer(inIndex, 0, sampleSize, extractor.sampleTime.coerceAtLeast(0), 0)
                                    extractor.advance()
                                }
                            }
                        }
                    }
                    val outIndex = codec.dequeueOutputBuffer(info, 8000)
                    if (outIndex >= 0) {
                        if (info.size > 0 && info.presentationTimeUs <= maxUs) {
                            val outBuf = codec.getOutputBuffer(outIndex)
                            if (outBuf != null) {
                                outBuf.position(info.offset)
                                outBuf.limit(info.offset + info.size)
                                val chunk = ByteArray(info.size)
                                outBuf.get(chunk)
                                val room = maxPcmBytes - outBytes.size()
                                if (room > 0) outBytes.write(chunk, 0, minOf(chunk.size, room))
                            }
                        }
                        codec.releaseOutputBuffer(outIndex, false)
                        if ((info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) outputDone = true
                        if (outBytes.size() >= maxPcmBytes) outputDone = true
                    }
                }
                val pcm = outBytes.toByteArray()
                if (pcm.size < sampleRate) { runOnUiThread { result.success(null) }; return@execute }
                runOnUiThread {
                    result.success(hashMapOf("sampleRate" to sampleRate, "channels" to channelCount, "pcm" to pcm))
                }
            } catch (e: Exception) {
                runOnUiThread { result.success(null) }
            } finally {
                try { codec?.stop() } catch (_: Exception) {}
                try { codec?.release() } catch (_: Exception) {}
                try { extractor?.release() } catch (_: Exception) {}
            }
        }
    }

    override fun onDestroy() {
        releaseEffects()
        super.onDestroy()
    }
}
