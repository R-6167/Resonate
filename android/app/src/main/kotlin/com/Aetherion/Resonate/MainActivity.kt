package com.Aetherion.Resonate

import android.app.Activity
import android.content.Intent
import android.media.AudioManager
import android.provider.DocumentsContract
import com.Aetherion.Resonate.media.PermissionHelper
import com.Aetherion.Resonate.media.Media3PlaybackBridge
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

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
    private var media3PlaybackBridge: Media3PlaybackBridge? = null
    private val pcmAnalysisHandler = PcmAnalysisHandler(this)
    private val folderScanHandler = FolderScanHandler(this) { permissionHelper.hasAudioPermission() }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestAudioPermission" -> permissionHelper.requestAudioPermission(result)
                "requestVisualizationPermission" -> permissionHelper.requestVisualizationPermission(result)
                "requestNotificationPermission" -> permissionHelper.requestNotificationPermission(result)
                "getSystemVolume" -> getSystemVolume(result)
                "setSystemVolume" -> setSystemVolume(call.argument<Double>("value") ?: 1.0, result)
                "pickFolder" -> pickFolder(result)
                "saveDiagnosticReport" -> saveDiagnosticReport(call.argument<String>("fileName") ?: "resonate-diagnostics.json", call.argument<ByteArray>("bytes") ?: ByteArray(0), result)
                "scanAudio" -> result.success(folderScanHandler.scanAudio(call.argument<List<String>>("folders") ?: emptyList(), call.argument<Int>("minimumDurationMs") ?: 30000, call.argument<Boolean>("includeNonMusic") ?: false))
                "scanModeFolder" -> folderScanHandler.scanModeFolderAsync(call.argument<String>("folderUri") ?: "", result)
                "getAudioSize" -> result.success(folderScanHandler.getAudioSize(call.argument<List<String>>("folders") ?: emptyList()))
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
        media3PlaybackBridge?.release()
        media3PlaybackBridge = Media3PlaybackBridge(this, flutterEngine.dartExecutor.binaryMessenger)
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

    override fun onDestroy() {
        media3PlaybackBridge?.release()
        media3PlaybackBridge = null
        effectsChannelHandler.release()
        pcmAnalysisHandler.release()
        folderScanHandler.release()
        super.onDestroy()
    }
}
