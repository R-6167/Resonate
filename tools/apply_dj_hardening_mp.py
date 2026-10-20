#!/usr/bin/env python3
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
MP = ROOT / "lib/providers/music_provider.dart"

PATCHES = [
(
"""        await ResonateDiagnostics.record('dj_handoff_skipped', {
          'reason': 'missing_bpm',
          'outgoingSongId': outgoingSong.id,
          'incomingSongId': incomingSong.id,
        });""",
"""        await ResonateDiagnostics.record('dj_handoff_skipped', {
          'reason': 'missing_bpm',
          'outgoingSongId': outgoingSong.id,
          'incomingSongId': incomingSong.id,
        });
        await ResonateDiagnostics.recordDj(
          stage: 'handoff',
          outcome: 'skipped',
          reason: 'missing_bpm',
          songId: incomingSong.id,
        );""",
),
(
"""          await ResonateDiagnostics.record('dj_tempo_match_skipped', {
            'reason': 'stretch_budget',
            'bpmA': bpmA,
            'bpmB': bpmB,
            'maxPercent': _djMaxStretchPercent,
          });""",
"""          await ResonateDiagnostics.record('dj_tempo_match_skipped', {
            'reason': 'stretch_budget',
            'bpmA': bpmA,
            'bpmB': bpmB,
            'maxPercent': _djMaxStretchPercent,
          });
          await ResonateDiagnostics.recordDj(
            stage: 'tempo_match',
            outcome: 'skipped',
            reason: 'stretch_budget',
            bpmA: bpmA,
            bpmB: bpmB,
            songId: incomingSong.id,
          );""",
),
(
"""          await ResonateDiagnostics.record('dj_beat_align_skipped', {
            'reason': 'bpm_delta',
            'bpmA': bpmA,
            'bpmB': bpmB,
            'stretched': stretch != null,
          });""",
"""          await ResonateDiagnostics.record('dj_beat_align_skipped', {
            'reason': 'bpm_delta',
            'bpmA': bpmA,
            'bpmB': bpmB,
            'stretched': stretch != null,
          });
          await ResonateDiagnostics.recordDj(
            stage: 'beat_align',
            outcome: 'skipped',
            reason: 'bpm_delta',
            bpmA: bpmA,
            bpmB: bpmB,
            songId: incomingSong.id,
          );""",
),
]

def main() -> int:
    mt = MP.read_text()
    if "stage: 'handoff'" in mt and "recordDj" in mt:
        print("mp recordDj already"); return 0
    n = 0
    for a, b in PATCHES:
        if a in mt:
            mt = mt.replace(a, b, 1)
            n += 1
    old = "      debugPrint('DJ handoff prepare skipped: $e');"
    if old in mt and "handoff_prepare" not in mt:
        mt = mt.replace(old, old + """
      try {
        await ResonateDiagnostics.recordDj(
          stage: 'handoff_prepare',
          outcome: 'failed',
          reason: e.toString(),
        );
      } catch (_) {}""", 1)
        n += 1
    MP.write_text(mt)
    print("mp patches", n)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
