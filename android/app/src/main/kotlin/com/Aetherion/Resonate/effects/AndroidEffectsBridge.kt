package com.Aetherion.Resonate.effects

import android.media.audiofx.EnvironmentalReverb
import android.media.audiofx.Visualizer
import android.media.audiofx.Virtualizer

/**
 * Thin bridge for optional system-level creative effects (Virtualizer / Reverb).
 * Effects are owned per Android audio session because Resonate's A/B players
 * have independent sessions that may be recreated during playback.
 */
class AndroidEffectsBridge {

    private var effectSessionId: Int = 0
    private val virtualizers = mutableMapOf<Int, Virtualizer>()
    private val reverbs = mutableMapOf<Int, EnvironmentalReverb>()
    private val visualizers = mutableMapOf<Int, Visualizer>()
    private val knownSessionIds = mutableSetOf<Int>()
    private val spectra = mutableMapOf<Int, FloatArray>()
    private val spectrumLock = Any()
    private val spectrumSize = 32

    fun attachToSession(sessionId: Int) {
        if (sessionId <= 0) return
        effectSessionId = sessionId
        knownSessionIds.add(sessionId)
        if (visualizers.containsKey(sessionId)) return
        try {
            val range = Visualizer.getCaptureSizeRange()
            val size = Integer.highestOneBit(range[1].coerceAtMost(1024)).coerceAtLeast(range[0])
            val visualizer = Visualizer(sessionId)
            visualizer.captureSize = size
            visualizer.scalingMode = Visualizer.SCALING_MODE_NORMALIZED
            visualizer.setDataCaptureListener(object : Visualizer.OnDataCaptureListener {
                override fun onWaveFormDataCapture(
                    visualizer: Visualizer?, waveform: ByteArray?, samplingRate: Int
                ) = Unit

                override fun onFftDataCapture(
                    visualizer: Visualizer?, fft: ByteArray?, samplingRate: Int
                ) {
                    if (fft == null || fft.size < 4) return
                    val bands = FloatArray(spectrumSize)
                    val binCount = fft.size / 2
                    for (band in 0 until spectrumSize) {
                        val start = (Math.pow(binCount.toDouble(), band.toDouble() / spectrumSize)).toInt().coerceAtLeast(1)
                        val end = (Math.pow(binCount.toDouble(), (band + 1).toDouble() / spectrumSize)).toInt().coerceAtLeast(start + 1)
                        var peak = 0.0
                        for (bin in start until end.coerceAtMost(binCount)) {
                            val offset = bin * 2
                            if (offset + 1 >= fft.size) break
                            val real = fft[offset].toDouble()
                            val imag = fft[offset + 1].toDouble()
                            peak = maxOf(peak, kotlin.math.sqrt(real * real + imag * imag))
                        }
                        bands[band] = (peak / 180.0).coerceIn(0.0, 1.0).toFloat()
                    }
                    synchronized(spectrumLock) { spectra[sessionId] = bands }
                }
            }, (Visualizer.getMaxCaptureRate() / 2).coerceAtMost(20000), false, true)
            visualizer.enabled = true
            visualizers[sessionId] = visualizer
        } catch (_: Throwable) {
            // Spectrum is optional: unsupported routes/devices must keep audio unaffected.
            releaseVisualizer(sessionId)
        }
    }

    fun refreshVisualizers() {
        // Sessions can be discovered before Android grants RECORD_AUDIO. Keep
        // their IDs and retry capture once the user grants visualization access.
        knownSessionIds.toList().forEach(::attachToSession)
    }

    fun getSpectrum(): List<Double> {
        synchronized(spectrumLock) {
            val active = spectra.values
            if (active.isEmpty()) return List(spectrumSize) { 0.0 }
            return List(spectrumSize) { i -> active.maxOfOrNull { it.getOrElse(i) { 0f }.toDouble() } ?: 0.0 }
        }
    }

    fun detachFromSession(sessionId: Int) {
        if (sessionId <= 0) return
        releaseVirtualizer(sessionId)
        releaseReverb(sessionId)
        releaseVisualizer(sessionId)
        knownSessionIds.remove(sessionId)
        if (effectSessionId == sessionId) effectSessionId = 0
    }

    fun setVirtualizer(strength: Int) {
        val sessionId = effectSessionId
        if (sessionId <= 0) return
        val s = strength.coerceIn(0, 1000)
        if (s == 0) {
            releaseVirtualizer(sessionId)
            return
        }
        try {
            val effect = virtualizers[sessionId] ?: Virtualizer(0, sessionId).also {
                it.enabled = true
                virtualizers[sessionId] = it
            }
            effect.setStrength(s.toShort())
            effect.enabled = true
        } catch (_: Throwable) {
            releaseVirtualizer(sessionId)
        }
    }

    fun setReverb(strength: Int) {
        val sessionId = effectSessionId
        if (sessionId <= 0) return
        val s = strength.coerceIn(-900, 0)
        if (s == 0) {
            releaseReverb(sessionId)
            return
        }
        try {
            val effect = reverbs[sessionId] ?: EnvironmentalReverb(0, sessionId).also {
                it.enabled = true
                reverbs[sessionId] = it
            }
            effect.reverbLevel = s.toShort()
            effect.enabled = true
        } catch (_: Throwable) {
            releaseReverb(sessionId)
        }
    }

    fun release() {
        virtualizers.keys.toList().forEach(::releaseVirtualizer)
        reverbs.keys.toList().forEach(::releaseReverb)
        visualizers.keys.toList().forEach(::releaseVisualizer)
        knownSessionIds.clear()
        synchronized(spectrumLock) { spectra.clear() }
        effectSessionId = 0
    }

    private fun releaseVisualizer(sessionId: Int) {
        try {
            visualizers.remove(sessionId)?.let {
                it.enabled = false
                it.setDataCaptureListener(null, 0, false, false)
                it.release()
            }
        } catch (_: Throwable) {}
        synchronized(spectrumLock) { spectra.remove(sessionId) }
    }

    private fun releaseVirtualizer(sessionId: Int) {
        try {
            virtualizers.remove(sessionId)?.release()
        } catch (_: Exception) {
        }
    }

    private fun releaseReverb(sessionId: Int) {
        try {
            reverbs.remove(sessionId)?.release()
        } catch (_: Exception) {
        }
    }
}
