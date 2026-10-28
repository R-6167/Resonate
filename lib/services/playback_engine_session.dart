import '../models/song.dart';
import 'playback_backend.dart';
import 'playback_observation_source.dart';

/// A complete provider-facing playback session.
///
/// Observations and commands belong to the same session so a future engine
/// cutover cannot accidentally read state from Media3 while sending transport
/// commands to just_audio (or vice versa). Implementations must not be selected
/// for production until the full Resonate playback responsibilities have parity.
abstract interface class PlaybackEngineSession
    implements PlaybackObservationSource {
  Future<void> start();
  List<Song> get queue;

  /// Emits the active native audio session, including changes at deck handoff.
  /// A null value means the backend has no active session to attach DSP to.
  Stream<int?> get audioSessionIdStream;

  Future<void> loadQueue(List<Song> songs, {int startIndex = 0});
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
  Future<void> setShuffleMode(bool enabled);

  Future<void> preloadNext(Song song, {int? queueIndex});
  Future<void> crossfade({required Duration duration});
  Future<void> cancelCrossfade();

  Future<void> dispose();
}
