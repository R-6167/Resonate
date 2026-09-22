import 'package:just_audio/just_audio.dart';

/// Policy holder for EQ/loudness across engines A and B.
///
/// Native AudioEffect attach (BassBoost / Virtualizer / Reverb / waiting on
/// [AndroidEqualizer.parameters] before a session exists) is deliberately
/// NOT done here. Doing that during the first play() races ExoPlayer and
/// kills the Flutter Activity while audio keeps going.
class AudioEffectsController {
  final AndroidEqualizer equalizerA;
  final AndroidEqualizer equalizerB;
  final AndroidLoudnessEnhancer loudnessA;
  final AndroidLoudnessEnhancer loudnessB;

  AudioEffectsController({
    required this.equalizerA,
    required this.equalizerB,
    required this.loudnessA,
    required this.loudnessB,
  });

  Future<void> syncAll() async {
    // no-op — see class doc
  }

  Future<void> activateFor(AudioPlayer player) async {
    // no-op — see class doc
  }

  Future<void> applyNativeEffects({
    required bool effectsEnabled,
    required double bassBoost,
    required double virtualizer,
    required double reverb,
  }) async {
    // no-op — native extras are applied only from AudioEffectsProvider
    // when the user moves a slider (session already alive).
  }
}
