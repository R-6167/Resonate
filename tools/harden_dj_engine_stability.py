#!/usr/bin/env python3
"""Stability hardening for dj_engine_v2 playback core."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "lib/providers/music_provider.dart"
t = path.read_text()

if "_lastUserPauseAt" in t and "_forceClearStuckTransition" in t:
    print("already hardened")
    raise SystemExit(0)

# --- 1) Fields for pause cooldown + stuck transition watchdog ---
old_fields = "  DateTime? _lastSilentRecoverAt;\n"
new_fields = """  DateTime? _lastSilentRecoverAt;
  /// After user pause, suppress auto play-kicks briefly (stream / ensureAudible).
  DateTime? _lastUserPauseAt;
  /// When an automatic/true crossfade was armed — detect stuck flags.
  DateTime? _transitionArmedAt;
"""
if old_fields not in t:
    raise SystemExit("silent recover field miss")
t = t.replace(old_fields, new_fields, 1)

# --- 2) Helper methods after _cancelAutomaticPlaybackWork ---
old_cancel_end = """    _endOfTrackWatchdog?.cancel();
    _endOfTrackWatchdog = null;
  }

  /// Explicit play/resume — used by media-session onPlay and as the play half of toggle.
"""

new_cancel_block = """    _endOfTrackWatchdog?.cancel();
    _endOfTrackWatchdog = null;
    _transitionArmedAt = null;
    // Drop transition SFX so reverb/EQ cannot linger after user transport.
    unawaited(_restoreDjTransitionSfx());
    // Silence whichever engine is idle (A or B), not only B.
    unawaited(() async {
      try {
        final idle = inactivePlayer;
        await idle.pause();
        await idle.setVolume(0.0);
      } catch (_) {}
    }());
  }

  /// True for a short window after the user explicitly paused.
  bool get _recentlyUserPaused {
    final at = _lastUserPauseAt;
    if (at == null) return false;
    return DateTime.now().difference(at) < const Duration(seconds: 2);
  }

  /// If crossfade flags stay true too long, force a safe reset so pause/next work.
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
"""

if old_cancel_end not in t:
    raise SystemExit("cancel end miss")
t = t.replace(old_cancel_end, new_cancel_block, 1)

# --- 3) Arm transition timestamp when flags go true ---
t = t.replace(
    "      _repeatSelfHandoffInFlight = true;\n      _automaticCrossfadeInFlight = true;\n",
    "      _repeatSelfHandoffInFlight = true;\n      _automaticCrossfadeInFlight = true;\n      _transitionArmedAt = DateTime.now();\n",
    1,
)
# second arm for normal auto xf
# only the line that is alone before unawaited(_runAutomaticCrossfade)
old_arm = """    if (remaining < const Duration(milliseconds: 1200)) return;
    _automaticCrossfadeInFlight = true;
    unawaited(_runAutomaticCrossfade());
"""
new_arm = """    if (remaining < const Duration(milliseconds: 1200)) return;
    _automaticCrossfadeInFlight = true;
    _transitionArmedAt = DateTime.now();
    unawaited(_runAutomaticCrossfade());
"""
if old_arm in t:
    t = t.replace(old_arm, new_arm, 1)

# true crossfade start
old_true = "_crossfadeInProgress = true; final outgoing = audioPlayer;"
if old_true in t and "_transitionArmedAt = DateTime.now(); final outgoing" not in t:
    t = t.replace(
        old_true,
        "_crossfadeInProgress = true; _transitionArmedAt = DateTime.now(); final outgoing = audioPlayer;",
        1,
    )

# --- 4) Clear armed + automatic flag in true-crossfade finally ownsTransition ---
old_fin = """      if (ownsTransition) {
        _crossfadeInProgress = false;
        try {
          await _clearDjStretchSpeeds(outgoing: _playerA, incoming: _playerB);
"""
new_fin = """      if (ownsTransition) {
        _crossfadeInProgress = false;
        _automaticCrossfadeInFlight = false;
        _transitionArmedAt = null;
        try {
          await _clearDjStretchSpeeds(outgoing: _playerA, incoming: _playerB);
"""
if old_fin in t:
    t = t.replace(old_fin, new_fin, 1)
    print("crossfade finally hardened")

# --- 5) Silent recover guards ---
old_silent = """  void _maybeRecoverSilentPlayback() {
    if (_crossfadeInProgress ||
        _automaticCrossfadeInFlight ||
        _repeatSelfHandoffInFlight ||
        _transportInFlight ||
        _loadingSource) {
      return;
    }
    if (!_userWantsPlaying) return;
"""
new_silent = """  void _maybeRecoverSilentPlayback() {
    _forceClearStuckTransition(reason: 'silent_recover_probe');
    if (_crossfadeInProgress ||
        _automaticCrossfadeInFlight ||
        _repeatSelfHandoffInFlight ||
        _transportInFlight ||
        _loadingSource ||
        _djSfxEngaged ||
        _isDucked ||
        _recentlyUserPaused) {
      return;
    }
    if (!_userWantsPlaying) return;
"""
if old_silent in t:
    t = t.replace(old_silent, new_silent, 1)
    print("silent recover guarded")

# --- 6) ensureAudible respects recent pause ---
old_ens = """  Future<void> ensureAudiblePlayback() async {
    try {
      if (!_userWantsPlaying && !audioPlayer.playing) return;
"""
new_ens = """  Future<void> ensureAudiblePlayback() async {
    try {
      if (_recentlyUserPaused) return;
      if (!_userWantsPlaying && !audioPlayer.playing) return;
      if (!_userWantsPlaying) return;
"""
if old_ens in t:
    t = t.replace(old_ens, new_ens, 1)
    print("ensureAudible guarded")

# --- 7) Stream auto-kick respects recent pause ---
old_kick = """      } else if (!loading &&
          !state.playing &&
          _userWantsPlaying &&
          !_loadingSource &&
          player.audioSource != null) {
"""
new_kick = """      } else if (!loading &&
          !state.playing &&
          _userWantsPlaying &&
          !_recentlyUserPaused &&
          !_loadingSource &&
          player.audioSource != null) {
"""
if old_kick in t:
    t = t.replace(old_kick, new_kick, 1)
    print("stream kick guarded")

# --- 8) Stamp pause time in hard pause path ---
if "_lastUserPauseAt = DateTime.now()" not in t:
    t = t.replace(
        """    if (!fromSystemFocus) {
      _userWantsPlaying = false;
      isPlaying = false;
      _volumeFadeGen++;
""",
        """    if (!fromSystemFocus) {
      _userWantsPlaying = false;
      isPlaying = false;
      _lastUserPauseAt = DateTime.now();
      _volumeFadeGen++;
",
        1,
    )
    print("pause stamp added")

# --- 9) Position stream / periodic: probe stuck transitions when updating position ---
# Hook near notifyListeners after position update if pattern exists
old_pos = None
# Find a common position update block
marker = "currentPosition = position;"
if marker in t and "_forceClearStuckTransition(reason: 'position_tick')" not in t:
    t = t.replace(
        marker,
        "currentPosition = position;\n"
        "      _forceClearStuckTransition(reason: 'position_tick');\n",
        1,
    )
    print("position tick stuck probe")

path.write_text(t)
print("stability harden complete")
