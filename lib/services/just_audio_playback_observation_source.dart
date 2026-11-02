import 'package:just_audio/just_audio.dart';

import 'playback_observation_source.dart';

/// Read-only observation adapter for the current dual just_audio engines.
///
/// The active player is resolved for each subscription request, so a widget
/// rebuilding after an A/B handoff subscribes to the newly active engine.
/// This adapter does not own players or issue playback commands.
class JustAudioPlaybackObservationSource implements PlaybackObservationSource {
  JustAudioPlaybackObservationSource(this._activePlayer);

  final AudioPlayer Function() _activePlayer;

  @override
  Stream<Duration> get positionStream => _activePlayer().positionStream;

  @override
  Stream<Duration> get bufferedPositionStream =>
      _activePlayer().bufferedPositionStream;

  @override
  Stream<Duration?> get durationStream => _activePlayer().durationStream;

  @override
  Stream<bool> get playingStream => _activePlayer().playerStateStream.map(
        (state) => state.playing &&
            state.processingState != ProcessingState.completed,
      );

  @override
  Stream<bool> get bufferingStream => _activePlayer().playerStateStream.map(
        (state) => state.processingState == ProcessingState.buffering,
      );

  @override
  Stream<bool> get completedStream => _activePlayer().playerStateStream.map(
        (state) => state.processingState == ProcessingState.completed,
      );
}
