package com.Aetherion.Resonate.media

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class Media3CrossfadeClockTest {
    @Test
    fun pauseFreezesProgressAndResumeContinuesFromSamePoint() {
        val clock = Media3CrossfadeClock()
        clock.start(durationMs = 10_000L, nowMs = 1_000L)

        assertEquals(0.1f, clock.progress(nowMs = 2_000L), 0.0001f)
        assertTrue(clock.pause(nowMs = 2_000L))
        assertEquals(0.1f, clock.progress(nowMs = 9_000L), 0.0001f)
        assertFalse(clock.pause(nowMs = 9_000L))

        assertTrue(clock.resume(nowMs = 9_000L))
        assertEquals(0.2f, clock.progress(nowMs = 10_000L), 0.0001f)
        assertFalse(clock.resume(nowMs = 10_000L))
    }

    @Test
    fun progressClampsAtCompletionAndResetClearsTheClock() {
        val clock = Media3CrossfadeClock()
        clock.start(durationMs = 500L, nowMs = 100L)

        assertEquals(1f, clock.progress(nowMs = 700L), 0.0001f)
        clock.reset()

        assertEquals(0f, clock.progress(nowMs = 900L), 0.0001f)
        assertFalse(clock.pause(nowMs = 900L))
        assertFalse(clock.resume(nowMs = 900L))
    }
}
