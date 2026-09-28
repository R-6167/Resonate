package com.aetherion.resonate.dsp

import androidx.media3.common.audio.AudioProcessor
import android.util.Log

/**
 * Reflection entry point for the just_audio pub-cache / fork patch.
 * just_audio calls createProcessors() so the DSP sits in DefaultAudioSink.
 */
object DspEngineSinkHook {
    private const val TAG = "DspEngineSinkHook"

    @JvmStatic
    fun createProcessors(): Array<AudioProcessor> {
        return try {
            val proc = DspEngineAudioProcessor()
            proc.setNativeProcessEnabled(true)
            Log.i(TAG, "Injected 1 host AudioProcessor(s) into DefaultAudioSink")
            arrayOf(proc)
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to create DspEngineAudioProcessor", t)
            emptyArray()
        }
    }
}
