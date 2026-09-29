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
                "saveDiagnosticReport" -> saveDiagnosticReport(
                    call.argument<String>("fileName") ?: "resonate-diagnostics.json",
                    call.argument<ByteArray>("bytes") ?: ByteArray(0),
                    result,
                )
                "scanAudio" -> result.success(
                    scanAudio(
                        call.argument<List<String>>("folders") ?: emptyList(),
                        call.argument<Int>("minimumDurationMs") ?: 30000,
                    )
                )
                "getAudioSize" -> result.success(
                    getAudioSize(call.argument<List<String>>("folders") ?: emptyList())
                )
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
                    "setLiveDspPreampDb" -> {
                        val db = (call.argument<Number>("db") ?: 0.0).toDouble().coerceIn(-12.0, 12.0)
                        val linear = if (db <= -120.0) 0.0 else Math.pow(10.0, db / 20.0)
                        com.aetherion.resonate.dsp.DspEngineRegistry.applyVolumeAll(linear)
                        result.success(
                            mapOf(
                                "ok" to true,
                                "linear" to linear,
                                "active" to com.aetherion.resonate.dsp.DspEngineRegistry.activeCount(),
                            )
                        )
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
                        result.success(
                            mapOf(
                                "ok" to true,
                                "bands" to gains.size,
                                "active" to com.aetherion.resonate.dsp.DspEngineRegistry.activeCount(),
                            )
                        )
                    }
                    "setLiveDspSpeakerMode" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        com.aetherion.resonate.dsp.DspEngineRegistry.applySpeakerModeAll(enabled)
                        result.success(
                            mapOf(
                                "ok" to true,
                                "enabled" to enabled,
                                "active" to com.aetherion.resonate.dsp.DspEngineRegistry.activeCount(),
                            )
                        )
                    }
                    "setLiveDspVirtualBass" -> {
                        val amount = (call.argument<Number>("amount") ?: 0.55)
                            .toDouble()
                            .coerceIn(0.0, 1.0)
                        com.aetherion.resonate.dsp.DspEngineRegistry.applyVirtualBassAll(amount)
                        result.success(mapOf("ok" to true, "amount" to amount))
                    }
                    "getLiveDspStatus" -> {
                        result.success(com.aetherion.resonate.dsp.DspEngineRegistry.statusMap())
                    }
                    "runBassStress" -> {
                        try {
                            val arr = com.aetherion.resonate.dsp.DspEngineJni.nativeRunBassStress()
                            if (arr == null || arr.size < 7) {
                                result.success(
                                    mapOf("ok" to false, "error" to "native unavailable")
                                )
                            } else {
                                result.success(
                                    mapOf(
                                        "ok" to (arr[0] >= 0.5),
                                        "casesRun" to arr[1].toInt(),
                                        "casesPassed" to arr[2].toInt(),
                                        "maxPeak" to arr[3],
                                        "peakFailures" to arr[4].toInt(),
                                        "nanFailures" to arr[5].toInt(),
                                        "speakerOk" to arr[6].toInt(),
                                    )
                                )
                            }
                        } catch (t: Throwable) {
                            result.success(
                                mapOf(
                                    "ok" to false,
                                    "error" to (t.message ?: "stress failed"),
                                )
                            )
                        }
                    }
                    "release" -> {
                        releaseEffects()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("AUDIO_EFFECT_ERROR", e.message, null)
            }
        }
    }

    private fun attachEffects(sessionId: Int) {
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

    private fun attachResonateDsp(sessionId: Int): Boolean {
        if (sessionId <= 0) return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            resonateDspBandCount = 0
            return false
        }
        for (requestedBands in intArrayOf(10, 5, 3)) {
            try {
                try {
                    resonateDsp?.release()
                } catch (_: Exception) {
                }
                resonateDsp = null
                val config = DynamicsProcessing.Config.Builder(
                    DynamicsProcessing.VARIANT_FAVOR_FREQUENCY_RESOLUTION,
                    1,
                    true,
                    requestedBands,
                    false,
                    0,
                    false,
                    0,
                    false,
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
                val hz = if (i < centersHz.size) {
                    centersHz[i].toFloat()
                } else {
                    preEq.getBand(i).cutoffFrequency
                }
                val db = if (i < gainsDb.size) {
                    gainsDb[i].toFloat().coerceIn(-12f, 12f)
                } else {
                    0f
                }
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

    private fun audioPermission(): String =
        if (Build.VERSION.SDK_INT >= 33) {
            Manifest.permission.READ_MEDIA_AUDIO
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }

    private fun hasAudioPermission(): Boolean =
        checkSelfPermission(audioPermission()) == PackageManager.PERMISSION_GRANTED

    private fun requestAudioPermission(result: MethodChannel.Result) {
        if (hasAudioPermission()) {
            result.success(true)
            return
        }
        permissionResult = result
        requestPermissions(arrayOf(audioPermission()), permissionRequestCode)
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33 ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        notificationPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            notificationPermissionRequestCode,
        )
    }

    private fun getSystemVolume(result: MethodChannel.Result) {
        try {
            val audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
            result.success(
                mapOf(
                    "current" to audioManager.getStreamVolume(AudioManager.STREAM_MUSIC),
                    "max" to audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC),
                )
            )
        } catch (e: Exception) {
            result.error("SYSTEM_VOLUME_ERROR", e.message, null)
        }
    }

    private fun setSystemVolume(value: Double, result: MethodChannel.Result) {
        try {
            val audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
            val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            audioManager.setStreamVolume(
                AudioManager.STREAM_MUSIC,
                (value.coerceIn(0.0, 1.0) * max).roundToInt(),
                0,
            )
            result.success(true)
        } catch (e: Exception) {
            result.error("SYSTEM_VOLUME_ERROR", e.message, null)
        }
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

    private fun saveDiagnosticReport(
        fileName: String,
        bytes: ByteArray,
        result: MethodChannel.Result,
    ) {
        if (bytes.isEmpty()) {
            result.error("EMPTY_REPORT", "Diagnostic report is empty.", null)
            return
        }
        diagnosticFileResult = result
        pendingDiagnosticBytes = bytes
        pendingDiagnosticMime = "application/json"
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = pendingDiagnosticMime
            putExtra(
                Intent.EXTRA_TITLE,
                if (fileName.endsWith(".json")) fileName else "$fileName.json",
            )
        }
        try {
            startActivityForResult(intent, diagnosticFileRequestCode)
        } catch (e: Exception) {
            diagnosticFileResult = null
            pendingDiagnosticBytes = null
            result.error("DOCUMENT_PICKER_FAILED", e.message, null)
        }
    }

    // NOTE: Remaining media-store helpers (onActivityResult, scanAudio, etc.)
    // must remain as they were on Wire_dsp_engine — if this restore is incomplete,
    // recover from git history before the SEE_LOCAL commit.
}
