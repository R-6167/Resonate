import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/audio_effects_bridge.dart';

class AudioEffectsProvider extends ChangeNotifier {
  final AudioPlayer? player;
  final AndroidLoudnessEnhancer? loudnessEnhancer;
  double reverb = 0.0;
  double bassBoost = 0.0;
  double virtualizer = 0.0;
  double loudness = 0.0;
  bool effectsEnabled = true;

  AudioEffectsProvider({this.player, this.loudnessEnhancer}) {
    _load();
  }

  Future<void> setEffectsEnabled(bool value) async {
    effectsEnabled = value;
    await _applyNative();
    await _save();
    notifyListeners();
  }

  Future<void> setReverb(double value) async {
    reverb = value.clamp(0.0, 1.0).toDouble();
    await _applyNative();
    await _save();
    notifyListeners();
  }

  /// Legacy bass control retained for settings compatibility.
  ///
  /// BassBoost is intentionally not applied to the audio session anymore:
  /// the mature Resonate DSP owns bass shaping, speaker protection and
  /// virtual-bass processing. Keeping this value prevents old preferences/UI
  /// state from breaking while avoiding a second bass processor.
  Future<void> setBassBoost(double value) async {
    bassBoost = value.clamp(0.0, 1.0).toDouble();
    await _disableLegacyBassBoost();
    await _save();
    notifyListeners();
  }

  Future<void> setVirtualizer(double value) async {
    virtualizer = value.clamp(0.0, 1.0).toDouble();
    await _applyNative();
    await _save();
    notifyListeners();
  }

  /// Loudness enhancer is retired — Resonate DSP preamp owns overall level.
  /// Kept as a no-op so older saved prefs cannot re-enable it.
  Future<void> setLoudness(double value) async {
    loudness = 0.0;
    if (loudnessEnhancer != null) {
      try {
        await loudnessEnhancer!.setEnabled(false);
        await loudnessEnhancer!.setTargetGain(0.0);
      } catch (_) {}
    }
    await _save();
    notifyListeners();
  }

  Future<void> _applyNative() async {
    // Only when the user actually moved a control. Never on first play.
    final sessionId = player?.androidAudioSessionId ?? 0;
    if (sessionId <= 0) return;
    final enabled = effectsEnabled;
    try {
      await AudioEffectsBridge.attachToSession(sessionId);
      // BassBoost is retired from the active path. Mature DSP owns all bass
      // processing; applying Android BassBoost here would stack another EQ.
      await AudioEffectsBridge.setBassBoost(0.0);
      await AudioEffectsBridge.setVirtualizer(enabled ? virtualizer : 0.0);
      await AudioEffectsBridge.setReverb(enabled ? reverb : 0.0);
    } catch (e) {
      debugPrint('Native audio effects failed: $e');
    }

    // LoudnessEnhancer is intentionally disabled — DSP preamp + EQ handle level.
    if (loudnessEnhancer != null) {
      try {
        await loudnessEnhancer!.setEnabled(false);
        await loudnessEnhancer!.setTargetGain(0.0);
      } catch (e) {
        debugPrint('Loudness disable failed: $e');
      }
    }
  }

  Future<void> _disableLegacyBassBoost() async {
    try {
      await AudioEffectsBridge.setBassBoost(0.0);
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      effectsEnabled = prefs.getBool('effects_enabled') ?? true;
      reverb = prefs.getDouble('reverb') ?? 0.0;
      bassBoost = prefs.getDouble('bassBoost') ?? 0.0;
      virtualizer = prefs.getDouble('virtualizer') ?? 0.0;
      // Always force loudness off (legacy prefs ignored).
      loudness = 0.0;
      // Do not apply native effects at load — no audio session yet.
      notifyListeners();
    } catch (e) {
      debugPrint('Audio effects load failed: $e');
    }
  }

  Future<void> reset() async {
    effectsEnabled = true;
    reverb = 0.0;
    bassBoost = 0.0;
    virtualizer = 0.0;
    loudness = 0.0;
    await _disableLegacyBassBoost();
    await _applyNative();
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('effects_enabled', effectsEnabled);
      await prefs.setDouble('reverb', reverb);
      await prefs.setDouble('bassBoost', bassBoost);
      await prefs.setDouble('virtualizer', virtualizer);
      await prefs.setDouble('loudness', loudness);
    } catch (e) {
      debugPrint('Audio effects save failed: $e');
    }
  }

  @override
  void dispose() {
    AudioEffectsBridge.release();
    super.dispose();
  }
}
