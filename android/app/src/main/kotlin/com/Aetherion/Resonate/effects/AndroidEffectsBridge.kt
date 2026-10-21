package com.Aetherion.Resonate.effects

import android.media.audiofx.EnvironmentalReverb
import android.media.audiofx.Virtualizer

/**
 * Thin bridge for optional system-level creative effects (Virtualizer / Reverb).
 * Effects are owned per Android audio session because Resonate's A/B players
 * have independent sessions that may be recreated during playback.
 */
class AndroidEffectsBridge {

    private var effectSessionId: Int = 0
    private val virtualizers = mutableMapOf<Int, Virtualizer>()
    private val reverbs = mutableMapOf<Int, EnvironmentalReverb>()

    fun attachToSession(sessionId: Int) {
        if (sessionId > 0) effectSessionId = sessionId
    }

    fun detachFromSession(sessionId: Int) {
        if (sessionId <= 0) return
        releaseVirtualizer(sessionId)
        releaseReverb(sessionId)
        if (effectSessionId == sessionId) effectSessionId = 0
    }

    fun setVirtualizer(strength: Int) {
        val sessionId = effectSessionId
        if (sessionId <= 0) return
        val s = strength.coerceIn(0, 1000)
        if (s == 0) {
            releaseVirtualizer(sessionId)
            return
        }
        try {
            val effect = virtualizers[sessionId] ?: Virtualizer(0, sessionId).also {
                it.enabled = true
                virtualizers[sessionId] = it
            }
            effect.setStrength(s.toShort())
            effect.enabled = true
        } catch (_: Throwable) {
            releaseVirtualizer(sessionId)
        }
    }

    fun setReverb(strength: Int) {
        val sessionId = effectSessionId
        if (sessionId <= 0) return
        val s = strength.coerceIn(-900, 0)
        if (s == 0) {
            releaseReverb(sessionId)
            return
        }
        try {
            val effect = reverbs[sessionId] ?: EnvironmentalReverb(0, sessionId).also {
                it.enabled = true
                reverbs[sessionId] = it
            }
            effect.reverbLevel = s.toShort()
            effect.enabled = true
        } catch (_: Throwable) {
            releaseReverb(sessionId)
        }
    }

    fun release() {
        virtualizers.keys.toList().forEach(::releaseVirtualizer)
        reverbs.keys.toList().forEach(::releaseReverb)
        effectSessionId = 0
    }

    private fun releaseVirtualizer(sessionId: Int) {
        try {
            virtualizers.remove(sessionId)?.release()
        } catch (_: Exception) {
        }
    }

    private fun releaseReverb(sessionId: Int) {
        try {
            reverbs.remove(sessionId)?.release()
        } catch (_: Exception) {
        }
    }
}
