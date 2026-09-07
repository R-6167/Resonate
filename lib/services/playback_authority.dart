import 'dart:async';

import '../providers/music_provider.dart';

/// Central user-command authority for playback.
///
/// Intelligence can recommend or request a transition, but a direct user
/// command always gets priority. Emergency user actions also touch both A/B
/// players before entering the normal serialized path so a transition cannot
/// keep playing behind a paused UI.
class PlaybackAuthority {
  PlaybackAuthority._();
  static final PlaybackAuthority instance = PlaybackAuthority._();

  int _userGeneration = 0;
  String _lastSource = 'normal_player';
  String _lastCommand = 'none';

  int get userGeneration => _userGeneration;
  String get lastSource => _lastSource;
  String get lastCommand => _lastCommand;

  String engineLabel(MusicProvider music) => _engineLabelFor(music.audioPlayer, music);

  Future<void> userPause(MusicProvider music) async {
    _markUser('pause');
    await _pauseBoth(music);
    await music.pause();
  }

  Future<void> userStop(MusicProvider music) async {
    _markUser('stop');
    await _stopBoth(music);
    await music.stop();
  }

  Future<void> userNext(MusicProvider music) async {
    _markUser('next');
    await _stopBoth(music);
    await music.nextSong();
  }

  Future<void> userPrevious(MusicProvider music) async {
    _markUser('previous');
    await _stopBoth(music);
    await music.previousSong();
  }

  Future<void> userToggle(MusicProvider music) async {
    _markUser('toggle');
    if (music.isPlaying) {
      await _pauseBoth(music);
      await music.pause();
    } else {
      await music.togglePlayPause();
    }
  }

  Future<void> userSeek(MusicProvider music, Duration position) async {
    _markUser('seek');
    await _pauseTransitionPlayers(music);
    await music.seek(position);
  }

  void markExternalUserCommand(String source, String command) {
    _userGeneration++;
    _lastSource = source;
    _lastCommand = command;
  }

  bool isStale(int generation) => generation != _userGeneration;

  int beginAutomatic(String command) {
    _lastSource = 'automatic_transition';
    _lastCommand = command;
    return _userGeneration;
  }

  void _markUser(String command) {
    _userGeneration++;
    _lastSource = 'normal_player';
    _lastCommand = command;
  }

  Future<void> _pauseBoth(MusicProvider music) async {
    await _pauseTransitionPlayers(music);
  }

  Future<void> _pauseTransitionPlayers(MusicProvider music) async {
    try { await music.audioPlayer.pause(); } catch (_) {}
    try { await music.inactivePlayer.pause(); } catch (_) {}
  }

  Future<void> _stopBoth(MusicProvider music) async {
    try { await music.audioPlayer.stop(); } catch (_) {}
    try { await music.inactivePlayer.stop(); } catch (_) {}
  }

  static final Map<int, String> _engineIds = <int, String>{};

  String _engineLabelFor(Object player, MusicProvider music) {
    final id = identityHashCode(player);
    final known = _engineIds[id];
    if (known != null) return known;
    final label = _engineIds.isEmpty ? 'A' : (_engineIds.values.contains('A') ? 'B' : 'A');
    _engineIds[id] = label;
    return label;
  }
}
