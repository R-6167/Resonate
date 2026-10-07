#!/usr/bin/env bash
# Post-copy patches: pubspec, JNI exports, Kotlin, MethodChannel bridge.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# --- pubspec: path dependency ---
if ! grep -q "dsp_engine:" pubspec.yaml; then
  python3 - <<'PY'
from pathlib import Path
p = Path("pubspec.yaml")
t = p.read_text()
needle = "  url_launcher: ^6.3.2\n"
insert = needle + "\n  dsp_engine:\n    path: packages/dsp_engine\n  ffi: ^2.1.0\n"
if needle in t and "dsp_engine:" not in t:
    t = t.replace(needle, insert, 1)
    p.write_text(t)
    print("pubspec dsp_engine path dep")
else:
    print("pubspec skip or already")
PY
fi

# --- JNI: add preamp / limiter / crossover if missing ---
JNI="android/app/src/main/cpp/dsp_engine_jni.cpp"
if [ -f "$JNI" ] && ! grep -q "nativeSetPreamp" "$JNI"; then
  python3 - <<'PY'
from pathlib import Path
p = Path("android/app/src/main/cpp/dsp_engine_jni.cpp")
t = p.read_text()
extra = r'''
extern "C" JNIEXPORT void JNICALL
Java_com_aetherion_resonate_dsp_DspEngineJni_nativeSetPreamp(
    JNIEnv*, jclass, jlong handle, jdouble linearGain) {
    if (!handle) return;
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
  # insert before last stress function or at end before final lines
  if "nativeRunBassStress" in t:
      idx = t.find("Java_com_aetherion_resonate_dsp_DspEngineJni_nativeRunBassStress")
      t = t[:idx] + extra + "\n" + t[idx:]
  else:
      t = t + "\n" + extra
  p.write_text(t)
  print("jni exports added")
else:
  print("jni skip")

# --- Kotlin DspEngineJni ---
KT="android/app/src/main/kotlin/com/Aetherion/Resonate/dsp/DspEngineJni.kt"
# case variants
for cand in \
  "android/app/src/main/kotlin/com/Aetherion/Resonate/dsp/DspEngineJni.kt" \
  "android/app/src/main/kotlin/com/aetherion/resonate/dsp/DspEngineJni.kt"
do
  if [ -f "$cand" ]; then KT="$cand"; break; fi
done

if [ -f "$KT" ] && ! grep -q "nativeSetPreamp" "$KT"; then
  python3 - <<PY
from pathlib import Path
p = Path("$KT")
t = p.read_text()
extra = '''
    external fun nativeSetPreamp(handle: Long, linearGain: Double)
    external fun nativeSetLimiterCeiling(handle: Long, highDb: Float, lowDb: Float)
    external fun nativeSetCrossoverHz(handle: Long, freqHz: Float)
'''
  if "nativeSetVirtualBass" in t:
      t = t.replace(
          "external fun nativeSetVirtualBass(handle: Long, amount: Double)\n",
          "external fun nativeSetVirtualBass(handle: Long, amount: Double)\n" + extra,
          1,
      )
  else:
      t = t.rstrip() + "\n" + extra
  p.write_text(t)
  print("kotlin jni")
else:
  print("kotlin skip")

# --- Registry / processor: apply defaults on create ---
# Best-effort: DspEngineRegistry or AudioProcessor after create
for reg in \
  android/app/src/main/kotlin/com/Aetherion/Resonate/dsp/DspEngineRegistry.kt \
  android/app/src/main/kotlin/com/aetherion/resonate/dsp/DspEngineRegistry.kt
do
  if [ -f "$reg" ] && ! grep -q "nativeSetLimiterCeiling" "$reg"; then
    echo "registry present $reg (manual defaults via channel)"
  fi
done

# --- Dart AudioEffectsBridge methods ---
BR="lib/services/audio_effects_bridge.dart"
if [ -f "$BR" ] && ! grep -q "setLiveDspLimiterCeiling" "$BR"; then
  python3 - <<'PY'
from pathlib import Path
p = Path("lib/services/audio_effects_bridge.dart")
t = p.read_text()
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
  # append before last closing brace of class
  idx = t.rfind("}")
  if idx > 0:
      t = t[:idx] + extra + t[idx:]
      p.write_text(t)
      print("dart bridge")
PY
fi

# --- Docs pointer ---
mkdir -p docs
cat > docs/DSP_V04_INTEGRATION.md <<'MD'
# DSP ENGINE v0.4 on modes_on_dj_v2

Ported from branch `Wire_dsp_engine`.

## Layout

| Path | Role |
|------|------|
| `packages/dsp_engine` | Flutter FFI package (Dart control / diagnostics) |
| `include/` + `src/` | Native sources for package CMake |
| `android/app/src/main/cpp/` | Live process path (just_audio AudioProcessor + JNI) |

## Process chain (v0.4)

```text
PCM → EQ → speaker/bass → auto headroom → limiter → soft clip → DVC → out
```

## App wiring

- Live audio still goes through `DspEngineSinkHook` → `DspEngineAudioProcessor` → JNI → `dsp_process`.
- EQ / speaker / virtual bass / preamp use existing MethodChannel + new limiter/crossover APIs.
- Dual A/B engines keep independent native handles for crossfade.

## Verify

1. Build release APK on `modes_on_dj_v2`.
2. Enable EQ + speaker mode; confirm no silence on crossfade.
3. Optional: call `DspEngine` FFI from a debug screen for stats.
MD

echo "port script done"
