package com.aetherion.resonate.dsp

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.audio.AudioProcessor.UnhandledAudioFormatException
import android.util.Log
import java.nio.ByteBuffer
import java.util.concurrent.atomic.AtomicInteger

/**
 * Live path: PCM16 from one ExoPlayer sink → JNI → dsp_process.
 *
 * Dual-engine rule: one processor + one native handle per player (A or B).
 * Fail-open: any native trouble → pass-through. Native resources are released
 * when a processor is demoted so a failed engine cannot leak across a sink
 * lifecycle.
 */
class DspEngineAudioProcessor : BaseAudioProcessor() {

    companion object {
        private const val TAG = "DspEngineAudioProcessor"
        const val MAX_FRAMES = 4096
        const val MAX_BYTES = MAX_FRAMES * 2 * 2

        private val nextId = AtomicInteger(1)
    }

    private val processorId = nextId.getAndIncrement()

    @Volatile
    private var nativeProcessEnabled = false

    private var engineHandle: Long = 0
    private var configuredRate: Int = 44100
    private var configuredChannels: Int = 2
    private var createAttempted = false
    private var consecutiveProcessErrors = 0

    fun setNativeProcessEnabled(enabled: Boolean) {
        nativeProcessEnabled = enabled && DspSessionGate.isNativeAllowed()
        if (!nativeProcessEnabled) return

        if (engineHandle != 0L) {
            try {
                DspEngineJni.nativeSetEnabled(engineHandle, true)
            } catch (t: Throwable) {
                Log.w(TAG, "id=$processorId failed to re-enable native DSP", t)
                demoteToPassThrough("enable_exception")
            }
        }
    }

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        if (inputAudioFormat.encoding != C.ENCODING_PCM_16BIT) {
            throw UnhandledAudioFormatException(inputAudioFormat)
        }

        val rate = inputAudioFormat.sampleRate
        val ch = inputAudioFormat.channelCount.coerceIn(1, 2)

        if (engineHandle != 0L && (rate != configuredRate || ch != configuredChannels)) {
            Log.i(TAG, "id=$processorId format change $configuredRate/$configuredChannels → $rate/$ch")
            destroyEngine()
            createAttempted = false
        }

        configuredRate = rate
        configuredChannels = ch

        maybeCreateEngine()
        return inputAudioFormat
    }

    private fun maybeCreateEngine() {
        if (!nativeProcessEnabled) return
        if (!DspSessionGate.isNativeAllowed()) {
            nativeProcessEnabled = false
            return
        }
        if (engineHandle != 0L || createAttempted) return

        createAttempted = true
        try {
            val h = DspEngineJni.nativeCreate(configuredRate.toDouble(), configuredChannels)
            if (h == 0L) {
                Log.w(TAG, "id=$processorId nativeCreate returned 0 — pass-through")
                DspSessionGate.noteCreateFailure("null_handle")
                nativeProcessEnabled = false
                return
            }

            engineHandle = h
            DspSessionGate.noteCreateSuccess()
            DspEngineRegistry.register(processorId, h)
            Log.i(TAG, "id=$processorId engine ok handle=$h sr=$configuredRate ch=$configuredChannels")
        } catch (t: Throwable) {
            Log.e(TAG, "id=$processorId nativeCreate failed", t)
            engineHandle = 0
            nativeProcessEnabled = false
            DspSessionGate.noteCreateFailure(t.javaClass.simpleName)
        }
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        val remaining = inputBuffer.remaining()
        if (remaining <= 0) return

        if (!nativeProcessEnabled ||
            engineHandle == 0L ||
            !DspSessionGate.isNativeAllowed() ||
            remaining > MAX_BYTES
        ) {
            val output = replaceOutputBuffer(remaining)
            output.put(inputBuffer)
            output.flip()
            return
        }

        val output = replaceOutputBuffer(remaining)
        output.put(inputBuffer)
        output.flip()

        val frames = remaining / (configuredChannels * 2)
        if (frames <= 0 || frames > MAX_FRAMES) return

        try {
            val rc = DspEngineJni.nativeProcessPcm16Direct(
                engineHandle,
                output,
                frames,
                configuredChannels,
                configuredRate.toDouble()
            )

            if (rc != 0) {
                consecutiveProcessErrors++
                if (consecutiveProcessErrors == 1 || consecutiveProcessErrors % 4 == 0) {
                    Log.w(TAG, "id=$processorId process rc=$rc errs=$consecutiveProcessErrors")
                }
                if (consecutiveProcessErrors >= DspSessionGate.MAX_PROCESS_ERRORS) {
                    demoteToPassThrough("process_errors=$consecutiveProcessErrors")
                }
            } else {
                consecutiveProcessErrors = 0
            }
        } catch (t: Throwable) {
            Log.e(TAG, "id=$processorId process exception — pass-through buffer intact", t)
            consecutiveProcessErrors++
            if (consecutiveProcessErrors >= DspSessionGate.MAX_PROCESS_ERRORS) {
                demoteToPassThrough("process_exception")
            }
        }
    }

    /**
     * Permanently disables this processor's native path until the sink resets.
     *
     * Important: destroy the native handle here rather than merely disabling
     * processing. Otherwise a failed A/B engine remains registered and can
     * retain native memory/session state for the rest of the player lifetime.
     */
    private fun demoteToPassThrough(reason: String) {
        if (!nativeProcessEnabled && engineHandle == 0L) return

        nativeProcessEnabled = false
        val h = engineHandle
        engineHandle = 0L

        if (h != 0L) {
            DspEngineRegistry.unregister(processorId)
            try {
                DspEngineJni.nativeDestroy(h)
            } catch (t: Throwable) {
                Log.w(TAG, "id=$processorId nativeDestroy after demotion failed", t)
            }
        }

        Log.w(TAG, "id=$processorId demoted to pass-through reason=$reason")
    }

    override fun onFlush() {
        // Continuous engine; no hard reset.
    }

    override fun onReset() {
        destroyEngine()
        createAttempted = false
        consecutiveProcessErrors = 0
    }

    private fun destroyEngine() {
        val h = engineHandle
        if (h != 0L) {
            engineHandle = 0L
            DspEngineRegistry.unregister(processorId)
            try {
                DspEngineJni.nativeDestroy(h)
            } catch (_: Throwable) { }
        }
    }
}
