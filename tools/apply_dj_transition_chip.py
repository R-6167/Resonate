#!/usr/bin/env python3
"""Expose last DJ handoff fields on MusicProvider and mount reason chip on player."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def patch_music() -> None:
    path = ROOT / "lib/providers/music_provider.dart"
    t = path.read_text()
    if "hasRecentDjTransition" in t:
        print("music getters already present")
    else:
        # Insert public getters after activeEngineLabel getter block
        anchor = "  String get activeEngineLabel => _authority.engineLabel(this);\n"
        getters = """  String get activeEngineLabel => _authority.engineLabel(this);

  /// Last DJ handoff snapshot for Now Playing "why this transition" chip.
  DateTime? get lastDjHandoffAt => _lastDjHandoffAt;
  String? get lastDjStrategy => _lastDjStrategy;
  double? get lastDjTransitionScore => _lastDjTransitionScore;
  double? get lastDjTransitionConfidence => _lastDjTransitionConfidence;
  List<String> get lastDjTransitionRisks =>
      List<String>.unmodifiable(_lastDjTransitionRisks);

  /// True for a short window after a DJ plan was applied (UI chip visibility).
  bool get hasRecentDjTransition {
    final at = _lastDjHandoffAt;
    if (at == null || _lastDjStrategy == null) return false;
    return DateTime.now().difference(at) <= const Duration(seconds: 50);
  }
"""
        if anchor not in t:
            raise SystemExit("activeEngineLabel anchor miss")
        t = t.replace(anchor, getters, 1)
        print("music getters added")

    # After V2 handoff fields are set, ensure UI rebuilds.
    # Pattern near _lastDjHandoffAt = DateTime.now() for V2 path
    marker = "    _lastDjStrategy = candidate.kind.name;\n    _lastDjTransitionScore = candidate.score;\n    _lastDjTransitionConfidence = candidate.confidence;\n    _lastDjTransitionRisks = candidate.risks.map((r) => r.name).toList();\n    _lastDjTransitionDurationMs = candidate.durationMs;\n    _lastDjRecoveryAttempts = 0;\n"
    if marker in t and "notifyListeners(); // dj transition chip" not in t:
        t = t.replace(
            marker,
            marker + "    notifyListeners(); // dj transition chip\n",
            1,
        )
        print("notifyListeners after V2 handoff")

    # Legacy plan path
    marker2 = "      _lastDjStrategy = appliedStrategy;\n      _lastDjTransitionScore = null;\n      _lastDjTransitionConfidence = math.min(plan.confidenceA, plan.confidenceB);\n      _lastDjTransitionRisks = const <String>[];\n      _lastDjTransitionDurationMs = null;\n      _lastDjRecoveryAttempts = 0;\n"
    if marker2 in t and t.count("notifyListeners(); // dj transition chip") < 2:
        t = t.replace(
            marker2,
            marker2 + "      notifyListeners(); // dj transition chip\n",
            1,
        )
        print("notifyListeners after legacy handoff")

    path.write_text(t)
    print("music done")


def patch_player() -> None:
    path = ROOT / "lib/screens/player_screen.dart"
    t = path.read_text()
    if "DjTransitionReasonChip" in t:
        print("player already has reason chip")
        return

    # After album text, before seek bar spacer
    old = """              Text(
                song.album,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              const SizedBox(height: 8),
"""
    new = """              Text(
                song.album,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const DjTransitionReasonChip(),
              const SizedBox(height: 10),
              const SizedBox(height: 8),
"""
    if old not in t:
        raise SystemExit("player album anchor miss")
    t = t.replace(old, new, 1)
    path.write_text(t)
    print("player done")


def main() -> None:
    patch_music()
    patch_player()
    print("transition reason chip apply complete")


if __name__ == "__main__":
    main()
