/// Engine-neutral read-only playback observations consumed by the UI.
///
/// Implementations expose state only; transport commands remain owned by the
/// playback authority/runtime so observing state cannot accidentally issue
/// engine commands.
abstract interface class PlaybackObservationSource {
  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;
  Stream<bool> get playingStream;
}
