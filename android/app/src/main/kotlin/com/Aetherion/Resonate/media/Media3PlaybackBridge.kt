package com.Aetherion.Resonate.media

import android.content.ComponentName
import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.ListenableFuture
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executor

/**
 * Narrow Flutter boundary for the isolated Media3 prototype.
 *
 * Native Media3 objects stay native; Flutter receives commands and immutable
 * state snapshots rather than mutable player objects.
 */
class Media3PlaybackBridge(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val POSITION_UPDATE_INTERVAL_MS = 250L
    }
    private val mainHandler = Handler(Looper.getMainLooper())
    private val mainExecutor = Executor { command -> mainHandler.post(command) }
    private val methodChannel = MethodChannel(messenger, "com.aetherion.resonate/media3")
    private val eventChannel = EventChannel(messenger, "com.aetherion.resonate/media3_events")
    private var eventSink: EventChannel.EventSink? = null
    private var controller: MediaController? = null
    private var controllerFuture: ListenableFuture<MediaController>? = null
    private var released = false

    private val positionTicker = object : Runnable {
        override fun run() {
            val player = controller
            if (released || eventSink == null || player == null || !player.isPlaying) {
                return
            }
            publishState()
            mainHandler.postDelayed(this, POSITION_UPDATE_INTERVAL_MS)
        }
    }

    private val listener = object : Player.Listener {
        override fun onEvents(player: Player, events: Player.Events) {
            publishState()
            if (player.isPlaying) {
                schedulePositionUpdates()
            } else {
                stopPositionUpdates()
            }
        }
    }

    private fun schedulePositionUpdates() {
        stopPositionUpdates()
        if (!released && eventSink != null && controller?.isPlaying == true) {
            mainHandler.postDelayed(positionTicker, POSITION_UPDATE_INTERVAL_MS)
        }
    }

    private fun stopPositionUpdates() {
        mainHandler.removeCallbacks(positionTicker)
    }

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        ensureConnected { connected ->
            if (connected == null) {
                result.error("MEDIA3_NOT_READY", "Could not connect to the native Media3 session.", null)
            } else {
                executeCommand(call, connected, result)
            }
        }
    }

    private fun executeCommand(
        call: MethodCall,
        connected: MediaController,
        result: MethodChannel.Result,
    ) {
        try {
            when (call.method) {
                "setQueue" -> {
                    val rawItems = call.argument<List<Map<String, Any?>>>("items")
                    val startIndex = call.argument<Number>("startIndex")?.toInt() ?: 0
                    if (rawItems.isNullOrEmpty()) {
                        result.error("INVALID_QUEUE", "At least one playable queue item is required.", null)
                        return
                    }
                    if (rawItems.size > 500) {
                        result.error("INVALID_QUEUE", "Queue is too large; maximum is 500 items.", null)
                        return
                    }
                    if (startIndex !in rawItems.indices) {
                        result.error("INVALID_QUEUE_INDEX", "startIndex must identify an item in the queue.", null)
                        return
                    }
                    val items = mutableListOf<MediaItem>()
                    for (raw in rawItems) {
                        val source = raw["uri"] as? String
                        if (source.isNullOrBlank()) {
                            result.error("INVALID_QUEUE", "Every queue item needs a non-empty URI.", null)
                            return
                        }
                        val uri = Uri.parse(source)
                        val title = (raw["title"] as? String)?.takeIf { it.isNotBlank() }
                            ?: uri.lastPathSegment?.substringAfterLast('/')?.takeIf { it.isNotBlank() }
                            ?: "Unknown track"
                        val metadata = MediaMetadata.Builder()
                            .setTitle(title)
                            .setArtist(raw["artist"] as? String)
                            .setAlbumTitle(raw["album"] as? String)
                            .apply {
                                val artwork = raw["artworkUri"] as? String
                                if (!artwork.isNullOrBlank()) setArtworkUri(Uri.parse(artwork))
                            }
                            .build()
                        items += MediaItem.Builder()
                            .setMediaId((raw["id"] as? String)?.takeIf { it.isNotBlank() } ?: source)
                            .setUri(uri)
                            .setMediaMetadata(metadata)
                            .build()
                    }
                    connected.setMediaItems(items, startIndex, 0L)
                    connected.prepare()
                    result.success(true)
                }
                "skipToNext" -> { connected.seekToNextMediaItem(); result.success(true) }
                "skipToPrevious" -> { connected.seekToPreviousMediaItem(); result.success(true) }
                "setRepeatMode" -> {
                    val mode = call.argument<String>("mode")
                    connected.repeatMode = when (mode) {
                        "one" -> Player.REPEAT_MODE_ONE
                        "all" -> Player.REPEAT_MODE_ALL
                        "off" -> Player.REPEAT_MODE_OFF
                        else -> {
                            result.error("INVALID_REPEAT_MODE", "mode must be off, one, or all.", null)
                            return
                        }
                    }
                    result.success(true)
                }
                "setSource" -> {
                    val source = call.argument<String>("uri")
                    if (source.isNullOrBlank()) {
                        result.error("INVALID_URI", "A non-empty media URI is required.", null)
                        return
                    }
                    val uri = Uri.parse(source)
                    val title = uri.lastPathSegment?.substringAfterLast('/')
                        ?.takeIf { it.isNotBlank() }
                        ?: "Media3 Engine Lab test audio"
                    val item = MediaItem.Builder()
                        .setUri(uri)
                        .setMediaMetadata(MediaMetadata.Builder().setTitle(title).build())
                        .build()
                    connected.setMediaItem(item)
                    connected.prepare()
                    result.success(true)
                }
                "play" -> { connected.play(); result.success(true) }
                "pause" -> { connected.pause(); result.success(true) }
                "stop" -> {
                    Media3PlaybackService.instance?.cancelCrossfade()
                    connected.stop()
                    result.success(true)
                }
                "seekTo" -> {
                    val positionMs = call.argument<Number>("positionMs")?.toLong()
                    if (positionMs == null || positionMs < 0L) {
                        result.error("INVALID_POSITION", "positionMs must be non-negative.", null)
                        return
                    }
                    connected.seekTo(positionMs)
                    result.success(true)
                }
                "setVolume" -> {
                    val volume = call.argument<Number>("value")?.toFloat()
                    if (volume == null || !volume.isFinite()) {
                        result.error("INVALID_VOLUME", "A finite volume value is required.", null)
                        return
                    }
                    val accepted = Media3PlaybackService.instance?.setMasterVolume(
                        volume.coerceIn(0f, 1f),
                    ) ?: run {
                        // Defensive fallback if the service is being torn down.
                        connected.volume = volume.coerceIn(0f, 1f)
                        true
                    }
                    result.success(accepted)
                }
                "preloadNext" -> {
                    val uri = call.argument<String>("uri")
                    if (uri.isNullOrBlank()) {
                        result.error("INVALID_URI", "A non-empty incoming URI is required.", null)
                        return
                    }
                    val accepted = Media3PlaybackService.instance?.preloadNext(uri) == true
                    if (accepted) result.success(true)
                    else result.error("MEDIA3_PRELOAD_FAILED", "The incoming deck could not be prepared.", null)
                }
                "crossfade" -> {
                    val durationMs = call.argument<Number>("durationMs")?.toLong()
                    if (durationMs == null || durationMs !in 250L..15000L) {
                        result.error("INVALID_CROSSFADE_DURATION", "Crossfade duration must be 250–15000 ms.", null)
                        return
                    }
                    val accepted = Media3PlaybackService.instance?.startCrossfade(durationMs) == true
                    if (accepted) result.success(true)
                    else result.error("CROSSFADE_NOT_READY", "Load an incoming track and wait until it is ready.", null)
                }
                "cancelCrossfade" -> result.success(Media3PlaybackService.instance?.cancelCrossfade() == true)
                "crossfadeState" -> result.success(Media3PlaybackService.instance?.crossfadeState()
                    ?: mapOf("status" to "service_unavailable"))
                "getState" -> result.success(stateSnapshot(connected))
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            result.error("MEDIA3_COMMAND_FAILED", error.message, null)
        }
    }

    private fun ensureConnected(onReady: (MediaController?) -> Unit) {
        if (released) {
            onReady(null)
            return
        }
        controller?.let {
            onReady(it)
            return
        }

        val future = controllerFuture ?: MediaController.Builder(
            context,
            SessionToken(context, ComponentName(context, Media3PlaybackService::class.java)),
        ).buildAsync().also { controllerFuture = it }

        future.addListener({
            if (released) {
                onReady(null)
                return@addListener
            }
            try {
                val connected = future.get()
                if (controller == null) {
                    controller = connected
                    connected.addListener(listener)
                }
                onReady(controller)
                publishState()
            } catch (error: Exception) {
                android.util.Log.e("ResonateMedia3", "Could not connect to Media3 service", error)
                controllerFuture = null
                onReady(null)
            }
        }, mainExecutor)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        if (events != null) {
            ensureConnected { connected ->
                if (connected == null) {
                    eventSink?.error("MEDIA3_NOT_READY", "Could not connect to the native Media3 session.", null)
                } else {
                    publishState()
                    schedulePositionUpdates()
                }
            }
        }
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        stopPositionUpdates()
    }

    private fun publishState() {
        val player = controller ?: return
        eventSink?.success(stateSnapshot(player))
    }

    private fun stateSnapshot(player: Player): Map<String, Any?> = mapOf(
        "connected" to true,
        "isPlaying" to player.isPlaying,
        "playbackState" to player.playbackState,
        "playWhenReady" to player.playWhenReady,
        "positionMs" to player.currentPosition.coerceAtLeast(0L),
        "durationMs" to player.duration.takeIf { it != C.TIME_UNSET }?.coerceAtLeast(0L),
        "mediaId" to player.currentMediaItem?.mediaId,
        "title" to player.mediaMetadata.title?.toString(),
        "artist" to player.mediaMetadata.artist?.toString(),
        "album" to player.mediaMetadata.albumTitle?.toString(),
        "currentMediaItemIndex" to player.currentMediaItemIndex,
        "mediaItemCount" to player.mediaItemCount,
        "volume" to player.volume,
        "hasError" to (player.playerError != null),
        "error" to player.playerError?.message,
    )

    fun release() {
        released = true
        stopPositionUpdates()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventSink = null
        controller?.removeListener(listener)
        controller?.release()
        controller = null
        controllerFuture?.cancel(true)
        controllerFuture = null
    }
}
