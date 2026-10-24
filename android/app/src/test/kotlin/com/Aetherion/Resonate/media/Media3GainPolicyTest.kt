package com.Aetherion.Resonate.media

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.cos
import kotlin.math.sin

class Media3GainPolicyTest {
    @Test
    fun masterVolumeScalesBothDecksDuringFade() {
        val policy = Media3GainPolicy(initialMasterVolume = 0.4f)
        policy.setCrossfadeGains(active = 0.6f, standby = 0.8f)

        assertEquals(0.24f, policy.activeVolume(), 0.0001f)
        assertEquals(0.32f, policy.standbyVolume(), 0.0001f)
    }

    @Test
    fun changingMasterVolumeDuringFadePreservesEnvelope() {
        val policy = Media3GainPolicy(initialMasterVolume = 0.7f)
        policy.setCrossfadeGains(active = cos(Math.PI.toFloat() / 4f), standby = sin(Math.PI.toFloat() / 4f))

        assertTrue(policy.setMasterVolume(0.25f))
        assertEquals(0.25f * cos(Math.PI.toFloat() / 4f), policy.activeVolume(), 0.0001f)
        assertEquals(0.25f * sin(Math.PI.toFloat() / 4f), policy.standbyVolume(), 0.0001f)
    }

    @Test
    fun resetAfterCompletionOrCancellationRestoresComposedBaseGain() {
        val policy = Media3GainPolicy(initialMasterVolume = 0.35f)
        assertTrue(policy.setGainFactors(trackLevel = 0.8f, preamp = 0.5f, sleepFade = 0.6f, focusDuck = 0.5f))
        policy.setCrossfadeGains(active = 0f, standby = 1f)

        policy.resetDecks()

        assertEquals(0.35f * 0.8f * 0.5f * 0.6f * 0.5f, policy.activeVolume(), 0.0001f)
        assertEquals(0f, policy.standbyVolume(), 0f)
    }

    @Test
    fun gainFactorsComposeWithCrossfadeOnBothDecks() {
        val policy = Media3GainPolicy(initialMasterVolume = 0.8f)
        assertTrue(policy.setGainFactors(trackLevel = 0.5f, preamp = 0.8f, sleepFade = 0.75f, focusDuck = 0.5f))
        policy.setCrossfadeGains(active = 0.6f, standby = 0.8f)

        val base = 0.8f * 0.5f * 0.8f * 0.75f * 0.5f
        assertEquals(base * 0.6f, policy.activeVolume(), 0.0001f)
        assertEquals(base * 0.8f, policy.standbyVolume(), 0.0001f)
    }

    @Test
    fun invalidGainFactorUpdateIsRejectedAtomically() {
        val policy = Media3GainPolicy(initialMasterVolume = 0.5f)
        assertTrue(policy.setGainFactors(trackLevel = 0.7f, preamp = 0.8f, sleepFade = 0.9f, focusDuck = 1f))
        val before = policy.activeVolume()

        assertFalse(policy.setGainFactors(trackLevel = 0.2f, preamp = Float.NaN, sleepFade = 0.1f, focusDuck = 0.3f))
        assertEquals(before, policy.activeVolume(), 0f)
        assertFalse(policy.setGainFactors(trackLevel = 1.1f, preamp = 1f, sleepFade = 1f, focusDuck = 1f))
    }

    @Test
    fun masterVolumeIsClampedAndNonFiniteUpdatesAreRejected() {
        val policy = Media3GainPolicy(initialMasterVolume = 1.5f)
        assertEquals(1f, policy.masterVolume, 0f)

        assertFalse(policy.setMasterVolume(Float.NaN))
        assertFalse(policy.setMasterVolume(Float.POSITIVE_INFINITY))
        assertTrue(policy.setMasterVolume(-0.5f))
        assertEquals(0f, policy.masterVolume, 0f)
    }
}
