package com.Aetherion.Resonate.media

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class Media3QueueReconciliationPolicyTest {
    private fun item(id: String, uri: String = "file:///music/$id.mp3") =
        Media3QueueEntryIdentity(mediaId = id, uri = uri)

    @Test
    fun keepsPositionWhenCurrentOccurrenceRemainsAtItsIndex() {
        val queue = listOf(item("a"), item("b"), item("c"))

        val result = Media3QueueReconciliationPolicy.resolve(
            newQueue = queue,
            oldIndex = 1,
            oldItem = item("b"),
        )

        assertEquals(1, result.targetIndex)
        assertTrue(result.keepPosition)
        assertEquals(42_000L, result.targetPosition(42_000L))
    }

    @Test
    fun followsCurrentItemWhenQueueEditMovesIt() {
        val queue = listOf(item("b"), item("a"), item("c"))

        val result = Media3QueueReconciliationPolicy.resolve(
            newQueue = queue,
            oldIndex = 1,
            oldItem = item("b"),
        )

        assertEquals(0, result.targetIndex)
        assertTrue(result.keepPosition)
        assertEquals(42_000L, result.targetPosition(42_000L))
    }

    @Test
    fun duplicateIdentityPrefersTheSameOccurrenceWhenPossible() {
        val repeated = item("same")
        val queue = listOf(repeated, item("middle"), repeated)

        val result = Media3QueueReconciliationPolicy.resolve(
            newQueue = queue,
            oldIndex = 2,
            oldItem = repeated,
        )

        assertEquals(2, result.targetIndex)
        assertTrue(result.keepPosition)
    }

    @Test
    fun removedCurrentTrackFallsBackToNearestIndexAtZeroPosition() {
        val queue = listOf(item("a"), item("c"))

        val result = Media3QueueReconciliationPolicy.resolve(
            newQueue = queue,
            oldIndex = 1,
            oldItem = item("b"),
        )

        assertEquals(1, result.targetIndex)
        assertFalse(result.keepPosition)
        assertEquals(0L, result.targetPosition(42_000L))
    }

    @Test
    fun sameMediaIdWithDifferentUriIsNotTreatedAsTheSameTrack() {
        val queue = listOf(item("same", "file:///music/other.mp3"))

        val result = Media3QueueReconciliationPolicy.resolve(
            newQueue = queue,
            oldIndex = 0,
            oldItem = item("same", "file:///music/original.mp3"),
        )

        assertFalse(result.keepPosition)
        assertEquals(0L, result.targetPosition(9_000L))
    }

    @Test
    fun negativeOldPositionIsNormalizedToZero() {
        val result = Media3QueueReconciliationPolicy.resolve(
            newQueue = listOf(item("a")),
            oldIndex = 0,
            oldItem = item("a"),
        )

        assertEquals(0L, result.targetPosition(-1L))
    }
}
