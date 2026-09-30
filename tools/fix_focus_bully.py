#!/usr/bin/env python3
"""Stop Resonate reclaiming audio focus from other apps/calls."""
from pathlib import Path

path = Path(__file__).resolve().parents[1] / "lib/providers/music_provider.dart"
t = path.read_text()

if "_focusSuspended" in t and "skip_auto_resume_exclusive_focus_loss" in t:
    print("focus fix already present")
    raise SystemExit(0)

# 1) Flag next to _focusLostAt
if "bool _focusSuspended" not in t:
    t = t.replace(
        "  /// When exclusive focus was lost (call / other media) — used for long-call gate.\n"
        "  DateTime? _focusLostAt;\n",
        "  /// When exclusive focus was lost (call / other media).\n"
        "  DateTime? _focusLostAt;\n"
        "  /// True after exclusive focus loss until the user explicitly plays again.\n"
        "  /// Prevents silent-watchdog / route recovery from reclaiming focus.\n"
        "  bool _focusSuspended = false;\n",
        1,
    )
    print("added _focusSuspended")

# 2) Replace interruption handler exclusive-pause logic
old_handler = """        if (event.begin) {
          if (event.type == AudioInterruptionType.pause) {
            // Calls / exclusive media: pause, keep intent, stamp focus-loss time.
            _focusLostAt = DateTime.now();
            unawaited(pause(source: 'system'));
          } else if (event.type == AudioInterruptionType.duck) {
            // Notifications / nav / transient: soft duck with fade.
            unawaited(_duckForInterruption());
          } else {
            // Unknown transient — prefer duck over a hard stop.
            unawaited(_duckForInterruption());
          }
        } else {
          if (event.type == AudioInterruptionType.duck) {
            if (_userWantsPlaying) unawaited(_unduckAfterInterruption());
          } else if (event.type == AudioInterruptionType.pause) {
            final lostAt = _focusLostAt;
            _focusLostAt = null;
            final lostLong = lostAt != null &&
                DateTime.now().difference(lostAt) > _autoResumeMaxFocusLoss;
            if (lostLong) {
              // Long call: do not surprise-resume; user taps play when ready.
              _userWantsPlaying = false;
              unawaited(ResonateDiagnostics.record('audio_focus_event', {
                'action': 'skip_auto_resume_long_focus_loss',
                'lostMs': lostAt == null
                    ? null
                    : DateTime.now().difference(lostAt).inMilliseconds,
              }));
              return;
            }
            if (_userWantsPlaying) {
              unawaited(_resumeAfterSystemFocus());
            }
          } else if (_userWantsPlaying && _isDucked) {
            unawaited(_unduckAfterInterruption());
          }
        }
"""

new_handler = """        if (event.begin) {
          if (event.type == AudioInterruptionType.pause) {
            // Calls / other media: yield completely. Do not keep play-intent
            // or we will reclaim focus from Google Files / the phone app.
            _focusLostAt = DateTime.now();
            _focusSuspended = true;
            _userWantsPlaying = false;
            unawaited(pause(source: 'system'));
            unawaited(ResonateDiagnostics.record('audio_focus_event', {
              'action': 'yield_exclusive_focus',
              'songId': currentSong?.id,
            }));
          } else if (event.type == AudioInterruptionType.duck) {
            // Notifications / nav / transient: soft duck with fade.
            unawaited(_duckForInterruption());
          } else {
            // Unknown transient — prefer duck over a hard stop.
            unawaited(_duckForInterruption());
          }
        } else {
          if (event.type == AudioInterruptionType.duck) {
            if (_userWantsPlaying && !_focusSuspended) {
              unawaited(_unduckAfterInterruption());
            }
          } else if (event.type == AudioInterruptionType.pause) {
            // Never auto-resume after exclusive focus loss. User must press play.
            final lostAt = _focusLostAt;
            _focusLostAt = null;
            _focusSuspended = true;
            _userWantsPlaying = false;
            unawaited(ResonateDiagnostics.record('audio_focus_event', {
              'action': 'skip_auto_resume_exclusive_focus_loss',
              'lostMs': lostAt == null
                  ? null
                  : DateTime.now().difference(lostAt).inMilliseconds,
            }));
          } else if (_userWantsPlaying && _isDucked && !_focusSuspended) {
            unawaited(_unduckAfterInterruption());
          }
        }
"""

if old_handler not in t:
    raise SystemExit("interruption handler block miss")
t = t.replace(old_handler, new_handler, 1)
print("interruption handler fixed")

# 3) Silent watchdog: respect focus suspension
old_silent = """    if (!_userWantsPlaying) return;
    try {
      final active = audioPlayer;
"""
# More unique context
old_silent2 = """  void _maybeRecoverSilentPlayback() {
    if (_crossfadeInProgress ||
        _automaticCrossfadeInFlight ||
        _repeatSelfHandoffInFlight ||
        _transportInFlight ||
        _loadingSource) {
      return;
    }
    if (!_userWantsPlaying) return;
"""
new_silent2 = """  void _maybeRecoverSilentPlayback() {
    if (_crossfadeInProgress ||
        _automaticCrossfadeInFlight ||
        _repeatSelfHandoffInFlight ||
        _transportInFlight ||
        _loadingSource) {
      return;
    }
    // Do not reclaim focus after yielding to a call / another player.
    if (_focusSuspended) return;
    if (!_userWantsPlaying) return;
"""
if old_silent2 in t:
    t = t.replace(old_silent2, new_silent2, 1)
    print("silent watchdog gated")
