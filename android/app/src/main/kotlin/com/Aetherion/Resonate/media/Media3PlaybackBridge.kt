package com.Aetherion.Resonate.media

import android.content.ComponentName
import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.BinaryMessenger
import java.util.concurrent.Executor

/**
 * Narrow Flutter boundary for the isolated Media3 prototype.
 *
 * Native Media3 objects stay native; Flutter receives commands and immutable
 * state snapshots rather than mutable Player/ExoPlayer instances.
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
    private var released = false

    private val listener = object : Player.Listener {
        override fun onEvents(player: Player, events: Player.Events) {
            publishState()
        }
    }

    private val controllerFuture = MediaController.Builder(
        context,
        SessionToken(context, ComponentName(context, Media3PlaybackService::class.java)),
    ).buildAsync()

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        controllerFuture.addListener({
            if (released) {
                controllerFuture.get().release()
                return@addListener
            }
            try {
                controller = controllerFuture.get().also { it.addListener(listener) }
                publishState()
            } catch (error: Exception) {
                android.util.Log.e("ResonateMedia3", "Could not connect to Media3 service", error)
            }
        }, mainExecutor)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val connected = controller
        if (connected == null) {
            result.error("MEDIA3_NOT_READY", "Native Media3 session is not connected yet.", null)
            return
        }

        try {
            when (call.method) {
                "setSource" -> {
                    val source = call.argument<String>("uri")
                    if (source.isNullOrBlank()) {
                        result.error("INVALID_URI", "A non-empty media URI is required.", null)
                        return
                    }
                    connected.setMediaItem(MediaItem.fromUri(Uri.parse(source)))
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

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        publishState()
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
        "durationMs" to player.duration.takeIf { it != androidx.media3.common.C.TIME_UNSET }?.coerceAtLeast(0L),
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
        if (!controllerFuture.isDone) controllerFuture.cancel(true)
    }
}
