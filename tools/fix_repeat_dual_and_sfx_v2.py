#!/usr/bin/env python3
"""1) Dual-engine A→B repeat-one with timeout fallback.
2) DJ SFX: no bass boost; vinyl/echo/rewind on outgoing engine.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MUSIC = ROOT / 'lib/providers/music_provider.dart'
SFX = ROOT / 'lib/services/dj_sfx_rack.dart'

SFX_CONTENT = r'''import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audio_effects_bridge.dart';

/// Transition SFX focused on the *outgoing* engine — no bass-boost loudness.
enum DjSfxPreset {
  /// Reverb tail / slap on the fade-out.
  echo,
  /// Speed ramp down on outgoing (classic vinyl stop).
  vinylStop,
  /// Faster pitch-down / rewind feel on outgoing.
  rewind,
  /// High-shelf open on EQ.
  filterOpen,
  /// High-shelf close on EQ.
  filterClose,
  /// Subtle space, no bass.
  tightGlue,
  /// Dry transient via short reverb blip only.
  dryEcho,
}

/// Picks and drives transition SFX without blocking playback.
class DjSfxRack {
  DjSfxRack({math.Random? random}) : _rng = random ?? math.Random();

  final math.Random _rng;
  DjSfxPreset? activePreset;
  bool engaged = false;
  List<double>? _savedEqGains;
  bool _eqTouched = false;
  double _savedOutgoingSpeed = 1.0;
  AudioPlayer? _outgoing;

  static const presets = DjSfxPreset.values;

  DjSfxPreset pickRandom({double energyScore = 0.5}) {
    final high = energyScore >= 0.75;
    // Prefer character FX over loudness FX.
    final weights = <DjSfxPreset, int>{
      DjSfxPreset.echo: high ? 3 : 3,
      DjSfxPreset.vinylStop: high ? 3 : 2,
      DjSfxPreset.rewind: high ? 2 : 2,
      DjSfxPreset.filterOpen: high ? 3 : 2,
      DjSfxPreset.filterClose: high ? 2 : 2,
      DjSfxPreset.tightGlue: high ? 2 : 3,
      DjSfxPreset.dryEcho: high ? 2 : 2,
    };
    final total = weights.values.fold<int>(0, (a, b) => a + b);
    var r = _rng.nextInt(total);
    for (final e in weights.entries) {
      r -= e.value;
      if (r < 0) return e.key;
    }
    return DjSfxPreset.echo;
  }

  Future<void> engage({
    required double energyScore,
    DjSfxPreset? preset,
    AndroidEqualizer? equalizerA,
    AndroidEqualizer? equalizerB,
    AudioPlayer? outgoing,
  }) async {
    final score =
        energyScore.isFinite ? energyScore.clamp(0.0, 1.0).toDouble() : 0.5;
    activePreset = preset ?? pickRandom(energyScore: score);
    engaged = true;
    _eqTouched = false;
    _outgoing = outgoing;
    _savedOutgoingSpeed = 1.0;
    try {
      if (outgoing != null) {
        _savedOutgoingSpeed = outgoing.speed;
      }
    } catch (_) {}

    try {
      await _snapshotEq(equalizerA);
      // Never push bass during transitions — loudness was the main complaint.
      await AudioEffectsBridge.setBassBoost(0.0);
      await _applyFxAt(0.0, score);
      if (_usesEq(activePreset!)) {
        await _applyEqAt(equalizerA, 0.0);
        await _applyEqAt(equalizerB, 0.0);
        _eqTouched = true;
      }
    } catch (e) {
      debugPrint('DjSfxRack.engage: $e');
    }
  }

  /// [t] is 0→1 over the crossfade; >1 is post-gap release.
  Future<void> tick(
    double t, {
    AndroidEqualizer? equalizerA,
    AndroidEqualizer? equalizerB,
    double energyScore = 0.5,
    AudioPlayer? outgoing,
  }) async {
    if (!engaged || activePreset == null) return;
    final score =
        energyScore.isFinite ? energyScore.clamp(0.0, 1.0).toDouble() : 0.5;
    if (outgoing != null) _outgoing = outgoing;
    try {
      await _applyFxAt(t, score);
      if (_usesEq(activePreset!)) {
        await _applyEqAt(equalizerA, t);
        await _applyEqAt(equalizerB, t);
        _eqTouched = true;
      }
    } catch (_) {}
  }

  Future<void> restore({
    AndroidEqualizer? equalizerA,
    AndroidEqualizer? equalizerB,
  }) async {
    if (!engaged && !_eqTouched) return;
    try {
      // Restore outgoing speed first.
      final out = _outgoing;
      if (out != null) {
        try {
          await out.setSpeed(_savedOutgoingSpeed.clamp(0.5, 1.5));
        } catch (_) {
          try {
            await out.setSpeed(1.0);
          } catch (_) {}
        }
      }
      final prefs = await SharedPreferences.getInstance();
      final effectsEnabled = prefs.getBool('effects_enabled') ?? true;
      final reverb = prefs.getDouble('reverb') ?? 0.0;
      final virt = prefs.getDouble('virtualizer') ?? 0.0;
      final bass = prefs.getDouble('bassBoost') ?? 0.0;
      await AudioEffectsBridge.setBassBoost(effectsEnabled ? bass : 0.0);
      await AudioEffectsBridge.setReverb(effectsEnabled ? reverb : 0.0);
      await AudioEffectsBridge.setVirtualizer(effectsEnabled ? virt : 0.0);
      if (_eqTouched) {
        await _restoreEq(equalizerA);
        await _restoreEq(equalizerB);
      }
    } catch (e) {
      debugPrint('DjSfxRack.restore: $e');
    } finally {
      engaged = false;
      _eqTouched = false;
      activePreset = null;
      _savedEqGains = null;
      _outgoing = null;
      _savedOutgoingSpeed = 1.0;
    }
  }

  bool _usesEq(DjSfxPreset p) =>
      p == DjSfxPreset.filterOpen || p == DjSfxPreset.filterClose;

  bool _usesSpeed(DjSfxPreset p) =>
      p == DjSfxPreset.vinylStop || p == DjSfxPreset.rewind;

  double _envelope(double t) {
    if (t <= 0) return 0.0;
    if (t < 0.15) return (t / 0.15).clamp(0.0, 1.0);
    if (t <= 1.0) return 1.0;
    return ((1.55 - t) / 0.55).clamp(0.0, 1.0);
  }

  Future<void> _applyFxAt(double t, double score) async {
    final p = activePreset ?? DjSfxPreset.echo;
    final env = _envelope(t);
    final x = t.clamp(0.0, 1.0);
    // No bass path at all during SFX.
    await AudioEffectsBridge.setBassBoost(0.0);

    double width = 0.0;
    double reverb = 0.0;
    switch (p) {
      case DjSfxPreset.echo:
        width = (0.04 + 0.10 * x).clamp(0.0, 0.18);
        reverb = (0.22 + 0.28 * math.sin(x * math.pi)).clamp(0.12, 0.48);
        break;
      case DjSfxPreset.vinylStop:
      case DjSfxPreset.rewind:
        width = (0.06 * (1.0 - x)).clamp(0.0, 0.10);
        reverb = (0.08 + 0.12 * x).clamp(0.04, 0.22);
        break;
      case DjSfxPreset.filterOpen:
      case DjSfxPreset.filterClose:
        width = (0.05 + 0.08 * x).clamp(0.0, 0.16);
        reverb = (0.08 + 0.10 * math.sin(x * math.pi)).clamp(0.04, 0.22);
        break;
      case DjSfxPreset.tightGlue:
        width = (0.04 + 0.06 * x).clamp(0.0, 0.12);
        reverb = (0.14 + 0.16 * math.sin(x * math.pi)).clamp(0.08, 0.32);
        break;
      case DjSfxPreset.dryEcho:
        width = 0.03;
        reverb = (0.16 * math.sin(x * math.pi)).clamp(0.0, 0.22);
        break;
    }
    final energyScale = score >= 0.85 ? 0.7 : (score >= 0.7 ? 0.85 : 1.0);
    width = (width * env * energyScale).clamp(0.0, 0.28);
    reverb = (reverb * env * energyScale).clamp(0.0, 0.48);
    await AudioEffectsBridge.setVirtualizer(width);
    await AudioEffectsBridge.setReverb(reverb);

    // Outgoing engine speed for vinyl / rewind character.
    if (_usesSpeed(p) && _outgoing != null) {
      double speed;
      if (p == DjSfxPreset.vinylStop) {
        // 1.0 → ~0.55 over the fade (tape/vinyl stop).
        speed = (1.0 - 0.45 * x).clamp(0.55, 1.0);
      } else {
        // Rewind: slightly faster dive.
        speed = (1.0 - 0.55 * x).clamp(0.45, 1.0);
      }
      try {
        await _outgoing!.setSpeed(speed);
      } catch (_) {}
    }
  }

  Future<void> _snapshotEq(AndroidEqualizer? eq) async {
    if (eq == null) return;
    try {
      final p = await eq.parameters;
      _savedEqGains = [for (final b in p.bands) b.gain];
    } catch (_) {
      _savedEqGains = null;
    }
  }

  Future<void> _applyEqAt(AndroidEqualizer? eq, double t) async {
    if (eq == null || activePreset == null) return;
    try {
      final p = await eq.parameters;
      final bands = p.bands;
      if (bands.isEmpty) return;
      final n = bands.length;
      final minG = p.minDecibels;
      final maxG = p.maxDecibels;
      final env = _envelope(t);
      final x = t.clamp(0.0, 1.0);
      for (var i = 0; i < n; i++) {
        final frac = n <= 1 ? 0.5 : i / (n - 1);
        double gain = 0.0;
        switch (activePreset!) {
          case DjSfxPreset.filterOpen:
            gain = -6.0 * (1.0 - x) * frac;
            break;
          case DjSfxPreset.filterClose:
            gain = -5.5 * (1.0 - x) * (1.0 - frac);
            break;
          default:
            gain = 0.0;
        }
        gain *= env;
        await bands[i].setGain(gain.clamp(minG, maxG).toDouble());
      }
      await eq.setEnabled(true);
    } catch (_) {}
  }

  Future<void> _restoreEq(AndroidEqualizer? eq) async {
    if (eq == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final eqOn = prefs.getBool('equalizer_enabled') ?? true;
      final p = await eq.parameters;
      final bands = p.bands;
      for (var i = 0; i < bands.length; i++) {
        double g = 0.0;
        if (_savedEqGains != null && i < _savedEqGains!.length) {
          g = _savedEqGains![i];
        } else {
          g = prefs.getDouble('eq_band_${bands[i].index}') ?? 0.0;
        }
        await bands[i]
            .setGain(g.clamp(p.minDecibels, p.maxDecibels).toDouble());
      }
      await eq.setEnabled(eqOn);
    } catch (_) {}
  }

  String get presetName => activePreset?.name ?? 'none';
}
'''


def try_replace(path: Path, old: str, new: str, label: str) -> bool:
    t = path.read_text()
    if old not in t:
        print('skip', label)
        return False
    path.write_text(t.replace(old, new, 1))
    print('ok', label)
    return True


def main() -> None:
    SFX.write_text(SFX_CONTENT)
    print('ok wrote sfx rack')

    # Pass outgoing player into SFX engage/tick
    try_replace(
        MUSIC,
        """      await _djSfxRack.engage(
        energyScore: energyScore,
        equalizerA: _equalizerA,
        equalizerB: _equalizerB,
      );""",
        """      await _djSfxRack.engage(
        energyScore: energyScore,
        equalizerA: _equalizerA,
        equalizerB: _equalizerB,
        outgoing: audioPlayer,
      );""",
        'sfx_engage_outgoing',
    )

    try_replace(
        MUSIC,
        """    await _djSfxRack.tick(
      t,
      equalizerA: _equalizerA,
      equalizerB: _equalizerB,
      energyScore: _lastDjEnergyScore,
    );""",
        """    await _djSfxRack.tick(
      t,
      equalizerA: _equalizerA,
      equalizerB: _equalizerB,
      energyScore: _lastDjEnergyScore,
      outgoing: audioPlayer,
    );""",
        'sfx_tick_outgoing',
    )

    # Dual-engine repeat-one trigger (prefer A→B; soft fallback inside)
    try_replace(
        MUSIC,
        """    // Repeat-one: soft single-engine loop (same MediaStore URI on two
    // engines hangs on many OEMs — dual path removed for reliability).
    if (_repeatMode == PlaybackRepeatMode.one) {
      if (!_crossfadeEnabled || _repeatSelfHandoffInFlight || _transportInFlight) {
        return;
      }
      if (currentSong == null) return;
      // Short loop fade: long dual fades were arming late and never committing.
      final loopMs = _crossfadeDurationMs.clamp(800, 3500);
      final triggerMs = (loopMs + 400).clamp(1200, 4000);
      if (remaining > Duration(milliseconds: triggerMs)) return;
      if (remaining < const Duration(milliseconds: 250)) return;
      _repeatSelfHandoffInFlight = true;
      _automaticCrossfadeInFlight = true;
      unawaited(_runRepeatSelfSoftLoop(loopMs: loopMs));
      return;
    }""",
        """    // Repeat-one + crossfade: dual-engine A→B self-handoff (same song).
    // Soft single-engine loop is the fallback if the idle engine load times out.
    if (_repeatMode == PlaybackRepeatMode.one) {
      if (!_crossfadeEnabled ||
          _repeatSelfHandoffInFlight ||
          _transportInFlight ||
          _crossfadeInProgress) {
        return;
      }
      if (currentSong == null) return;
      // Keep the blend short so we start near the true end (not mid-outro).
      final loopMs = _crossfadeDurationMs.clamp(1200, 4000);
      final triggerMs = (loopMs + 500).clamp(1500, 4500);
      if (remaining > Duration(milliseconds: triggerMs)) return;
      // Do not start if already past the end window.
      if (remaining < const Duration(milliseconds: 400)) return;
      _repeatSelfHandoffInFlight = true;
      _automaticCrossfadeInFlight = true;
      unawaited(_runRepeatSelfDualOrSoft(loopMs: loopMs));
      return;
    }""",
        'repeat_dual_trigger',
    )

    # Insert dual-or-soft runner before soft loop
    try_replace(
        MUSIC,
        """  /// Soft loop: fade out → seek(0) → fade in on the *active* engine only.
  /// Avoids loading the same content:// URI on A and B (OEM hang / static).
  Future<void> _runRepeatSelfSoftLoop({required int loopMs}) async {""",
        """  /// Prefer dual-engine A→B self-crossfade; fall back to soft loop on timeout.
  Future<void> _runRepeatSelfDualOrSoft({required int loopMs}) async {
    final song = currentSong;
    if (song == null) {
      _automaticCrossfadeInFlight = false;
      _repeatSelfHandoffInFlight = false;
      return;
    }
    final ms = loopMs.clamp(1200, 4000);
    final ok = await _performRepeatSelfDual(milliseconds: ms).timeout(
      Duration(milliseconds: ms + 4500),
      onTimeout: () {
        debugPrint('repeat self dual timed out');
        return false;
      },
    );
    if (ok) {
      _automaticCrossfadeInFlight = false;
      _crossfadeInProgress = false;
      _repeatSelfHandoffInFlight = false;
      _repeatSelfHandoffArmed = false;
      return;
    }
    unawaited(ResonateDiagnostics.record('repeat_self_fallback', {
      'reason': 'dual_timeout_or_fail',
      'songId': song.id,
    }));
    await _runRepeatSelfSoftLoop(loopMs: math.min(ms, 2000));
  }

  Future<bool> _performRepeatSelfDual({required int milliseconds}) async {
    final song = currentSong;
    if (song == null || song.filePath.trim().isEmpty) return false;
    if (!audioPlayer.playing && !_userWantsPlaying) return false;
    _crossfadeInProgress = true;
    final outgoing = audioPlayer;
    final incoming = inactivePlayer;
    final incomingEq = inactiveEqualizer;
    final incomingLoud = inactiveLoudnessEnhancer;
    final master = _eqPreampScale.clamp(0.05, 1.0);
    final ms = milliseconds.clamp(1200, 4000);
    try {
      try {
        await incoming.stop();
      } catch (_) {}
      // Load with a hard timeout — same MediaStore URI can hang on some OEMs.
      await _loadSingle(
        incoming,
        incomingEq,
        incomingLoud,
        song,
        start: false,
      ).timeout(const Duration(milliseconds: 2800));
      try {
        await incoming.seek(Duration.zero);
      } catch (_) {}
      await incoming.setVolume(0.0);
      try {
        final session = await AudioSession.instance;
        await session.setActive(true);
      } catch (_) {}
      try {
        incoming.play();
      } catch (_) {}
      for (var i = 0; i < 8 && !incoming.playing; i++) {
        await Future<void>.delayed(Duration(milliseconds: 30 + i * 25));
        try {
          incoming.play();
        } catch (_) {}
      }
      if (!incoming.playing) return false;

      unawaited(ResonateDiagnostics.record('repeat_self_ramp', {
        'mode': 'dual',
        'songId': song.id,
        'ms': ms,
        'fromEngine': _activeIsA ? 'A' : 'B',
        'toEngine': _activeIsA ? 'B' : 'A',
      }));

      final steps = (ms / 40).round().clamp(10, 60);
      final stepMs = (ms / steps).round().clamp(20, 60);
      final startOut = outgoing.volume.clamp(0.05, 1.0);
      for (var i = 1; i <= steps; i++) {
        if (!_userWantsPlaying || !_repeatSelfHandoffInFlight) return false;
        final t = i / steps;
        try {
          await outgoing.setVolume((startOut * (1.0 - t)).clamp(0.0, 1.0));
        } catch (_) {}
        try {
          await incoming.setVolume((master * t).clamp(0.0, 1.0));
        } catch (_) {}
        await Future<void>.delayed(Duration(milliseconds: stepMs));
      }

      _activeIsA = !_activeIsA;
      _lastCompletionSongId = null;
      currentPosition = incoming.position;
      currentDuration = song.duration;
      isPlaying = incoming.playing || _userWantsPlaying;
      _bindActivePlayerStreams();
      _publishServiceState();
      notifyListeners();

      try {
        await outgoing.pause();
      } catch (_) {}
      try {
        await outgoing.setVolume(master);
      } catch (_) {}
      try {
        await outgoing.setSpeed(1.0);
      } catch (_) {}
      try {
        await incoming.setVolume(master);
      } catch (_) {}

      unawaited(ResonateDiagnostics.record('repeat_self_committed', {
        'mode': 'dual',
        'songId': song.id,
        'activeEngine': _activeIsA ? 'A' : 'B',
        'playing': incoming.playing,
      }));
      return true;
    } catch (e, st) {
      debugPrint('repeat dual failed: $e');
      debugPrint('$st');
      try {
        await incoming.pause();
      } catch (_) {}
      try {
        await incoming.setVolume(0.0);
      } catch (_) {}
      try {
        await outgoing.setVolume(master);
      } catch (_) {}
      return false;
    }
  }

  /// Soft loop: fade out → seek(0) → fade in on the *active* engine only.
  /// Avoids loading the same content:// URI on A and B (OEM hang / static).
  Future<void> _runRepeatSelfSoftLoop({required int loopMs}) async {""",
        'dual_runner',
    )

    print('repeat dual + sfx v2 done')


if __name__ == '__main__':
    main()
