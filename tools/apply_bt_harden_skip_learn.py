#!/usr/bin/env python3
"""Bluetooth route recovery + deeper early-skip transition memory."""
from pathlib import Path

# ---------- Transition memory: weighted outcomes ----------
TM = Path('lib/services/dj_transition_memory.dart')
tm = TM.read_text()
if 'weight' not in tm or 'required int weight' not in tm:
    old = '''  static Future<void> recordOutcome({
    required String fromId,
    required String toId,
    required String strategy,
    required bool successful,
  }) async {
    if (fromId.isEmpty || toId.isEmpty) return;
    try {
      final map = await _load();
      final key = _pairKey(fromId, toId);
      final row = Map<String, dynamic>.from(map[key] ?? <String, dynamic>{});
      row['strategy'] = strategy;
      if (successful) {
        row['ok'] = ((row['ok'] as num?)?.toInt() ?? 0) + 1;
      } else {
        row['bad'] = ((row['bad'] as num?)?.toInt() ?? 0) + 1;
      }'''
    new = '''  static Future<void> recordOutcome({
    required String fromId,
    required String toId,
    required String strategy,
    required bool successful,
    int weight = 1,
  }) async {
    if (fromId.isEmpty || toId.isEmpty) return;
    final w = weight.clamp(1, 5);
    try {
      final map = await _load();
      final key = _pairKey(fromId, toId);
      final row = Map<String, dynamic>.from(map[key] ?? <String, dynamic>{});
      row['strategy'] = strategy;
      if (successful) {
        row['ok'] = ((row['ok'] as num?)?.toInt() ?? 0) + w;
      } else {
        row['bad'] = ((row['bad'] as num?)?.toInt() ?? 0) + w;
      }'''
    if old not in tm:
        raise SystemExit('tm recordOutcome miss')
    tm = tm.replace(old, new, 1)
    print('tm weight')
TM.write_text(tm)

# ---------- music_provider: route change recovery + stronger skip learn ----------
MP = Path('lib/providers/music_provider.dart')
mp = MP.read_text()

# Add devices subscription field near other subs
if '_devicesChangedSubscription' not in mp:
    mp = mp.replace(
        '  StreamSubscription<void>? _noisySubscription;',
        '  StreamSubscription<void>? _noisySubscription;\n  StreamSubscription<void>? _devicesChangedSubscription;\n  DateTime? _lastRouteRecoverAt;',
        1,
    )
    print('devices field')

# Hook devicesChanged in _configureAudioSession after noisy subscription
if 'devicesChangedEventStream' not in mp:
    old_noisy = '''      _noisySubscription = session.becomingNoisyEventStream.listen((_) {
        // Headphones unplugged: treat as user-facing pause (do not auto-resume).
        if (isPlaying || _userWantsPlaying) {
          unawaited(pause(source: 'becoming_noisy'));
        }
      });'''
    new_noisy = '''      _noisySubscription = session.becomingNoisyEventStream.listen((_) {
        // Headphones unplugged: treat as user-facing pause (do not auto-resume).
        if (isPlaying || _userWantsPlaying) {
          unawaited(pause(source: 'becoming_noisy'));
        }
      });
      // Bluetooth / headset route changes often leave volume or focus stuck silent.
      try {
        await _devicesChangedSubscription?.cancel();
      } catch (_) {}
      _devicesChangedSubscription =
          session.devicesChangedEventStream.listen((_) {
        unawaited(_onAudioRouteChanged());
      });'''
    if old_noisy not in mp:
        raise SystemExit('noisy block miss')
    mp = mp.replace(old_noisy, new_noisy, 1)
    print('devices stream')

# Add _onAudioRouteChanged method after _maybeRecoverSilentPlayback or _unduck
if '_onAudioRouteChanged' not in mp:
    method = '''
  /// BT/headset route change: re-claim session and force audible volume.
  /// OEMs often take 0.5–3s to settle A2DP; we pulse volume a few times.
  Future<void> _onAudioRouteChanged() async {
    final now = DateTime.now();
    if (_lastRouteRecoverAt != null &&
        now.difference(_lastRouteRecoverAt!) < const Duration(milliseconds: 800)) {
      return;
    }
    _lastRouteRecoverAt = now;
    try {
      await ResonateDiagnostics.record('audio_route_changed', {
        'userWantsPlaying': _userWantsPlaying,
        'isPlaying': isPlaying,
        'crossfade': _crossfadeInProgress,
        'songId': currentSong?.id,
      });
    } catch (_) {}
    if (!_userWantsPlaying) return;
    if (_crossfadeInProgress || _automaticCrossfadeInFlight) return;
    try {
      final session = await AudioSession.instance;
      try {
        await session.setActive(true);
      } catch (_) {}
    } catch (_) {}
    // Staggered volume/play kicks while the BT stack finishes routing.
    for (final delayMs in <int>[200, 700, 1600, 3200]) {
      await Future<void>.delayed(Duration(milliseconds: delayMs));
      if (!_userWantsPlaying) return;
      if (_crossfadeInProgress || _automaticCrossfadeInFlight) return;
      try {
        await _recoverDjEngineState(reason: 'audio_route_changed');
      } catch (_) {}
      try {
        final active = audioPlayer;
        final vol = (_volume * _eqPreampScale).clamp(0.05, 1.0);
        await active.setVolume(vol);
        if (_userWantsPlaying && !active.playing) {
          try {
            await active.play();
          } catch (_) {}
        }
      } catch (_) {}
    }
    try {
      await ResonateDiagnostics.record('audio_route_recover_done', {
        'playing': audioPlayer.playing,
        'volume': audioPlayer.volume,
        'songId': currentSong?.id,
      });
    } catch (_) {}
  }

'''
    # insert before _duckForInterruption
    if 'Future<void> _duckForInterruption()' in mp:
        mp = mp.replace(
            '  /// Soft-duck both engines so crossfade overlap does not leave one at full level.\n  Future<void> _duckForInterruption() async {',
            method + '  /// Soft-duck both engines so crossfade overlap does not leave one at full level.\n  Future<void> _duckForInterruption() async {',
            1,
        )
        print('route recover method')
    else:
        print('WARN duck marker')

