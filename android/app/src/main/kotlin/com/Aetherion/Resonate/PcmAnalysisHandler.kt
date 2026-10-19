package com.Aetherion.Resonate

import android.app.Activity
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Owns short-window PCM decoding and media-head reads used by background analysis.
 * Cancellation invalidates active and queued PCM requests without affecting playback.
 */
internal class PcmAnalysisHandler(private val activity: Activity) {
    private val pcmExecutor = Executors.newSingleThreadExecutor()
    @Volatile private var cancellationGeneration: Long = 0L

    fun cancel(result: MethodChannel.Result) {
        // Invalidates active and already-queued PCM jobs. A fresh request captures
        // the new generation and remains eligible.
        cancellationGeneration += 1L
        result.success(true)
    }

        /** Read first N bytes of a content:// or file path (ID3 head scan). */
        fun readMediaHead(uriString: String, maxBytes: Int, result: MethodChannel.Result) {
            if (uriString.isBlank()) { result.success(null); return }
            pcmExecutor.execute {
                try {
                    val uri = Uri.parse(uriString)
                    val limit = maxBytes.coerceIn(1024, 2 * 1024 * 1024)
                    val bytes = activity.contentResolver.openInputStream(uri)?.use { input ->
                        val buf = ByteArray(limit)
                        var off = 0
                        while (off < limit) {
                            val n = input.read(buf, off, limit - off)
                            if (n <= 0) break
                            off += n
                        }
                        if (off <= 0) null else buf.copyOf(off)
                    }
                    activity.runOnUiThread { result.success(bytes) }
                } catch (e: Exception) {
                    try {
                        val file = java.io.File(uriString)
                        if (file.exists() && file.canRead()) {
                            val limit = maxBytes.coerceIn(1024, 2 * 1024 * 1024)
                            val len = minOf(limit.toLong(), file.length()).toInt()
                            val bytes = file.inputStream().use { stream ->
                                val b = stream.readBytes()
                                if (b.size > len) b.copyOf(len) else b
                            }
                            activity.runOnUiThread { result.success(bytes) }
                            return@execute
                        }
                    } catch (_: Exception) {}
                    activity.runOnUiThread { result.success(null) }
                }
            }
        }
    
