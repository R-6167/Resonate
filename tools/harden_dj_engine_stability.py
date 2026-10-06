#!/usr/bin/env python3
"""Stability hardening for dj_engine_v2 playback core."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "lib/providers/music_provider.dart"
t = path.read_text()

if "_forceClearStuckTransition" in t and "_lastUserPauseAt" in t:
    print("already hardened")
    raise SystemExit(0)

# 1) Fields
needle = "  DateTime? _lastSilentRecoverAt;\n"
if needle not in t:
    raise SystemExit("field anchor miss")
t = t.replace(
    needle,
    "  DateTime? _lastSilentRecoverAt;\n"
    "  DateTime? _lastUserPauseAt;\n"
    "  DateTime? _transitionArmedAt;\n",
    1,
)

# 2) Expand cancel + helpers
old_cancel_tail = (
    "    _endOfTrackWatchdog?.cancel();\n"
    "    _endOfTrackWatchdog = null;\n"
    "  }\n\n"
    "  /// Explicit play/resume — used by media-session onPlay and as the play half of toggle.\n"
)
if old_cancel_tail not in t:
    raise SystemExit("cancel tail miss")

helpers = r'''    _endOfTrackWatchdog?.cancel();
    _endOfTrackWatchdog = null;
    _transitionArmedAt = null;
    unawaited(_restoreDjTransitionSfx());
    unawaited(() async {
      try {
        final idle = inactivePlayer;
        await idle.pause();
        await idle.setVolume(0.0);
      } catch (_) {}
    }());
  }

  bool get _recentlyUserPaused {
    final at = _lastUserPauseAt;
    if (at == null) return false;
    return DateTime.now().difference(at) < const Duration(seconds: 2);
  }

  void _forceClearStuckTransition({String reason = 'watchdog'}) {
    if (!_crossfadeInProgress && !_automaticCrossfadeInFlight) {
      _transitionArmedAt = null;
      return;
    }
    final armed = _transitionArmedAt;
    if (armed != null &&
        DateTime.now().difference(armed) < const Duration(seconds: 22)) {
      return;
    }
    unawaited(ResonateDiagnostics.record('stuck_transition_cleared', {
      'reason': reason,
      'crossfadeInProgress': _crossfadeInProgress,
      'automaticCrossfadeInFlight': _automaticCrossfadeInFlight,
      'armedMs': armed == null
          ? null
          : DateTime.now().difference(armed).inMilliseconds,
      'songId': currentSong?.id,
    }));
    _crossfadeInProgress = false;
    _automaticCrossfadeInFlight = false;
    _repeatSelfHandoffInFlight = false;
    _transitionArmedAt = null;
    unawaited(_restoreDjTransitionSfx());
    unawaited(() async {
      try {
        await inactivePlayer.pause();
      } catch (_) {}
      try {
        await inactivePlayer.setVolume(0.0);
      } catch (_) {}
      try {
        await _clearDjStretchSpeeds(outgoing: _playerA, incoming: _playerB);
      } catch (_) {}
    }());
  }

  /// Explicit play/resume — used by media-session onPlay and as the play half of toggle.
'''
t = t.replace(old_cancel_tail, helpers, 1)

# 3) Arm timestamps
t = t.replace(
    "      _repeatSelfHandoffInFlight = true;\n      _automaticCrossfadeInFlight = true;\n",
    "      _repeatSelfHandoffInFlight = true;\n"
    "      _automaticCrossfadeInFlight = true;\n"
    "      _transitionArmedAt = DateTime.now();\n",
    1,
)
t = t.replace(
    "    if (remaining < const Duration(milliseconds: 1200)) return;\n"
    "    _automaticCrossfadeInFlight = true;\n"
    "    unawaited(_runAutomaticCrossfade());\n",
    "    if (remaining < const Duration(milliseconds: 1200)) return;\n"
    "    _automaticCrossfadeInFlight = true;\n"
    "    _transitionArmedAt = DateTime.now();\n"
    "    unawaited(_runAutomaticCrossfade());\n",
    1,
)
t = t.replace(
    "_crossfadeInProgress = true; final outgoing = audioPlayer;",
    "_crossfadeInProgress = true; _transitionArmedAt = DateTime.now(); final outgoing = audioPlayer;",
    1,
)

# 4) True-crossfade finally
old_fin = (
    "      if (ownsTransition) {\n"
    "        _crossfadeInProgress = false;\n"
    "        try {\n"
    "          await _clearDjStretchSpeeds(outgoing: _playerA, incoming: _playerB);\n"
)
new_fin = (
    "      if (ownsTransition) {\n"
    "        _crossfadeInProgress = false;\n"
    "        _automaticCrossfadeInFlight = false;\n"
    "        _transitionArmedAt = null;\n"
    "        try {\n"
    "          await _clearDjStretchSpeeds(outgoing: _playerA, incoming: _playerB);\n"
)
if old_fin in t:
    t = t.replace(old_fin, new_fin, 1)
    print("finally ok")
else:
    print("WARNING finally miss")

# 5) Silent recover
old_s = (
    "  void _maybeRecoverSilentPlayback() {\n"
    "    if (_crossfadeInProgress ||\n"
    "        _automaticCrossfadeInFlight ||\n"
    "        _repeatSelfHandoffInFlight ||\n"
    "        _transportInFlight ||\n"
    "        _loadingSource) {\n"
    "      return;\n"
    "    }\n"
    "    if (!_userWantsPlaying) return;\n"
)
new_s = (
    "  void _maybeRecoverSilentPlayback() {\n"
    "    _forceClearStuckTransition(reason: 'silent_recover_probe');\n"
    "    if (_crossfadeInProgress ||\n"
    "        _automaticCrossfadeInFlight ||\n"
    "        _repeatSelfHandoffInFlight ||\n"
    "        _transportInFlight ||\n"
    "        _loadingSource ||\n"
    "        _djSfxEngaged ||\n"
    "        _isDucked ||\n"
    "        _recentlyUserPaused) {\n"
    "      return;\n"
    "    }\n"
    "    if (!_userWantsPlaying) return;\n"
)
if old_s in t:
    t = t.replace(old_s, new_s, 1)
    print("silent ok")
else:
    print("WARNING silent miss")

# 6) ensureAudible
old_e = (
    "  Future<void> ensureAudiblePlayback() async {\n"
    "    try {\n"
    "      if (!_userWantsPlaying && !audioPlayer.playing) return;\n"
)
new_e = (
    "  Future<void> ensureAudiblePlayback() async {\n"
    "    try {\n"
    "      if (_recentlyUserPaused) return;\n"
    "      if (!_userWantsPlaying) return;\n"
)
if old_e in t:
    t = t.replace(old_e, new_e, 1)
    print("ensure ok")
else:
    print("WARNING ensure miss")

# 7) Stream kick
old_k = (
    "      } else if (!loading &&\n"
    "          !state.playing &&\n"
    "          _userWantsPlaying &&\n"
    "          !_loadingSource &&\n"
    "          player.audioSource != null) {\n"
)
new_k = (
    "      } else if (!loading &&\n"
    "          !state.playing &&\n"
    "          _userWantsPlaying &&\n"
    "          !_recentlyUserPaused &&\n"
    "          !_loadingSource &&\n"
    "          player.audioSource != null) {\n"
)
if old_k in t:
    t = t.replace(old_k, new_k, 1)
    print("kick ok")
else:
    print("WARNING kick miss")

# 8) Pause stamp
old_p = (
    "    if (!fromSystemFocus) {\n"
    "      _userWantsPlaying = false;\n"
    "      isPlaying = false;\n"
    "      _volumeFadeGen++;\n"
)
new_p = (
    "    if (!fromSystemFocus) {\n"
    "      _userWantsPlaying = false;\n"
    "      isPlaying = false;\n"
    "      _lastUserPauseAt = DateTime.now();\n"
    "      _volumeFadeGen++;\n"
)
if old_p in t:
    t = t.replace(old_p, new_p, 1)
    print("pause stamp ok")
else:
    print("WARNING pause stamp miss")

# 9) Position probe (first occurrence only)
if "_forceClearStuckTransition(reason: 'position_tick')" not in t:
    t = t.replace(
        "currentPosition = position;",
        "currentPosition = position;\n"
        "      _forceClearStuckTransition(reason: 'position_tick');",
        1,
    )
    print("position probe ok")

path.write_text(t)
print("stability harden complete")
