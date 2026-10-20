#!/usr/bin/env python3
"""Fix silent playback when DJ Mode tempo stretch / handoff leaves engines muted."""
from pathlib import Path
MP = Path(__file__).resolve().parents[1] / "lib/providers/music_provider.dart"
EST = Path(__file__).resolve().parents[1] / "lib/services/dj_bpm_estimator.dart"

def main() -> int:
    t = MP.read_text()
    if "_recoverDjEngineState" in t and "dj_mode_disabled" in t:
        print("silence fix already in music_provider")
    else:
        n = 0
        old_cfg = """  void configureDjMode({
    required bool beatAlignActive,
    bool tempoMatchActive = false,
    int maxStretchPercent = 12,
    DjAnalysisService? analysis,
  }) {
    _djBeatAlignActive = beatAlignActive;
    _djTempoMatchActive = tempoMatchActive;
    _djMaxStretchPercent = maxStretchPercent.clamp(3, 20);
    _djAnalysis = analysis;
  }"""
        new_cfg = """  void configureDjMode({
    required bool beatAlignActive,
    bool tempoMatchActive = false,
    int maxStretchPercent = 12,
    DjAnalysisService? analysis,
  }) {
    final wasActive = _djBeatAlignActive || _djTempoMatchActive;
    _djBeatAlignActive = beatAlignActive;
    _djTempoMatchActive = tempoMatchActive;
    _djMaxStretchPercent = maxStretchPercent.clamp(3, 20);
    _djAnalysis = analysis;
    if (wasActive && !beatAlignActive && !tempoMatchActive) {
      unawaited(_recoverDjEngineState(reason: 'dj_mode_disabled'));
    }
  }

  /// Restore normal speed + audible volume after DJ handoff mistakes.
  Future<void> _recoverDjEngineState({String reason = 'recover'}) async {
    try {
      await _clearDjStretchSpeeds(outgoing: _playerA, incoming: _playerB);
    } catch (_) {}
    try {
      final active = audioPlayer;
      final inactive = inactivePlayer;
      final vol = _eqPreampScale.clamp(0.05, 1.0);
      try {
        await active.setSpeed(1.0);
      } catch (_) {}
      try {
        await inactive.setSpeed(1.0);
      } catch (_) {}
      try {
        if (active.playing && active.volume < 0.02) {
          await active.setVolume(vol);
        }
      } catch (_) {}
      try {
        await inactive.setVolume(0.0);
      } catch (_) {}
      await ResonateDiagnostics.recordDj(
        stage: 'engine_recover',
        outcome: 'applied',
        reason: reason,
        extra: {
          'activeVolume': active.volume,
          'activePlaying': active.playing,
          'activeEngine': _activeIsA ? 'A' : 'B',
        },
      );
    } catch (e) {
      debugPrint('DJ engine recover failed: $e');
    }
  }"""
        if old_cfg in t:
            t = t.replace(old_cfg, new_cfg, 1)
            n += 1
            print("patched configureDjMode")
        else:
            print("MISS configureDjMode")

        old_load = """  Future<void> _loadSingle(AudioPlayer player, AndroidEqualizer eq, AndroidLoudnessEnhancer loud, Song song, {bool start = true}) async {
    await player.setLoopMode(LoopMode.off);
    await player.setAudioSource(AudioSource.uri(_audioUri(song.filePath), tag: song));
    unawaited(_enableEffects(player, eq, loud));
    await player.setVolume(start ? 1.0 : 0.0);"""
        new_load = """  Future<void> _loadSingle(AudioPlayer player, AndroidEqualizer eq, AndroidLoudnessEnhancer loud, Song song, {bool start = true}) async {
    await player.setLoopMode(LoopMode.off);
    try {
      await player.setSpeed(1.0);
    } catch (_) {}
    await player.setAudioSource(AudioSource.uri(_audioUri(song.filePath), tag: song));
    unawaited(_enableEffects(player, eq, loud));
    await player.setVolume(start ? _eqPreampScale.clamp(0.05, 1.0) : 0.0);"""
        if old_load in t:
            t = t.replace(old_load, new_load, 1)
            n += 1
            print("patched loadSingle")
        else:
            print("MISS loadSingle")

        old_xfade = """    _crossfadeInProgress = true; final outgoing = audioPlayer; final outgoingSong = currentSong; final incoming = inactivePlayer; final incomingEq = inactiveEqualizer; final incomingLoud = inactiveLoudnessEnhancer; final master = _eqPreampScale;
    try {
      await outgoing.setLoopMode(LoopMode.off);"""
        new_xfade = """    _crossfadeInProgress = true; final outgoing = audioPlayer; final outgoingSong = currentSong; final incoming = inactivePlayer; final incomingEq = inactiveEqualizer; final incomingLoud = inactiveLoudnessEnhancer; final master = _eqPreampScale.clamp(0.05, 1.0);
    try {
      await _clearDjStretchSpeeds(outgoing: outgoing, incoming: incoming);
      await outgoing.setLoopMode(LoopMode.off);"""
        if old_xfade in t:
            t = t.replace(old_xfade, new_xfade, 1)
            n += 1
            print("patched xfade start")
        else:
            print("MISS xfade start")

        old_stretch = """      if (stretch != null) {
        try {
          await outgoing.setSpeed(stretch.speedOutgoing);
        } catch (_) {}
        try {
          await incoming.setSpeed(stretch.speedIncoming);
        } catch (_) {}
        _djStretchSpeedOut = stretch.speedOutgoing;
        _djStretchSpeedIn = stretch.speedIncoming;
        await ResonateDiagnostics.record('dj_tempo_match_applied', {
          'outgoingSongId': outgoingSong.id,
          'incomingSongId': incomingSong.id,
          'bpmA': bpmA,
          'bpmB': bpmB,
          'speedOut': stretch.speedOutgoing,
          'speedIn': stretch.speedIncoming,
          'mode': stretch.mode,
          'effectiveBpm': stretch.effectiveBpm,
        });
      }"""
        new_stretch = """      if (stretch != null) {
        try {
          if ((stretch.speedOutgoing - 1.0).abs() > 0.001) {
            await outgoing.setSpeed(stretch.speedOutgoing);
          }
          await incoming.setSpeed(stretch.speedIncoming);
          _djStretchSpeedOut = stretch.speedOutgoing;
          _djStretchSpeedIn = stretch.speedIncoming;
          await ResonateDiagnostics.record('dj_tempo_match_applied', {
            'outgoingSongId': outgoingSong.id,
            'incomingSongId': incomingSong.id,
            'bpmA': bpmA,
            'bpmB': bpmB,
            'speedOut': stretch.speedOutgoing,
            'speedIn': stretch.speedIncoming,
            'mode': stretch.mode,
            'effectiveBpm': stretch.effectiveBpm,
          });
        } catch (e) {
          await _clearDjStretchSpeeds(outgoing: outgoing, incoming: incoming);
          await ResonateDiagnostics.recordDj(
            stage: 'tempo_match',
            outcome: 'failed',
            reason: e.toString(),
            songId: incomingSong.id,
          );
        }
      }"""
        if old_stretch in t:
            t = t.replace(old_stretch, new_stretch, 1)
            n += 1
            print("patched stretch")
        else:
            print("MISS stretch")

        old_commit = """      try { await incoming.setVolume(master); } catch (_) {}
      await _clearDjStretchSpeeds(outgoing: outgoing, incoming: incoming);
      _activeIsA = !_activeIsA; // Phase 2: only crossfade may leave Engine B active"""
        new_commit = """      try { await incoming.setVolume(master); } catch (_) {}
      await _clearDjStretchSpeeds(outgoing: outgoing, incoming: incoming);
      try {
        if (incoming.volume < 0.05) await incoming.setVolume(master);
      } catch (_) {}
      _activeIsA = !_activeIsA; // Phase 2: only crossfade may leave Engine B active"""
        if old_commit in t:
            t = t.replace(old_commit, new_commit, 1)
            n += 1
            print("patched commit")
        else:
            print("MISS commit")

        old_ensure = """  void _ensureEngineA({String reason = 'default'}) {
    if (_activeIsA) return;
    _activeIsA = true;
    _bindActivePlayerStreams();
    unawaited(ResonateDiagnostics.record('engine_policy', {
      'action': 'promote_a',
      'reason': reason,
      'songId': currentSong?.id,
      'queueIndex': _queueIndex,
    }));
    // Quiet B so it cannot steal focus after a crossfade.
    unawaited(() async {
      try {
        await _playerB.pause();
      } catch (_) {}
      try {
        await _playerB.setVolume(0.0);
      } catch (_) {}
    }());
  }"""
        new_ensure = """  void _ensureEngineA({String reason = 'default'}) {
    if (_activeIsA) return;
    _activeIsA = true;
    _bindActivePlayerStreams();
    unawaited(ResonateDiagnostics.record('engine_policy', {
      'action': 'promote_a',
      'reason': reason,
      'songId': currentSong?.id,
      'queueIndex': _queueIndex,
    }));
    unawaited(() async {
      try {
        await _playerB.setSpeed(1.0);
      } catch (_) {}
      try {
        await _playerA.setSpeed(1.0);
      } catch (_) {}
      try {
        await _playerB.pause();
      } catch (_) {}
      try {
        await _playerB.setVolume(0.0);
      } catch (_) {}
    }());
  }"""
        if old_ensure in t:
            t = t.replace(old_ensure, new_ensure, 1)
            n += 1
            print("patched ensure")
        else:
            print("MISS ensure")

        MP.write_text(t)
        print("music_provider patches", n)

    if EST.exists():
        e = EST.read_text()
        old_mid = """  final mid = (bpmA + bpmB) / 2.0;
  final speedA = mid / bpmA;
  final speedB = mid / bpmB;
  if (within(speedA) && within(speedB)) {
    return DjTempoStretchPlan(
      speedOutgoing: speedA,
      speedIncoming: speedB,
      effectiveBpm: mid,
      mode: 'meet_middle',
    );
  }
  return null;"""
        new_mid = """  // meet_middle stretches the audible outgoing deck — skip for stability.
  return null;"""
        if old_mid in e:
            EST.write_text(e.replace(old_mid, new_mid, 1))
            print("estimator meet_middle disabled")
        elif "meet_middle stretches" in e:
            print("estimator already")
        else:
            print("MISS estimator mid")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
