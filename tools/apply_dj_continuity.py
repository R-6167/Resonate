#!/usr/bin/env python3
from pathlib import Path
P = Path(__file__).resolve().parents[1] / "lib/services/intelligence_decision_engine.dart"

def main() -> int:
    t = P.read_text()
    if "rel <= 0.08" in t and "djContinuityOn" in t:
        print("continuity already"); return 0
    t = t.replace(
        """    final djEnabled = await DjModeSettingsStore.enabled();
    final harmonicOn = djEnabled && await DjModeSettingsStore.harmonicMix();
    DjAnalysis? currentDj;
    final Map<String, DjAnalysis> djById = <String, DjAnalysis>{};
    if (harmonicOn) {
""",
        """    final djEnabled = await DjModeSettingsStore.enabled();
    final harmonicOn = djEnabled && await DjModeSettingsStore.harmonicMix();
    final djContinuityOn = djEnabled;
    DjAnalysis? currentDj;
    final Map<String, DjAnalysis> djById = <String, DjAnalysis>{};
    if (djContinuityOn) {
""",
        1,
    )
    old = """      if (harmonicOn && currentDj != null && currentDj.hasUsableKey) {
        final cand = djById[r.song.id];
        if (cand != null && cand.hasUsableKey) {
          final compat = harmonicCompatibility(
            rootA: currentDj.keyRoot,
            modeA: currentDj.keyMode,
            rootB: cand.keyRoot,
            modeB: cand.keyMode,
          );
          value += harmonicDecisionBoost(compat);
        }
      }
"""
    new = """      if (djContinuityOn && currentDj != null) {
        final cand = djById[r.song.id];
        if (cand != null) {
          if (currentDj.hasUsableKey && cand.hasUsableKey) {
            final compat = harmonicCompatibility(
              rootA: currentDj.keyRoot,
              modeA: currentDj.keyMode,
              rootB: cand.keyRoot,
              modeB: cand.keyMode,
            );
            value += harmonicDecisionBoost(compat);
          }
          if (currentDj.hasUsableBpm && cand.hasUsableBpm) {
            final a = currentDj.bpm!;
            final b = cand.bpm!;
            final rel = (a - b).abs() / a;
            if (rel <= 0.08) {
              value += 1.15;
            } else if (rel <= 0.12) {
              value += 0.55;
            } else if (rel <= 0.20) {
              value += 0.2;
            }
          }
        }
      }
"""
    if old in t:
        t = t.replace(old, new, 1)
    P.write_text(t)
    print("continuity applied", P.stat().st_size)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