# Strengthen silent watchdog: also recover when volume low after longer silence
old_watch = '''  void _maybeRecoverSilentPlayback() {
    if (_crossfadeInProgress || _automaticCrossfadeInFlight) return;
    if (!_userWantsPlaying) return;
    try {
      final active = audioPlayer;
      if (!active.playing) return;
      if (active.volume >= 0.05) return;
      final now = DateTime.now();
      if (_lastSilentRecoverAt != null &&
          now.difference(_lastSilentRecoverAt!) < const Duration(seconds: 3)) {
        return;
      }
      _lastSilentRecoverAt = now;
      unawaited(_recoverDjEngineState(reason: 'silent_watchdog'));
    } catch (_) {}
  }'''
new_watch = '''  void _maybeRecoverSilentPlayback() {
    if (_crossfadeInProgress || _automaticCrossfadeInFlight) return;
    if (!_userWantsPlaying) return;
    try {
      final active = audioPlayer;
      // Playing but muted, or wants play but engine not playing (BT route lag).
      final mutedWhilePlaying =
          active.playing && active.volume < 0.05;
      final wantsButStopped = !active.playing;
      if (!mutedWhilePlaying && !wantsButStopped) return;
      final now = DateTime.now();
      final cooldown = wantsButStopped
          ? const Duration(seconds: 2)
          : const Duration(seconds: 3);
      if (_lastSilentRecoverAt != null &&
          now.difference(_lastSilentRecoverAt!) < cooldown) {
        return;
      }
      _lastSilentRecoverAt = now;
      unawaited(() async {
        try {
          final session = await AudioSession.instance;
          await session.setActive(true);
        } catch (_) {}
        await _recoverDjEngineState(reason: mutedWhilePlaying
            ? 'silent_watchdog'
            : 'silent_watchdog_not_playing');
        if (_userWantsPlaying && !audioPlayer.playing) {
          try {
            await audioPlayer.play();
          } catch (_) {}
        }
        try {
          await ResonateDiagnostics.record('playback_volume_unstick', {
            'reason': mutedWhilePlaying ? 'muted' : 'not_playing',
            'volume': audioPlayer.volume,
            'playing': audioPlayer.playing,
            'songId': currentSong?.id,
          });
        } catch (_) {}
      }());
    } catch (_) {}
  }'''
if old_watch in mp:
    mp = mp.replace(old_watch, new_watch, 1)
    print('watchdog stronger')
else:
    print('WARN watchdog miss')

# Deeper early-skip learn in nextSong
old_skip = '''          if (handoffAt != null &&
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
          }'''
new_skip = '''          if (handoffAt != null &&
              fromId != null &&
              toId != null &&
              strategy != null &&
              currentSong?.id == toId) {
            final age = DateTime.now().difference(handoffAt);
            final posMs = currentPosition.inMilliseconds;
            final durMs = (currentDuration ?? currentSong?.duration)?.inMilliseconds ?? 0;
            final earlyByTime = age < const Duration(seconds: 120) && posMs < 45000;
            final earlyByRatio =
                durMs > 0 && posMs < (durMs * 0.35).round() && age < const Duration(minutes: 3);
            if (earlyByTime || earlyByRatio) {
              // Heavier penalty the earlier the skip (deeper transition memory).
              final weight = posMs < 5000
                  ? 4
                  : posMs < 15000
                      ? 3
                      : posMs < 30000
                          ? 2
                          : 1;
              unawaited(DjTransitionMemory.recordOutcome(
                fromId: fromId,
                toId: toId,
                strategy: strategy,
                successful: false,
                weight: weight,
              ));
              unawaited(ResonateDiagnostics.recordDj(
                stage: 'learn',
                outcome: 'early_skip',
                reason: strategy,
                songId: toId,
                extra: {
                  'fromId': fromId,
                  'positionMs': posMs,
                  'weight': weight,
                  'ageMs': age.inMilliseconds,
                },
              ));
              _lastDjHandoffAt = null;
            }
          }'''
if old_skip in mp:
    mp = mp.replace(old_skip, new_skip, 1)
    print('early skip deeper')
else:
    print('WARN early skip miss')

# Dispose devices sub if dispose exists
if '_devicesChangedSubscription' in mp and 'await _noisySubscription?.cancel()' in mp:
    mp = mp.replace(
        'await _noisySubscription?.cancel();',
        'await _noisySubscription?.cancel();\n    try { await _devicesChangedSubscription?.cancel(); } catch (_) {}',
        1,
    )
    print('dispose devices')

MP.write_text(mp)
print('BT+SKIP APPLY DONE')
