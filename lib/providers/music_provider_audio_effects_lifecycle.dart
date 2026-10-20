part of 'music_provider.dart';

/// Defers Android effects activation until playback has established its session.
///
/// Kept off the source-load/play critical path because awaiting effect parameter
/// discovery during startup has crashed the Activity on some target devices.
extension MusicProviderAudioEffectsLifecycle on MusicProvider {
  Future<void> syncSavedAudioEffects() async {
    try {
      await _audioEffectsController.syncAll();
    } catch (e) {
      debugPrint('Saved audio effects sync failed: $e');
    }
  }

  Future<void> _enableEffects(
    AudioPlayer player,
    AndroidEqualizer eq,
    AndroidLoudnessEnhancer loud,
  ) async {
    // Preserve the existing delay and fire-and-forget behavior. The controller
    // performs session attach and guards native effect failures.
    unawaited(Future<void>.delayed(const Duration(milliseconds: 500), () async {
      try {
        await _audioEffectsController.activateFor(player);
      } catch (e) {
        debugPrint('deferred enableEffects failed: $e');
      }
    }));
  }
}
