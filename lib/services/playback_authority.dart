import 'dart:async';

import '../providers/music_provider.dart';
import 'resonate_diagnostics.dart';

/// Central playback authority. UI methods delegate to MusicProvider, which is
/// the single owner of intent tokens and command diagnostics. This facade no
/// longer marks the same tap a second time.
class PlaybackAuthority {
  PlaybackAuthority._();
  static final PlaybackAuthority instance = PlaybackAuthority._();

  int _userGeneration = 0;
  String _lastSource = 'normal_player';
  String _lastCommand = 'none';

  int get userGeneration => _userGeneration;
  String get lastSource => _lastSource;
  String get lastCommand => _lastCommand;

  String engineLabel(MusicProvider music) => _engineLabelFor(music.audioPlayer);

  Future<void> userPause(MusicProvider music) => music.pause();
  Future<void> userStop(MusicProvider music) => music.stop();
  Future<void> userNext(MusicProvider music) => music.nextSong();
  Future<void> userPrevious(MusicProvider music) => music.previousSong();
  Future<void> userToggle(MusicProvider music) => music.togglePlayPause();
  Future<void> userSeek(MusicProvider music, Duration position) => music.seek(position);

  void markExternalUserCommand(String source, String command) {
    _userGeneration++;
    _lastSource = source;
    _lastCommand = command;
    _recordCommand(source, command);
  }

  bool isStale(int generation) => generation != _userGeneration;

  int beginAutomatic(String command) {
    _lastSource = 'automatic_transition';
    _lastCommand = command;
    unawaited(ResonateDiagnostics.record('automatic_command_started', {
      'command': command,
      'userCommandGeneration': _userGeneration,
    }));
    return _userGeneration;
  }

  void _recordCommand(String source, String command) {
    unawaited(ResonateDiagnostics.recordPlaybackCommand(source: source, command: command, generation: _userGeneration));
  }

  static final Map<int, String> _engineIds = <int, String>{};

  String _engineLabelFor(Object player) {
    final id = identityHashCode(player);
    final known = _engineIds[id];
    if (known != null) return known;
    final label = _engineIds.isEmpty ? 'A' : (_engineIds.values.contains('A') ? 'B' : 'A');
    _engineIds[id] = label;
    return label;
  }
}
