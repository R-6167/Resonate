import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audio_effects_bridge.dart';

/// Keeps the user's sound profile coherent across both playback engines.
///
/// Called only *after* play has started (deferred from MusicProvider) so we
/// never race ExoPlayer session attach / setAudioSource on the critical path.
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
    final prefs = await SharedPreferences.getInstance();
    final equalizerEnabled = prefs.getBool('equalizer_enabled') ?? true;
    final effectsEnabled = prefs.getBool('effects_enabled') ?? true;
    final bassBoost = prefs.getDouble('bassBoost') ?? 0.0;
    final virtualizer = prefs.getDouble('virtualizer') ?? 0.0;
    final reverb = prefs.getDouble('reverb') ?? 0.0;
    final loudness = prefs.getDouble('loudness') ?? 0.0;

    for (final pair in <(AndroidEqualizer, AndroidLoudnessEnhancer)>[
      (equalizerA, loudnessA),
      (equalizerB, loudnessB),
    ]) {
      final eq = pair.$1;
      final loud = pair.$2;
      try {
        final parameters = await eq.parameters;
        for (final band in parameters.bands) {
          final saved = prefs.getDouble('eq_band_${band.index}');
          if (saved != null) {
            await band.setGain(
              saved.clamp(parameters.minDecibels, parameters.maxDecibels).toDouble(),
            );
          }
        }
        await eq.setEnabled(equalizerEnabled);
      } catch (_) {}

      try {
        await loud.setTargetGain(effectsEnabled ? loudness * 600.0 : 0.0);
        await loud.setEnabled(effectsEnabled && loudness > 0);
      } catch (_) {}
    }

    await applyNativeEffects(
      effectsEnabled: effectsEnabled,
      bassBoost: bassBoost,
      virtualizer: virtualizer,
      reverb: reverb,
    );
  }

  Future<void> activateFor(AudioPlayer player) async {
    try {
      await syncAll();
      final sessionId = player.androidAudioSessionId;
      if (sessionId == null || sessionId <= 0) return;
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('effects_enabled') ?? true;
      await AudioEffectsBridge.attachToSession(sessionId);
      await AudioEffectsBridge.setBassBoost(
        enabled ? (prefs.getDouble('bassBoost') ?? 0.0) : 0.0,
      );
      await AudioEffectsBridge.setVirtualizer(
        enabled ? (prefs.getDouble('virtualizer') ?? 0.0) : 0.0,
      );
      await AudioEffectsBridge.setReverb(
        enabled ? (prefs.getDouble('reverb') ?? 0.0) : 0.0,
      );
    } catch (_) {}
  }


  /// Temporarily attenuate the lowest EQ bands during a DJ overlap.
  /// Returns the exact pre-transition gains so the user's EQ is restored byte-for-byte.
  Future<Map<int, double>> duckBassForTransition({
    required AndroidEqualizer equalizer,
    double attenuationDb = 4.0,
  }) async {
    final original = <int, double>{};
    try {
      final parameters = await equalizer.parameters;
      final bands = parameters.bands.take(2).toList();
      for (final band in bands) {
        final gain = band.gain;
        original[band.index] = gain;
        final next = (gain - attenuationDb)
            .clamp(parameters.minDecibels, parameters.maxDecibels)
            .toDouble();
        await band.setGain(next);
      }
    } catch (_) {
      // Partial application is restored by restoreBassAfterTransition.
    }
    return original;
  }

  /// Restore the exact EQ gains captured before a DJ bass duck.
  Future<void> restoreBassAfterTransition({
    required AndroidEqualizer equalizer,
    required Map<int, double> original,
  }) async {
    if (original.isEmpty) return;
    try {
      final parameters = await equalizer.parameters;
      for (final band in parameters.bands) {
        final gain = original[band.index];
        if (gain != null) {
          await band.setGain(
            gain.clamp(parameters.minDecibels, parameters.maxDecibels).toDouble(),
          );
        }
      }
    } catch (_) {}
  }

  Future<void> applyNativeEffects({
    required bool effectsEnabled,
    required double bassBoost,
    required double virtualizer,
    required double reverb,
  }) async {
    // Session-bound attach is handled by activateFor / AudioEffectsProvider.
  }
}
