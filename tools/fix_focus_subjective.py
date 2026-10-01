#!/usr/bin/env python3
"""Make Resonate yield focus hard: abandon session, block reclaim until user play."""
from pathlib import Path

path = Path(__file__).resolve().parents[1] / "lib/providers/music_provider.dart"
t = path.read_text()

if "_abandonAudioFocus" in t and "claim_blocked_while_suspended" in t:
    print("subjective focus already applied")
    raise SystemExit(0)

# --- 1) Add yield/abandon helpers after _claimAudioFocus ---
old_claim = """  /// Claim media focus before any intentional play. Safe to call often.
  Future<void> _claimAudioFocus({String reason = 'play'}) async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(true);
"""

# Find actual claim body more flexibly
if "Future<void> _claimAudioFocus" in t and "_abandonAudioFocus" not in t:
    # Replace entire claim method start through its try setActive
    import re
    # Insert helpers before _claimAudioFocus
    helpers = '''
  /// True while we have yielded to a call / another player.
  /// Public so Autopilot / UI can avoid driving playback.
  bool get isFocusSuspended => _focusSuspended;

  /// Explicitly release Android/iOS audio focus so other apps can play undisturbed.
  Future<void> _abandonAudioFocus({String reason = 'yield'}) async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(false);
    } catch (_) {}
    try {
      await ResonateDiagnostics.record('audio_focus_event', {
        'action': 'abandon_focus',
        'reason': reason,
        'songId': currentSong?.id,
      });
    } catch (_) {}
  }

  /// Yield to an external audio source (call, Files, other player).
  /// Clears play-intent and abandons focus so we cannot bully them back.
  Future<void> _yieldToExternalAudio({String reason = 'exclusive_loss'}) async {
    _focusSuspended = true;
    _userWantsPlaying = false;
    _focusLostAt = DateTime.now();
    _isDucked = false;
    try {
      await audioPlayer.pause();
    } catch (_) {}
    try {
      await inactivePlayer.pause();
    } catch (_) {}
    isPlaying = false;
    await _abandonAudioFocus(reason: reason);
    _publishServiceState();
    notifyListeners();
    try {
      await ResonateDiagnostics.record('audio_focus_event', {
        'action': 'yield_to_external',
        'reason': reason,
        'songId': currentSong?.id,
      });
    } catch (_) {}
  }

'''
    t = t.replace(
        "  /// Claim media focus before any intentional play. Safe to call often.\n",
        helpers + "  /// Claim media focus before any intentional play. Safe to call often.\n",
        1,
    )

    # Gate claim: while suspended, refuse setActive (caller must clear suspension first)
    old_claim_body = """  Future<void> _claimAudioFocus({String reason = 'play'}) async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(true);
"""
    new_claim_body = """  Future<void> _claimAudioFocus({String reason = 'play'}) async {
    if (_focusSuspended) {
      try {
        await ResonateDiagnostics.record('audio_focus_event', {
          'action': 'claim_blocked_while_suspended',
          'reason': reason,
          'songId': currentSong?.id,
        });
      } catch (_) {}
      return;
    }
    try {
      final session = await AudioSession.instance;
      await session.setActive(true);
"""
    if old_claim_body in t:
        t = t.replace(old_claim_body, new_claim_body, 1)
        print("claim gated")
    else:
        print("WARNING claim body miss")

# --- 2) Interruption: use _yieldToExternalAudio ---
old_begin = """          if (event.type == AudioInterruptionType.pause) {
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
"""
new_begin = """          if (event.type == AudioInterruptionType.pause) {
            // Calls / other media: full yield + abandon focus (subjective player).
            unawaited(_yieldToExternalAudio(reason: 'interruption_pause'));
"""
if old_begin in t:
    t = t.replace(old_begin, new_begin, 1)
    print("interruption begin → yield")
else:
    # try older variant
    old2 = """          if (event.type == AudioInterruptionType.pause) {
            // Calls / exclusive media: pause, keep intent, stamp focus-loss time.
            _focusLostAt = DateTime.now();
            unawaited(pause(source: 'system'));
"""
    if old2 in t:
        t = t.replace(old2, new_begin, 1)
        print("interruption begin → yield (legacy)")
    else:
        print("WARNING interruption begin miss")

# End of pause interruption — ensure no resume, reinforce yield
old_end = """          } else if (event.type == AudioInterruptionType.pause) {
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
"""
new_end = """          } else if (event.type == AudioInterruptionType.pause) {
            // Focus returned to the system pool — still do not auto-resume.
            final lostAt = _focusLostAt;
            _focusLostAt = null;
            _focusSuspended = true;
            _userWantsPlaying = false;
            unawaited(_abandonAudioFocus(reason: 'interruption_pause_end'));
            unawaited(ResonateDiagnostics.record('audio_focus_event', {
              'action': 'skip_auto_resume_exclusive_focus_loss',
              'lostMs': lostAt == null
                  ? null
                  : DateTime.now().difference(lostAt).inMilliseconds,
            }));
"""
if old_end in t:
    t = t.replace(old_end, new_end, 1)
    print("interruption end reinforced")
