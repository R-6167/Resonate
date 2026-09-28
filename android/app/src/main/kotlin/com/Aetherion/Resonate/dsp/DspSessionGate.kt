package com.aetherion.resonate.dsp

import android.util.Log
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/**
 * Process-wide fail-open for live DSP.
 */
object DspSessionGate {
    private const val TAG = "DspSessionGate"
    private const val MAX_CREATE_FAILURES = 2
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
        createFailures.set(0)
    }

    @JvmStatic
    fun trip(reason: String) {
        if (disabled.compareAndSet(false, true)) {
            Log.e(TAG, "SESSION native DSP DISABLED — pass-through only. reason=$reason")
        }
    }

    @JvmStatic
    fun resetForTests() {
        disabled.set(false)
        createFailures.set(0)
        Log.i(TAG, "session gate reset")
    }

    @JvmStatic
    fun isTripped(): Boolean = disabled.get()
}
