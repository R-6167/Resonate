package com.aetherion.resonate.dsp

import org.junit.After
import org.junit.Before
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class DspEngineRegistryTest {
    private open class FakeApi : DspEngineRegistry.NativeDspApi {
        val calls = mutableListOf<String>()

        override fun setEnabled(handle: Long, enabled: Boolean) {
            calls += "eq-enabled:" + handle + ":" + enabled
        }

        override fun setProcessingEnabled(handle: Long, enabled: Boolean) {
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
    @Test
    fun dvc_gain_is_clamped_and_inherited_by_new_engines() {
        DspEngineRegistry.applyVolumeAll(99.0)
        assertTrue(fake.calls.none { it.startsWith("volume:") })

        fake.calls.clear()
        assertTrue(DspEngineRegistry.register(7, 7007L))
        assertTrue(fake.calls.contains("volume:7007:4.0"))

        fake.calls.clear()
        DspEngineRegistry.applyVolumeAll(-2.0)
        assertTrue(fake.calls.contains("volume:7007:0.0"))
    }

    @Test
    fun setting_update_cannot_miss_engine_being_registered() {
        val enteredRegister = CountDownLatch(1)
        val releaseRegister = CountDownLatch(1)
        val blocking = object : FakeApi() {
            override fun setVolume(handle: Long, linearGain: Double) {
                if (handle == 2002L && enteredRegister.count > 0) {
                    enteredRegister.countDown()
                    check(releaseRegister.await(2, TimeUnit.SECONDS)) {
                        "test timed out waiting to release registration"
                    }
                }
                super.setVolume(handle, linearGain)
            }
        }
        DspEngineRegistry.nativeApi = blocking

        val registerThread = Thread {
            check(DspEngineRegistry.register(2, 2002L))
        }
        registerThread.start()
        assertTrue(enteredRegister.await(2, TimeUnit.SECONDS))

        val updateDone = CountDownLatch(1)
        val updateThread = Thread {
            try {
                DspEngineRegistry.applyVolumeAll(0.42)
            } finally {
                updateDone.countDown()
            }
        }
        updateThread.start()

        // The update must block while registration is applying its sticky snapshot.
        // Without the shared lock, it can finish now and miss the unpublished handle.
        val updateWasBlocked = !updateDone.await(100, TimeUnit.MILLISECONDS)
        releaseRegister.countDown()
        registerThread.join(2000)
        updateThread.join(2000)
        assertFalse(registerThread.isAlive)
        assertFalse(updateThread.isAlive)
        assertTrue(updateWasBlocked)

        assertTrue(blocking.calls.any { it == "volume:2002:0.42" })
        blocking.calls.clear()
        assertTrue(DspEngineRegistry.register(3, 3003L))
        assertTrue(blocking.calls.any { it == "volume:3003:0.42" })
    }


    @Test
    fun master_enable_updates_live_engines_and_is_inherited_by_new_engines() {
        assertTrue(DspEngineRegistry.register(1, 1001L))
        DspEngineRegistry.applyEnabledAll(false)
        assertTrue(fake.calls.any { it == "enabled:1001:false" })

        fake.calls.clear()
        assertTrue(DspEngineRegistry.register(2, 2002L))
        assertTrue(fake.calls.any { it == "enabled:2002:false" })

        fake.calls.clear()
        DspEngineRegistry.applyEnabledAll(true)
        assertTrue(fake.calls.any { it == "enabled:1001:true" })
        assertTrue(fake.calls.any { it == "enabled:2002:true" })
    }

    @Test
    fun limiter_and_crossover_updates_are_clamped_and_sticky_for_both_engines() {
        assertTrue(DspEngineRegistry.register(1, 1001L))
        assertTrue(DspEngineRegistry.register(2, 2002L))
        fake.calls.clear()

        DspEngineRegistry.applyLimiterCeilingAll(-99f, 1f)
        DspEngineRegistry.applyCrossoverHzAll(900f)

        assertTrue(fake.calls.contains("limiter:1001:-6.0:-0.1"))
        assertTrue(fake.calls.contains("limiter:2002:-6.0:-0.1"))
        assertTrue(fake.calls.contains("crossover:1001:200.0"))
        assertTrue(fake.calls.contains("crossover:2002:200.0"))

        fake.calls.clear()
        assertTrue(DspEngineRegistry.register(3, 3003L))
        assertTrue(fake.calls.contains("limiter:3003:-6.0:-0.1"))
        assertTrue(fake.calls.contains("crossover:3003:200.0"))
    }

}
