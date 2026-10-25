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
    fun resetAfterCompletionOrCancellationRestoresMasterNotFullVolume() {
        val policy = Media3GainPolicy(initialMasterVolume = 0.35f)
        policy.setCrossfadeGains(active = 0f, standby = 1f)

        policy.resetDecks()

        assertEquals(0.35f, policy.activeVolume(), 0.0001f)
        assertEquals(0f, policy.standbyVolume(), 0.0001f)
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
