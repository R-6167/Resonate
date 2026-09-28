#!/usr/bin/env python3
"""Restore MainActivity.kt after accidental PLACEHOLDER overwrite; add live DSP APIs."""
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / "android/app/src/main/kotlin/com/Aetherion/Resonate/MainActivity.kt"
# Last known good blob before PLACEHOLDER commit
GOOD_SHA = "7ad3c5b51b6204448872ad301e0bfc12198e3b3c"

OLD = '''                    "setResonateDspEnabled" -> {
                        resonateDspEnabled = call.argument<Boolean>("enabled") ?: true
                        try {
                            resonateDsp?.enabled = resonateDspEnabled
                        } catch (_: Exception) {
                        }
                        result.success(true)
                    }
                    "release" -> {
                        releaseEffects()
                        result.success(true)
                    }'''

NEW = '''                    "setResonateDspEnabled" -> {
                        resonateDspEnabled = call.argument<Boolean>("enabled") ?: true
                        try {
                            resonateDsp?.enabled = resonateDspEnabled
                        } catch (_: Exception) {
                        }
                        result.success(true)
                    }
                    // ---- Live DSP ENGINE (per-stream A/B via DspEngineRegistry) ----
                    "setLiveDspPreampDb" -> {
                        val db = (call.argument<Number>("db") ?: 0.0).toDouble().coerceIn(-12.0, 12.0)
                        val linear = if (db <= -120.0) 0.0 else Math.pow(10.0, db / 20.0)
                        com.aetherion.resonate.dsp.DspEngineRegistry.applyVolumeAll(linear)
                        result.success(mapOf("ok" to true, "linear" to linear, "active" to com.aetherion.resonate.dsp.DspEngineRegistry.activeCount()))
                    }
                    "setLiveDspEqBands" -> {
                        val centers = (call.argument<List<Double>>("centersHz") ?: emptyList()).toDoubleArray()
                        val gains = (call.argument<List<Double>>("gainsDb") ?: emptyList()).toDoubleArray()
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        com.aetherion.resonate.dsp.DspEngineRegistry.applyEqBandsAll(
                            if (centers.isEmpty()) null else centers,
                            gains,
                            enabled,
                        )
                        result.success(mapOf("ok" to true, "bands" to gains.size, "active" to com.aetherion.resonate.dsp.DspEngineRegistry.activeCount()))
                    }
                    "getLiveDspStatus" -> {
                        result.success(com.aetherion.resonate.dsp.DspEngineRegistry.statusMap())
                    }
                    "release" -> {
                        releaseEffects()
                        result.success(true)
                    }'''

def main() -> None:
    raw = subprocess.check_output(["git", "cat-file", "-p", GOOD_SHA], cwd=ROOT)
    text = raw.decode("utf-8")
    if "setLiveDspPreampDb" in text:
        print("already has live DSP APIs")
        TARGET.write_text(text)
        return
    if OLD not in text:
        raise SystemExit("expected block not found in good blob")
    text = text.replace(OLD, NEW, 1)
    TARGET.write_text(text)
    print("restored+patched MainActivity.kt", TARGET.stat().st_size)

if __name__ == "__main__":
    main()
