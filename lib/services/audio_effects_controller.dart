import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audio_effects_bridge.dart';

/// Keeps the user's sound profile coherent across both playback engines.
/// Engine-specific EQ/loudness objects remain owned by MusicProvider, while
/// this controller owns the policy for restoring and activating them.
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

  Future<void> applyNativeEffects({
    required bool effectsEnabled,
    required double bassBoost,
    required double virtualizer,
    required double reverb,
  }) async {
    final sessionId = 0;
    // Native session effects are attached by activateFor(), because only the
    // active player has a meaningful Android audio session at this point.
    if (sessionId != 0) await AudioEffectsBridge.attachToSession(sessionId);
  }
}
