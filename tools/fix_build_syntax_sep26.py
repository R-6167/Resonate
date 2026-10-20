#!/usr/bin/env python3
"""Fix compile errors from duplicate BPM merge + broken debugPrint newline."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MUSIC = ROOT / 'lib/providers/music_provider.dart'
BPM = ROOT / 'lib/services/dj_bpm_estimator.dart'


def main() -> None:
    # --- music_provider: unbroken multiline string in debugPrint ---
    t = MUSIC.read_text()
    bad = """    } catch (e, st) {
      debugPrint('repeat self handoff failed: $e
$st');
      try {
        await incoming.pause();
      } catch (_) {}
      try {
        await outgoing.setVolume(master);
      } catch (_) {}
      return false;
    } finally {"""
    good = """    } catch (e, st) {
      debugPrint('repeat self handoff failed: $e');
      debugPrint('$st');
      try {
        await incoming.pause();
      } catch (_) {}
      try {
        await outgoing.setVolume(master);
      } catch (_) {}
      return false;
    } finally {"""
    if bad in t:
        t = t.replace(bad, good, 1)
        print('ok music debugPrint')
    elif "debugPrint('repeat self handoff failed: $e\n$st')" in t:
        t = t.replace(
            "debugPrint('repeat self handoff failed: $e\n$st');",
            "debugPrint('repeat self handoff failed: $e');\n      debugPrint('$st');",
            1,
        )
        print('ok music debugPrint escaped')
    else:
        print('skip music debugPrint')
    MUSIC.write_text(t)

    # --- dj_bpm_estimator: remove duplicated end-window block ---
    b = BPM.read_text()
    dup = """      final mergedNative = _mergeStructure(nativePcm, endPcm);
      // Whole-track structure: second window near the end when duration is known.
      DjBpmEstimate? endPcm;
      final dur = durationMs ?? 0;
      if (dur > 45000) {
        final startMs = (dur - 18000).clamp(20000, dur - 8000).toInt();
        endPcm = await _estimateFromNativePcm(
          filePath,
          maxSeconds: 14.0,
          startMs: startMs,
          windowRole: 'end',
        );
      }
      final mergedNative = _mergeStructure(nativePcm, endPcm);
"""
    if dup in b:
        b = b.replace(
            dup,
            '      final mergedNative = _mergeStructure(nativePcm, endPcm);\n',
            1,
        )
        print('ok bpm duplicate removed')
    else:
        # try without toInt on startMs
        dup2 = """      final mergedNative = _mergeStructure(nativePcm, endPcm);
      // Whole-track structure: second window near the end when duration is known.
      DjBpmEstimate? endPcm;
      final dur = durationMs ?? 0;
      if (dur > 45000) {
        final startMs = (dur - 18000).clamp(20000, dur - 8000);
        endPcm = await _estimateFromNativePcm(
          filePath,
          maxSeconds: 14.0,
          startMs: startMs,
          windowRole: 'end',
        );
      }
      final mergedNative = _mergeStructure(nativePcm, endPcm);
"""
        if dup2 in b:
            b = b.replace(
                dup2,
                '      final mergedNative = _mergeStructure(nativePcm, endPcm);\n',
                1,
            )
            print('ok bpm duplicate removed (alt)')
        else:
            print('skip bpm duplicate')
            # show nearby context
            i = b.find('final mergedNative')
            print(repr(b[i:i+500]) if i >= 0 else 'no mergedNative')
    BPM.write_text(b)
    print('fix build syntax done')


if __name__ == '__main__':
    main()
