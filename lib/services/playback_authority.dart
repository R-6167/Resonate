import '../providers/music_provider.dart';

/// Thin command facade for UI surfaces. MusicProvider is the single playback
/// owner and is responsible for intent tokens, priority and diagnostics.
/// Keeping the facade side-effect free prevents one tap from being recorded as
/// two user commands.
class PlaybackAuthority {
  PlaybackAuthority._();
  static final PlaybackAuthority instance = PlaybackAuthority._();

  int get userGeneration => 0;
  String get lastSource => 'normal_player';
  String get lastCommand => 'none';

  String engineLabel(MusicProvider music) => music.audioPlayer == music.inactivePlayer ? 'B' : _engineLabelFor(music);

  Future<void> userPause(MusicProvider music) => music.pause();
  Future<void> userStop(MusicProvider music) => music.stop();
  Future<void> userNext(MusicProvider music) => music.nextSong();
  Future<void> userPrevious(MusicProvider music) => music.previousSong();
  Future<void> userToggle(MusicProvider music) => music.togglePlayPause();
  Future<void> userSeek(MusicProvider music, Duration position) => music.seek(position);

  /// Kept for compatibility with automatic transition code. Automatic work
  /// uses the provider's intent gate; a generation is now represented by the
  /// current user-intent generation in MusicProvider.
  bool isStale(int generation) => false;
  int beginAutomatic(String command) => 0;

  String _engineLabelFor(MusicProvider music) => music.activeEngineLabel == 'A' ? 'A' : 'B';
}
