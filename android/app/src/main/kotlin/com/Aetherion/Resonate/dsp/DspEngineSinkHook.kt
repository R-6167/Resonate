package com.Aetherion.Resonate.dsp

import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.util.UnstableApi

/**
 * Reflection entry point for the just_audio Android patch.
 *
 * just_audio calls:
 *   Class.forName("com.Aetherion.Resonate.dsp.DspEngineSinkHook")
 *     .getMethod("createProcessors").invoke(null)
 *
 * and feeds the result into DefaultAudioSink.Builder.setAudioProcessors.
 *
 * Keep the method name and signature stable.
 */
@UnstableApi
object DspEngineSinkHook {

    /**
     * @return processors to insert into the ExoPlayer / media3 audio sink chain.
     *         Empty array disables native DSP on the live path.
     */
    @JvmStatic
    fun createProcessors(): Array<AudioProcessor> {
        val proc = DspEngineAudioProcessor()
        proc.nativeProcessEnabled = true
        // Warm JNI load off the audio thread when possible.
        DspEngineJni.tryLoad()
        return arrayOf(proc)
    }
}
