package com.Aetherion.Resonate.media

/**
 * Pure queue-edit policy shared by the Media3 bridge and JVM tests.
 *
 * Identity includes both the app media ID and source URI. Duplicate tracks keep
 * their occurrence when the same identity remains at the old index; otherwise
 * the first matching occurrence is preferred. If the current item was removed,
 * select the nearest valid index but start that fallback item at position zero.
 */
internal data class Media3QueueEntryIdentity(
    val mediaId: String,
    val uri: String,
)

internal data class Media3QueueReconciliation(
    val targetIndex: Int,
    val keepPosition: Boolean,
) {
    fun targetPosition(oldPositionMs: Long): Long =
        if (keepPosition) oldPositionMs.coerceAtLeast(0L) else 0L
}

internal object Media3QueueReconciliationPolicy {
    fun resolve(
        newQueue: List<Media3QueueEntryIdentity>,
        oldIndex: Int,
        oldItem: Media3QueueEntryIdentity,
    ): Media3QueueReconciliation {
        require(newQueue.isNotEmpty()) { "New queue must not be empty." }
        require(oldIndex >= 0) { "Old queue index must be non-negative." }

        val sameOccurrence = newQueue.getOrNull(oldIndex) == oldItem
        val matchingIndex = if (sameOccurrence) oldIndex else newQueue.indexOf(oldItem)
        val targetIndex = if (matchingIndex >= 0) {
            matchingIndex
        } else {
            oldIndex.coerceIn(0, newQueue.lastIndex)
        }
        return Media3QueueReconciliation(
            targetIndex = targetIndex,
            keepPosition = newQueue[targetIndex] == oldItem,
        )
    }
}
