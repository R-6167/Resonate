package com.aetherion.resonate.dsp

import androidx.media3.common.audio.AudioProcessor
import android.util.Log

/**
 * Reflection entry point for the just_audio pub-cache / fork patch.
 * just_audio calls createProcessors() so the DSP sits in DefaultAudioSink.
 *
 * LIVE native processing is OFF by default: libdsp_engine.so dsp_create currently
 * SIGSEGVs on device (tombstone: dsp_create+36). Processor still injects as
 * pass-through so the sink chain is wired; enable only after engine ABI is fixed.
 */
object DspEngineSinkHook {
    private const val TAG = "DspEngineSinkHook"

    /** Flip to true only after libdsp_engine dsp_create is stable on device. */
    private const val ENABLE_NATIVE_LIVE_DSP = false

    @JvmStatic
    fun createProcessors(): Array<AudioProcessor> {
        return try {
            val proc = DspEngineAudioProcessor()
            proc.setNativeProcessEnabled(ENABLE_NATIVE_LIVE_DSP)
            if (ENABLE_NATIVE_LIVE_DSP) {
                Log.i(TAG, "Injected 1 host AudioProcessor(s) with native DSP enabled")
            } else {
                Log.i(TAG, "Injected 1 host AudioProcessor(s) pass-through (native DSP disabled — dsp_create unsafe)")
            }
            arrayOf(proc)
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to create DspEngineAudioProcessor", t)
            emptyArray()
        }
    }
}
