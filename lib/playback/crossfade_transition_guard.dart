/// Snapshot of the playback state that an automatic crossfade is allowed to own.
/// It does not cancel work or touch audio engines; it only centralizes the
/// identity checks used before fallback playback can commit.
class CrossfadeTransitionGuard {
  const CrossfadeTransitionGuard({
    required this.userTransportEpoch,
    required this.transitionGeneration,
    required this.outgoingSongId,
    required this.queueIndex,
  });

  final int userTransportEpoch;
  final int transitionGeneration;
  final String? outgoingSongId;
  final int queueIndex;

  bool matches({
    required int userTransportEpoch,
    required int transitionGeneration,
    required String? currentSongId,
    required int queueIndex,
  }) =>
      this.userTransportEpoch == userTransportEpoch &&
      this.transitionGeneration == transitionGeneration &&
      outgoingSongId == currentSongId &&
      this.queueIndex == queueIndex;
}
