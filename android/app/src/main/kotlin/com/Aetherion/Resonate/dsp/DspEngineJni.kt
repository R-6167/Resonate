package com.Aetherion.Resonate.dsp

import java.nio.ByteBuffer

/**
 * JNI front for live [dsp_process] on direct buffers.
 *
 * Loads `libdsp_jni.so` which dlopen's `libdsp_engine.so` (packaged by the
 * Flutter dsp_engine plugin) and resolves the C ABI at runtime.
 *
 * Buffer policy matches docs/DSP_JNI_BUFFERS.md (64-byte align, ≤4096 frames).
 */
object DspEngineJni {
    @Volatile
    private var loaded = false

    @Volatile
    var loadError: String? = null
        private set

    fun tryLoad(): Boolean {
        if (loaded) return true
        return try {
            System.loadLibrary("dsp_jni")
            loaded = nativeIsLibReady()
            if (!loaded) loadError = "libdsp_engine.so symbols missing"
            loaded
        } catch (t: Throwable) {
            loadError = t.message
            loaded = false
            false
        }
    }

    fun isReady(): Boolean = loaded && nativeIsLibReady()

    /**
     * @return opaque handle, or 0 on failure
     */
    fun create(sampleRate: Int, channels: Int, bufferFrames: Int = DspEngineAudioProcessor.MAX_FRAMES_PER_BLOCK): Long {
        if (!tryLoad()) return 0L
        return nativeCreate(sampleRate, channels, bufferFrames)
    }

    fun destroy(handle: Long) {
        if (handle == 0L || !loaded) return
        nativeDestroy(handle)
    }

    /**
     * Process interleaved PCM16 LE in direct buffers.
     * @return frames processed, or negative error code
     */
    fun processPcm16Direct(
        handle: Long,
        input: ByteBuffer,
        inputOffset: Int,
        output: ByteBuffer,
        outputOffset: Int,
        frames: Int,
    ): Int {
        if (handle == 0L || !loaded) return -10
        if (!input.isDirect || !output.isDirect) return -11
        return nativeProcessPcm16Direct(
            handle,
            input,
            inputOffset,
            output,
            outputOffset,
            frames,
        )
    }

    private external fun nativeIsLibReady(): Boolean
    private external fun nativeCreate(sampleRate: Int, channels: Int, bufferFrames: Int): Long
    private external fun nativeDestroy(handle: Long)
    private external fun nativeProcessPcm16Direct(
        handle: Long,
        inBuf: ByteBuffer,
        inOffset: Int,
        outBuf: ByteBuffer,
        outOffset: Int,
        frames: Int,
    ): Int
}
