package com.aetherion.resonate.dsp

import android.util.Log
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/**
 * Process-wide fail-open guard for native DSP.
 *
 * Normal engine failures are deliberately LOCAL to each processor. A/B players
 * must not disable one another because one engine could not be created.
 *
 * This gate is reserved for an explicit process-wide/native-ABI failure that
 * makes further native entry unsafe. Playback always remains pass-through.
 */
object DspSessionGate {
    private const val TAG = "DspSessionGate"

    private val disabled = AtomicBoolean(false)
    private val createFailures = AtomicInteger(0)

    @JvmStatic
    fun isNativeAllowed(): Boolean = !disabled.get()

    /**
     * Record a create failure for diagnostics only.
     *
     * Do NOT trip the process-wide gate here. Each DspEngineAudioProcessor has
     * its own createAttempted latch and therefore cannot spin on nativeCreate.
     */
    @JvmStatic
    fun noteCreateFailure(reason: String) {
        val n = createFailures.incrementAndGet()
        Log.e(TAG, "nativeCreate failure #$n (processor-local) reason=$reason")
    }

    @JvmStatic
    fun noteCreateSuccess() {
        createFailures.set(0)
    }

    /**
     * Reserved for a confirmed process-wide/native-ABI failure.
     */
    @JvmStatic
    fun trip(reason: String) {
        if (disabled.compareAndSet(false, true)) {
            Log.e(TAG, "SESSION native DSP DISABLED — pass-through only. reason=$reason")
        }
    }

    /** Test / advanced UI only. */
    @JvmStatic
    fun resetForTests() {
        disabled.set(false)
        createFailures.set(0)
        Log.i(TAG, "session gate reset")
    }

    @JvmStatic
    fun isTripped(): Boolean = disabled.get()

    @JvmStatic
    fun createFailureCount(): Int = createFailures.get()
}
