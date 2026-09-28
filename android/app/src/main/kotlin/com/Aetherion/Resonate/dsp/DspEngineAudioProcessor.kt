package com.Aetherion.Resonate.dsp

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * media3 [BaseAudioProcessor] scaffold for live DSP ENGINE processing.
 *
 * Buffer policy (locked — see docs/DSP_JNI_BUFFERS.md):
 * - Align: 64 bytes (native pool; media3 already hands direct buffers)
 * - Max frames/block: 4096
 * - Max channels: 2
 * - Live encoding: PCM 16-bit (2 bytes/sample)
 * - Max bytes/block: 16384
 * - Pool slots: 4 (allocated off the audio thread when JNI is wired)
 *
 * Today: identity pass-through (copy input → output). No alloc on the
 * hot path. When JNI is connected, [queueInput] will call dsp_process on
 * direct buffer addresses without malloc.
 *
 * Injection requires a custom DefaultRenderersFactory / just_audio fork;
 * this class alone does not attach to the player.
 */
@UnstableApi
class DspEngineAudioProcessor : BaseAudioProcessor() {

    companion object {
        /** Locked alignment target for any native scratch (posix_memalign). */
        const val ALIGN_BYTES: Int = 64

        /** Stereo first live path. */
        const val MAX_CHANNELS: Int = 2

        /** Upper bound for a single queueInput block. */
        const val MAX_FRAMES_PER_BLOCK: Int = 4096

        /** Fixed pool depth for native scratch (when JNI pool is enabled). */
        const val POOL_SLOTS: Int = 4

        /** Live path sample width (PCM 16-bit). */
        const val BYTES_PER_SAMPLE: Int = 2

        /** 4096 * 2 * 2 */
        const val MAX_BYTES_PER_BLOCK: Int =
            MAX_FRAMES_PER_BLOCK * MAX_CHANNELS * BYTES_PER_SAMPLE
    }

    /** True when native dsp_process is linked; false → pure pass-through. */
    @Volatile
    var nativeProcessEnabled: Boolean = false

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        if (inputAudioFormat.encoding != C.ENCODING_PCM_16BIT) {
            throw AudioProcessor.UnhandledAudioFormatException(inputAudioFormat)
        }
        if (inputAudioFormat.channelCount !in 1..MAX_CHANNELS) {
            throw AudioProcessor.UnhandledAudioFormatException(inputAudioFormat)
        }
        // Output format unchanged (format-preserving DSP).
        return inputAudioFormat
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        if (!inputBuffer.hasRemaining()) return

        val remaining = inputBuffer.remaining()
        if (remaining > MAX_BYTES_PER_BLOCK) {
            // Oversized block: pass through without native process to stay RT-safe.
            val output = replaceOutputBuffer(remaining)
            output.put(inputBuffer)
            output.flip()
            return
        }

        // media3 guarantees direct + native order for processor I/O.
        val output = replaceOutputBuffer(remaining)

        if (nativeProcessEnabled && inputBuffer.isDirect && output.isDirect) {
            // Future: GetDirectBufferAddress once cached + dsp_process(in, out, frames).
            // Until JNI is wired, fall through to copy.
            output.put(inputBuffer)
        } else {
            output.put(inputBuffer)
        }
        output.flip()
    }

    override fun onFlush() {
        // No pending state in pass-through mode.
    }

    override fun onQueueEndOfStream() {
        // No draining delay.
    }

    override fun onReset() {
        nativeProcessEnabled = false
    }
}
