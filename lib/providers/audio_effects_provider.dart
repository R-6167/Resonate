import 'dart:async';
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
  StreamSubscription<int?>? _sessionSubscription;

  AudioEffectsProvider({this.player, this.loudnessEnhancer}) {
    _load();
    if (player != null) {
      _sessionSubscription = player!.androidAudioSessionIdStream.listen((sessionId) {
        if (sessionId != null && sessionId > 0) {
          AudioEffectsBridge.attachToSession(sessionId).then((_) => _applyNative());
        }
      });
    }
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

  Future<void> setLoudness(double value) async {
    loudness = value.clamp(0.0, 1.0).toDouble();
    await _applyNative();
    await _save();
    notifyListeners();
  }

  Future<void> _applyNative() async {
    final enabled = effectsEnabled;

    try {
      await AudioEffectsBridge.setBassBoost(enabled ? bassBoost : 0.0);
      await AudioEffectsBridge.setVirtualizer(enabled ? virtualizer : 0.0);
      await AudioEffectsBridge.setReverb(enabled ? reverb : 0.0);
    } catch (e) {
      debugPrint('Native audio effects failed: $e');
    }

    if (loudnessEnhancer != null) {
      try {
        await loudnessEnhancer!.setTargetGain(enabled ? loudness * 600.0 : 0.0);
        await loudnessEnhancer!.setEnabled(enabled && loudness > 0);
      } catch (e) {
        debugPrint('Loudness effect failed: $e');
      }
    }
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      effectsEnabled = prefs.getBool('effects_enabled') ?? true;
      reverb = prefs.getDouble('reverb') ?? 0.0;
      bassBoost = prefs.getDouble('bassBoost') ?? 0.0;
      virtualizer = prefs.getDouble('virtualizer') ?? 0.0;
      loudness = prefs.getDouble('loudness') ?? 0.0;
      await _applyNative();
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
    _sessionSubscription?.cancel();
    AudioEffectsBridge.release();
    super.dispose();
  }
}
