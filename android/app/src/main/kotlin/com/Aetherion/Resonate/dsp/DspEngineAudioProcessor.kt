package com.Aetherion.Resonate.dsp

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import java.nio.ByteBuffer

/**
 * media3 [BaseAudioProcessor] for live DSP ENGINE processing.
 *
 * Buffer policy (locked — see docs/DSP_JNI_BUFFERS.md):
 * - Align: 64 bytes (native float scratch via posix_memalign)
 * - Max frames/block: 4096
 * - Max channels: 2
 * - Live encoding: PCM 16-bit
 * - Max bytes/block: 16384
 *
 * When [nativeProcessEnabled] and the engine handle is valid, [queueInput]
 * calls JNI → cached [GetDirectBufferAddress] → PCM16↔float → [dsp_process].
 * Otherwise identity pass-through (still no alloc on the hot path).
 *
 * Injection into ExoPlayer still requires a just_audio RenderersFactory hook.
 */
@UnstableApi
class DspEngineAudioProcessor : BaseAudioProcessor() {

    companion object {
        const val ALIGN_BYTES: Int = 64
        const val MAX_CHANNELS: Int = 2
        const val MAX_FRAMES_PER_BLOCK: Int = 4096
        const val POOL_SLOTS: Int = 4
        const val BYTES_PER_SAMPLE: Int = 2
        const val MAX_BYTES_PER_BLOCK: Int =
            MAX_FRAMES_PER_BLOCK * MAX_CHANNELS * BYTES_PER_SAMPLE
    }

    /** Set true to attempt native process (requires libdsp_engine.so). */
    @Volatile
    var nativeProcessEnabled: Boolean = false

    private var engineHandle: Long = 0L
    private var configuredChannels: Int = 2

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        if (inputAudioFormat.encoding != C.ENCODING_PCM_16BIT) {
            throw AudioProcessor.UnhandledAudioFormatException(inputAudioFormat)
        }
        if (inputAudioFormat.channelCount !in 1..MAX_CHANNELS) {
            throw AudioProcessor.UnhandledAudioFormatException(inputAudioFormat)
        }

        configuredChannels = inputAudioFormat.channelCount
        releaseEngine()

        if (nativeProcessEnabled && DspEngineJni.tryLoad()) {
            engineHandle = DspEngineJni.create(
                sampleRate = inputAudioFormat.sampleRate,
                channels = configuredChannels,
                bufferFrames = MAX_FRAMES_PER_BLOCK,
            )
            if (engineHandle == 0L) {
                // Stay active as pass-through; caller can inspect DspEngineJni.loadError
                nativeProcessEnabled = false
            }
        }

        return inputAudioFormat
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        if (!inputBuffer.hasRemaining()) return

        val remaining = inputBuffer.remaining()
        if (remaining > MAX_BYTES_PER_BLOCK) {
            val output = replaceOutputBuffer(remaining)
            output.put(inputBuffer)
            output.flip()
            return
        }

        val frames = remaining / (configuredChannels * BYTES_PER_SAMPLE)
        if (frames <= 0) {
            inputBuffer.position(inputBuffer.limit())
            return
        }

        val output = replaceOutputBuffer(remaining)

        val useNative =
            nativeProcessEnabled &&
                engineHandle != 0L &&
                inputBuffer.isDirect &&
                output.isDirect

        if (useNative) {
            val inPos = inputBuffer.position()
            // Output from replaceOutputBuffer is cleared (pos=0); process into it.
            val processed = DspEngineJni.processPcm16Direct(
                handle = engineHandle,
                input = inputBuffer,
                inputOffset = inPos,
                output = output,
                outputOffset = 0,
                frames = frames,
            )
            if (processed > 0) {
                inputBuffer.position(inPos + processed * configuredChannels * BYTES_PER_SAMPLE)
                output.position(processed * configuredChannels * BYTES_PER_SAMPLE)
                output.flip()
                return
            }
            // Fall through to copy on native error
        }

        output.put(inputBuffer)
        output.flip()
    }

    override fun onFlush() {
        // Engine state is continuous; no per-flush clear of EQ memory.
    }

    override fun onQueueEndOfStream() {}

    override fun onReset() {
        releaseEngine()
        nativeProcessEnabled = false
    }

    private fun releaseEngine() {
        if (engineHandle != 0L) {
            DspEngineJni.destroy(engineHandle)
            engineHandle = 0L
        }
    }
}
