#!/usr/bin/env python3
from pathlib import Path
P = Path(__file__).resolve().parents[1] / "lib/services/resonate_diagnostics.dart"
HINT = """
  static String _djHealthHint({
    required int djFailures,
    required int djSkips,
    required int djApplied,
    required Map<String, int> djStages,
  }) {
    if (djStages.isEmpty && djFailures == 0 && djSkips == 0 && djApplied == 0) {
      return 'no_dj_signal - enable DJ Mode and play a crossfade, or run idle analysis';
    }
    if (djFailures > djApplied && djFailures > 2) {
      return 'dj_handoff_failures - check djStages / topErrors';
    }
    if (djSkips > 0 && djApplied == 0 && (djStages['analysis'] ?? 0) == 0) {
      return 'dj_skips_without_analysis - enable idle scan for BPM/key tags';
    }
    if ((djStages['idle_scan_error'] ?? 0) > 0) {
      return 'idle_scan_errors - see dj_event stage idle_scan_error';
    }
    if (djApplied > 0) {
      return 'dj_handoffs_ok - applied $djApplied, skipped $djSkips, failed $djFailures';
    }
    return 'dj_partial - skips $djSkips, applied $djApplied; missing tags are expected';
  }

"""

def main() -> int:
    t = P.read_text()
    if "static String _djHealthHint" in t:
        print("health hint already"); return 0
    idx = t.find("  static String _playbackHealthHint")
    if idx < 0:
        print("marker missing"); return 1
    P.write_text(t[:idx] + HINT + t[idx:])
    print("health hint applied", P.stat().st_size)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
