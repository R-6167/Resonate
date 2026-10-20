#!/usr/bin/env python3
"""Phase 7 lite: record DJ transition outcomes from early skip vs complete."""
from pathlib import Path

MP = Path("lib/providers/music_provider.dart")
t = MP.read_text()
n = 0

if "DjTransitionMemory" in t and "_lastDjHandoffAt" in t:
    print("already phase7")
    raise SystemExit(0)

old_imp = "import '../services/dj_transition_planner.dart';\n"
new_imp = (
    "import '../services/dj_transition_planner.dart';\n"
    "import '../services/dj_transition_memory.dart';\n"
)
if "dj_transition_memory.dart" not in t and old_imp in t:
    t = t.replace(old_imp, new_imp, 1)
    n += 1
    print("import")
elif "dj_transition_memory.dart" not in t:
    alt = "import '../services/dj_analysis_service.dart';\n"
    if alt in t:
        t = t.replace(alt, alt + "import '../services/dj_transition_memory.dart';\n", 1)
        n += 1
        print("import alt")

old_f = "  double? _djStretchSpeedIn;\n"
new_f = (
    "  double? _djStretchSpeedIn;\n"
    "  DateTime? _lastDjHandoffAt;\n"
    "  String? _lastDjFromId;\n"
    "  String? _lastDjToId;\n"
    "  String? _lastDjStrategy;\n"
)
if "_lastDjHandoffAt" not in t and old_f in t:
    t = t.replace(old_f, new_f, 1)
    n += 1
    print("fields")

old_end = """      await ResonateDiagnostics.recordDj(
        stage: 'handoff',
        outcome: 'applied',
        reason: appliedStrategy,
        songId: incomingSong.id,
        bpmA: bpmA,
        bpmB: bpmB,
        extra: {
          ...plan.toDiagExtra(),
          'strategyApplied': appliedStrategy,
          'beatApplied': beatApplied,
          'tempoApplied': tempoApplied,
        },
      );
"""
new_end = """      await ResonateDiagnostics.recordDj(
        stage: 'handoff',
        outcome: 'applied',
        reason: appliedStrategy,
        songId: incomingSong.id,
        bpmA: bpmA,
        bpmB: bpmB,
        extra: {
          ...plan.toDiagExtra(),
          'strategyApplied': appliedStrategy,
          'beatApplied': beatApplied,
          'tempoApplied': tempoApplied,
        },
      );
      _lastDjHandoffAt = DateTime.now();
      _lastDjFromId = outgoingSong.id;
      _lastDjToId = incomingSong.id;
      _lastDjStrategy = appliedStrategy;
"""
if "_lastDjHandoffAt = DateTime.now()" not in t and old_end in t:
    t = t.replace(old_end, new_end, 1)
    n += 1
    print("stamp handoff")
else:
    print("MISS stamp" if "_lastDjHandoffAt = DateTime.now()" not in t else "stamp already")

old_next = """  Future<void> nextSong({String source = 'normal_player'}) {
    final intentToken = _playbackIntentGate.issue();
    _cancelAutomaticPlaybackWork();

    return _serializePlayback(
      () async {
        if (_queue.isEmpty) return;
        _transportInFlight = true;
        try {
"""
new_next = """  Future<void> nextSong({String source = 'normal_player'}) {
    final intentToken = _playbackIntentGate.issue();
    _cancelAutomaticPlaybackWork();

    return _serializePlayback(
      () async {
        if (_queue.isEmpty) return;
        // Phase 7: early skip after a DJ handoff → soft negative signal.
        try {
          final handoffAt = _lastDjHandoffAt;
          final fromId = _lastDjFromId;
          final toId = _lastDjToId;
          final strategy = _lastDjStrategy;
          if (handoffAt != null &&
              fromId != null &&
              toId != null &&
              strategy != null &&
              currentSong?.id == toId &&
              DateTime.now().difference(handoffAt) < const Duration(seconds: 90) &&
              currentPosition.inMilliseconds < 25000) {
            unawaited(DjTransitionMemory.recordOutcome(
              fromId: fromId,
              toId: toId,
              strategy: strategy,
              successful: false,
            ));
            unawaited(ResonateDiagnostics.recordDj(
              stage: 'learn',
              outcome: 'early_skip',
              reason: strategy,
              songId: toId,
              extra: {
                'fromId': fromId,
                'positionMs': currentPosition.inMilliseconds,
              },
            ));
            _lastDjHandoffAt = null;
          }
        } catch (_) {}
        _transportInFlight = true;
        try {
"""
if "early_skip" not in t and old_next in t:
    t = t.replace(old_next, new_next, 1)
    n += 1
    print("nextSong learn")
else:
    print("MISS nextSong" if "early_skip" not in t else "next already")

needle = "skipped: !wasCompleted && position > 0, skipPositionMs: !wasCompleted && position > 0 ? position : null);"
if "outcome: 'completed'" not in t and needle in t:
    inject = needle + """
      // Phase 7: full listen after DJ handoff → soft positive signal.
      try {
        final handoffAt = _lastDjHandoffAt;
        final fromId = _lastDjFromId;
        final toId = _lastDjToId;
        final strategy = _lastDjStrategy;
        if (wasCompleted &&
            handoffAt != null &&
            fromId != null &&
            toId != null &&
            strategy != null &&
            event.songId == toId) {
          unawaited(DjTransitionMemory.recordOutcome(
            fromId: fromId,
            toId: toId,
            strategy: strategy,
            successful: true,
          ));
          unawaited(ResonateDiagnostics.recordDj(
            stage: 'learn',
            outcome: 'completed',
            reason: strategy,
            songId: toId,
            extra: {'fromId': fromId},
          ));
          _lastDjHandoffAt = null;
        }
      } catch (_) {}
"""
    t = t.replace(needle, inject, 1)
    n += 1
    print("history learn")
else:
    print("MISS history" if "outcome: 'completed'" not in t else "history already")

MP.write_text(t)
print("patches", n)
