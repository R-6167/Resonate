package com.aetherion.resonate.dsp

object DspEngineJni {
    init {
        try {
            System.loadLibrary("dsp_engine")
        } catch (_: Throwable) {
            // Still load jni which links the engine.
        }
        try {
            System.loadLibrary("dsp_jni")
        } catch (_: Throwable) {
            // Optional until NDK is present; processors pass-through.
        }
    }

    external fun nativeCreate(sampleRate: Double, channels: Int): Long

    external fun nativeDestroy(handle: Long)

    external fun nativeProcessPcm16Direct(
        handle: Long,
        buffer: java.nio.ByteBuffer,
        frames: Int,
        channels: Int,
        sampleRate: Double
    ): Int

    external fun nativeSetEnabled(handle: Long, enabled: Boolean)

    /** Linear gain (1.0 = unity). Applied via dsp_set_volume (DVC). */
    external fun nativeSetVolume(handle: Long, linearGain: Double)

    /**
     * Bulk EQ. [centersHz] may be empty to keep existing centers.
     * [gainsDb] length is the band count (clamped to 31 in native).
     */
    external fun nativeSetEqBands(
        handle: Long,
        centersHz: DoubleArray?,
        gainsDb: DoubleArray,
        enabled: Boolean
    )

    /** Phone speaker path: HPF + virtual bass + tighter limiter. */
    external fun nativeSetSpeakerMode(handle: Long, enabled: Boolean)

    /** Virtual-bass amount 0..1 (active only in speaker mode). */
    external fun nativeSetVirtualBass(handle: Long, amount: Double)
}
