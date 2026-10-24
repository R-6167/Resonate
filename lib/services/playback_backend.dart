import '../models/song.dart';
import 'playback_snapshot.dart';

/// The transport/state contract a playback engine must provide to Resonate.
///
/// This contract is engine-neutral. DSP, audio-session routing, leveling,
/// focus ducking, and crossfade must be integrated into the chosen backend's
/// runtime before MusicProvider switches production playback authority.
abstract interface class PlaybackBackend {
  Stream<PlaybackSnapshot> get states;

  Future<void> loadQueue(List<Song> songs, {int startIndex = 0});
  Future<PlaybackSnapshot> currentState();

  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> next();
  Future<void> previous();
  Future<void> setVolume(double value);
  Future<void> setRepeatMode(PlaybackQueueRepeatMode mode);
}

/// Repeat behavior shared by backend implementations.
enum PlaybackQueueRepeatMode {
  off('off'),
  one('one'),
  all('all');

  const PlaybackQueueRepeatMode(this.nativeValue);

  final String nativeValue;
}
