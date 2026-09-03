import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/audio_effects_bridge.dart';

class AudioEffectsProvider extends ChangeNotifier {
  final AudioPlayer? player;
  double reverb = 0.0;
  double bassBoost = 0.0;
  double virtualizer = 0.0;
  double loudness = 0.0;
  bool effectsEnabled = true;
  StreamSubscription<int?>? _sessionSubscription;

  AudioEffectsProvider({this.player}) {
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
    if (player != null) {
      try {
        await player!.loudnessEnhancer.setTargetGain(loudness * 6.0);
        await player!.loudnessEnhancer.setEnabled(effectsEnabled && loudness > 0);
      } catch (e) {
        debugPrint('Loudness effect failed: $e');
      }
    }
    await _save();
    notifyListeners();
  }

  Future<void> _applyNative() async {
    if (!effectsEnabled) {
      await AudioEffectsBridge.setBassBoost(0);
      await AudioEffectsBridge.setVirtualizer(0);
      await AudioEffectsBridge.setReverb(0);
      if (player != null) {
        try { await player!.loudnessEnhancer.setEnabled(false); } catch (_) {}
      }
      return;
    }

    try {
      await AudioEffectsBridge.setBassBoost(bassBoost);
      await AudioEffectsBridge.setVirtualizer(virtualizer);
      await AudioEffectsBridge.setReverb(reverb);
    } catch (e) {
      debugPrint('Native audio effects failed: $e');
    }

    if (player != null) {
      try {
        await player!.loudnessEnhancer.setTargetGain(loudness * 6.0);
        await player!.loudnessEnhancer.setEnabled(loudness > 0);
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
