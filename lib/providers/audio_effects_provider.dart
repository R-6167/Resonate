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

  Future<void> setBassBoost(double value) async {
    bassBoost = value.clamp(0.0, 1.0).toDouble();
    await _applyNative();
    await _save();
    notifyListeners();
  }

  Future<void> setVirtualizer(double value) async {
    virtualizer = value.clamp(0.0, 1.0).toDouble();
    await _applyNative();
    await _save();
    notifyListeners();
  }

  /// Deprecated — Loudness UI removed; use EQ Preamp (DVC).
  Future<void> setLoudness(double value) async {
    loudness = 0.0;
    await _applyNative();
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
      await AudioEffectsBridge.setBassBoost(enabled ? bassBoost : 0.0);
      await AudioEffectsBridge.setVirtualizer(enabled ? virtualizer : 0.0);
      await AudioEffectsBridge.setReverb(enabled ? reverb : 0.0);
    } catch (e) {
      debugPrint('Native audio effects failed: $e');
    }

    // Loudness removed from UI — EQ Preamp (DVC) owns overall level.
    // Keep loudnessEnhancer disabled so it cannot stack with DVC.
    if (loudnessEnhancer != null) {
      try {
        await loudnessEnhancer!.setTargetGain(0.0);
        await loudnessEnhancer!.setEnabled(false);
      } catch (_) {}
    }
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      effectsEnabled = prefs.getBool('effects_enabled') ?? true;
      reverb = prefs.getDouble('reverb') ?? 0.0;
      bassBoost = prefs.getDouble('bassBoost') ?? 0.0;
      virtualizer = prefs.getDouble('virtualizer') ?? 0.0;
      loudness = 0.0; // Loudness retired; Preamp owns level
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
