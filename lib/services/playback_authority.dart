import '../providers/music_provider.dart';
import 'resonate_diagnostics.dart';

/// Central playback authority. User commands advance a generation so an
/// Intelligence/automatic transition can detect that the user has taken over.
/// The normal MusicProvider remains the only playback owner.
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
    final wasPlaying = music.isPlaying || music.audioPlayer.playing;
    await _pauseBoth(music);
    await music.seek(position);
    // Seeking is an input, not a request to pause. Resume the same active
    // engine after the seek so fast dragging/10-second jumps stay continuous.
    if (wasPlaying) {
      try {
        await music.audioPlayer.play();
      } catch (_) {}
    }
  }

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

  void _markUser(String command) {
    _userGeneration++;
    _lastSource = 'normal_player';
    _lastCommand = command;
    _recordCommand('normal_player', command);
  }

  void _recordCommand(String source, String command) {
    unawaited(ResonateDiagnostics.recordPlaybackCommand(
      source: source,
      command: command,
      generation: _userGeneration,
    ));
  }

  Future<void> _pauseBoth(MusicProvider music) async {
    try { await music.audioPlayer.pause(); } catch (_) {}
    try { await music.inactivePlayer.pause(); } catch (_) {}
  }

  Future<void> _stopBoth(MusicProvider music) async {
    try { await music.audioPlayer.stop(); } catch (_) {}
    try { await music.inactivePlayer.stop(); } catch (_) {}
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