        /** Decode a short PCM window via MediaExtractor/MediaCodec (MP3/M4A/content://). */
        fun extractPcmWindow(uriString: String, maxSeconds: Double, startMs: Long, result: MethodChannel.Result) {
            if (uriString.isBlank()) { result.success(null); return }
            val requestGeneration = cancellationGeneration
            pcmExecutor.execute {
                var extractor: MediaExtractor? = null
                var codec: MediaCodec? = null
                try {
                    extractor = MediaExtractor()
                    val uri = Uri.parse(uriString)
                    var opened = false
                    try {
                        if (uriString.startsWith("content://") || uriString.startsWith("file://")) {
                            extractor.setDataSource(activity, uri, null)
                            opened = true
                        }
                    } catch (_: Exception) {}
                    if (!opened) {
                        try {
                            activity.contentResolver.openFileDescriptor(uri, "r")?.use { pfd ->
                                extractor.setDataSource(pfd.fileDescriptor)
                                opened = true
                            }
                        } catch (_: Exception) {}
                    }
                    if (!opened) {
                        try { extractor.setDataSource(uriString); opened = true } catch (_: Exception) {}
                    }
                    if (!opened) { activity.runOnUiThread { result.success(null) }; return@execute }
                    var audioTrack = -1
                    var format: MediaFormat? = null
                    for (i in 0 until extractor.trackCount) {
                        val f = extractor.getTrackFormat(i)
                        val mime = f.getString(MediaFormat.KEY_MIME) ?: continue
                        if (mime.startsWith("audio/")) { audioTrack = i; format = f; break }
                    }
                    if (audioTrack < 0 || format == null) { activity.runOnUiThread { result.success(null) }; return@execute }
                    extractor.selectTrack(audioTrack)
                    if (startMs > 0L) {
                        try {
                            extractor.seekTo(startMs * 1000L, MediaExtractor.SEEK_TO_CLOSEST_SYNC)
                        } catch (_: Exception) {}
                    }
                    val mime = format.getString(MediaFormat.KEY_MIME) ?: run {
                        activity.runOnUiThread { result.success(null) }; return@execute
                    }
                    val sampleRate = if (format.containsKey(MediaFormat.KEY_SAMPLE_RATE)) format.getInteger(MediaFormat.KEY_SAMPLE_RATE) else 44100
                    val channelCount = if (format.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) format.getInteger(MediaFormat.KEY_CHANNEL_COUNT) else 2
                    codec = MediaCodec.createDecoderByType(mime)
                    codec.configure(format, null, null, 0)
                    codec.start()
                    val maxUs = (maxSeconds.coerceIn(4.0, 25.0) * 1_000_000L).toLong()
                    val maxPcmBytes = (sampleRate * channelCount * 2 * maxSeconds.coerceIn(4.0, 25.0)).toInt().coerceIn(64 * 1024, 3 * 1024 * 1024)
                    val outBytes = java.io.ByteArrayOutputStream(maxPcmBytes.coerceAtMost(512 * 1024))
                    val info = MediaCodec.BufferInfo()
                    var inputDone = false
                    var outputDone = false
                    var safety = 0
                    while (!outputDone &&
                        safety < 800 &&
                        outBytes.size() < maxPcmBytes &&
                        requestGeneration == cancellationGeneration
                    ) {
                        safety++
                        if (!inputDone) {
                            val inIndex = codec.dequeueInputBuffer(100)
                            if (inIndex >= 0) {
                                val inBuf = codec.getInputBuffer(inIndex)
                                if (inBuf != null) {
                                    inBuf.clear()
                                    val sampleSize = extractor.readSampleData(inBuf, 0)
                                    if (sampleSize < 0 || extractor.sampleTime < 0L || extractor.sampleTime > startMs * 1000L + maxUs) {
                                        codec.queueInputBuffer(inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                                        inputDone = true
                                    } else {
                                        codec.queueInputBuffer(inIndex, 0, sampleSize, extractor.sampleTime.coerceAtLeast(0), 0)
                                        extractor.advance()
                                    }
                                }
                            }
                        }
                        val outIndex = codec.dequeueOutputBuffer(info, 100)
                        if (outIndex >= 0) {
                            if (info.size > 0 && info.presentationTimeUs <= maxUs) {
                                val outBuf = codec.getOutputBuffer(outIndex)
                                if (outBuf != null) {
                                    outBuf.position(info.offset)
                                    outBuf.limit(info.offset + info.size)
                                    val chunk = ByteArray(info.size)
                                    outBuf.get(chunk)
                                    val room = maxPcmBytes - outBytes.size()
                                    if (room > 0) outBytes.write(chunk, 0, minOf(chunk.size, room))
                                }
                            }
                            codec.releaseOutputBuffer(outIndex, false)
                            if ((info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) outputDone = true
                            if (outBytes.size() >= maxPcmBytes) outputDone = true
                        }
                    }
                    if (requestGeneration != cancellationGeneration) {
                        activity.runOnUiThread { result.success(null) }
                        return@execute
                    }
                    val pcm = outBytes.toByteArray()
                    if (pcm.size < sampleRate) { activity.runOnUiThread { result.success(null) }; return@execute }
                    activity.runOnUiThread {
                        result.success(hashMapOf("sampleRate" to sampleRate, "channels" to channelCount, "pcm" to pcm))
                    }
                } catch (e: Exception) {
                    activity.runOnUiThread { result.success(null) }
                } finally {
                    try { codec?.stop() } catch (_: Exception) {}
                    try { codec?.release() } catch (_: Exception) {}
                    try { extractor?.release() } catch (_: Exception) {}
                }
            }
        }

    fun release() {
        cancellationGeneration += 1L
        pcmExecutor.shutdownNow()
    }
}
