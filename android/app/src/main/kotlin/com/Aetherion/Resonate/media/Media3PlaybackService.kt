package com.Aetherion.Resonate.media

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.DefaultAudioSink
import androidx.media3.exoplayer.ExoPlayer
import com.aetherion.resonate.dsp.DspEngineSinkHook
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import kotlin.math.cos
import kotlin.math.sin

/**
 * Isolated Media3 playback owner for the migration branch.
 *
 * A second deck is used only by the Engine Lab crossfade experiment. Production
 * MusicProvider and just_audio remain unchanged.
 */
class Media3PlaybackService : MediaSessionService() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var mediaSession: MediaSession? = null
    private lateinit var activePlayer: ExoPlayer
    private lateinit var standbyPlayer: ExoPlayer
    private var fadeRunnable: Runnable? = null
    private var fadeGeneration = 0
    private var fadeStartedAt = 0L
    private var fadeDurationMs = 0L
    private var crossfadeStatus = "idle"

    // All Media3 output gain changes pass through one policy. Future leveling,
    // preamp, sleep fade and focus-duck factors belong in this composition point.
    private val gainPolicy = Media3GainPolicy()

    private fun applyDeckVolumes() {
        if (::activePlayer.isInitialized) activePlayer.volume = gainPolicy.activeVolume()
        if (::standbyPlayer.isInitialized) standbyPlayer.volume = gainPolicy.standbyVolume()
    }

    fun setMasterVolume(value: Float): Boolean {
        if (!gainPolicy.setMasterVolume(value)) return false
        applyDeckVolumes()
        return true
    }

    /** Apply track leveling, DSP preamp, sleep fade and focus ducking together. */
    fun setGainFactors(
        trackLevel: Float,
        preamp: Float,
        sleepFade: Float,
        focusDuck: Float,
    ): Boolean {
        if (!gainPolicy.setGainFactors(trackLevel, preamp, sleepFade, focusDuck)) return false
        applyDeckVolumes()
        return true
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        activePlayer = newPlayer(handleAudioFocus = true)
        standbyPlayer = newPlayer(handleAudioFocus = false).apply {
            addListener(object : Player.Listener {
                override fun onPlaybackStateChanged(playbackState: Int) {
                    if (crossfadeStatus == "preparing") {
                        crossfadeStatus = when (playbackState) {
                            Player.STATE_READY -> "ready"
                            Player.STATE_IDLE -> "preparing"
                            Player.STATE_BUFFERING -> "preparing"
                            Player.STATE_ENDED -> "incoming_ended"
                            else -> crossfadeStatus
                        }
                    }
                }

                override fun onPlayerError(error: androidx.media3.common.PlaybackException) {
                    crossfadeStatus = "incoming_error"
                }
            })
        }
        mediaSession = MediaSession.Builder(this, activePlayer).build()
        applyDeckVolumes()
    }

    private fun newPlayer(handleAudioFocus: Boolean) = ExoPlayer.Builder(
        this,
        object : DefaultRenderersFactory(this) {
            override fun buildAudioSink(
                context: Context,
                enableFloatOutput: Boolean,
                enableAudioOutputPlaybackParams: Boolean,
            ): AudioSink = DefaultAudioSink.Builder(context)
                .setAudioProcessors(DspEngineSinkHook.createProcessors())
                .setEnableFloatOutput(enableFloatOutput)
                .setEnableAudioTrackPlaybackParams(enableAudioOutputPlaybackParams)
                .build()
        },
    ).build().apply {
        setAudioAttributes(audioAttributes(), handleAudioFocus)
        repeatMode = Player.REPEAT_MODE_OFF
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? =
        mediaSession

    private fun audioAttributes() = AudioAttributes.Builder()
        .setUsage(C.USAGE_MEDIA)
        .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
        .build()

    /** Prepares the inactive deck without disturbing current playback. */
    fun preloadNext(items: List<MediaItem>, startIndex: Int): Boolean {
        if (!::standbyPlayer.isInitialized || items.isEmpty() ||
            startIndex !in items.indices ||
            items.any { it.localConfiguration?.uri == null }
        ) return false
        cancelCrossfade()
        gainPolicy.setCrossfadeGains(active = 1f, standby = 0f)
        applyDeckVolumes()
        // Keep the complete queue on the standby deck. After the deck swap,
        // next/previous/repeat continue to work without reconstructing the
        // playlist mid-playback or briefly reloading the incoming track.
        standbyPlayer.setMediaItems(items, startIndex, 0L)
        standbyPlayer.prepare()
        crossfadeStatus = "preparing"
        return true
    }

    /**
     * Starts a cancellable gain ramp. Equal-power curves avoid the large perceived
     * dip of a linear crossfade. Calls are main-thread serialized by the bridge.
     */
    fun startCrossfade(durationMs: Long): Boolean {
        if (durationMs !in 250L..15000L) return false
        if (!activePlayer.isPlaying || standbyPlayer.mediaItemCount == 0 ||
            standbyPlayer.playbackState != Player.STATE_READY
        ) {
            crossfadeStatus = "incoming_not_ready"
            return false
        }
        cancelCrossfade()
        fadeDurationMs = durationMs
        fadeStartedAt = android.os.SystemClock.elapsedRealtime()
        val generation = ++fadeGeneration
        crossfadeStatus = "fading"
        gainPolicy.resetDecks()
        applyDeckVolumes()
        standbyPlayer.play()
        val task = object : Runnable {
            override fun run() {
                if (generation != fadeGeneration || isDestroyed) return
                val elapsed = (android.os.SystemClock.elapsedRealtime() - fadeStartedAt).coerceAtLeast(0L)
                val progress = (elapsed.toFloat() / fadeDurationMs.toFloat()).coerceIn(0f, 1f)
                gainPolicy.setCrossfadeGains(
                    active = cos(progress * Math.PI.toFloat() / 2f),
                    standby = sin(progress * Math.PI.toFloat() / 2f),
                )
                applyDeckVolumes()
                if (progress >= 1f) {
                    val oldPlayer = activePlayer
                    activePlayer = standbyPlayer
                    standbyPlayer = oldPlayer
                    oldPlayer.setAudioAttributes(audioAttributes(), false)
                    activePlayer.setAudioAttributes(audioAttributes(), true)
                    mediaSession?.setPlayer(activePlayer)
                    gainPolicy.resetDecks()
                    applyDeckVolumes()
                    standbyPlayer.pause()
                    standbyPlayer.clearMediaItems()
                    crossfadeStatus = "completed"
                    fadeRunnable = null
                } else {
                    mainHandler.postDelayed(this, 32L)
                }
            }
        }
        fadeRunnable = task
        mainHandler.post(task)
        return true
    }

    fun cancelCrossfade(): Boolean {
        fadeGeneration++
        fadeRunnable?.let(mainHandler::removeCallbacks)
        fadeRunnable = null
        if (::activePlayer.isInitialized && ::standbyPlayer.isInitialized) {
            // Cancellation preserves the current deck; the incoming deck is silenced
            // and paused so a second request cannot leave two audible players.
            gainPolicy.resetDecks()
            applyDeckVolumes()
            standbyPlayer.pause()
        }
        if (crossfadeStatus == "fading" || crossfadeStatus == "preparing" || crossfadeStatus == "ready") {
            crossfadeStatus = "cancelled"
        }
        if (::activePlayer.isInitialized) {
            gainPolicy.resetDecks()
            applyDeckVolumes()
        }
        return true
    }

    fun crossfadeState(): Map<String, Any?> = mapOf(
        "status" to crossfadeStatus,
        "activeMediaId" to activePlayer.currentMediaItem?.mediaId,
        "incomingReady" to (standbyPlayer.playbackState == Player.STATE_READY),
        "activePositionMs" to activePlayer.currentPosition.coerceAtLeast(0L),
        "incomingPositionMs" to standbyPlayer.currentPosition.coerceAtLeast(0L),
        "activeVolume" to activePlayer.volume,
        "incomingVolume" to standbyPlayer.volume,
    )

    private var isDestroyed = false

    override fun onDestroy() {
        isDestroyed = true
        cancelCrossfade()
        mainHandler.removeCallbacksAndMessages(null)
        mediaSession?.release()
        mediaSession = null
        if (::activePlayer.isInitialized) activePlayer.release()
        if (::standbyPlayer.isInitialized) standbyPlayer.release()
        if (instance === this) instance = null
        super.onDestroy()
    }

    companion object {
        @Volatile
        var instance: Media3PlaybackService? = null
            private set
    }
}
