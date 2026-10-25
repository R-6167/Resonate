package com.Aetherion.Resonate.media

/**
 * Composes every output gain factor before it reaches either ExoPlayer deck.
 *
 * Keeping these factors here prevents master volume, track leveling, preamp,
 * sleep fade, focus ducking and crossfade from overwriting each other's volume.
 */
internal class Media3GainPolicy(initialMasterVolume: Float = 1f) {
    var masterVolume: Float = initialMasterVolume.coerceFiniteUnit()
        private set
    private var trackLevelGain: Float = 1f
    private var preampGain: Float = 1f
    private var sleepFadeGain: Float = 1f
    private var focusDuckGain: Float = 1f
    private var activeDeckGain: Float = 1f
    private var standbyDeckGain: Float = 0f

    fun setMasterVolume(value: Float): Boolean {
        if (!value.isFinite()) return false
        masterVolume = value.coerceIn(0f, 1f)
        return true
    }

    /** Atomically update the non-crossfade gains. Invalid values reject the
     * entire update, so a malformed factor cannot partially alter output. */
    fun setGainFactors(
        trackLevel: Float,
        preamp: Float,
        sleepFade: Float,
        focusDuck: Float,
    ): Boolean {
        // Output-normalized factors stay in [0, 1]. Preamp is a linear gain
        // stage and may boost up to 4x; final deck output is still capped at 1.
        val normalized = listOf(trackLevel, sleepFade, focusDuck)
        if (normalized.any { !it.isFinite() || it !in 0f..1f }) return false
        if (!preamp.isFinite() || preamp !in 0f..4f) return false
        trackLevelGain = trackLevel
        preampGain = preamp
        sleepFadeGain = sleepFade
        focusDuckGain = focusDuck
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

    private fun composedBaseGain(): Float =
        (masterVolume * trackLevelGain * preampGain * sleepFadeGain * focusDuckGain)
            .coerceIn(0f, 1f)

    fun activeVolume(): Float = (composedBaseGain() * activeDeckGain).coerceIn(0f, 1f)
    fun standbyVolume(): Float = (composedBaseGain() * standbyDeckGain).coerceIn(0f, 1f)

    private fun Float.coerceFiniteUnit(): Float =
        if (isFinite()) coerceIn(0f, 1f) else 0f
}
