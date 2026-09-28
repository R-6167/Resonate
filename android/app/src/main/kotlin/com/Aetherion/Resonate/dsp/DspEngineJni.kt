package com.aetherion.resonate.dsp

object DspEngineJni {
    init {
        try {
            System.loadLibrary("dsp_jni")
        } catch (t: Throwable) {
            // Library optional until NDK build is wired; processor will pass-through.
        }
    }

    /** Create engine; returns opaque handle (0 on failure). */
    external fun nativeCreate(sampleRate: Double, channels: Int): Long

    external fun nativeDestroy(handle: Long)

    /**
     * Process interleaved PCM16 in a direct ByteBuffer in-place (or via scratch).
     * @return 0 on success, negative on error.
     */
    external fun nativeProcessPcm16Direct(
        handle: Long,
        buffer: java.nio.ByteBuffer,
        frames: Int,
        channels: Int,
        sampleRate: Double
    ): Int

    external fun nativeSetEnabled(handle: Long, enabled: Boolean)
}
