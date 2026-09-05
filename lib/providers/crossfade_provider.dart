import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'music_provider.dart';

class CrossfadeProvider extends ChangeNotifier {
  final MusicProvider music;
  double duration = 0.0;
  bool isEnabled = false;
  String fadeType = 'linear';

  CrossfadeProvider({required this.music}) {
    unawaited(_load());
  }

  Future<void> setDuration(double value) async {
    duration = value.clamp(0.0, 12000.0).toDouble();
    isEnabled = duration > 0;
    await _syncPlayerSettings();
    await _save();
    notifyListeners();
  }

  Future<void> toggleCrossfade(bool value) async {
    isEnabled = value;
    if (!isEnabled) {
      duration = 0.0;
    } else if (duration == 0.0) {
      duration = 3000.0;
    }
    await _syncPlayerSettings();
    await _save();
    notifyListeners();
  }

  Future<void> _syncPlayerSettings() async {
    await music.setCrossfadeEnabled(isEnabled);
    if (duration > 0) {
      await music.setCrossfadeDuration(duration.round());
    }
    await music.setCrossfadeFadeType(fadeType);
  }

  Future<void> setFadeType(String value) async {
    const validTypes = ['linear', 'ease_in', 'ease_out', 'ease_in_out'];
    if (!validTypes.contains(value)) return;
    fadeType = value;
    await music.setCrossfadeFadeType(value);
    await _save();
    notifyListeners();
  }

  Future<void> reset() async {
    duration = 0.0;
    isEnabled = false;
    fadeType = 'linear';
    await _syncPlayerSettings();
    await _save();
    notifyListeners();
  }

  String getDurationString() {
    if (duration <= 0) return 'Off';
    if (duration < 1000) return '${duration.round()}ms';
    final seconds = duration / 1000;
    return seconds == seconds.roundToDouble()
        ? '${seconds.toInt()}s'
        : '${seconds.toStringAsFixed(1)}s';
  }

  Future<void> applyPreset(double value) => setDuration(value);

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      isEnabled = prefs.getBool('crossfade_enabled') ?? false;
      duration = prefs.getDouble('crossfade_duration') ?? 0.0;
      fadeType = prefs.getString('crossfade_fade_type') ?? 'linear';
      if (!['linear', 'ease_in', 'ease_out', 'ease_in_out'].contains(fadeType)) {
        fadeType = 'linear';
      }
      await _syncPlayerSettings();
      notifyListeners();
    } catch (e) {
      debugPrint('Crossfade settings load failed: $e');
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('crossfade_enabled', isEnabled);
      await prefs.setDouble('crossfade_duration', duration);
      await prefs.setString('crossfade_fade_type', fadeType);
    } catch (e) {
      debugPrint('Crossfade settings save failed: $e');
    }
  }

  @override
  void dispose() {
    super.dispose();
  }
}
