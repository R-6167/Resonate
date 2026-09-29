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

    @JvmStatic
    fun register(processorId: Int, handle: Long) {
        if (handle == 0L) return
        handles[processorId] = handle
        applyStickyToHandle(handle)
        Log.i(TAG, "register id=$processorId handle=$handle active=${handles.size}")
    }

    @JvmStatic
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

    @JvmStatic
    fun statusMap(): Map<String, Any> = mapOf(
        "activeEngines" to activeCount(),
        "gateTripped" to DspSessionGate.isTripped(),
        "nativeAllowed" to DspSessionGate.isNativeAllowed(),
        "linearGain" to stickyLinearGain,
        "eqEnabled" to stickyEqEnabled,
        "eqBands" to (stickyGainsDb?.size ?: 0),
        "speakerMode" to stickySpeakerMode,
        "virtualBass" to stickyVirtualBass,
    )

    /** Preamp / DVC — linear gain (1.0 = unity). Call off the audio thread. */
    @JvmStatic
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

    private fun applyStickyToHandle(handle: Long) {
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
        } catch (t: Throwable) {
            Log.w(TAG, "applySticky failed", t)
        }
    }
}