else:
    print("WARNING silent watchdog pattern miss")

# 4) ensureAudiblePlayback
if "Future<void> ensureAudiblePlayback()" in t:
    old_ens = """  Future<void> ensureAudiblePlayback() async {
    try {
      if (!_userWantsPlaying && !audioPlayer.playing) return;
"""
    new_ens = """  Future<void> ensureAudiblePlayback() async {
    try {
      if (_focusSuspended) return;
      if (!_userWantsPlaying && !audioPlayer.playing) return;
"""
    if old_ens in t:
        t = t.replace(old_ens, new_ens, 1)
        print("ensureAudible gated")

# 5) Route recovery — find the method that loops delays and plays
# Gate at start of the recovery body after userWants check
if "audio_route_changed" in t and "_focusSuspended" not in t.split("audio_route_changed")[0][-800:]:
    # Patch the early return chain in route recover
    old_route = """    if (!_userWantsPlaying) return;
    if (_crossfadeInProgress || _automaticCrossfadeInFlight) return;
    try {
      final session = await AudioSession.instance;
      try {
        await session.setActive(true);
      } catch (_) {}
    } catch (_) {}
    for (final delayMs in <int>[200, 700, 1600, 3200]) {
      await Future<void>.delayed(Duration(milliseconds: delayMs));
      if (!_userWantsPlaying) return;
"""
    new_route = """    if (_focusSuspended) return;
    if (!_userWantsPlaying) return;
    if (_crossfadeInProgress || _automaticCrossfadeInFlight) return;
    try {
      final session = await AudioSession.instance;
      try {
        await session.setActive(true);
      } catch (_) {}
    } catch (_) {}
    for (final delayMs in <int>[200, 700, 1600, 3200]) {
      await Future<void>.delayed(Duration(milliseconds: delayMs));
      if (_focusSuspended) return;
      if (!_userWantsPlaying) return;
"""
    if old_route in t:
        t = t.replace(old_route, new_route, 1)
        print("route recovery gated")
    else:
        print("WARNING route recovery pattern miss")

# 6) Clear suspension on explicit user play — in resumePlayback and play paths
# resumePlayback sets _userWantsPlaying = true in several places; clear flag at start of resumePlayback
if "Future<bool> resumePlayback" in t or "resumePlayback({" in t:
    # Find resumePlayback method
    import re
    m = re.search(r"(Future<[^>]+>\s+resumePlayback\s*\([^)]*\)\s*\{)", t)
    if not m:
        m = re.search(r"(Future<[^>]+>\s+resumePlayback[^{]*\{)", t)
    if m:
        start = m.end()
        # Insert clear after opening brace if not present nearby
        snippet = t[start : start + 200]
        if "_focusSuspended = false" not in snippet:
            t = t[:start] + "\n    _focusSuspended = false;\n" + t[start:]
            print("resumePlayback clears suspension")
    else:
        print("WARNING resumePlayback not found")

# playSongInternal already sets _userWantsPlaying = true — clear suspension there once
if "_userWantsPlaying = true;\n    await _claimAudioFocus(reason: 'play_song_internal')" in t:
    t = t.replace(
        "_userWantsPlaying = true;\n    await _claimAudioFocus(reason: 'play_song_internal')",
        "_userWantsPlaying = true;\n    _focusSuspended = false;\n    await _claimAudioFocus(reason: 'play_song_internal')",
        1,
    )
    print("play_song_internal clears suspension")
elif "_userWantsPlaying = true;" in t and "play_song_internal" in t:
    # broader: first occurrence in _playSongInternal
    idx = t.find("Future<bool> _playSongInternal")
    if idx > 0:
        sub = t[idx : idx + 2500]
        if "_focusSuspended = false" not in sub:
            sub2 = sub.replace(
                "_userWantsPlaying = true;",
                "_userWantsPlaying = true;\n    _focusSuspended = false;",
                1,
            )
            t = t[:idx] + sub2 + t[idx + 2500 :]
            print("play_song_internal clears suspension (alt)")

# 7) _resumeAfterSystemFocus — hard no-op when suspended (belt and suspenders)
old_raf = """  Future<void> _resumeAfterSystemFocus() async {
"""
if old_raf in t and "if (_focusSuspended) return;" not in t[t.find(old_raf) : t.find(old_raf) + 300]:
    t = t.replace(
        old_raf,
        "  Future<void> _resumeAfterSystemFocus() async {\n"
        "    // Exclusive focus loss must not auto-resume (other apps / calls).\n"
        "    if (_focusSuspended || !_userWantsPlaying) return;\n",
        1,
    )
    print("_resumeAfterSystemFocus guarded")

path.write_text(t)
print("focus bully fix applied")
