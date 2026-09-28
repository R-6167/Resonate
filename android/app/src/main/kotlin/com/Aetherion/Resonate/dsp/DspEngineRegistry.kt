package com.aetherion.resonate.dsp

import android.util.Log
import java.util.concurrent.ConcurrentHashMap

/**
 * Tracks live native engine handles for dual-player (A/B) sinks.
 *
 * Design (flawless dual playback):
 * - Each just_audio / ExoPlayer sink owns **one** [DspEngineAudioProcessor]
 *   and **one** native handle. Never share a handle across two audio threads.
 * - Crossfade A→B = two independent process graphs at the same sample rate.
 * - UI (preamp / EQ) will broadcast to all registered handles (future).
 * - Fail-open: [DspSessionGate] can ban new creates; existing handles may
 *   still process until reset, or processors demote to pass-through.
 */
object DspEngineRegistry {
    private const val TAG = "DspEngineRegistry"

    private val handles = ConcurrentHashMap<Int, Long>()

    @JvmStatic
    fun register(processorId: Int, handle: Long) {
        if (handle == 0L) return
        handles[processorId] = handle
        Log.i(TAG, "register id=$processorId handle=$handle active=${handles.size}")
    }

    @JvmStatic
    fun unregister(processorId: Int) {
        val h = handles.remove(processorId)
        Log.i(TAG, "unregister id=$processorId handle=$h active=${handles.size}")
    }

    @JvmStatic
    fun activeCount(): Int = handles.size

    /** Snapshot of live handles (for future bulk volume/EQ apply). */
    @JvmStatic
    fun snapshotHandles(): List<Long> = handles.values.filter { it != 0L }.toList()

    /**
     * Apply linear gain to every live engine (DVC). Safe no-op if JNI missing.
     * Call from UI / Dart bridge thread — not from the audio thread.
     */
    @JvmStatic
    fun applyVolumeAll(linearGain: Double) {
        val list = snapshotHandles()
        if (list.isEmpty()) return
        // nativeSetEnabled is EQ toggle today; volume needs a dedicated JNI later.
        // Placeholder log until dsp_set_volume is exposed on DspEngineJni.
        Log.i(TAG, "applyVolumeAll gain=$linearGain targets=${list.size}")
    }
}
