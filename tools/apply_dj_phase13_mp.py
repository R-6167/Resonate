#!/usr/bin/env python3
from pathlib import Path
MP = Path(__file__).resolve().parents[1] / "lib/providers/music_provider.dart"

def main():
    t = MP.read_text()
    n = 0
    old1 = """      if (!analysisA.hasUsableBpm || !analysisB.hasUsableBpm) {
        await ResonateDiagnostics.record('dj_handoff_skipped', {
          'reason': 'missing_bpm',
          'outgoingSongId': outgoingSong.id,
          'incomingSongId': incomingSong.id,
        });
        await ResonateDiagnostics.recordDj(
          stage: 'handoff',
          outcome: 'skipped',
          reason: 'missing_bpm',
          songId: incomingSong.id,
        );
        return;
      }"""
    new1 = """      if (!analysisA.hasUsableBpm || !analysisB.hasUsableBpm) {
        await ResonateDiagnostics.record('dj_handoff_safe_fallback', {
          'reason': 'missing_bpm',
          'strategy': 'safe_fallback',
          'outgoingSongId': outgoingSong.id,
          'incomingSongId': incomingSong.id,
          'hasBpmA': analysisA.hasUsableBpm,
          'hasBpmB': analysisB.hasUsableBpm,
        });
        await ResonateDiagnostics.recordDj(
          stage: 'handoff',
          outcome: 'applied',
          reason: 'safe_fallback',
          songId: incomingSong.id,
          extra: {
            'strategy': 'safe_fallback',
            'hasBpmA': analysisA.hasUsableBpm,
            'hasBpmB': analysisB.hasUsableBpm,
          },
        );
        return;
      }"""
    if "dj_handoff_safe_fallback" in t:
        print("handoff already")
    elif old1 in t:
        t = t.replace(old1, new1, 1)
        n += 1
        print("handoff")
    else:
        print("MISS handoff")

    old2 = """        results = await Future.wait<DjAnalysis>([aFuture, bFuture]).timeout(
          const Duration(milliseconds: 400),
          onTimeout: () => const <DjAnalysis>[],
        );"""
    new2 = """        results = await Future.wait<DjAnalysis>([aFuture, bFuture]).timeout(
          const Duration(milliseconds: 2800),
          onTimeout: () => const <DjAnalysis>[],
        );"""
    if "milliseconds: 2800" in t:
        print("timeout already")
    elif old2 in t:
        t = t.replace(old2, new2, 1)
        n += 1
        print("timeout")
    else:
        print("MISS timeout")

    MP.write_text(t)
    print("patches", n)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
