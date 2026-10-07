package com.aetherion.resonate.dsp

import org.junit.After
import org.junit.Before
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class DspEngineRegistryTest {
    private open class FakeApi : DspEngineRegistry.NativeDspApi {
        val calls = mutableListOf<String>()

        override fun setEnabled(handle: Long, enabled: Boolean) {
            calls += "enabled:" + handle + ":" + enabled
        }

        override fun setVolume(handle: Long, linearGain: Double) {
            calls += "volume:" + handle + ":" + linearGain
        }

        override fun setEqBands(handle: Long, centersHz: DoubleArray?, gainsDb: DoubleArray, enabled: Boolean) {
            calls += "eq:" + handle + ":" + gainsDb.joinToString(",") + ":" + enabled
        }

        override fun setSpeakerMode(handle: Long, enabled: Boolean) {
            calls += "speaker:" + handle + ":" + enabled
        }

        override fun setVirtualBass(handle: Long, amount: Double) {
            calls += "bass:" + handle + ":" + amount
        }

        override fun setPreamp(handle: Long, linearGain: Double) {
            calls += "preamp:" + handle + ":" + linearGain
        }

        override fun setLimiterCeiling(handle: Long, highDb: Float, lowDb: Float) {
            calls += "limiter:" + handle + ":" + highDb + ":" + lowDb
        }

        override fun setCrossoverHz(handle: Long, freqHz: Float) {
            calls += "crossover:" + handle + ":" + freqHz
        }
    }

    private lateinit var fake: FakeApi

    @Before
    fun setUp() {
        DspEngineRegistry.resetForTests()
        fake = FakeApi()
        DspEngineRegistry.nativeApi = fake
    }

    @After
    fun tearDown() {
        DspEngineRegistry.resetForTests()
    }

    @Test
    fun register_applies_one_coherent_sticky_generation_to_new_engine() {
        DspEngineRegistry.applyVolumeAll(0.72)
        DspEngineRegistry.applyEqBandsAll(
            doubleArrayOf(60.0, 1000.0, 8000.0),
            doubleArrayOf(2.0, -1.5, 3.0),
            true
        )
        DspEngineRegistry.applySpeakerModeAll(true)
        DspEngineRegistry.applyVirtualBassAll(0.81)
        DspEngineRegistry.applyPreampAll(1.35)
        DspEngineRegistry.applyLimiterCeilingAll(-0.8f, -0.3f)
        DspEngineRegistry.applyCrossoverHzAll(140f)

        fake.calls.clear()
        assertTrue(DspEngineRegistry.register(2, 2002L))

        assertEquals(1, DspEngineRegistry.activeCount())
        assertTrue(fake.calls.any { it == "volume:2002:0.72" })
        assertTrue(fake.calls.any { it == "eq:2002:2.0,-1.5,3.0:true" })
        assertTrue(fake.calls.any { it == "speaker:2002:true" })
        assertTrue(fake.calls.any { it == "bass:2002:0.81" })
        assertTrue(fake.calls.any { it == "preamp:2002:1.35" })
        assertTrue(fake.calls.any { it == "limiter:2002:-0.8:-0.3" })
        assertTrue(fake.calls.any { it == "crossover:2002:140.0" })
    }

    @Test
    fun register_rejects_engine_when_sticky_application_fails() {
        val failing = object : FakeApi() {
            override fun setVolume(handle: Long, linearGain: Double) {
                throw IllegalStateException("synthetic JNI failure")
            }
        }
        DspEngineRegistry.nativeApi = failing

        assertFalse(DspEngineRegistry.register(3, 3003L))
        assertEquals(0, DspEngineRegistry.activeCount())
    }

    @Test
    fun live_updates_reach_all_registered_engines() {
        assertTrue(DspEngineRegistry.register(1, 1001L))
        assertTrue(DspEngineRegistry.register(2, 2002L))
        fake.calls.clear()

        DspEngineRegistry.applyPreampAll(1.5)

        assertEquals(
            setOf("preamp:1001:1.5", "preamp:2002:1.5"),
            fake.calls.filter { it.startsWith("preamp:") }.toSet()
        )
    }
}
