import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/dsp_settings.dart';
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
  int? _lastAppliedSessionId;

  AudioEffectsProvider({this.player, this.loudnessEnhancer}) {
    // Android audio sessions can be recreated after interruption or player
    // teardown. Reattach the saved auxiliary effects when the session changes;
    // preferences alone do not make an effect active on the new session.
    _sessionSubscription = player?.androidAudioSessionIdStream.listen((id) {
      if (id == null || id <= 0 || id == _lastAppliedSessionId) return;
      _lastAppliedSessionId = id;
      unawaited(_applyNative(sessionIdOverride: id));
    }, onError: (Object error) {
      debugPrint('Audio-effects session stream failed: $error');
    });
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

  Future<void> _applyNative({int? sessionIdOverride}) async {
    final sessionId = sessionIdOverride ?? player?.androidAudioSessionId ?? 0;
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
      final canonical = await DspSettings.load();
      effectsEnabled = canonical.effectsEnabled;
      reverb = canonical.reverbAmount;
      virtualizer = canonical.virtualizerAmount;
      bassBoost = prefs.getDouble('bassBoost') ?? 0.0;
      // Always force loudness off (legacy prefs ignored).
      loudness = 0.0;
      // If playback/session creation raced the preference load, apply the
      // restored settings now. Otherwise the session stream applies them when
      // a valid session appears.
      final sessionId = player?.androidAudioSessionId ?? 0;
      if (sessionId > 0) {
        _lastAppliedSessionId = sessionId;
        await _applyNative(sessionIdOverride: sessionId);
      }
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
      await prefs.setDouble('bassBoost', bassBoost);
      await prefs.setDouble('loudness', loudness);
      // Keep legacy keys readable by older builds while canonical state owns
      // effect enable/reverb/virtualizer settings.
      await prefs.setBool('effects_enabled', effectsEnabled);
      await prefs.setDouble('reverb', reverb);
      await prefs.setDouble('virtualizer', virtualizer);
      await DspSettings.update((settings) => settings.copyWith(
            effectsEnabled: effectsEnabled,
            reverbAmount: reverb,
            virtualizerAmount: virtualizer,
          ));
    } catch (e) {
      debugPrint('Audio effects save failed: $e');
    }
  }

  @override
  void dispose() {
    unawaited(_sessionSubscription?.cancel());
    _sessionSubscription = null;
    AudioEffectsBridge.release();
    super.dispose();
  }
}
