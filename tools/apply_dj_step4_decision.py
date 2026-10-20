#!/usr/bin/env python3
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
P = ROOT / "lib/services/intelligence_decision_engine.dart"

def main() -> int:
    t = P.read_text()
    if "harmonicDecisionBoost" in t:
        print("step4 decision already"); return 0
    if "intelligence_settings_store.dart" not in t:
        print("unexpected"); return 1
    t = t.replace(
        "import 'intelligence_settings_store.dart';",
        "import 'intelligence_settings_store.dart';\n"
        "import 'dj_mode_settings_store.dart';\n"
        "import 'dj_harmonic.dart';\n"
        "import '../models/dj_analysis.dart';",
        1,
    )
    inject = """
    // DJ Mode Step 4: optional soft key bias (off by default; never a hard filter).
    final djEnabled = await DjModeSettingsStore.enabled();
    final harmonicOn = djEnabled && await DjModeSettingsStore.harmonicMix();
    DjAnalysis? currentDj;
    final Map<String, DjAnalysis> djById = <String, DjAnalysis>{};
    if (harmonicOn) {
      if (currentSong != null) {
        try {
          currentDj = await database.getDjAnalysis(currentSong.id);
        } catch (_) {}
      }
      for (final r in recommendations) {
        try {
          final row = await database.getDjAnalysis(r.song.id);
          if (row != null) djById[r.song.id] = row;
        } catch (_) {}
      }
    }
"""
    marker = "    final patternSongs = _counts(pattern['songs']);"
    if marker not in t:
        print("marker missing"); return 2
    t = t.replace(marker, inject + marker, 1)
    needle = "      value += historicalSongBoost + historicalArtistBoost;"
    boost = """
      if (harmonicOn && currentDj != null && currentDj.hasUsableKey) {
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
    if needle not in t:
        print("needle missing"); return 3
    t = t.replace(needle, needle + boost, 1)
    P.write_text(t)
    print("applied", P.stat().st_size)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
