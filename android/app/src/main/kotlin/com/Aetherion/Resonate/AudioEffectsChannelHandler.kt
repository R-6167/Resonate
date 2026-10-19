package com.Aetherion.Resonate

import com.Aetherion.Resonate.effects.AndroidEffectsBridge
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Owns the Android audio-effects and live-DSP method channel.
 * Kept separate from MainActivity so platform-channel dispatch and DSP lifecycle
 * can be reviewed independently of media scanning and PCM analysis.
 */
internal class AudioEffectsChannelHandler {
    private val channelName = "com.aetherion.resonate/audio_effects"
    private val effectsBridge = AndroidEffectsBridge()

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, channelName).setMethodCallHandler { call, result ->
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
                    // Live DSP engine, applied to every active stream in the registry.
                    "setLiveDspPreampDb" -> {
                        val db = (call.argument<Number>("db") ?: 0.0).toDouble().coerceIn(-12.0, 12.0)
                        val linear = Math.pow(10.0, db / 20.0)
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
                    "getLiveDspStatus" -> result.success(com.aetherion.resonate.dsp.DspEngineRegistry.statusMap())
                    "release" -> {
                        release()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("AUDIO_EFFECT_ERROR", e.message, null)
            }
        }
    }

    fun release() {
        effectsBridge.release()
    }
}
