package com.aetherion.resonate.dsp

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import java.nio.ByteBuffer
import org.junit.After
import org.junit.Before
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class DspEngineAudioProcessorTest {

    private class FakeProcessorApi : DspEngineAudioProcessor.NativeDspApi {
        var nextHandle = 100L
        var createCalls = 0
        var destroyCalls = 0
        val destroyed = mutableListOf<Long>()
        var processResult = 0
        var processThrows = false
        var mutateBeforeFailure = false

        override fun create(sampleRate: Double, channels: Int): Long {
            createCalls++
            return nextHandle++
        }

        override fun destroy(handle: Long) {
            destroyCalls++
            destroyed += handle
        }

        override fun process(
            handle: Long,
            buffer: ByteBuffer,
            frames: Int,
            channels: Int,
            sampleRate: Double
        ): Int {
            if (processThrows) {
                if (mutateBeforeFailure) {
                    buffer.put(0, 0x7f.toByte())
                }
                throw IllegalStateException("synthetic process failure")
            }
            if (processResult != 0 && mutateBeforeFailure) {
                buffer.put(0, 0x7f.toByte())
            }
            return processResult
        }

        override fun setEnabled(handle: Long, enabled: Boolean) = Unit
    }

    private class FakeRegistryApi : DspEngineRegistry.NativeDspApi {
        override fun setEnabled(handle: Long, enabled: Boolean) = Unit
        override fun setVolume(handle: Long, linearGain: Double) = Unit
        override fun setEqBands(handle: Long, centersHz: DoubleArray?, gainsDb: DoubleArray, enabled: Boolean) = Unit
        override fun setSpeakerMode(handle: Long, enabled: Boolean) = Unit
        override fun setVirtualBass(handle: Long, amount: Double) = Unit
        override fun setPreamp(handle: Long, linearGain: Double) = Unit
        override fun setLimiterCeiling(handle: Long, highDb: Float, lowDb: Float) = Unit
        override fun setCrossoverHz(handle: Long, freqHz: Float) = Unit
    }

    private lateinit var api: FakeProcessorApi

    @Before
    fun setUp() {
        DspSessionGate.resetForTests()
        DspEngineRegistry.resetForTests()
        DspEngineRegistry.nativeApi = FakeRegistryApi()
        api = FakeProcessorApi()
        DspEngineAudioProcessor.nativeApi = api
    }

    @After
    fun tearDown() {
        DspEngineRegistry.resetForTests()
        DspSessionGate.resetForTests()
        DspEngineAudioProcessor.nativeApi = object : DspEngineAudioProcessor.NativeDspApi {
            override fun create(sampleRate: Double, channels: Int) =
                DspEngineJni.nativeCreate(sampleRate, channels)
            override fun destroy(handle: Long) = DspEngineJni.nativeDestroy(handle)
            override fun process(
                handle: Long,
                buffer: ByteBuffer,
                frames: Int,
                channels: Int,
                sampleRate: Double
            ) = DspEngineJni.nativeProcessPcm16Direct(handle, buffer, frames, channels, sampleRate)
            override fun setEnabled(handle: Long, enabled: Boolean) =
                DspEngineJni.nativeSetEnabled(handle, enabled)
        }
    }

    private fun configure(): DspEngineAudioProcessor {
        val processor = DspEngineAudioProcessor()
        processor.setNativeProcessEnabled(true)
        processor.configure(
            AudioProcessor.AudioFormat(
                44100,
                2,
                C.ENCODING_PCM_16BIT
            )
        )
        return processor
    }

    private fun pcm(): ByteBuffer =
        ByteBuffer.allocateDirect(8).apply {
            put(byteArrayOf(1, 2, 3, 4, 5, 6, 7, 8))
            flip()
        }

    private fun outputBytes(processor: DspEngineAudioProcessor): ByteArray {
        val output = processor.output
        val bytes = ByteArray(output.remaining())
        output.get(bytes)
        return bytes
    }

    @Test
    fun native_process_error_restores_exact_original_pcm() {
        val processor = configure()
        api.processResult = -17
        api.mutateBeforeFailure = true

        val source = byteArrayOf(1, 2, 3, 4, 5, 6, 7, 8)
        processor.queueInput(ByteBuffer.allocateDirect(source.size).apply {
            put(source)
            flip()
        })

        assertTrue(outputBytes(processor).contentEquals(source))
        assertEquals(1, api.createCalls)
        assertEquals(1, DspEngineRegistry.activeCount())
    }

    @Test
    fun native_process_exception_restores_exact_original_pcm() {
        val processor = configure()
        api.processThrows = true
        api.mutateBeforeFailure = true

        val source = byteArrayOf(8, 7, 6, 5, 4, 3, 2, 1)
        processor.queueInput(ByteBuffer.allocateDirect(source.size).apply {
            put(source)
            flip()
        })

        assertTrue(outputBytes(processor).contentEquals(source))
        assertEquals(1, api.createCalls)
        assertEquals(1, DspEngineRegistry.activeCount())
    }

    @Test
    fun repeated_process_failures_demote_processor_and_destroy_unregister_handle() {
        val processor = configure()
        api.processResult = -1

        repeat(8) {
            processor.queueInput(pcm())
        }

        assertEquals(1, api.createCalls)
        assertEquals(1, api.destroyCalls)
        assertEquals(listOf(100L), api.destroyed)
        assertEquals(0, DspEngineRegistry.activeCount())

        val callsBefore = api.createCalls
        processor.queueInput(pcm())
        assertEquals(callsBefore, api.createCalls)
        assertFalse(processor.nativeProcessEnabledForTest())
    }

    @Test
    fun format_change_destroys_old_engine_and_creates_new_engine() {
        val processor = configure()

        processor.configure(
            AudioProcessor.AudioFormat(
                48000,
                2,
                C.ENCODING_PCM_16BIT
            )
        )

        assertEquals(2, api.createCalls)
        assertEquals(listOf(100L), api.destroyed)
        assertEquals(1, DspEngineRegistry.activeCount())
    }
}
