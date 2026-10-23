package com.Aetherion.Resonate.media

/**
 * Composes the user's master volume with the current crossfade envelope.
 *
 * Additional production factors (track leveling, preamp, sleep fade, and focus
 * ducking) must be added here rather than writing ExoPlayer.volume separately.
 */
internal class Media3GainPolicy(initialMasterVolume: Float = 1f) {
    var masterVolume: Float = initialMasterVolume.coerceFiniteUnit()
        private set
    private var activeDeckGain: Float = 1f
    private var standbyDeckGain: Float = 0f

    fun setMasterVolume(value: Float): Boolean {
        if (!value.isFinite()) return false
        masterVolume = value.coerceIn(0f, 1f)
        return true
    }

    fun setCrossfadeGains(active: Float, standby: Float) {
        activeDeckGain = active.coerceFiniteUnit()
        standbyDeckGain = standby.coerceFiniteUnit()
    }

    fun resetDecks() {
        activeDeckGain = 1f
        standbyDeckGain = 0f
    }

    fun activeVolume(): Float = (masterVolume * activeDeckGain).coerceIn(0f, 1f)
    fun standbyVolume(): Float = (masterVolume * standbyDeckGain).coerceIn(0f, 1f)

    private fun Float.coerceFiniteUnit(): Float =
        if (isFinite()) coerceIn(0f, 1f) else 0f
}
