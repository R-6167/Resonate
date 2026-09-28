package com.aetherion.resonate.dsp

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.audio.AudioProcessor.UnhandledAudioFormatException
import android.util.Log
import java.nio.ByteBuffer

/**
 * Live path: PCM16 blocks from ExoPlayer → JNI → dsp_process.
 * Locked policy: max 4096 frames stereo 16-bit = 16384 bytes, 64-byte align in native.
 *
 * nativeCreate is only invoked when nativeProcessEnabled is true. Calling
 * libdsp_engine dsp_create currently crashes (SIGSEGV) on some devices.
 */
class DspEngineAudioProcessor : BaseAudioProcessor() {

    companion object {
        private const val TAG = "DspEngineAudioProcessor"
        const val MAX_FRAMES = 4096
        const val MAX_BYTES = MAX_FRAMES * 2 * 2 // stereo PCM16
    }

    @Volatile
    private var nativeProcessEnabled = false

    private var engineHandle: Long = 0
    private var configuredRate: Double = 44100.0
    private var configuredChannels: Int = 2
    private var createAttempted = false

    fun setNativeProcessEnabled(enabled: Boolean) {
        nativeProcessEnabled = enabled
        if (!enabled) {
            // Keep existing handle if any; do not create while disabled.
            return
        }
        if (engineHandle != 0L) {
            try {
                DspEngineJni.nativeSetEnabled(engineHandle, true)
            } catch (_: Throwable) { }
        }
    }

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        if (inputAudioFormat.encoding != C.ENCODING_PCM_16BIT) {
            throw UnhandledAudioFormatException(inputAudioFormat)
        }
        configuredRate = inputAudioFormat.sampleRate.toDouble()
        configuredChannels = inputAudioFormat.channelCount

        // CRITICAL: never call nativeCreate unless live native DSP is explicitly enabled.
        // dsp_create in libdsp_engine.so has been observed to SIGSEGV (null deref).
        if (nativeProcessEnabled && engineHandle == 0L && !createAttempted) {
            createAttempted = true
            try {
                engineHandle = DspEngineJni.nativeCreate(configuredRate, configuredChannels)
                if (engineHandle == 0L) {
                    Log.w(TAG, "nativeCreate returned 0 — pass-through only")
                    nativeProcessEnabled = false
                }
            } catch (t: Throwable) {
                Log.e(TAG, "nativeCreate failed", t)
                engineHandle = 0
                nativeProcessEnabled = false
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

        val output = replaceOutputBuffer(remaining)
        output.put(inputBuffer)
        output.flip()

        val frames = remaining / (configuredChannels * 2)
        if (frames > 0 && frames <= MAX_FRAMES) {
            try {
                val rc = DspEngineJni.nativeProcessPcm16Direct(
                    engineHandle,
                    output,
                    frames,
                    configuredChannels,
                    configuredRate
                )
                if (rc != 0) {
                    Log.w(TAG, "nativeProcessPcm16Direct rc=$rc")
                }
            } catch (t: Throwable) {
                Log.e(TAG, "process failed — leaving buffer unprocessed", t)
            }
        }
    }

    override fun onFlush() {
        // Engine state is continuous; no hard reset required.
    }

    override fun onReset() {
        destroyEngine()
        createAttempted = false
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
