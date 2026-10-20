#!/usr/bin/env python3
"""Copy live DSP stack from Wire_dsp_engine onto dj_Mode; keep library/DJ intact."""
from __future__ import annotations

import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = "https://raw.githubusercontent.com/R-6167/Resonate/Wire_dsp_engine"

COPY_PATHS = [
    "android/app/src/main/cpp/CMakeLists.txt",
    "android/app/src/main/cpp/dsp_engine_jni.cpp",
    "android/app/src/main/kotlin/com/Aetherion/Resonate/dsp/DspEngineAudioProcessor.kt",
    "android/app/src/main/kotlin/com/Aetherion/Resonate/dsp/DspEngineJni.kt",
    "android/app/src/main/kotlin/com/Aetherion/Resonate/dsp/DspEngineSinkHook.kt",
    "android/app/src/main/kotlin/com/Aetherion/Resonate/dsp/DspSessionGate.kt",
    "android/app/src/main/kotlin/com/Aetherion/Resonate/dsp/DspEngineRegistry.kt",
    "scripts/patch_just_audio_dsp_sink.py",
]

BUILD_GRADLE = '''plugins {
    id "com.android.application"
    id "kotlin-android"
    id "dev.flutter.flutter-gradle-plugin"
}

android {
    namespace = "com.Aetherion.Resonate"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    defaultConfig {
        applicationId = "com.Aetherion.Resonate"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        externalNativeBuild {
            cmake {
                cppFlags "-std=c++17 -O3 -fPIC"
                arguments "-DANDROID_STL=c++_shared"
            }
        }

        ndk {
            abiFilters "arm64-v8a", "armeabi-v7a"
        }
    }

    externalNativeBuild {
        cmake {
            path "src/main/cpp/CMakeLists.txt"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildTypes {
        release {
            minifyEnabled false
            shrinkResources false
            signingConfig = signingConfigs.debug
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation "androidx.media3:media3-common:1.5.1"
}
'''

ANDROID_APK_YML = r'''name: Android APK

on:
  push:
    branches: [dj_Mode, Wire_dsp_engine, main]
  pull_request:
    branches: [dj_Mode, Wire_dsp_engine, main]
  workflow_dispatch:

concurrency:
  group: android-apk-${{ github.ref }}
  cancel-in-progress: true

jobs:
  build:
    name: Build debug APK
    runs-on: ubuntu-latest
    timeout-minutes: 60

    steps:
      - name: Checkout Resonate
        uses: actions/checkout@v4

      - name: Setup Java 17
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: "17"

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true

      - name: Flutter version
        run: flutter --version

      - name: Pub get
        run: flutter pub get

      - name: Patch just_audio for DSP AudioProcessor injection
        run: |
          set +e
          python3 scripts/patch_just_audio_dsp_sink.py
          rc=$?
          set -e
          if [ "$rc" -eq 1 ]; then
            echo "FATAL: AudioPlayer.java missing after pub get"
            exit 1
          fi
          echo "patch_just_audio exit=$rc"

      - name: Analyze (non-blocking)
        continue-on-error: true
        run: flutter analyze --no-fatal-infos || true

      - name: Build APK (debug)
        run: flutter build apk --debug --no-tree-shake-icons

      - name: List outputs
        run: find build/app/outputs -type f -name "*.apk" -ls || true

      - name: Upload APK
        uses: actions/upload-artifact@v4
        with:
          name: resonate-debug-apk
          path: build/app/outputs/flutter-apk/*.apk
          if-no-files-found: error
          retention-days: 14
'''

LIVE_METHODS = '''
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
'''

AUDIO_EFFECTS_BRIDGE = '''import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AudioEffectsBridge {
  static const MethodChannel _channel =
      MethodChannel('com.aetherion.resonate/audio_effects');

  static Future<void> attachToSession(int sessionId) async {
    if (sessionId <= 0) return;
    try {
      await _channel.invokeMethod('attachToSession', {'sessionId': sessionId});
    } catch (e) {
      debugPrint('AudioEffectsBridge.attachToSession failed: $e');
    }
  }

  static Future<void> setBassBoost(double strength) async {
    try {
      final s = (strength.clamp(0.0, 1.0) * 1000).round();
      await _channel.invokeMethod('setBassBoost', {'strength': s});
    } catch (e) {
      debugPrint('setBassBoost failed: $e');
    }
  }

  static Future<void> setVirtualizer(double strength) async {
    try {
      final s = (strength.clamp(0.0, 1.0) * 1000).round();
      await _channel.invokeMethod('setVirtualizer', {'strength': s});
    } catch (e) {
      debugPrint('setVirtualizer failed: $e');
    }
  }

  static Future<void> setReverb(double strength) async {
    try {
      final s = (strength.clamp(0.0, 1.0) * 1900 - 900).round();
      await _channel.invokeMethod('setReverb', {'strength': s});
    } catch (e) {
      debugPrint('setReverb failed: $e');
    }
  }

  static Future<Map<String, dynamic>?> setLiveDspPreampDb(double db) async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('setLiveDspPreampDb', {
        'db': db.clamp(-12.0, 12.0),
      });
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (e) {
      debugPrint('setLiveDspPreampDb failed: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> setLiveDspEqBands({
    List<double>? centersHz,
    required List<double> gainsDb,
    bool enabled = true,
  }) async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('setLiveDspEqBands', {
        if (centersHz != null) 'centersHz': centersHz,
        'gainsDb': gainsDb,
        'enabled': enabled,
      });
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (e) {
      debugPrint('setLiveDspEqBands failed: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> getLiveDspStatus() async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('getLiveDspStatus');
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (e) {
      debugPrint('getLiveDspStatus failed: $e');
    }
    return null;
  }

  static Future<void> release() async {
    try {
      await _channel.invokeMethod('release');
    } catch (_) {}
  }
}
'''


