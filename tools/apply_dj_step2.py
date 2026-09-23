#!/usr/bin/env python3
"""Apply DJ Mode Step 2 (beat-align) to music_provider.dart."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
MP = ROOT / "lib/providers/music_provider.dart"
FRAG = Path(__file__).with_name("frag_beat_align_method.txt")

def main() -> int:
    mt = MP.read_text()
    if "_maybeBeatAlignIncoming" in mt and "configureDjMode" in mt and "scheduleAnalyze" in mt:
        print("step2 already in music_provider")
        return 0

    if "dj_analysis_service.dart" not in mt:
        mt = mt.replace(
            "import '../services/database_helper.dart';",
            "import '../services/database_helper.dart';\n"
            "import '../services/dj_analysis_service.dart';\n"
            "import '../services/dj_bpm_estimator.dart';",
        )
    if "import '../models/dj_analysis.dart';" not in mt:
        mt = mt.replace(
            "import '../models/song.dart';",
            "import '../models/song.dart';\nimport '../models/dj_analysis.dart';",
        )

    if "_djBeatAlignActive" not in mt:
        for anchor in (
            "  bool _crossfadePreloadInFlight = false;",
            "  bool _crossfadeEnabled = false;",
        ):
            if anchor in mt:
                mt = mt.replace(
                    anchor,
                    anchor
                    + "\n  /// DJ Mode Step 2 — only true when DjModeProvider master + beat-align are on.\n"
                    "  bool _djBeatAlignActive = false;\n"
                    "  DjAnalysisService? _djAnalysis;\n",
                    1,
                )
                break

    if "void configureDjMode" not in mt:
        method_lines = [
            "",
            "  /// Called by [DjModeProvider]. When [beatAlignActive] is false, crossfade",
            "  /// ignores BPM and behaves exactly as before.",
            "  void configureDjMode({",
            "    required bool beatAlignActive,",
            "    DjAnalysisService? analysis,",
            "  }) {",
            "    _djBeatAlignActive = beatAlignActive;",
            "    _djAnalysis = analysis;",
            "  }",
            "",
            "",
        ]
        method = "\n".join(method_lines)
        for marker in ("Future<void> setCrossfadeEnabled", "bool get crossfadeEnabled"):
            idx = mt.find(marker)
            if idx >= 0:
                line = mt.rfind("\n", 0, idx) + 1
                mt = mt[:line] + method + mt[line:]
                break
        else:
            print("configure insert point missing")
            return 2

    old_preload = (
        "  Future<void> _preloadNextForCrossfade() async {\n"
        "    if (!_crossfadeEnabled || _crossfadePreloadInFlight || !canCrossfadeNext) return;\n"
        "    final next = _crossfadeTargetSong;\n"
        "    if (next == null) return;\n"
        "    if (_preloadedNextSongId == next.id) return;\n"
        "    _crossfadePreloadInFlight = true;\n"
    )
    new_preload = old_preload + (
        "    // DJ Mode: warm BPM cache for A/B without blocking the preload path.\n"
        "    if (_djBeatAlignActive && _djAnalysis != null) {\n"
        "      final cur = currentSong;\n"
        "      if (cur != null) _djAnalysis!.scheduleAnalyze(cur);\n"
        "      _djAnalysis!.scheduleAnalyze(next);\n"
        "    }\n"
    )
    if "scheduleAnalyze" not in mt and old_preload in mt:
        mt = mt.replace(old_preload, new_preload, 1)

    if "_maybeBeatAlignIncoming" not in mt:
        needle = "      // Fire-and-poll play on B — await play() can hang and block auto-next forever."
        call = (
            "      await _maybeBeatAlignIncoming(\n"
            "        outgoing: outgoing,\n"
            "        incoming: incoming,\n"
            "        outgoingSong: outgoingSong,\n"
            "        incomingSong: nextSong,\n"
            "      );\n"
            "      // Fire-and-poll play on B — await play() can hang and block auto-next forever."
        )
        if needle not in mt:
            print("fire-and-poll marker missing")
            return 3
        mt = mt.replace(needle, call, 1)
        if not FRAG.exists():
            print("missing", FRAG)
            return 4
        method = FRAG.read_text()
        idx = mt.find("  Future<bool> _performTrueCrossfade")
        if idx < 0:
            idx = mt.find("  Future<bool> performTrueCrossfade")
        if idx < 0:
            print("performTrueCrossfade missing")
            return 5
        mt = mt[:idx] + method + mt[idx:]

    MP.write_text(mt)
    print("music_provider step2 applied", MP.stat().st_size)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
