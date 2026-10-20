#!/usr/bin/env python3
"""Connect DSP ENGINE v0.4 APIs through JNI → Kotlin → Registry → MethodChannel."""
from pathlib import Path
import os

ROOT = Path(__file__).resolve().parents[1]

# --- JNI ---
jni = ROOT / "android/app/src/main/cpp/dsp_engine_jni.cpp"
t = jni.read_text()
if "nativeSetPreamp" not in t:
    extra = r'''
extern "C" JNIEXPORT void JNICALL
Java_com_aetherion_resonate_dsp_DspEngineJni_nativeSetPreamp(
        JNIEnv*, jclass, jlong handle, jdouble linearGain) {
    if (!handle) return;
    if (linearGain < 0.0) linearGain = 0.0;
    if (linearGain > 4.0) linearGain = 4.0;
    dsp_set_preamp(reinterpret_cast<void*>(handle), linearGain);
}

extern "C" JNIEXPORT void JNICALL
Java_com_aetherion_resonate_dsp_DspEngineJni_nativeSetLimiterCeiling(
        JNIEnv*, jclass, jlong handle, jfloat highDb, jfloat lowDb) {
    if (!handle) return;
    dsp_set_limiter_ceiling(reinterpret_cast<void*>(handle), highDb, lowDb);
}

extern "C" JNIEXPORT void JNICALL
Java_com_aetherion_resonate_dsp_DspEngineJni_nativeSetCrossoverHz(
        JNIEnv*, jclass, jlong handle, jfloat freqHz) {
    if (!handle) return;
    dsp_set_crossover_hz(reinterpret_cast<void*>(handle), freqHz);
}
'''
    idx = t.find("Java_com_aetherion_resonate_dsp_DspEngineJni_nativeRunBassStress")
    t = (t[:idx] + extra + "\n" + t[idx:]) if idx >= 0 else t + extra
    jni.write_text(t)
    print("jni ok")
else:
    print("jni already")

# --- Kotlin DspEngineJni ---
for root, _, files in os.walk(ROOT / "android"):
    for f in files:
        if f != "DspEngineJni.kt":
            continue
        path = Path(root) / f
        kt = path.read_text()
        if "nativeSetPreamp" in kt:
            print("kotlin already")
            continue
        kt = kt.replace(
            "external fun nativeSetVirtualBass(handle: Long, amount: Double)\n",
            "external fun nativeSetVirtualBass(handle: Long, amount: Double)\n"
            "    external fun nativeSetPreamp(handle: Long, linearGain: Double)\n"
            "    external fun nativeSetLimiterCeiling(handle: Long, highDb: Float, lowDb: Float)\n"
            "    external fun nativeSetCrossoverHz(handle: Long, freqHz: Float)\n",
            1,
        )
        path.write_text(kt)
        print("kotlin", path)

# --- Registry ---
reg = None
for root, _, files in os.walk(ROOT / "android"):
    for f in files:
        if f == "DspEngineRegistry.kt":
            reg = Path(root) / f
if reg and reg.exists():
    rt = reg.read_text()
    if "applyPreampAll" not in rt:
        # sticky fields near stickyVirtualBass
        if "stickyVirtualBass" in rt and "stickyPreamp" not in rt:
            rt = rt.replace(
                "private var stickyVirtualBass: Double = 0.55",
                "private var stickyVirtualBass: Double = 0.55\n"
                "    private var stickyPreamp: Double = 1.0\n"
                "    private var stickyLimiterHigh: Float = -0.5f\n"
                "    private var stickyLimiterLow: Float = -0.2f\n"
                "    private var stickyCrossoverHz: Float = 120f",
                1,
            )
        # applyStickyToHandle
        if "nativeSetVirtualBass(handle, stickyVirtualBass)" in rt and "nativeSetPreamp" not in rt:
            rt = rt.replace(
                "DspEngineJni.nativeSetVirtualBass(handle, stickyVirtualBass)\n",
                "DspEngineJni.nativeSetVirtualBass(handle, stickyVirtualBass)\n"
                "            DspEngineJni.nativeSetPreamp(handle, stickyPreamp)\n"
                "            DspEngineJni.nativeSetLimiterCeiling(handle, stickyLimiterHigh, stickyLimiterLow)\n"
                "            DspEngineJni.nativeSetCrossoverHz(handle, stickyCrossoverHz)\n",
                1,
            )
        # methods before closing of object
        methods = '''
    /** True preamp (v0.4) — separate from DVC/volume. */
    @JvmStatic
    fun applyPreampAll(linearGain: Double) {
        val g = linearGain.coerceIn(0.0, 4.0)
        stickyPreamp = g
        val list = snapshotHandles()
        for (h in list) {
            try {
                DspEngineJni.nativeSetPreamp(h, g)
            } catch (t: Throwable) {
                Log.w(TAG, "setPreamp failed handle=$h", t)
            }
        }
        Log.i(TAG, "applyPreampAll gain=$g targets=${list.size}")
    }

    @JvmStatic
    fun applyLimiterCeilingAll(highDb: Float, lowDb: Float) {
        stickyLimiterHigh = highDb.coerceIn(-6f, -0.1f)
        stickyLimiterLow = lowDb.coerceIn(-6f, -0.1f)
        val list = snapshotHandles()
        for (h in list) {
            try {
                DspEngineJni.nativeSetLimiterCeiling(h, stickyLimiterHigh, stickyLimiterLow)
            } catch (t: Throwable) {
                Log.w(TAG, "setLimiter failed handle=$h", t)
            }
        }
    }

    @JvmStatic
    fun applyCrossoverHzAll(hz: Float) {
        stickyCrossoverHz = hz.coerceIn(80f, 200f)
        val list = snapshotHandles()
        for (h in list) {
            try {
                DspEngineJni.nativeSetCrossoverHz(h, stickyCrossoverHz)
            } catch (t: Throwable) {
                Log.w(TAG, "setCrossover failed handle=$h", t)
            }
        }
    }
'''
        # insert before last closing braces of file
        if "fun applyPreampAll" not in rt:
            # insert before final closing of object - find last statusMap or applyVolumeAll block end
            marker = "    /** Preamp / DVC — linear gain (1.0 = unity). Call off the audio thread. */"
            if marker in rt:
                rt = rt.replace(marker, methods + "\n" + marker, 1)
            else:
                idx = rt.rfind("}")
                # object closes with }
                rt = rt[:idx] + methods + "\n" + rt[idx:]
        reg.write_text(rt)
        print("registry ok")
    else:
        print("registry already")

