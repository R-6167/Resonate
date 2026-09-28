package com.aetherion.resonate.dsp

import androidx.media3.common.audio.AudioProcessor
import android.util.Log

/**
 * Reflection entry for just_audio patch → DefaultAudioSink processors.
 *
 * Called once per ExoPlayer / just_audio engine. Resonate dual playback
 * therefore gets **two** independent [DspEngineAudioProcessor] instances
 * (engine A and engine B) when both players are created — which is what
 * we want for flawless crossfade (no shared native handle across threads).
 */
object DspEngineSinkHook {
    private const val TAG = "DspEngineSinkHook"

    /** Master switch; still subject to [DspSessionGate]. */
    private const val ENABLE_NATIVE_LIVE_DSP = true

    @JvmStatic
    fun createProcessors(): Array<AudioProcessor> {
        return try {
            val allow = ENABLE_NATIVE_LIVE_DSP && DspSessionGate.isNativeAllowed()
            val proc = DspEngineAudioProcessor()
            proc.setNativeProcessEnabled(allow)
            val active = DspEngineRegistry.activeCount()
            if (allow) {
                Log.i(
                    TAG,
                    "Injected 1 host AudioProcessor(s) native=ON " +
                        "(session ok; registry_active=$active — dual A/B uses 2 injects)"
                )
            } else {
                Log.i(
                    TAG,
                    "Injected 1 host AudioProcessor(s) pass-through " +
                        "(ENABLE=$ENABLE_NATIVE_LIVE_DSP gate_tripped=${DspSessionGate.isTripped()})"
                )
            }
            arrayOf(proc)
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to create DspEngineAudioProcessor", t)
            emptyArray()
        }
    }
}
