package com.Aetherion.Resonate

import com.Aetherion.Resonate.effects.AndroidEffectsBridge
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Owns the Android audio-effects method channel.
 * Live native DSP control is delegated to a focused handler so system effects and
 * the registry-backed processing engine can be reviewed independently.
 */
internal class AudioEffectsChannelHandler {
    private val channelName = "com.aetherion.resonate/audio_effects"
    private val effectsBridge = AndroidEffectsBridge()
    private val liveDspChannelHandler = LiveDspChannelHandler()

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, channelName).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "attachToSession" -> {
                        effectsBridge.attachToSession(call.argument<Int>("sessionId") ?: 0)
                        result.success(true)
                    }
                    "detachFromSession" -> {
                        effectsBridge.detachFromSession(call.argument<Int>("sessionId") ?: 0)
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
                    // Live DSP controls have their own boundary from Android system effects.
                    "setLiveDspEnabled",
                    "setLiveDspPreampDb",
                    "setLiveDspDvcDb",
                    "setLiveDspLimiterCeiling",
                    "setLiveDspCrossoverHz",
                    "setLiveDspEqBands",
                    "setLiveDspSpeakerMode",
                    "setLiveDspVirtualBass",
                    "getLiveDspStatus" -> liveDspChannelHandler.handle(call, result)
                    "getAudioSpectrum" -> result.success(effectsBridge.getSpectrum())
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
