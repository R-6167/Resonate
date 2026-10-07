package com.aetherion.resonate.dsp

import android.util.Log
import java.util.concurrent.ConcurrentHashMap

/**
 * Live native engine handles for dual-player (A/B) sinks.
 *
 * Sticky volume/EQ/speaker: when player B is created mid-session, [register] reapplies
 * the last UI settings so both engines stay in sync during crossfade.
 */
object DspEngineRegistry {
    private const val TAG = "DspEngineRegistry"

    private val handles = ConcurrentHashMap<Int, Long>()

    @Volatile
    private var stickyLinearGain: Double = 1.0

    @Volatile
    private var stickyEqEnabled: Boolean = true

    @Volatile
    private var stickyCentersHz: DoubleArray? = null

    @Volatile
    private var stickyGainsDb: DoubleArray? = null

    @Volatile
    private var stickySpeakerMode: Boolean = false

    @Volatile
    private var stickyVirtualBass: Double = 0.55
    @Volatile
    private var stickyPreamp: Double = 1.0
    @Volatile
    private var stickyLimiterHigh: Float = -0.5f
    @Volatile
    private var stickyLimiterLow: Float = -0.2f
    @Volatile
    private var stickyCrossoverHz: Float = 120f

    @JvmStatic
    @Synchronized
    fun register(processorId: Int, handle: Long): Boolean {
        if (handle == 0L) return false

        // Configure the new engine before publishing it to the live registry.
        // If JNI configuration fails, the caller still owns the handle and can
        // destroy it safely; the registry never exposes a partially configured
        // engine to A/B-wide setting updates.
        if (!applyStickyToHandle(handle)) {
            Log.w(TAG, "reject id=$processorId handle=$handle: sticky configuration failed")
            return false
        }

        handles[processorId] = handle
        Log.i(TAG, "register id=$processorId handle=$handle active=${handles.size}")
        return true
    }

    @JvmStatic
    @Synchronized
    fun unregister(processorId: Int) {
        val h = handles.remove(processorId)
        Log.i(TAG, "unregister id=$processorId handle=$h active=${handles.size}")
    }

    @JvmStatic
    fun activeCount(): Int = handles.size

    @JvmStatic
    fun snapshotHandles(): List<Long> = handles.values.filter { it != 0L }.toList()

    /** Phone-speaker delivery: HPF + virtual bass + tighter limiter. */
    @JvmStatic
    @Synchronized
    fun applySpeakerModeAll(enabled: Boolean) {
        stickySpeakerMode = enabled
        val list = snapshotHandles()
        for (h in list) {
            try {
                DspEngineJni.nativeSetSpeakerMode(h, enabled)
                DspEngineJni.nativeSetVirtualBass(h, stickyVirtualBass)
            } catch (t: Throwable) {
                Log.w(TAG, "setSpeakerMode failed handle=$h", t)
            }
        }
        Log.i(TAG, "applySpeakerModeAll enabled=$enabled targets=${list.size}")
    }

    @JvmStatic
    @Synchronized
    fun applyVirtualBassAll(amount: Double) {
        stickyVirtualBass = amount.coerceIn(0.0, 1.0)
        if (!stickySpeakerMode) return
        val list = snapshotHandles()
        for (h in list) {
            try {
                DspEngineJni.nativeSetVirtualBass(h, stickyVirtualBass)
            } catch (t: Throwable) {
                Log.w(TAG, "setVirtualBass failed handle=$h", t)
            }
        }
    }

    /** Aggregate Phase-2 latency across all live engines. */
    @JvmStatic
    fun latencySnapshot(): Map<String, Any> {
        var calls = 0.0
        var avgUs = 0.0
        var maxUs = 0.0
        var overruns = 0.0
        var lastFrames = 0.0
        var sampleRate = 0.0
        var n = 0
        for (h in snapshotHandles()) {
            try {
                val s = DspEngineJni.nativeGetStats(h) ?: continue
                if (s.size < 6) continue
                calls += s[0]
                avgUs += s[1]
                if (s[2] > maxUs) maxUs = s[2]
                overruns += s[3]
                lastFrames = s[4]
                sampleRate = s[5]
                n++
            } catch (_: Throwable) {
            }
        }
        if (n > 0) avgUs /= n.toDouble()
        return mapOf(
            "processCalls" to calls,
            "avgUs" to avgUs,
            "maxUs" to maxUs,
            "overruns" to overruns,
            "lastFrames" to lastFrames,
            "sampleRate" to sampleRate,
            "engines" to n,
        )
    }

