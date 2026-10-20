package com.aetherion.resonate.dsp

import org.junit.After
import org.junit.Before
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class DspSessionGateTest {
    @Before
    fun setUp() {
        DspSessionGate.resetForTests()
    }

    @After
    fun tearDown() {
        DspSessionGate.resetForTests()
    }

    @Test
    fun create_failures_are_processor_local_and_do_not_trip_gate() {
        repeat(3) { DspSessionGate.noteCreateFailure("synthetic") }

        assertTrue(DspSessionGate.isNativeAllowed())
        assertFalse(DspSessionGate.isTripped())
        assertEquals(3, DspSessionGate.createFailureCount())
    }

    @Test
    fun successful_create_clears_failure_diagnostics() {
        DspSessionGate.noteCreateFailure("synthetic")
        DspSessionGate.noteCreateFailure("synthetic")

        DspSessionGate.noteCreateSuccess()

        assertEquals(0, DspSessionGate.createFailureCount())
        assertTrue(DspSessionGate.isNativeAllowed())
    }

    @Test
    fun explicit_trip_is_process_wide_and_resettable() {
        DspSessionGate.trip("synthetic native ABI failure")

        assertFalse(DspSessionGate.isNativeAllowed())
        assertTrue(DspSessionGate.isTripped())

        DspSessionGate.resetForTests()

        assertTrue(DspSessionGate.isNativeAllowed())
        assertFalse(DspSessionGate.isTripped())
    }
}
