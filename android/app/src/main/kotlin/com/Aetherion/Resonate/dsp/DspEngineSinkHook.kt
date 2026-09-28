package com.aetherion.resonate.dsp

import androidx.media3.common.audio.AudioProcessor
import android.util.Log

/**
 * Reflection entry point for the just_audio pub-cache / fork patch.
 * just_audio calls createProcessors() so the DSP sits in DefaultAudioSink.
 *
 * Live native path uses ABI-correct dsp_create(const DspConfig*) via JNI.
 */
object DspEngineSinkHook {
    private const val TAG = "DspEngineSinkHook"

    /** Safe after JNI ABI fix (DspConfig*). Set false to force pass-through. */
    private const val ENABLE_NATIVE_LIVE_DSP = true

    @JvmStatic
    fun createProcessors(): Array<AudioProcessor> {
        return try {
            val proc = DspEngineAudioProcessor()
            proc.setNativeProcessEnabled(ENABLE_NATIVE_LIVE_DSP)
            if (ENABLE_NATIVE_LIVE_DSP) {
                Log.i(TAG, "Injected 1 host AudioProcessor(s) with native DSP enabled")
            } else {
                Log.i(TAG, "Injected 1 host AudioProcessor(s) pass-through (native DSP disabled)")
            }
            arrayOf(proc)
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to create DspEngineAudioProcessor", t)
            emptyArray()
        }
    }
}
