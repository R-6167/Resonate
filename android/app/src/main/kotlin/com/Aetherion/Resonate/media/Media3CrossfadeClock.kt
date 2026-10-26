package com.Aetherion.Resonate.media

/**
 * Tracks elapsed crossfade time independently of Android player state.
 *
 * Time spent paused is excluded, so the equal-power gain ramp resumes at the
 * same point instead of finishing while playback is silent.
 */
internal class Media3CrossfadeClock {
    private var durationMs = 0L
    private var elapsedBeforeSegmentMs = 0L
    private var segmentStartedAtMs = 0L
    private var paused = false

    fun start(durationMs: Long, nowMs: Long) {
        require(durationMs > 0L) { "Crossfade duration must be positive." }
        this.durationMs = durationMs
        elapsedBeforeSegmentMs = 0L
        segmentStartedAtMs = nowMs
        paused = false
    }

    fun pause(nowMs: Long): Boolean {
        if (durationMs <= 0L || paused) return false
        elapsedBeforeSegmentMs = elapsedAt(nowMs)
        paused = true
        return true
    }

    fun resume(nowMs: Long): Boolean {
        if (durationMs <= 0L || !paused) return false
        segmentStartedAtMs = nowMs
        paused = false
        return true
    }

    fun progress(nowMs: Long): Float {
        if (durationMs <= 0L) return 0f
        return (elapsedAt(nowMs).toFloat() / durationMs.toFloat()).coerceIn(0f, 1f)
    }

    fun reset() {
        durationMs = 0L
        elapsedBeforeSegmentMs = 0L
        segmentStartedAtMs = 0L
        paused = false
    }

    private fun elapsedAt(nowMs: Long): Long {
        val currentSegment = if (paused) 0L else (nowMs - segmentStartedAtMs).coerceAtLeast(0L)
        return (elapsedBeforeSegmentMs + currentSegment).coerceIn(0L, durationMs)
    }
}
