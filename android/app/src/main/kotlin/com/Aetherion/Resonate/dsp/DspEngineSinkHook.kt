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
 *
 * Crash history (2026-09-28): old JNI called dsp_create(double, int) but the
 * real ABI is dsp_create(const DspConfig*). That treated the sample-rate bits
 * as a pointer → SIGSEGV in dsp_create+36. JNI was corrected to build a
 * DspConfig and pass &cfg; native can be ON again.
 */
object DspEngineSinkHook {
    private const val TAG = "DspEngineSinkHook"

    /**
     * Master switch for live native EQ/DVC.
     * Requires libdsp_engine.so in the APK and ABI-matched JNI.
     */
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