else:
    print("WARNING interruption end miss")

# --- 3) Kick-play path: respect suspension ---
old_kick = """      } else if (!loading &&
          !state.playing &&
          _userWantsPlaying &&
          !_loadingSource &&
          player.audioSource != null) {
        // Kick play when a source is loaded and we still want audio.
        // Shorter throttle so auto-next / library taps recover quickly if the
        // first play() after setAudioSource did not stick.
        final now = DateTime.now();
        final due = _lastPlayKickAt == null ||
            now.difference(_lastPlayKickAt!) > const Duration(milliseconds: 250);
        if (due) {
          _lastPlayKickAt = now;
          isPlaying = true;
          unawaited(() async {
            // Do not re-claim focus mid-crossfade — it can reset OEM volume/routing mid-ramp.
            if (_crossfadeInProgress || _automaticCrossfadeInFlight) return;
            try {
              final session = await AudioSession.instance;
              await session.setActive(true);
            } catch (_) {}
            try {
              await player.seek(player.position);
            } catch (_) {}
            try {
              await player.play();
            } catch (_) {}
          }());
"""
new_kick = """      } else if (!loading &&
          !state.playing &&
          _userWantsPlaying &&
          !_focusSuspended &&
          !_loadingSource &&
          player.audioSource != null) {
        // Kick play when a source is loaded and we still want audio.
        // Never while focus is yielded to another app/call.
        final now = DateTime.now();
        final due = _lastPlayKickAt == null ||
            now.difference(_lastPlayKickAt!) > const Duration(milliseconds: 250);
        if (due) {
          _lastPlayKickAt = now;
          isPlaying = true;
          unawaited(() async {
            if (_focusSuspended) return;
            if (_crossfadeInProgress || _automaticCrossfadeInFlight) return;
            try {
              await _claimAudioFocus(reason: 'kick_play');
            } catch (_) {}
            if (_focusSuspended) return;
            try {
              await player.seek(player.position);
            } catch (_) {}
            try {
              await player.play();
            } catch (_) {}
          }());
"""
if old_kick in t:
    t = t.replace(old_kick, new_kick, 1)
    print("kick-play gated")
else:
    print("WARNING kick-play miss")

# --- 4) Player state: do not re-assert intent while suspended; force pause if playing ---
old_playing = """      } else if (state.playing) {
        if (!isPlaying) {
          isPlaying = true;
          _userWantsPlaying = true;
          notifyListeners();
          _publishServiceState();
        }
"""
new_playing = """      } else if (state.playing) {
        if (_focusSuspended) {
          // External focus owns the stream — do not adopt play-intent.
          unawaited(() async {
            try {
              await player.pause();
            } catch (_) {}
          }());
          return;
        }
        if (!isPlaying) {
          isPlaying = true;
          _userWantsPlaying = true;
          notifyListeners();
          _publishServiceState();
        }
"""
if old_playing in t:
    t = t.replace(old_playing, new_playing, 1)
    print("state.playing respects yield")
else:
    print("WARNING state.playing miss")

# --- 5) Completion must not re-arm wants while suspended ---
t = t.replace(
    """        // Stay "want playing" so the next track auto-starts (not resume).
        // Do NOT set isPlaying=false here — that raced with the advance play()
        // and left the new track loaded but paused.
        _userWantsPlaying = true;
""",
    """        // Stay "want playing" so the next track auto-starts (not resume),
        // but never while focus is yielded to another app/call.
        if (!_focusSuspended) {
          _userWantsPlaying = true;
        }
""",
    1,
)
print("completion intent gated")

# --- 6) User play paths already clear _focusSuspended — ensure resumePlayback does ---
if "Future<bool> resumePlayback" in t or "resumePlayback(" in t:
    # Already may have _focusSuspended = false from prior patch
    pass

# --- 7) Autopilot: skip evaluate while focus suspended ---
ap = Path(__file__).resolve().parents[1] / "lib/providers/autopilot_controller.dart"
if ap.exists():
    at = ap.read_text()
    if "isFocusSuspended" not in at:
        at = at.replace(
            "    if (!music.isPlaying && !forceTransition) return;\n",
            "    if (!music.isPlaying && !forceTransition) return;\n"
            "    // Do not drive queue/transitions while audio focus is yielded.\n"
            "    if (music.isFocusSuspended) return;\n",
            1,
        )
        ap.write_text(at)
        print("autopilot respects isFocusSuspended")
    else:
        print("autopilot already gated")

path.write_text(t)
print("subjective focus fix applied")
