#!/usr/bin/env python3
from pathlib import Path
import re

MP = Path("lib/providers/music_provider.dart")
mp = MP.read_text()

# 1) Strengthen recover: lower threshold + userWantsPlaying + SFX restore + session
if "reason: 'silent_watchdog'" in mp or "_maybeRecoverSilentPlayback" in mp:
    print("watchdog present")

# Replace the volume condition inside recover regardless of surrounding text
old_cond = "if (active.playing && active.volume < 0.02) {\n          await active.setVolume(vol);\n        }"
new_cond = "if ((_userWantsPlaying || active.playing) && active.volume < vol * 0.85) {\n          await active.setVolume(vol);\n        }"
if old_cond in mp:
    mp = mp.replace(old_cond, new_cond, 1)
    print("recover threshold")
elif "vol * 0.85" in mp:
    print("threshold already")
else:
    print("WARN threshold miss")

# Insert SFX restore + session after clearDjStretch in recover if missing
if "_restoreDjTransitionSfx()" in mp.split("_recoverDjEngineState")[1][:600]:
    print("recover already restores sfx")
else:
    old = """    try {
      await _clearDjStretchSpeeds(outgoing: _playerA, incoming: _playerB);
    } catch (_) {}
    try {
      final active = audioPlayer;"""
    new = """    try {
      await _clearDjStretchSpeeds(outgoing: _playerA, incoming: _playerB);
    } catch (_) {}
    try {
      await _restoreDjTransitionSfx();
    } catch (_) {}
    try {
      final active = audioPlayer;"""
    # Only first occurrence in recover - replace once if unique enough
    if old in mp:
        mp = mp.replace(old, new, 1)
        print("recover sfx restore")

# Session activate in recover
if "session.setActive(true)" not in mp.split("_recoverDjEngineState")[1][:1200]:
    # before recordDj in recover
    marker = "      await ResonateDiagnostics.recordDj(\n        stage: 'engine_recover',"
    insert = """      try {
        final session = await AudioSession.instance;
        await session.setActive(true);
      } catch (_) {}
      await ResonateDiagnostics.recordDj(
        stage: 'engine_recover',"""
    if marker in mp:
        mp = mp.replace(marker, insert, 1)
        print("recover session")

# 2) Finally unstick
if "playback_volume_unstick" not in mp:
    old_f = """    } finally {
      _crossfadeInProgress = false;
      notifyListeners();

      // Critical fix: if the outgoing track reached completed while we were"""
    new_f = """    } finally {
      _crossfadeInProgress = false;
      try {
        await _clearDjStretchSpeeds(outgoing: _playerA, incoming: _playerB);
      } catch (_) {}
      try {
        await _restoreDjTransitionSfx();
      } catch (_) {}
      try {
        final active = audioPlayer;
        final vol = _eqPreampScale.clamp(0.05, 1.0).toDouble();
        if ((_userWantsPlaying || active.playing) && active.volume < 0.05) {
          await active.setSpeed(1.0);
          await active.setVolume(vol);
          await ResonateDiagnostics.record('playback_volume_unstick', {
            'reason': 'crossfade_finally',
            'volume': active.volume,
            'engine': _activeIsA ? 'A' : 'B',
          });
        }
      } catch (_) {}
      notifyListeners();

      // Critical fix: if the outgoing track reached completed while we were"""
    if old_f in mp:
        mp = mp.replace(old_f, new_f, 1)
        print("finally unstick")
    else:
        print("WARN finally miss")

# 3) Commit volume guarantee before engine flip
if "crossfade_commit_volume" not in mp:
    old_c = """      try {
        if (incoming.volume < 0.05) await incoming.setVolume(master);
      } catch (_) {}
      _activeIsA = !_activeIsA; // Phase 2: only crossfade may leave Engine B active"""
    new_c = """      try {
        if (incoming.volume < 0.05) await incoming.setVolume(master);
      } catch (_) {}
      try {
        await incoming.setSpeed(1.0);
        await incoming.setVolume(master);
        if (!incoming.playing) {
          try { incoming.play(); } catch (_) {}
        }
        await ResonateDiagnostics.record('crossfade_commit_volume', {
          'volume': incoming.volume,
          'playing': incoming.playing,
          'master': master,
          'songId': nextSong.id,
        });
      } catch (_) {}
      _activeIsA = !_activeIsA; // Phase 2: only crossfade may leave Engine B active"""
    if old_c in mp:
        mp = mp.replace(old_c, new_c, 1)
        print("commit volume")
    else:
        print("WARN commit miss")

# 4) Ensure watchdog hooks position updates
if "_maybeRecoverSilentPlayback" in mp and mp.count("_maybeRecoverSilentPlayback") < 2:
    # method exists but not called
    if "currentPosition = position;" in mp:
        mp = mp.replace(
            "currentPosition = position;",
            "currentPosition = position;\n      _maybeRecoverSilentPlayback();",
            1,
        )
        print("hooked position")
elif "_maybeRecoverSilentPlayback()" in mp:
    print("watchdog already hooked")

# 5) play path speed reset
if "await timed('setVolume', target.setVolume(_eqPreampScale), ms: 2000);" in mp:
    mp = mp.replace(
        "await timed('setVolume', target.setVolume(_eqPreampScale), ms: 2000);",
        "await timed('setVolume', target.setVolume(_eqPreampScale.clamp(0.05, 1.0)), ms: 2000);\n      try { await target.setSpeed(1.0); } catch (_) {}",
        1,
    )
    print("play volume/speed")

MP.write_text(mp)
print("DONE v2")
