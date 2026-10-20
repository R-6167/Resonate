package com.Aetherion.Resonate

import com.aetherion.resonate.dsp.DspEngineRegistry
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Owns the Flutter-to-native boundary for live DSP controls.
 *
 * This handler only translates channel arguments into registry operations; native
 * processor ownership and sticky A/B state remain inside DspEngineRegistry.
 */
internal class LiveDspChannelHandler {
    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setLiveDspPreampDb" -> {
                val db = (call.argument<Number>("db") ?: 0.0).toDouble().coerceIn(-12.0, 12.0)
                val linear = Math.pow(10.0, db / 20.0)
                DspEngineRegistry.applyPreampAll(linear)
                result.success(mapOf("ok" to true, "linear" to linear, "active" to DspEngineRegistry.activeCount()))
            }
            "setLiveDspLimiterCeiling" -> {
                val high = (call.argument<Number>("highDb") ?: -0.5).toFloat()
                val low = (call.argument<Number>("lowDb") ?: -0.2).toFloat()
                DspEngineRegistry.applyLimiterCeilingAll(high, low)
                result.success(mapOf("ok" to true, "highDb" to high, "lowDb" to low))
            }
            "setLiveDspCrossoverHz" -> {
                val hz = (call.argument<Number>("hz") ?: 120.0).toFloat()
                DspEngineRegistry.applyCrossoverHzAll(hz)
                result.success(mapOf("ok" to true, "hz" to hz))
            }
            "setLiveDspEqBands" -> {
                val centers = (call.argument<List<Double>>("centersHz") ?: emptyList()).toDoubleArray()
                val gains = (call.argument<List<Double>>("gainsDb") ?: emptyList()).toDoubleArray()
                val enabled = call.argument<Boolean>("enabled") ?: true
                DspEngineRegistry.applyEqBandsAll(
                    if (centers.isEmpty()) null else centers,
                    gains,
                    enabled,
                )
                result.success(mapOf("ok" to true, "bands" to gains.size, "active" to DspEngineRegistry.activeCount()))
            }
            "setLiveDspSpeakerMode" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                DspEngineRegistry.applySpeakerModeAll(enabled)
                result.success(mapOf(
                    "ok" to true,
                    "enabled" to enabled,
                    "active" to DspEngineRegistry.activeCount(),
                ))
            }
            "setLiveDspVirtualBass" -> {
                val amount = (call.argument<Number>("amount") ?: 0.55).toDouble().coerceIn(0.0, 1.0)
                DspEngineRegistry.applyVirtualBassAll(amount)
                result.success(mapOf("ok" to true, "amount" to amount))
            }
            "getLiveDspStatus" -> result.success(DspEngineRegistry.statusMap())
            else -> result.notImplemented()
        }
    }
}
