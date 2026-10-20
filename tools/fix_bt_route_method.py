#!/usr/bin/env python3
"""Fix build: define _onAudioRouteChanged and correct StreamSubscription type."""
from pathlib import Path

MP = Path('lib/providers/music_provider.dart')
mp = MP.read_text()

# Fix subscription type: devicesChanged emits AudioDevicesChangedEvent, not void.
mp = mp.replace(
    'StreamSubscription<void>? _devicesChangedSubscription;',
    'StreamSubscription<AudioDevicesChangedEvent>? _devicesChangedSubscription;',
    1,
)
print('subscription type')

METHOD = '''
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

if 'Future<void> _onAudioRouteChanged()' not in mp:
    anchor = '  /// Soft-duck both engines so crossfade overlap does not leave one at full level.\n  Future<void> _duckForInterruption() async {'
    if anchor not in mp:
        raise SystemExit('duck anchor miss')
    mp = mp.replace(anchor, METHOD + anchor, 1)
    print('method inserted')
else:
    print('method already present')

# dispose cancel
if '_devicesChangedSubscription?.cancel()' not in mp:
    old = '''    _noisySubscription?.cancel();
    _sessionASub?.cancel();'''
    new = '''    _noisySubscription?.cancel();
    _devicesChangedSubscription?.cancel();
    _sessionASub?.cancel();'''
    if old in mp:
        mp = mp.replace(old, new, 1)
        print('dispose cancel')
    else:
        print('WARN dispose')

MP.write_text(mp)
print('FIX DONE')