    @JvmStatic
    fun statusMap(): Map<String, Any> {
        val base = mutableMapOf<String, Any>(
            "activeEngines" to activeCount(),
            "gateTripped" to DspSessionGate.isTripped(),
            "nativeAllowed" to DspSessionGate.isNativeAllowed(),
            "linearGain" to stickyLinearGain,
            "eqEnabled" to stickyEqEnabled,
            "eqBands" to (stickyGainsDb?.size ?: 0),
            "speakerMode" to stickySpeakerMode,
            "virtualBass" to stickyVirtualBass,
        )
        base.putAll(latencySnapshot())
        return base
    }


    /** True preamp (v0.4) — separate from DVC/volume. */
    @JvmStatic
    @Synchronized
    fun applyPreampAll(linearGain: Double) {
        val g = linearGain.coerceIn(0.0, 4.0)
        stickyPreamp = g
        val list = snapshotHandles()
        for (h in list) {
            try {
                DspEngineJni.nativeSetPreamp(h, g)
            } catch (t: Throwable) {
                Log.w(TAG, "setPreamp failed handle=$h", t)
            }
        }
        Log.i(TAG, "applyPreampAll gain=$g targets=${list.size}")
    }

    @JvmStatic
    @Synchronized
    fun applyLimiterCeilingAll(highDb: Float, lowDb: Float) {
        stickyLimiterHigh = highDb.coerceIn(-6f, -0.1f)
        stickyLimiterLow = lowDb.coerceIn(-6f, -0.1f)
        val list = snapshotHandles()
        for (h in list) {
            try {
                DspEngineJni.nativeSetLimiterCeiling(h, stickyLimiterHigh, stickyLimiterLow)
            } catch (t: Throwable) {
                Log.w(TAG, "setLimiter failed handle=$h", t)
            }
        }
    }

    @JvmStatic
    @Synchronized
    fun applyCrossoverHzAll(hz: Float) {
        stickyCrossoverHz = hz.coerceIn(80f, 200f)
        val list = snapshotHandles()
        for (h in list) {
            try {
                DspEngineJni.nativeSetCrossoverHz(h, stickyCrossoverHz)
            } catch (t: Throwable) {
                Log.w(TAG, "setCrossover failed handle=$h", t)
            }
        }
    }

    /** Preamp / DVC — linear gain (1.0 = unity). Call off the audio thread. */
    @JvmStatic
    @Synchronized
    fun applyVolumeAll(linearGain: Double) {
        val g = linearGain.coerceIn(0.0, 4.0)
        stickyLinearGain = g
        val list = snapshotHandles()
        for (h in list) {
            try {
                DspEngineJni.nativeSetVolume(h, g)
            } catch (t: Throwable) {
                Log.w(TAG, "setVolume failed handle=$h", t)
            }
        }
        Log.i(TAG, "applyVolumeAll gain=$g targets=${list.size}")
    }

    /** Studio curve → all live engines. */
    @JvmStatic
    @Synchronized
    fun applyEqBandsAll(centersHz: DoubleArray?, gainsDb: DoubleArray, enabled: Boolean) {
        stickyEqEnabled = enabled
        stickyCentersHz = centersHz?.copyOf()
        stickyGainsDb = gainsDb.copyOf()
        val list = snapshotHandles()
        for (h in list) {
            try {
                DspEngineJni.nativeSetEqBands(h, centersHz, gainsDb, enabled)
            } catch (t: Throwable) {
                Log.w(TAG, "setEqBands failed handle=$h", t)
            }
        }
        Log.i(TAG, "applyEqBandsAll bands=${gainsDb.size} enabled=$enabled targets=${list.size}")
    }

    private fun applyStickyToHandle(handle: Long): Boolean {
        try {
            DspEngineJni.nativeSetVolume(handle, stickyLinearGain)
            val gains = stickyGainsDb
            if (gains != null && gains.isNotEmpty()) {
                DspEngineJni.nativeSetEqBands(handle, stickyCentersHz, gains, stickyEqEnabled)
            } else {
                DspEngineJni.nativeSetEnabled(handle, stickyEqEnabled)
            }
            DspEngineJni.nativeSetSpeakerMode(handle, stickySpeakerMode)
            DspEngineJni.nativeSetVirtualBass(handle, stickyVirtualBass)
            DspEngineJni.nativeSetPreamp(handle, stickyPreamp)
            DspEngineJni.nativeSetLimiterCeiling(handle, stickyLimiterHigh, stickyLimiterLow)
            DspEngineJni.nativeSetCrossoverHz(handle, stickyCrossoverHz)
        } catch (t: Throwable) {
            Log.w(TAG, "applySticky failed handle=$handle", t)
            return false
        }
        return true
    }
}