# --- MainActivity: preamp uses applyPreampAll ---
for root, _, files in os.walk(ROOT / "android"):
    for f in files:
        if f != "MainActivity.kt":
            continue
        path = Path(root) / f
        mt = path.read_text()
        old = '''                    "setLiveDspPreampDb" -> {
                        val db = (call.argument<Number>("db") ?: 0.0).toDouble().coerceIn(-12.0, 12.0)
                        val linear = if (db <= -120.0) 0.0 else Math.pow(10.0, db / 20.0)
                        com.aetherion.resonate.dsp.DspEngineRegistry.applyVolumeAll(linear)
                        result.success(mapOf("ok" to true, "linear" to linear, "active" to com.aetherion.resonate.dsp.DspEngineRegistry.activeCount()))
                    }'''
        new = '''                    "setLiveDspPreampDb" -> {
                        val db = (call.argument<Number>("db") ?: 0.0).toDouble().coerceIn(-12.0, 12.0)
                        val linear = if (db <= -120.0) 0.0 else Math.pow(10.0, db / 20.0)
                        // v0.4: preamp is independent of DVC/volume
                        com.aetherion.resonate.dsp.DspEngineRegistry.applyPreampAll(linear)
                        result.success(mapOf("ok" to true, "linear" to linear, "active" to com.aetherion.resonate.dsp.DspEngineRegistry.activeCount()))
                    }
                    "setLiveDspLimiterCeiling" -> {
                        val high = (call.argument<Number>("highDb") ?: -0.5).toFloat()
                        val low = (call.argument<Number>("lowDb") ?: -0.2).toFloat()
                        com.aetherion.resonate.dsp.DspEngineRegistry.applyLimiterCeilingAll(high, low)
                        result.success(mapOf("ok" to true, "highDb" to high, "lowDb" to low))
                    }
                    "setLiveDspCrossoverHz" -> {
                        val hz = (call.argument<Number>("hz") ?: 120.0).toFloat()
                        com.aetherion.resonate.dsp.DspEngineRegistry.applyCrossoverHzAll(hz)
                        result.success(mapOf("ok" to true, "hz" to hz))
                    }'''
        if old in mt:
            mt = mt.replace(old, new, 1)
            path.write_text(mt)
            print("MainActivity ok")
        elif "applyPreampAll" in mt:
            print("MainActivity already")
        else:
            print("WARN MainActivity pattern miss")

# Dart bridge optional methods
br = ROOT / "lib/services/audio_effects_bridge.dart"
if br.exists() and "setLiveDspLimiterCeiling" not in br.read_text():
    bt = br.read_text()
    extra = '''
  static Future<Map<String, dynamic>?> setLiveDspLimiterCeiling({
    required double highDb,
    required double lowDb,
  }) async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('setLiveDspLimiterCeiling', {
        'highDb': highDb,
        'lowDb': lowDb,
      });
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (e) {
      debugPrint('setLiveDspLimiterCeiling failed: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> setLiveDspCrossoverHz(double hz) async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('setLiveDspCrossoverHz', {
        'hz': hz,
      });
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (e) {
      debugPrint('setLiveDspCrossoverHz failed: $e');
    }
    return null;
  }
'''
    idx = bt.rfind("}")
    bt = bt[:idx] + extra + bt[idx:]
    br.write_text(bt)
    print("bridge ok")

print("wire complete")
