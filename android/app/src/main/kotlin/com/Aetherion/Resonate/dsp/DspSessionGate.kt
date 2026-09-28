package com.aetherion.resonate.dsp

import android.util.Log
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/**
 * Process-wide fail-open for live DSP.
 *
 * Policy:
 * - Native DSP is allowed until create/process failures exceed a small budget.
 * - Once tripped, all processors stay pass-through for this process lifetime
 *   (or until [resetForTests]). Playback must never die because of DSP.
 * - Dual engines (A/B) share this gate so one bad create does not keep
 *   hammering dsp_create on the other player.
 */
object DspSessionGate {
    private const val TAG = "DspSessionGate"

    /** Max nativeCreate failures before session-wide disable. */
    private const val MAX_CREATE_FAILURES = 2

    /** Max consecutive process errors on any single processor before local disable. */
    const val MAX_PROCESS_ERRORS = 8

    private val disabled = AtomicBoolean(false)
    private val createFailures = AtomicInteger(0)

    @JvmStatic
    fun isNativeAllowed(): Boolean = !disabled.get()

    @JvmStatic
    fun noteCreateFailure(reason: String) {
        val n = createFailures.incrementAndGet()
        Log.e(TAG, "nativeCreate failure #$n: $reason")
        if (n >= MAX_CREATE_FAILURES) {
            trip("create_failures=$n ($reason)")
        }
    }

    @JvmStatic
    fun noteCreateSuccess() {
        // Soft recovery of the counter only — do not un-trip a session disable.
        createFailures.set(0)
    }

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
}
