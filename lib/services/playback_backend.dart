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
  Future<void> setGainFactors({
    double? trackLevel,
    double? preamp,
    double? sleepFade,
    double? focusDuck,
  });
  Future<void> setRepeatMode(PlaybackQueueRepeatMode mode);
}

/// Optional crossfade capability for engines that own two synchronized decks.
/// A backend without this capability must not emulate a crossfade by starting a
/// second independent playback authority.
abstract interface class PlaybackCrossfadeBackend {
  Future<void> preloadNext(Song song);
  Future<void> crossfade({required Duration duration});
  Future<void> cancelCrossfade();
}

/// Repeat behavior shared by backend implementations.
enum PlaybackQueueRepeatMode {
  off('off'),
  one('one'),
  all('all');

  const PlaybackQueueRepeatMode(this.nativeValue);

  final String nativeValue;
}
