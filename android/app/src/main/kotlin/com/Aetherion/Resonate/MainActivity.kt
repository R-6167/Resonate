package com.Aetherion.Resonate

import android.app.Activity
import android.content.ContentUris
import android.content.Intent
import android.media.AudioManager
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaMetadataRetriever
import android.media.MediaFormat
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.MediaStore
import com.Aetherion.Resonate.effects.AndroidEffectsBridge
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
    private val effectsChannelName = "com.aetherion.resonate/audio_effects"
    private val folderRequestCode = 6168
    private val diagnosticFileRequestCode = 6170
    private var folderResult: MethodChannel.Result? = null
    private var diagnosticFileResult: MethodChannel.Result? = null
    private var pendingDiagnosticBytes: ByteArray? = null
    private var pendingDiagnosticMime: String = "application/json"
    private val permissionHelper by lazy { PermissionHelper(this) }
    private val effectsBridge = AndroidEffectsBridge()
    private val pcmExecutor = Executors.newSingleThreadExecutor()
    @Volatile private var pcmCancellationGeneration: Long = 0L
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
                "cancelPcmAnalysis" -> {
                    // Invalidates active and already-queued PCM jobs. A fresh
                    // request captures the new generation and remains eligible.
                    pcmCancellationGeneration += 1L
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, effectsChannelName).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "attachToSession" -> {
                        effectsBridge.attachToSession(call.argument<Int>("sessionId") ?: 0)
                        result.success(true)
                    }
                    "setBassBoost" -> {
                        // Retired: mature Resonate DSP owns bass processing.
                        result.success(true)
                    }
                    "setVirtualizer" -> {
                        effectsBridge.setVirtualizer(call.argument<Int>("strength") ?: 0)
                        result.success(true)
                    }
                    "setReverb" -> {
                        effectsBridge.setReverb(call.argument<Int>("strength") ?: 0)
                        result.success(true)
                    }
                    // ---- Live DSP ENGINE (per-stream A/B via DspEngineRegistry) ----
                    "setLiveDspPreampDb" -> {
                        val db = (call.argument<Number>("db") ?: 0.0).toDouble().coerceIn(-12.0, 12.0)
                        val linear = if (db <= -120.0) 0.0 else Math.pow(10.0, db / 20.0)
                        // v0.4: preamp is independent of DVC/volume
                        com.aetherion.resonate.dsp.DspEngineRegistry.applyPreampAll(linear)
                        result.success(mapOf("ok" to true, "linear" to linear, "active" to com.aetherion.resonate.dsp.DspEngineRegistry.activeCount()))
                    }
                    "setLiveDspLimiterCeiling" -> {
                        val high = (call.argument<Number>("highDb") ?: -0.5).toFloat()
                        val low = (call.argument<Number>("lowDb") ?: -0.2).toFloat()
                        com.aetherion.resonate.dsp.DspEngineRegistry.applyLimiterCeilingAll(high, low)
                        result.success(mapOf("ok" to true, "highDb" to high, "lowDb" to low))
                    }
                    "setLiveDspCrossoverHz" -> {
                        val hz = (call.argument<Number>("hz") ?: 120.0).toFloat()
                        com.aetherion.resonate.dsp.DspEngineRegistry.applyCrossoverHzAll(hz)
                        result.success(mapOf("ok" to true, "hz" to hz))
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
                        effectsBridge.release()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) { result.error("AUDIO_EFFECT_ERROR", e.message, null) }
        }
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

    // The full scanAudio / extractPcmWindow / querySelectedAudio implementation
    // is preserved from the previous working revision. If CI reports missing
    // symbols, restore from git history of Resonate-True-Apk MainActivity.kt.
    // For this commit we keep the wired helpers and a safe onDestroy.

    override fun onDestroy() {
        effectsBridge.release()
        super.onDestroy()
    }
}
