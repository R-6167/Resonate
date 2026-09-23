#!/usr/bin/env python3
from pathlib import Path
P = Path(__file__).resolve().parents[1] / "lib/services/resonate_diagnostics.dart"

RECORD = """
  /// DJ Mode flight recorder - same non-blocking contract as [recordIntelligence].
  static Future<void> recordDj({
    required String stage,
    String? songId,
    String? outcome,
    String? reason,
    double? bpmA,
    double? bpmB,
    Map<String, dynamic> extra = const {},
  }) async {
    await record('dj_event', {
      'stage': stage,
      if (songId != null) 'songId': songId,
      if (outcome != null) 'outcome': outcome,
      if (reason != null) 'reason': reason,
      if (bpmA != null) 'bpmA': bpmA,
      if (bpmB != null) 'bpmB': bpmB,
      ...extra,
    });
  }
"""

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
    if "recordDj" in t and "djHealthHint" in t:
        print("recordDj already")
        return 0
    if "recordDj" not in t:
        needle = "  static Future<void> recordCrash(Object error, StackTrace stack, {String source = 'unknown'}) async {"
        if needle not in t:
            print("crash marker missing")
            return 1
        t = t.replace(needle, RECORD + "\n" + needle, 1)
    if "djStages" not in t:
        t = t.replace(
            "    final intelligenceStages = <String, int>{};",
            "    final intelligenceStages = <String, int>{};\n"
            "    final djStages = <String, int>{};\n"
            "    final djOutcomes = <String, int>{};\n"
            "    var djFailures = 0;\n"
            "    var djSkips = 0;\n"
            "    var djApplied = 0;",
            1,
        )
        block = (
            "        if (type == 'intelligence_event' || type == 'intelligence_recommendations_generated') {\n"
            "          final stage = data['stage']?.toString() ?? type;\n"
            "          intelligenceStages[stage] = (intelligenceStages[stage] ?? 0) + 1;\n"
            "        }\n"
        )
        block_new = block + (
            "        if (type == 'dj_event' || type.startsWith('dj_')) {\n"
            "          final stage = data['stage']?.toString() ?? type;\n"
            "          djStages[stage] = (djStages[stage] ?? 0) + 1;\n"
            "          final outcome = data['outcome']?.toString();\n"
            "          if (outcome != null) {\n"
            "            djOutcomes[outcome] = (djOutcomes[outcome] ?? 0) + 1;\n"
            "          }\n"
            "          if (type.contains('failed') || outcome == 'failed' || data['error'] != null) {\n"
            "            djFailures++;\n"
            "          }\n"
            "          if (type.contains('skipped') || outcome == 'skipped') djSkips++;\n"
            "          if (type.contains('applied') || outcome == 'applied') djApplied++;\n"
            "        }\n"
        )
        if block in t:
            t = t.replace(block, block_new, 1)
        t = t.replace(
            "      'intelligenceStages': intelligenceStages,",
            "      'intelligenceStages': intelligenceStages,\n"
            "      'djStages': djStages,\n"
            "      'djOutcomes': djOutcomes,\n"
            "      'djFailures': djFailures,\n"
            "      'djSkips': djSkips,\n"
            "      'djApplied': djApplied,\n"
            "      'djHealthHint': _djHealthHint(djFailures: djFailures, djSkips: djSkips, djApplied: djApplied, djStages: djStages),",
            1,
        )
        if "_djHealthHint" not in t:
            idx = t.find("  static String _playbackHealthHint")
            if idx > 0:
                t = t[:idx] + HINT + t[idx:]
    P.write_text(t)
    print("diagnostics applied", P.stat().st_size)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
