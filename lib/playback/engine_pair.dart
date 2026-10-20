import 'package:just_audio/just_audio.dart';

/// Dual just_audio engines (A primary, B crossfade/preload).
///
/// Owns construction of players + Android EQ/loudness effects and which side
/// is currently active. Stream binding, session callbacks, and crossfade
/// orchestration stay on [MusicProvider].
class EnginePair {
  EnginePair() {
    equalizerA = AndroidEqualizer();
    equalizerB = AndroidEqualizer();
    loudnessA = AndroidLoudnessEnhancer();
    loudnessB = AndroidLoudnessEnhancer();
    // Equalizer + LoudnessEnhancer in the pipeline (34h-stable path).
    // Extra native effects stay lazy on MusicProvider — attach after session.
    playerA = AudioPlayer(
      audioPipeline: AudioPipeline(
        androidAudioEffects: [equalizerA, loudnessA],
      ),
    );
    playerB = AudioPlayer(
      audioPipeline: AudioPipeline(
        androidAudioEffects: [equalizerB, loudnessB],
      ),
    );
  }

  late final AudioPlayer playerA;
  late final AudioPlayer playerB;
  late final AndroidEqualizer equalizerA;
  late final AndroidEqualizer equalizerB;
  late final AndroidLoudnessEnhancer loudnessA;
  late final AndroidLoudnessEnhancer loudnessB;

  /// True while Engine A is the audible / stream-bound side.
  bool activeIsA = true;

  AudioPlayer get active => activeIsA ? playerA : playerB;

  AudioPlayer get inactive => activeIsA ? playerB : playerA;

  AndroidEqualizer get equalizer => activeIsA ? equalizerA : equalizerB;

  AndroidLoudnessEnhancer get loudnessEnhancer =>
      activeIsA ? loudnessA : loudnessB;

  AndroidEqualizer get inactiveEqualizer =>
      activeIsA ? equalizerB : equalizerA;

  AndroidLoudnessEnhancer get inactiveLoudnessEnhancer =>
      activeIsA ? loudnessB : loudnessA;

  String get activeLabel => activeIsA ? 'A' : 'B';

  String get inactiveLabel => activeIsA ? 'B' : 'A';

  void swap() {
    activeIsA = !activeIsA;
  }

  void resetToA() {
    activeIsA = true;
  }

  Future<void> dispose() async {
    await playerA.dispose();
    await playerB.dispose();
  }
}
