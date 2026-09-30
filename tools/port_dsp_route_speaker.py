#!/usr/bin/env python3
"""Patch MainActivity + EqualizerProvider for speaker mode / route / DVC sync."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# --- MainActivity: add setLiveDspSpeakerMode + setLiveDspVirtualBass ---
ma = ROOT / "android/app/src/main/kotlin/com/Aetherion/Resonate/MainActivity.kt"
t = ma.read_text()

if "setLiveDspSpeakerMode" not in t:
    needle = '''                    "getLiveDspStatus" -> {
                        result.success(com.aetherion.resonate.dsp.DspEngineRegistry.statusMap())
                    }'''
    insert = '''                    "setLiveDspSpeakerMode" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        com.aetherion.resonate.dsp.DspEngineRegistry.applySpeakerModeAll(enabled)
                        result.success(mapOf(
                            "ok" to true,
                            "enabled" to enabled,
                            "active" to com.aetherion.resonate.dsp.DspEngineRegistry.activeCount(),
                        ))
                    }
                    "setLiveDspVirtualBass" -> {
                        val amount = (call.argument<Number>("amount") ?: 0.55).toDouble().coerceIn(0.0, 1.0)
                        com.aetherion.resonate.dsp.DspEngineRegistry.applyVirtualBassAll(amount)
                        result.success(mapOf("ok" to true, "amount" to amount))
                    }
                    "getLiveDspStatus" -> {
                        result.success(com.aetherion.resonate.dsp.DspEngineRegistry.statusMap())
                    }'''
    if needle not in t:
        raise SystemExit("MainActivity getLiveDspStatus block not found")
    t = t.replace(needle, insert, 1)
    ma.write_text(t)
    print("MainActivity: added speakerMode + virtualBass handlers")
else:
    print("MainActivity: already has speakerMode")

# --- EqualizerProvider: route listener + DVC sync helpers ---
eq = ROOT / "lib/providers/equalizer_provider.dart"
t = eq.read_text()

if "audio_output_route.dart" not in t:
    t = t.replace(
        "import '../services/audio_effects_bridge.dart';",
        "import '../services/audio_effects_bridge.dart';\n"
        "import '../services/audio_output_route.dart';\n"
        "import '../services/equalizer_dvc_sync.dart';",
        1,
    )
    print("eq: imports added")

if "_onOutputRouteChanged" not in t:
    # After _bluetooth?.addListener in constructor
    old = "    _bluetooth?.addListener(_onBluetoothChanged);"
    new = '''    _bluetooth?.addListener(_onBluetoothChanged);
    // Output route → speaker protection / virtual bass on live DSP engines.
    unawaited(AudioOutputRouteService.instance.start());
    AudioOutputRouteService.instance.addListener(_onOutputRouteChanged);
    _onOutputRouteChanged();'''
    if old not in t:
        raise SystemExit("eq constructor anchor not found")
    t = t.replace(old, new, 1)
    print("eq: route start wired")

if "void _onOutputRouteChanged()" not in t:
    # Insert after _onBluetoothChanged method
    anchor = "  void _onBluetoothChanged() {"
    idx = t.find(anchor)
    if idx < 0:
        raise SystemExit("eq _onBluetoothChanged not found")
    # find end of method (next method at same indent)
    end = t.find("\n  bool get btProfilesEnabled", idx)
    if end < 0:
        end = t.find("\n  Future<void> setNativeDspEnabled", idx)
    if end < 0:
        raise SystemExit("eq insert point after bluetooth not found")
    method = '''
  void _onOutputRouteChanged() {
    final route = AudioOutputRouteService.instance;
    syncSpeakerPolicy(
      needsSpeakerProtection: route.needsSpeakerProtection,
      virtualBassAmount: 0.55,
    );
  }

'''
    t = t[:end] + method + t[end:]
    print("eq: _onOutputRouteChanged added")

# Prefer sync helpers inside existing live pushes (idempotent replace)
if "syncStudioBandsToNativeEq" not in t:
    old_eq = '''      AudioEffectsBridge.setLiveDspEqBands(
        centersHz: centersLive,
        gainsDb: studioGainsLive,
        enabled: isEnabled,
      );'''
    new_eq = '''      syncStudioBandsToNativeEq(
        centersHz: centersLive,
        gainsDb: studioGainsLive,
        enabled: isEnabled,
      );'''
    if old_eq in t:
        t = t.replace(old_eq, new_eq, 1)
        print("eq: live EQ uses syncStudioBandsToNativeEq")

if "syncPreampToDvc" not in t:
    old_p = "      AudioEffectsBridge.setLiveDspPreampDb(effective);"
    new_p = "      syncPreampToDvc(effective, enabled: isEnabled);"
    if old_p in t:
        t = t.replace(old_p, new_p, 1)
        print("eq: preamp uses syncPreampToDvc")

eq.write_text(t)
print("done")
