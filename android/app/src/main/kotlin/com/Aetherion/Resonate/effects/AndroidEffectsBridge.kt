package com.Aetherion.Resonate.effects

import android.media.audiofx.EnvironmentalReverb
import android.media.audiofx.Virtualizer

/**
 * Thin bridge for optional system-level creative effects (Virtualizer / Reverb).
 * Mature Resonate DSP is the authoritative processing engine; these are secondary.
 */
class AndroidEffectsBridge {

    private var effectSessionId: Int = 0
    private var virtualizer: Virtualizer? = null
    private var reverb: EnvironmentalReverb? = null

    fun attachToSession(sessionId: Int) {
        if (sessionId <= 0) return
        effectSessionId = sessionId
    }

    fun setVirtualizer(strength: Int) {
        val s = strength.coerceIn(0, 1000)
        if (s > 0) ensureVirtualizer()?.setStrength(s.toShort())
    }

    fun setReverb(strength: Int) {
        val s = strength.coerceIn(-900, 1000)
        if (s != 0) ensureReverb()?.reverbLevel = s.toShort()
    }

    fun release() {
        try {
            virtualizer?.release()
        } catch (_: Exception) {
        }
        try {
            reverb?.release()
        } catch (_: Exception) {
        }
        virtualizer = null
        reverb = null
        effectSessionId = 0
    }

    private fun ensureVirtualizer(): Virtualizer? {
        if (effectSessionId <= 0) return null
        if (virtualizer != null) return virtualizer
        return try {
            Virtualizer(0, effectSessionId).also {
                it.enabled = true
                virtualizer = it
            }
        } catch (_: Throwable) {
            virtualizer = null
            null
        }
    }

    private fun ensureReverb(): EnvironmentalReverb? {
        if (effectSessionId <= 0) return null
        if (reverb != null) return reverb
        return try {
            EnvironmentalReverb(0, effectSessionId).also {
                it.enabled = true
                reverb = it
            }
        } catch (_: Throwable) {
            reverb = null
            null
        }
    }
}
