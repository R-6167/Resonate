import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CrossfadeProvider extends ChangeNotifier {
  final AudioPlayer? player;
  final Future<void> Function()? onNext;

  double duration = 0.0;
  bool isEnabled = false;
  String fadeType = 'linear';
  bool _transitionRunning = false;
  StreamSubscription<Duration>? _positionSubscription;

  CrossfadeProvider({this.player, this.onNext}) {
    _load();
    if (player != null && onNext != null) {
      _positionSubscription = player!.positionStream.listen(_watchPosition);
    }
  }

  void _watchPosition(Duration position) {
    if (!isEnabled || _transitionRunning || duration <= 0 || !player!.playing) return;
    final trackDuration = player!.duration;
    if (trackDuration == null || trackDuration <= Duration.zero) return;
    final remaining = trackDuration - position;
    if (remaining <= Duration(milliseconds: duration.round()) && remaining > Duration.zero) {
      _performTransition();
    }
  }

  Future<void> _performTransition() async {
    if (_transitionRunning || player == null || onNext == null) return;
    _transitionRunning = true;
    try {
      final originalVolume = player!.volume.clamp(0.0, 1.0).toDouble();
      final milliseconds = duration.round().clamp(250, 5000);
      const steps = 10;
      final stepDuration = Duration(milliseconds: 80);

      for (var i = steps; i > 0; i--) {
        if (!player!.playing) return;
        await player!.setVolume(originalVolume * (i / steps));
        await Future<void>.delayed(stepDuration);
      }

      await onNext!();
      await player!.setVolume(0.0);
      for (var i = 1; i <= steps; i++) {
        await player!.setVolume(originalVolume * (i / steps));
        await Future<void>.delayed(Duration(milliseconds: milliseconds ~/ steps));
      }
      await player!.setVolume(originalVolume);
    } catch (e) {
      debugPrint('Crossfade transition failed: $e');
      try { await player!.setVolume(1.0); } catch (_) {}
    } finally {
      _transitionRunning = false;
    }
  }

  Future<void> setDuration(double value) async {
    duration = value.clamp(0.0, 5000.0).toDouble();
    if (duration > 0 && !isEnabled) isEnabled = true;
    if (duration == 0) isEnabled = false;
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
    await _save();
    notifyListeners();
  }

  String getDurationString() {
    if (duration <= 0) return 'Off';
    if (duration < 1000) return '${duration.round()}ms';
    final seconds = duration / 1000;
    if (seconds == seconds.roundToDouble()) return '${seconds.toInt()}s';
    return '${seconds.toStringAsFixed(1)}s';
  }

  Future<void> applyPreset(double value) => setDuration(value);

  Future<void> setFadeType(String value) async {
    const validTypes = ['linear', 'ease_in', 'ease_out', 'ease_in_out'];
    if (validTypes.contains(value)) {
      fadeType = value;
      await _save();
      notifyListeners();
    }
  }

  Future<void> reset() async {
    duration = 0.0;
    isEnabled = false;
    fadeType = 'linear';
    await _save();
    notifyListeners();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      isEnabled = prefs.getBool('crossfade_enabled') ?? false;
      duration = prefs.getDouble('crossfade_duration') ?? 0.0;
      fadeType = prefs.getString('crossfade_fade_type') ?? 'linear';
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
    _positionSubscription?.cancel();
    super.dispose();
  }
}
