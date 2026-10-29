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
                    // A previous standby deck must not survive queue replacement.
                    Media3PlaybackService.instance?.clearPreload()
                    connected.setMediaItems(items, startIndex, 0L)
                    connected.prepare()
                    result.success(true)
                }
                "synchronizeQueue" -> {
                    val rawItems = call.argument<List<Map<String, Any?>>>("items")
                    if (rawItems.isNullOrEmpty()) {
                        Media3PlaybackService.instance?.clearPreload()
                        connected.stop()
                        connected.clearMediaItems()
                        result.success(true)
                        return
                    }
                    if (rawItems.size > 500) {
                        result.error("INVALID_QUEUE", "Queue is too large; maximum is 500 items.", null)
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

                    Media3PlaybackService.instance?.clearPreload()
                    val oldIndex = connected.currentMediaItemIndex
                    val oldItem = connected.currentMediaItem
                    val oldPosition = connected.currentPosition.coerceAtLeast(0L)
                    val oldPlayIntent = connected.playWhenReady
                    if (oldItem == null || connected.mediaItemCount == 0 || oldIndex !in 0 until connected.mediaItemCount) {
                        connected.setMediaItems(items, 0, 0L)
                        connected.prepare()
                        if (oldPlayIntent) connected.play()
                        result.success(true)
                        return
                    }

                    val sameOccurrence = items.getOrNull(oldIndex)?.let { candidate ->
                        candidate.mediaId == oldItem.mediaId &&
                            candidate.localConfiguration?.uri == oldItem.localConfiguration?.uri
                    } == true
                    val matchingIndex = if (sameOccurrence) oldIndex else items.indexOfFirst { candidate ->
                        candidate.mediaId == oldItem.mediaId &&
                            candidate.localConfiguration?.uri == oldItem.localConfiguration?.uri
                    }
                    val targetIndex = if (matchingIndex >= 0) matchingIndex
                        else oldIndex.coerceIn(0, items.lastIndex)
                    val keepPosition = items[targetIndex].mediaId == oldItem.mediaId &&
                        items[targetIndex].localConfiguration?.uri == oldItem.localConfiguration?.uri

                    // Keep the active deck attached to the player while rebuilding the
                    // surrounding playlist. This avoids resetting the whole player for
                    // append/remove/reorder edits and invalidates stale crossfade preload.
                    connected.removeMediaItems(oldIndex + 1, connected.mediaItemCount)
                    connected.removeMediaItems(0, oldIndex)
                    connected.replaceMediaItem(0, items[targetIndex])
                    if (targetIndex > 0) {
                        connected.addMediaItems(0, items.subList(0, targetIndex))
                    }
                    if (targetIndex < items.lastIndex) {
                        connected.addMediaItems(targetIndex + 1, items.subList(targetIndex + 1, items.size))
                    }
                    if (keepPosition && oldPosition > 0L) {
                        connected.seekTo(targetIndex, oldPosition)
                    }
                    result.success(true)
                }
                "clearQueue" -> {
                    Media3PlaybackService.instance?.clearPreload()
                    connected.stop()
                    connected.clearMediaItems()
                    result.success(true)
                }
                "skipToNext" -> { connected.seekToNextMediaItem(); result.success(true) }
                "skipToPrevious" -> { connected.seekToPreviousMediaItem(); result.success(true) }
                "setRepeatMode" -> {
                    val mode = call.argument<String>("mode")
                    val nativeMode = when (mode) {
                        "one" -> Player.REPEAT_MODE_ONE
                        "all" -> Player.REPEAT_MODE_ALL
                        "off" -> Player.REPEAT_MODE_OFF
                        else -> {
                            result.error("INVALID_REPEAT_MODE", "mode must be off, one, or all.", null)
                            return
                        }
                    }
                    val accepted = Media3PlaybackService.instance?.setRepeatMode(nativeMode) == true
                    if (accepted) result.success(true)
                    else result.error("MEDIA3_TRANSPORT_UNAVAILABLE", "Media3 repeat policy is unavailable.", null)
                }
                "setShuffleMode" -> {
                    val enabled = call.argument<Boolean>("enabled")
                    if (enabled == null) {
                        result.error("INVALID_SHUFFLE_MODE", "enabled must be a boolean.", null)
                        return
                    }
                    val accepted = Media3PlaybackService.instance?.setShuffleMode(enabled) == true
                    if (accepted) result.success(true)
                    else result.error("MEDIA3_TRANSPORT_UNAVAILABLE", "Media3 shuffle policy is unavailable.", null)
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
                    // Single-source loads also invalidate any old incoming deck.
                    Media3PlaybackService.instance?.clearPreload()
                    connected.setMediaItem(item)
                    connected.prepare()
                    result.success(true)
                }
                "play" -> {
                    connected.play()
                    Media3PlaybackService.instance?.resumeCrossfade()
                    result.success(true)
                }
                "pause" -> {
                    Media3PlaybackService.instance?.pauseCrossfade()
                    connected.pause()
                    result.success(true)
                }
                "stop" -> {
                    Media3PlaybackService.instance?.clearPreload()
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
                "setGainFactors" -> {
                    val trackLevel = call.argument<Number>("trackLevel")?.toFloat()
                    val preamp = call.argument<Number>("preamp")?.toFloat()
                    val sleepFade = call.argument<Number>("sleepFade")?.toFloat()
                    val focusDuck = call.argument<Number>("focusDuck")?.toFloat()
                    val normalizedFactors = listOf(trackLevel, sleepFade, focusDuck)
                    if (normalizedFactors.any { it == null || !it.isFinite() || it !in 0f..1f } ||
                        preamp == null || !preamp.isFinite() || preamp !in 0f..4f
                    ) {
                        result.error(
                            "INVALID_GAIN_FACTORS",
                            "Track level, sleep fade, and focus duck must be 0–1; preamp must be 0–4.",
                            null,
                        )
                        return
                    }
                    val accepted = Media3PlaybackService.instance?.setGainFactors(
                        trackLevel = trackLevel!!,
                        preamp = preamp!!,
                        sleepFade = sleepFade!!,
                        focusDuck = focusDuck!!,
                    ) == true
                    if (accepted) result.success(true)
                    else result.error("MEDIA3_GAIN_UNAVAILABLE", "Media3 gain policy is unavailable.", null)
                }
                "preloadNext" -> {
                    val raw = call.argument<Map<String, Any?>>("item")
                    val source = raw?.get("uri") as? String
                    if (raw == null || source.isNullOrBlank()) {
                        result.error("INVALID_URI", "An incoming queue item with a URI is required.", null)
                        return
                    }
                    val rawItems = call.argument<List<Map<String, Any?>>>("items")
                    val startIndex = call.argument<Number>("startIndex")?.toInt() ?: 0
                    val descriptors = rawItems ?: listOf(raw)
                    if (descriptors.isEmpty() || descriptors.size > 500 || startIndex !in descriptors.indices) {
                        result.error("INVALID_QUEUE", "Incoming queue must contain 1–500 items and a valid start index.", null)
                        return
                    }
                    val items = mutableListOf<MediaItem>()
                    for (descriptor in descriptors) {
                        val descriptorUri = descriptor["uri"] as? String
                        if (descriptorUri.isNullOrBlank()) {
                            result.error("INVALID_QUEUE", "Every incoming queue item needs a URI.", null)
                            return
                        }
                        val metadata = MediaMetadata.Builder()
                            .setTitle((descriptor["title"] as? String)?.takeIf { it.isNotBlank() } ?: "Unknown track")
                            .setArtist(descriptor["artist"] as? String)
                            .setAlbumTitle(descriptor["album"] as? String)
                            .apply {
                                val artwork = descriptor["artworkUri"] as? String
                                if (!artwork.isNullOrBlank()) setArtworkUri(Uri.parse(artwork))
                            }
                            .build()
                        items += MediaItem.Builder()
                            .setMediaId((descriptor["id"] as? String)?.takeIf { it.isNotBlank() } ?: descriptorUri)
                            .setUri(Uri.parse(descriptorUri))
                            .setMediaMetadata(metadata)
                            .build()
                    }
                    val incoming = items[startIndex]
                    if (incoming.mediaId != ((raw["id"] as? String)?.takeIf { it.isNotBlank() } ?: source) ||
                        incoming.localConfiguration?.uri?.toString() != source
                    ) {
                        result.error("INVALID_QUEUE_INDEX", "The selected queue occurrence must match the incoming item.", null)
                        return
                    }
                    val accepted = Media3PlaybackService.instance?.preloadNext(items, startIndex) == true
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
        "repeatMode" to when (player.repeatMode) {
            Player.REPEAT_MODE_ONE -> "one"
            Player.REPEAT_MODE_ALL -> "all"
            else -> "off"
        },
        "shuffleModeEnabled" to player.shuffleModeEnabled,
        "volume" to player.volume,
        "audioSessionId" to (Media3PlaybackService.instance?.activeAudioSessionId() ?: 0),
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
