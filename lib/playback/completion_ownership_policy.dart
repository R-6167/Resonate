/// Pure guard for duplicate/stale track-completion callbacks.
///
/// Completion can arrive from both the native processing-state stream and the
/// end-of-track watchdog. A callback from an outgoing engine must not advance
/// the queue after ownership has moved to another song, unless a transition is
/// still in progress and owns that completion.
class CompletionOwnershipPolicy {
  const CompletionOwnershipPolicy._();

  static bool shouldIgnoreStaleCompletion({
    required String? currentSongId,
    required String completedSongId,
    required bool crossfadeInProgress,
    required bool automaticCrossfadeInFlight,
  }) {
    return currentSongId != null &&
        currentSongId != completedSongId &&
        !crossfadeInProgress &&
        !automaticCrossfadeInFlight;
  }
}
