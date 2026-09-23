#!/usr/bin/env python3
from pathlib import Path
MP = Path(__file__).resolve().parents[1] / "lib/providers/music_provider.dart"
OLD = """      final aFuture = _djAnalysis!.analyzeSong(outgoingSong);
      final bFuture = _djAnalysis!.analyzeSong(incomingSong);
      final results = await Future.wait<DjAnalysis>([aFuture, bFuture]).timeout(
        const Duration(milliseconds: 400),
        onTimeout: () => <DjAnalysis>[],
      );
      if (results.length < 2) return;"""
NEW = """      List<DjAnalysis> results;
      try {
        final aFuture = _djAnalysis!.analyzeSong(outgoingSong);
        final bFuture = _djAnalysis!.analyzeSong(incomingSong);
        results = await Future.wait<DjAnalysis>([aFuture, bFuture]).timeout(
          const Duration(milliseconds: 400),
          onTimeout: () => const <DjAnalysis>[],
        );
      } catch (e) {
        await ResonateDiagnostics.recordDj(
          stage: 'handoff_prepare',
          outcome: 'failed',
          reason: 'analysis_wait: $e',
        );
        return;
      }
      if (results.length < 2) return;"""

def main() -> int:
    t = MP.read_text()
    if "analysis_wait:" in t:
        print("wait already"); return 0
    if OLD not in t:
        print("wait pattern miss"); return 1
    MP.write_text(t.replace(OLD, NEW, 1))
    print("wait hardened")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
