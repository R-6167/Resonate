package com.aetherion.resonate.dsp

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.audio.AudioProcessor.UnhandledAudioFormatException
import java.nio.ByteBuffer

/**
 * Live path: PCM16 blocks from ExoPlayer → JNI → dsp_process.
 * Locked policy: max 4096 frames stereo 16-bit = 16384 bytes, 64-byte align in native.
 */
class DspEngineAudioProcessor : BaseAudioProcessor() {

    companion object {
        const val MAX_FRAMES = 4096
        const val MAX_BYTES = MAX_FRAMES * 2 * 2 // stereo PCM16
    }

    @Volatile
    private var nativeProcessEnabled = false

    private var engineHandle: Long = 0
    private var configuredRate: Double = 44100.0
    private var configuredChannels: Int = 2

    fun setNativeProcessEnabled(enabled: Boolean) {
        nativeProcessEnabled = enabled
        if (engineHandle != 0L) {
            try {
                DspEngineJni.nativeSetEnabled(engineHandle, enabled)
            } catch (_: Throwable) { }
        }
    }

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        if (inputAudioFormat.encoding != C.ENCODING_PCM_16BIT) {
            throw UnhandledAudioFormatException(inputAudioFormat)
        }
        configuredRate = inputAudioFormat.sampleRate.toDouble()
        configuredChannels = inputAudioFormat.channelCount
        if (engineHandle == 0L) {
            try {
                engineHandle = DspEngineJni.nativeCreate(configuredRate, configuredChannels)
            } catch (_: Throwable) {
                engineHandle = 0
            }
        }
        return inputAudioFormat
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        val remaining = inputBuffer.remaining()
        if (remaining <= 0) return

        if (!nativeProcessEnabled || engineHandle == 0L || remaining > MAX_BYTES) {
            val output = replaceOutputBuffer(remaining)
            output.put(inputBuffer)
            output.flip()
            return
        }

        // Prefer in-place on a direct buffer; BaseAudioProcessor output is direct.
        val output = replaceOutputBuffer(remaining)
        // Copy input → output first so we always have a writable direct buffer.
        val pos = inputBuffer.position()
        output.put(inputBuffer)
        output.flip()

        val frames = remaining / (configuredChannels * 2)
        if (frames > 0 && frames <= MAX_FRAMES) {
            try {
                // Process the output buffer (direct) in place via JNI.
                DspEngineJni.nativeProcessPcm16Direct(
                    engineHandle,
                    output,
                    frames,
                    configuredChannels,
                    configuredRate
                )
            } catch (_: Throwable) {
                // Leave unprocessed PCM in output on any native failure.
            }
        }
        // output already flipped and filled
    }

    override fun onFlush() {
        // Engine state is continuous; no hard reset required.
    }

    override fun onReset() {
        destroyEngine()
    }

    private fun destroyEngine() {
        if (engineHandle != 0L) {
            try {
                DspEngineJni.nativeDestroy(engineHandle)
            } catch (_: Throwable) { }
            engineHandle = 0
        }
    }
}
