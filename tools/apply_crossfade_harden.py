#!/usr/bin/env python3
"""Harden outgoing crossfade volume ramp only."""
from pathlib import Path

path = Path("lib/providers/music_provider.dart")
text = path.read_text()

old_preload = """    if (remaining <= Duration(milliseconds: preloadMs) &&
        remaining > Duration(milliseconds: _crossfadeDurationMs + 400)) {
      unawaited(_preloadNextForCrossfade());
      return;
    }"""
new_preload = """    if (remaining <= Duration(milliseconds: preloadMs) &&
        remaining > Duration(milliseconds: _crossfadeDurationMs + 1400)) {
      unawaited(_preloadNextForCrossfade());
      return;
    }"""

old_trigger = """    if (_automaticCrossfadeInFlight) return;
    if (remaining > Duration(milliseconds: _crossfadeDurationMs)) return;
    _automaticCrossfadeInFlight = true;
    unawaited(_runAutomaticCrossfade());"""
new_trigger = """    if (_automaticCrossfadeInFlight) return;
    // Start early enough that Engine-B startup + full equal-power fade finish
    // before the outgoing source hits EOS (sudden silence mid-fade).
    final startMarginMs = 1400;
    final triggerMs = (_crossfadeDurationMs + startMarginMs).clamp(1200, 14000);
    if (remaining > Duration(milliseconds: triggerMs)) return;
    _automaticCrossfadeInFlight = true;
    unawaited(_runAutomaticCrossfade());"""

# Already patched?
if "startMarginMs" in text and "remainingMs" in text and "lastOut" in text:
    print("already hardened")
    raise SystemExit(0)

if old_preload not in text:
    # maybe already partially patched
    if "_crossfadeDurationMs + 1400" not in text:
        raise SystemExit("preload block not found")
else:
    text = text.replace(old_preload, new_preload, 1)

if old_trigger not in text:
    if "startMarginMs" not in text:
        raise SystemExit("trigger block not found")
else:
    text = text.replace(old_trigger, new_trigger, 1)

old_fade_start = """      double startOut = master;
      try {
        startOut = outgoing.volume.clamp(0.0, 1.0);
      } catch (_) {}
      if (startOut > master) startOut = master;
      // Cap base to master so we never fade from above user volume.
      final base = startOut <= 0.01 ? master : startOut;
      try {
        await outgoing.setVolume(base);
      } catch (_) {}
      await incoming.setVolume(0.0);

      final total = milliseconds.clamp(500, 12000).toInt();
      // Gentler stepping on Android (esp. API ≤ 26 / low-end): fewer setVolume calls.
      final gentle = Platform.isAndroid;
      final stepDiv = gentle ? 70 : 40;
      final steps = (total / stepDiv).round().clamp(gentle ? 10 : 12, gentle ? 120 : 300).toInt();
      final stepMs = (total / steps).round().clamp(gentle ? 28 : 16, gentle ? 100 : 80);
      for (var i = 1; i <= steps; i++) {
        if (_authority.isStale(generation) || !_playbackIntentGate.isCurrent(intentToken)) {
          try { await incoming.stop(); } catch (_) {}
          try { await outgoing.setVolume(master); } catch (_) {}
          await ResonateDiagnostics.record('crossfade_cancelled', {
            'stage': 'fade',
            'outgoingSongId': outgoingSong?.id,
            'incomingSongId': nextSong.id,
            'intentToken': intentToken,
          });
          return false;
        }
        final linear = i / steps;
        final t = switch (fadeType) {
          'ease_in' => linear * linear,
          'ease_out' => 1.0 - ((1.0 - linear) * (1.0 - linear)),
          'ease_in_out' => linear < 0.5
              ? 2.0 * linear * linear
              : 1.0 - ((-2.0 * linear + 2.0) * (-2.0 * linear + 2.0)) / 2.0,
          _ => linear,
        };
        // Equal-power crossfade: avoids the linear "volume bump" in the middle
        // and keeps the outgoing track from dominating the incoming one.
        final angle = t * (3.141592653589793 / 2.0);
        final outGain = math.cos(angle);
        final inGain = math.sin(angle);
        try {
          await outgoing.setVolume((base * outGain).clamp(0.0, 1.0));
          await incoming.setVolume((master * inGain).clamp(0.0, 1.0));
        } catch (_) {}
        await Future<void>.delayed(Duration(milliseconds: stepMs));
      }
      if (_authority.isStale(generation) || !_playbackIntentGate.isCurrent(intentToken)) { try { await incoming.stop(); } catch (_) {} try { await outgoing.setVolume(base); } catch (_) {} await ResonateDiagnostics.record('crossfade_cancelled', {'stage': 'commit', 'outgoingSongId': outgoingSong?.id, 'incomingSongId': nextSong.id, 'intentToken': intentToken}); return false; }
      // Finish the outgoing history record while currentSong still refers to it.
      // Mutating currentSong first caused history to be attributed to the next track.
      await _finishHistoryEvent();
      if (!_playbackIntentGate.isCurrent(intentToken)) { try { await incoming.stop(); } catch (_) {} try { await outgoing.setVolume(master); } catch (_) {} return false; }
      await outgoing.pause(); await outgoing.setVolume(master); await incoming.setLoopMode(LoopMode.off); await incoming.setVolume(master);"""

