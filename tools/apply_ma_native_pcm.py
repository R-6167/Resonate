#!/usr/bin/env python3
"""Surgically add readMediaHead + extractPcmWindow to MainActivity (Phase 1 native PCM)."""
from pathlib import Path

MA = Path("android/app/src/main/kotlin/com/Aetherion/Resonate/MainActivity.kt")
t = MA.read_text()
n = 0

if "fun readMediaHead" in t and "fun extractPcmWindow" in t:
    print("already patched")
    raise SystemExit(0)

# 1) Imports
old_imp = "import android.media.AudioManager\n"
new_imp = (
    "import android.media.AudioManager\n"
    "import android.media.MediaCodec\n"
    "import android.media.MediaExtractor\n"
    "import android.media.MediaFormat\n"
)
if "import android.media.MediaExtractor" not in t and old_imp in t:
    t = t.replace(old_imp, new_imp, 1)
    n += 1
    print("imports media")

old_imp2 = "import kotlin.math.roundToInt\n"
new_imp2 = "import kotlin.math.roundToInt\nimport java.util.concurrent.Executors\n"
if "import java.util.concurrent.Executors" not in t and old_imp2 in t:
    t = t.replace(old_imp2, new_imp2, 1)
    n += 1
    print("imports executors")

# 2) pcmExecutor field
old_field = "    private var resonateDspEnabled: Boolean = true\n"
new_field = (
    "    private var resonateDspEnabled: Boolean = true\n"
    "    private val pcmExecutor = Executors.newSingleThreadExecutor()\n"
)
if "pcmExecutor" not in t and old_field in t:
    t = t.replace(old_field, new_field, 1)
    n += 1
    print("pcmExecutor")

# 3) Channel handlers
old_when = (
    '                "getAudioSize" -> result.success(getAudioSize(call.argument<List<String>>("folders") ?: emptyList()))\n'
    '                else -> result.notImplemented()'
)
new_when = (
    '                "getAudioSize" -> result.success(getAudioSize(call.argument<List<String>>("folders") ?: emptyList()))\n'
    '                "readMediaHead" -> readMediaHead(\n'
    '                    call.argument<String>("uri") ?: "",\n'
    '                    call.argument<Int>("maxBytes") ?: (512 * 1024),\n'
    '                    result,\n'
    '                )\n'
    '                "extractPcmWindow" -> extractPcmWindow(\n'
    '                    call.argument<String>("uri") ?: "",\n'
    '                    (call.argument<Number>("maxSeconds") ?: 12.0).toDouble(),\n'
    '                    result,\n'
    '                )\n'
    '                else -> result.notImplemented()'
)
if '"readMediaHead"' not in t and old_when in t:
    t = t.replace(old_when, new_when, 1)
    n += 1
    print("channel handlers")
else:
    if '"readMediaHead"' in t:
        print("handlers already")
    else:
        print("MISS handlers")

# 4) Methods before onDestroy
methods = r'''
    /** Read first N bytes of a content:// or file path (ID3 head scan). */
    private fun readMediaHead(uriString: String, maxBytes: Int, result: MethodChannel.Result) {
        if (uriString.isBlank()) { result.success(null); return }
        pcmExecutor.execute {
            try {
                val uri = Uri.parse(uriString)
                val limit = maxBytes.coerceIn(1024, 2 * 1024 * 1024)
                val bytes = contentResolver.openInputStream(uri)?.use { input ->
                    val buf = ByteArray(limit)
                    var off = 0
                    while (off < limit) {
                        val n = input.read(buf, off, limit - off)
                        if (n <= 0) break
                        off += n
                    }
                    if (off <= 0) null else buf.copyOf(off)
                }
                runOnUiThread { result.success(bytes) }
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
                        runOnUiThread { result.success(bytes) }
                        return@execute
                    }
                } catch (_: Exception) {}
                runOnUiThread { result.success(null) }
            }
        }
    }

    /** Decode a short PCM window via MediaExtractor/MediaCodec (MP3/M4A/content://). */
    private fun extractPcmWindow(uriString: String, maxSeconds: Double, result: MethodChannel.Result) {
        if (uriString.isBlank()) { result.success(null); return }
        pcmExecutor.execute {
            var extractor: MediaExtractor? = null
            var codec: MediaCodec? = null
            try {
                extractor = MediaExtractor()
                val uri = Uri.parse(uriString)
                var opened = false
                try {
                    if (uriString.startsWith("content://") || uriString.startsWith("file://")) {
                        extractor.setDataSource(this@MainActivity, uri, null)
                        opened = true
                    }
                } catch (_: Exception) {}
                if (!opened) {
                    try {
                        contentResolver.openFileDescriptor(uri, "r")?.use { pfd ->
                            extractor.setDataSource(pfd.fileDescriptor)
                            opened = true
                        }
                    } catch (_: Exception) {}
                }
                if (!opened) {
                    try { extractor.setDataSource(uriString); opened = true } catch (_: Exception) {}
                }
                if (!opened) { runOnUiThread { result.success(null) }; return@execute }

                var audioTrack = -1
                var format: MediaFormat? = null
                for (i in 0 until extractor.trackCount) {
                    val f = extractor.getTrackFormat(i)
                    val mime = f.getString(MediaFormat.KEY_MIME) ?: continue
                    if (mime.startsWith("audio/")) { audioTrack = i; format = f; break }
                }
                if (audioTrack < 0 || format == null) { runOnUiThread { result.success(null) }; return@execute }
                extractor.selectTrack(audioTrack)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: run {
                    runOnUiThread { result.success(null) }; return@execute
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
                while (!outputDone && safety < 800 && outBytes.size() < maxPcmBytes) {
                    safety++
                    if (!inputDone) {
                        val inIndex = codec.dequeueInputBuffer(8000)
                        if (inIndex >= 0) {
                            val inBuf = codec.getInputBuffer(inIndex)
                            if (inBuf != null) {
                                inBuf.clear()
                                val sampleSize = extractor.readSampleData(inBuf, 0)
                                if (sampleSize < 0 || extractor.sampleTime > maxUs) {
                                    codec.queueInputBuffer(inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                                    inputDone = true
                                } else {
                                    codec.queueInputBuffer(inIndex, 0, sampleSize, extractor.sampleTime.coerceAtLeast(0), 0)
                                    extractor.advance()
                                }
                            }
                        }
                    }
                    val outIndex = codec.dequeueOutputBuffer(info, 8000)
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
                val pcm = outBytes.toByteArray()
                if (pcm.size < sampleRate) { runOnUiThread { result.success(null) }; return@execute }
                runOnUiThread {
                    result.success(hashMapOf("sampleRate" to sampleRate, "channels" to channelCount, "pcm" to pcm))
                }
            } catch (e: Exception) {
                runOnUiThread { result.success(null) }
            } finally {
                try { codec?.stop() } catch (_: Exception) {}
                try { codec?.release() } catch (_: Exception) {}
                try { extractor?.release() } catch (_: Exception) {}
            }
        }
    }

'''

old_destroy = "    override fun onDestroy() {\n        releaseEffects()\n        super.onDestroy()\n    }\n}"
new_destroy = methods + "    override fun onDestroy() {\n        releaseEffects()\n        super.onDestroy()\n    }\n}"
if "fun extractPcmWindow" not in t and old_destroy in t:
    t = t.replace(old_destroy, new_destroy, 1)
    n += 1
    print("methods")
else:
    if "fun extractPcmWindow" in t:
        print("methods already")
    else:
        print("MISS methods")

MA.write_text(t)
print("patches", n)
