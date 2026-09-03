import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PlaybackFeaturesProvider extends ChangeNotifier {
  final AudioPlayer player;

  double speed = 1.0;
  double pitch = 1.0;
  bool normalizationEnabled = false;
  double targetLoudness = -14.0;
  int sleepRemainingSeconds = 0;
  String? normalizedSongId;
  Timer? _sleepTimer;

  PlaybackFeaturesProvider({required this.player}) {
    _load();
  }

  bool get sleepTimerActive => sleepRemainingSeconds > 0;

  Future<void> setSpeed(double value) async {
    speed = value.clamp(0.25, 2.0).toDouble();
    try {
      await player.setSpeed(speed);
    } catch (e) {
      debugPrint('Playback speed failed: $e');
    }
    await _save();
    notifyListeners();
  }

  Future<void> setPitch(double value) async {
    pitch = value.clamp(0.5, 2.0).toDouble();
    try {
      await player.setPitch(pitch);
    } catch (e) {
      debugPrint('Playback pitch failed: $e');
    }
    await _save();
    notifyListeners();
  }

  Future<void> setNormalizationEnabled(bool value) async {
    normalizationEnabled = value;
    await _save();
    notifyListeners();
  }

  Future<void> setTargetLoudness(double value) async {
    targetLoudness = value.clamp(-20.0, -8.0).toDouble();
    await _save();
    notifyListeners();
  }

  /// Applies a stored ReplayGain-style track adjustment in dB.
  /// The app stores the adjustment per track; this remains safe even when
  /// actual ReplayGain metadata is unavailable in the Android media store.
  Future<void> applyTrackGain(String songId, double gainDb) async {
    normalizedSongId = songId;
    if (!normalizationEnabled) return;
    final linear = _dbToLinear(gainDb).clamp(0.0, 1.0).toDouble();
    try {
      await player.setVolume(linear);
    } catch (e) {
      debugPrint('Track normalization failed: $e');
    }
    notifyListeners();
  }

  Future<void> startSleepTimer(Duration duration) async {
    _sleepTimer?.cancel();
    sleepRemainingSeconds = duration.inSeconds.clamp(1, 24 * 60 * 60);
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (sleepRemainingSeconds <= 1) {
        timer.cancel();
        sleepRemainingSeconds = 0;
        try {
          await player.pause();
        } catch (_) {}
        notifyListeners();
        return;
      }
      sleepRemainingSeconds--;
      notifyListeners();
    });
    notifyListeners();
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    sleepRemainingSeconds = 0;
    notifyListeners();
  }

  String get sleepTimerLabel {
    if (sleepRemainingSeconds <= 0) return 'Off';
    final hours = sleepRemainingSeconds ~/ 3600;
    final minutes = (sleepRemainingSeconds % 3600) ~/ 60;
    final seconds = sleepRemainingSeconds % 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    if (minutes > 0) return '${minutes}m ${seconds}s';
    return '${seconds}s';
  }

  double _dbToLinear(double db) => 1.0 * (10 * _pow10(db / 20.0));

  double _pow10(double value) {
    var result = 1.0;
    if (value >= 0) {
      for (var i = 0; i < value.floor(); i++) result *= 10;
      result *= _fractionalPow10(value - value.floor());
      return result;
    }
    return 1.0 / _pow10(-value);
  }

  double _fractionalPow10(double value) {
    // Cubic approximation is sufficient for the volume compensation slider.
    const ln10 = 2.302585092994046;
    final x = value * ln10;
    return 1 + x + (x * x) / 2 + (x * x * x) / 6 + (x * x * x * x) / 24;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      speed = prefs.getDouble('playback_speed') ?? 1.0;
      pitch = prefs.getDouble('playback_pitch') ?? 1.0;
      normalizationEnabled = prefs.getBool('normalization_enabled') ?? false;
      targetLoudness = prefs.getDouble('target_loudness') ?? -14.0;
      await player.setSpeed(speed);
      await player.setPitch(pitch);
    } catch (e) {
      debugPrint('Playback settings load failed: $e');
    }
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('playback_speed', speed);
      await prefs.setDouble('playback_pitch', pitch);
      await prefs.setBool('normalization_enabled', normalizationEnabled);
      await prefs.setDouble('target_loudness', targetLoudness);
    } catch (e) {
      debugPrint('Playback settings save failed: $e');
    }
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    super.dispose();
  }
}
