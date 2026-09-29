#!/usr/bin/env python3
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
p = ROOT / "lib/providers/equalizer_provider.dart"
t = p.read_text()
old = """  String get dspEngineId => ResonateNativeDspBridge.available
      ? ResonateNativeDspBridge.engineLabel
      : _dspPipeline.id;"""
new = """  /// User-facing name for the in-house engine (never "unknown").
  String get dspEngineId => 'Resonate DSP Engine';
  /// Technical id for diagnostics / logs.
  String get dspEngineTechnicalId => ResonateNativeDspBridge.available
      ? ResonateNativeDspBridge.engineLabel
      : _dspPipeline.id;"""
if old in t:
    p.write_text(t.replace(old, new, 1))
    print("patched dspEngineId")
elif "Resonate DSP Engine" in t and "dspEngineId" in t:
    print("already patched")
else:
    raise SystemExit("pattern not found")
