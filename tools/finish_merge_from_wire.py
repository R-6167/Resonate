#!/usr/bin/env python3
"""Copy finished DSP from Wire_dsp_engine onto this branch (dj_Mode product)."""
from __future__ import annotations

import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = "https://raw.githubusercontent.com/R-6167/Resonate/Wire_dsp_engine"

# Product paths we MUST NOT overwrite with Wire (library/DJ/playback)
SKIP = {
    "lib/providers/music_provider.dart",
    "lib/providers/library_provider.dart",
    "lib/providers/dj_mode_provider.dart",
    "lib/services/database_helper.dart",
}

COPY = [
    "android/app/src/main/cpp/CMakeLists.txt",
    "android/app/src/main/cpp/dsp_engine.h",
    "android/app/src/main/cpp/dsp_engine_core.cpp",
    "android/app/src/main/cpp/dsp_engine_jni.cpp",
    "android/app/src/main/cpp/dsp_stress.cpp",
    "android/app/src/main/kotlin/com/Aetherion/Resonate/dsp/DspEngineAudioProcessor.kt",
    "android/app/src/main/kotlin/com/Aetherion/Resonate/dsp/DspEngineJni.kt",
    "android/app/src/main/kotlin/com/Aetherion/Resonate/dsp/DspEngineRegistry.kt",
    "android/app/src/main/kotlin/com/Aetherion/Resonate/dsp/DspEngineSinkHook.kt",
    "android/app/src/main/kotlin/com/Aetherion/Resonate/dsp/DspSessionGate.kt",
    "android/app/src/main/kotlin/com/Aetherion/Resonate/MainActivity.kt",
    "android/app/build.gradle",
    "scripts/patch_just_audio_dsp_sink.py",
    "lib/services/audio_effects_bridge.dart",
    "lib/services/equalizer_dvc_sync.dart",
    "lib/services/dsp_engine_bridge.dart",
    "lib/services/dsp_process_path.dart",
    "lib/providers/equalizer_provider.dart",
    "pubspec.yaml",
    ".github/workflows/android-apk.yml",
    ".github/workflows/build_apk.yml",
]


def fetch(rel: str) -> bytes:
    with urllib.request.urlopen(f"{BASE}/{rel}", timeout=120) as r:
        return r.read()


def main() -> None:
    for rel in COPY:
        if rel in SKIP:
            print("skip product", rel)
            continue
        try:
            data = fetch(rel)
        except Exception as e:
            print("FAIL", rel, e)
            continue
        dest = ROOT / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(data)
        print("ok", rel, len(data))

    # Ensure APK workflow builds dj_Mode
    yml = ROOT / ".github/workflows/android-apk.yml"
    if yml.exists():
        t = yml.read_text()
        t2 = t.replace(
            "branches: [Wire_dsp_engine, main]",
            "branches: [dj_Mode, Wire_dsp_engine, main]",
        )
        if t2 != t:
            yml.write_text(t2)
            print("patched android-apk branches for dj_Mode")

    print("finish_merge_from_wire done")


if __name__ == "__main__":
    main()