new_fade = """      double startOut = master;
      try {
        startOut = outgoing.volume.clamp(0.0, 1.0);
      } catch (_) {}
      if (startOut > master) startOut = master;
      // Cap base to master so we never fade from above user volume.
      final base = startOut <= 0.01 ? master : startOut;
      try {
        await outgoing.setVolume(base);
      } catch (_) {}
      await incoming.setVolume(0.0);

      final plannedMs = milliseconds.clamp(500, 12000).toInt();
      // Clamp fade length to actual remaining on the outgoing source so the
      // volume ramp finishes before ExoPlayer hits EOS and cuts audio dead.
      int remainingMs = plannedMs;
      try {
        final d = outgoing.duration;
        final p = outgoing.position;
        if (d != null && d > Duration.zero) {
          final rem = d.inMilliseconds - p.inMilliseconds;
          if (rem > 250) {
            // Leave a small buffer so the last step is not raced by completion.
            remainingMs = (rem - 120).clamp(400, plannedMs);
          }
        }
      } catch (_) {}
      final total = remainingMs;
      // Wall-clock equal-power ramp: keep steps on schedule even when setVolume
      // is slow on OEM audio stacks (Unisoc / low-end Android).
      final gentle = Platform.isAndroid;
      final stepMs = gentle ? 40 : 24;
      final fadeStartedAt = DateTime.now();
      var lastOut = base;
      while (true) {
        if (_authority.isStale(generation) || !_playbackIntentGate.isCurrent(intentToken)) {
          try { await incoming.stop(); } catch (_) {}
          try { await outgoing.setVolume(master); } catch (_) {}
          await ResonateDiagnostics.record('crossfade_cancelled', {
            'stage': 'fade',
            'outgoingSongId': outgoingSong?.id,
            'incomingSongId': nextSong.id,
            'intentToken': intentToken,
          });
          return false;
        }
        final elapsed = DateTime.now().difference(fadeStartedAt).inMilliseconds;
        final linear = (elapsed / total).clamp(0.0, 1.0);
        final t = switch (fadeType) {
          'ease_in' => linear * linear,
          'ease_out' => 1.0 - ((1.0 - linear) * (1.0 - linear)),
          'ease_in_out' => linear < 0.5
              ? 2.0 * linear * linear
              : 1.0 - ((-2.0 * linear + 2.0) * (-2.0 * linear + 2.0)) / 2.0,
          _ => linear,
        };
        // Equal-power: cos out / sin in — smooth energy, no mid-fade dip.
        final angle = t * (math.pi / 2.0);
        final outGain = math.cos(angle);
        final inGain = math.sin(angle);
        final outVol = (base * outGain).clamp(0.0, 1.0);
        final inVol = (master * inGain).clamp(0.0, 1.0);
        lastOut = outVol;
        final stepStarted = DateTime.now();
        try {
          // Parallel volume writes so outgoing does not stall waiting on incoming.
          await Future.wait([
            outgoing.setVolume(outVol),
            incoming.setVolume(inVol),
          ]);
        } catch (_) {}
        if (linear >= 1.0) break;
        final spent = DateTime.now().difference(stepStarted).inMilliseconds;
        final sleep = (stepMs - spent).clamp(0, stepMs);
        if (sleep > 0) {
          await Future<void>.delayed(Duration(milliseconds: sleep));
        }
      }
      // Guarantee silence on outgoing before pause/stop — never cut from a
      // still-audible level (the "sudden volume loss" symptom).
      if (lastOut > 0.02) {
        try {
          await outgoing.setVolume(0.0);
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 40));
      } else {
        try {
          await outgoing.setVolume(0.0);
        } catch (_) {}
      }
      if (_authority.isStale(generation) || !_playbackIntentGate.isCurrent(intentToken)) { try { await incoming.stop(); } catch (_) {} try { await outgoing.setVolume(base); } catch (_) {} await ResonateDiagnostics.record('crossfade_cancelled', {'stage': 'commit', 'outgoingSongId': outgoingSong?.id, 'incomingSongId': nextSong.id, 'intentToken': intentToken}); return false; }
      // Finish the outgoing history record while currentSong still refers to it.
      // Mutating currentSong first caused history to be attributed to the next track.
      await _finishHistoryEvent();
      if (!_playbackIntentGate.isCurrent(intentToken)) { try { await incoming.stop(); } catch (_) {} try { await outgoing.setVolume(master); } catch (_) {} return false; }
      // Pause only after volume is already 0 so pause cannot audibly chop the tail.
      try { await outgoing.pause(); } catch (_) {}
      try { await incoming.setLoopMode(LoopMode.off); } catch (_) {}
      try { await incoming.setVolume(master); } catch (_) {}"""

if old_fade_start not in text:
    raise SystemExit("fade block not found — already patched or changed")
text = text.replace(old_fade_start, new_fade, 1)

old_stop = """      await _persistQueue(); _bindActivePlayerStreams(); await _startHistoryEvent(nextSong); _publishServiceState(); notifyListeners(); await outgoing.stop();
      _preloadedNextSongId = null;"""
new_stop = """      await _persistQueue(); _bindActivePlayerStreams(); await _startHistoryEvent(nextSong); _publishServiceState(); notifyListeners();
      try { await outgoing.stop(); } catch (_) {}
      // Restore volume on the now-idle engine so the next time it is used it is not stuck at 0.
      try { await outgoing.setVolume(master); } catch (_) {}
      _preloadedNextSongId = null;"""
if old_stop in text:
    text = text.replace(old_stop, new_stop, 1)
elif "Restore volume on the now-idle engine" not in text:
    raise SystemExit("stop block not found")

path.write_text(text)
assert "startMarginMs" in text
assert "remainingMs" in text
assert "lastOut" in text
print("crossfade outgoing harden applied OK")
