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
 * Connection is lazy: merely launching Resonate does not create a second player
 * or bind the experimental service. Native Media3 objects stay native; Flutter
 * receives commands and immutable state snapshots rather than mutable objects.
 */
class Media3PlaybackBridge(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val mainExecutor = Executor { command -> mainHandler.post(command) }
    private val methodChannel = MethodChannel(messenger, "com.aetherion.resonate/media3")
    private val eventChannel = EventChannel(messenger, "com.aetherion.resonate/media3_events")
    private var eventSink: EventChannel.EventSink? = null
    private var controller: MediaController? = null
    private var controllerFuture: ListenableFuture<MediaController>? = null
    private var released = false

    private val listener = object : Player.Listener {
        override fun onEvents(player: Player, events: Player.Events) {
            publishState()
        }
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
                "stop" -> { connected.stop(); result.success(true) }
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
                    connected.volume = volume.coerceIn(0f, 1f)
                    result.success(true)
                }
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
                }
            }
        }
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
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
        "volume" to player.volume,
        "hasError" to (player.playerError != null),
        "error" to player.playerError?.message,
    )

    fun release() {
        released = true
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