def fetch(rel: str) -> bytes:
    url = f"{BASE}/{rel}"
    with urllib.request.urlopen(url, timeout=90) as r:
        return r.read()


def main() -> None:
    for rel in COPY_PATHS:
        try:
            data = fetch(rel)
        except Exception as e:
            print("skip", rel, e)
            continue
        dest = ROOT / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(data)
        print("copied", rel, len(data))

    (ROOT / "android/app/build.gradle").write_text(BUILD_GRADLE)
    print("wrote build.gradle with NDK/cmake")

    (ROOT / ".github/workflows/android-apk.yml").parent.mkdir(parents=True, exist_ok=True)
    (ROOT / ".github/workflows/android-apk.yml").write_text(ANDROID_APK_YML)
    print("wrote android-apk.yml")

    (ROOT / "lib/services/audio_effects_bridge.dart").write_text(AUDIO_EFFECTS_BRIDGE)
    print("wrote audio_effects_bridge.dart")

    ma = ROOT / "android/app/src/main/kotlin/com/Aetherion/Resonate/MainActivity.kt"
    text = ma.read_text()
    if "setLiveDspPreampDb" not in text:
        needle = '                    "release" -> {\n                        releaseEffects()\n                        result.success(true)\n                    }'
        if needle not in text:
            raise SystemExit("MainActivity release block not found")
        text = text.replace(needle, LIVE_METHODS + "\n" + needle, 1)
        ma.write_text(text)
        print("patched MainActivity live DSP methods")
    else:
        print("MainActivity already has live DSP methods")

    eq = ROOT / "lib/providers/equalizer_provider.dart"
    et = eq.read_text()
    if "setLiveDspEqBands" not in et:
        if "audio_effects_bridge" not in et:
            lines = et.splitlines(True)
            insert_at = 0
            for i, line in enumerate(lines):
                if line.startswith("import "):
                    insert_at = i + 1
            lines.insert(insert_at, "import '../services/audio_effects_bridge.dart';\n")
            et = "".join(lines)

        old_push = "  Future<void> _pushToHardware() async {\n    if (!_hardwareBound) return;"
        new_push = (
            "  Future<void> _pushToHardware() async {\n"
            "    // Live DSP ENGINE (A/B sinks) — sticky even if hardware not bound yet.\n"
            "    try {\n"
            "      final studioGainsLive = studioBands.map((b) => b.gainDb).toList();\n"
            "      final centersLive = studioBands.map((b) => b.frequencyHz).toList();\n"
            "      // ignore: unawaited_futures\n"
            "      AudioEffectsBridge.setLiveDspEqBands(\n"
            "        centersHz: centersLive,\n"
            "        gainsDb: studioGainsLive,\n"
            "        enabled: isEnabled,\n"
            "      );\n"
            "    } catch (e) {\n"
            "      debugPrint('live DSP EQ push failed: $e');\n"
            "    }\n"
            "    if (!_hardwareBound) return;"
        )
        if old_push not in et:
            raise SystemExit("_pushToHardware header not found")
        et = et.replace(old_push, new_push, 1)

        old_pre = (
            "    final effective = isEnabled ? preamp.clamp(-6.0, 6.0) : 0.0;\n"
            "    final cutDb = effective < 0 ? effective : 0.0;"
        )
        new_pre = (
            "    final effective = isEnabled ? preamp.clamp(-6.0, 6.0) : 0.0;\n"
            "    try {\n"
            "      // ignore: unawaited_futures\n"
            "      AudioEffectsBridge.setLiveDspPreampDb(effective);\n"
            "    } catch (_) {}\n"
            "    final cutDb = effective < 0 ? effective : 0.0;"
        )
        if old_pre not in et:
            raise SystemExit("_applyPreamp effective line not found")
        et = et.replace(old_pre, new_pre, 1)
        eq.write_text(et)
        print("patched equalizer_provider live DSP")
    else:
        print("equalizer_provider already wired")

    print("port_dsp_onto_dj_mode done")


if __name__ == "__main__":
    main()
