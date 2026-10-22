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
    final effectsEnabled = prefs.getBool('effects_enabled') ?? true;
    final bassBoost = prefs.getDouble('bassBoost') ?? 0.0;
    final virtualizer = prefs.getDouble('virtualizer') ?? 0.0;
    final reverb = prefs.getDouble('reverb') ?? 0.0;

    // The live Resonate DSP is the sole owner of EQ. This legacy controller
    // runs after source setup and on A/B handoffs, so restoring old Android
    // Equalizer band preferences here could silently re-enable a second EQ
    // after the user switched the authoritative EQ off.
    for (final eq in <AndroidEqualizer>[equalizerA, equalizerB]) {
      try {
        await eq.setEnabled(false);
      } catch (_) {}
    }

    // LoudnessEnhancer is retired. Track leveling and the Resonate preamp/DVC
    // path own gain; never let legacy preferences create a competing gain stage.
    for (final loud in <AndroidLoudnessEnhancer>[loudnessA, loudnessB]) {
      try {
        await loud.setTargetGain(0.0);
        await loud.setEnabled(false);
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
