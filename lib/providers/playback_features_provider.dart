import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'music_provider.dart';

class PlaybackFeaturesProvider extends ChangeNotifier {
  final MusicProvider music;
  double speed = 1.0;
  double pitch = 1.0;
  bool normalizationEnabled = false;
  double targetLoudness = -14.0;
  int sleepRemainingSeconds = 0;
  String? normalizedSongId;
  Timer? _sleepTimer;
  String? _lastSongId;
  String? _lastEngine;

  PlaybackFeaturesProvider({required this.music}) {
    music.addListener(_syncEngineIfNeeded);
    _load();
  }

  AudioPlayer get player => music.audioPlayer;
  AndroidLoudnessEnhancer get loudnessEnhancer => music.loudnessEnhancer;
  bool get sleepTimerActive => sleepRemainingSeconds > 0;

  void _syncEngineIfNeeded() {
    final songId = music.currentSong?.id;
    final engine = music.activeEngineLabel;
    if (songId == _lastSongId && engine == _lastEngine) return;
    _lastSongId = songId;
    _lastEngine = engine;
    unawaited(applyToActiveEngine());
  }

  Future<void> setSpeed(double value) async {
    speed = value.clamp(0.25, 2.0).toDouble();
    try { await player.setSpeed(speed); } catch (e) { debugPrint('Playback speed failed: $e'); }
    await _save();
    notifyListeners();
  }

  Future<void> setPitch(double value) async {
    pitch = value.clamp(0.5, 2.0).toDouble();
    try { await player.setPitch(pitch); } catch (e) { debugPrint('Playback pitch failed: $e'); }
    await _save();
    notifyListeners();
  }

  Future<void> setNormalizationEnabled(bool value) async {
    normalizationEnabled = value;
    await _applyNormalization();
    await _save();
    notifyListeners();
  }

  Future<void> setTargetLoudness(double value) async {
    targetLoudness = value.clamp(-20.0, -8.0).toDouble();
    if (normalizationEnabled) await _applyNormalization();
    await _save();
    notifyListeners();
  }

  Future<void> applyTrackGain(String songId, double gainDb) async {
    normalizedSongId = songId;
    if (!normalizationEnabled) return;
    try {
      await loudnessEnhancer.setTargetGain((gainDb * 100.0).clamp(-1000.0, 1000.0));
      await loudnessEnhancer.setEnabled(true);
    } catch (e) { debugPrint('Track normalization failed: $e'); }
    notifyListeners();
  }

  Future<void> _applyNormalization() async {
    try {
      // LoudnessEnhancer has no per-track LUFS measurement. Keep the target as a
      // user preference, but never pretend that -14 LUFS itself is a gain value.
      // Track-specific gain is applied through applyTrackGain() when metadata is available.
      final gainDb = 0.0;
      await loudnessEnhancer.setTargetGain(gainDb * 100.0);
      await loudnessEnhancer.setEnabled(normalizationEnabled);
    } catch (e) { debugPrint('Volume normalization failed: $e'); }
  }

  Future<void> applyToActiveEngine() async {
    try {
      await player.setSpeed(speed);
      await player.setPitch(pitch);
      if (normalizationEnabled) await _applyNormalization();
      else await loudnessEnhancer.setEnabled(false);
    } catch (e) { debugPrint('Active playback feature sync failed: $e'); }
  }

  Future<void> startSleepTimer(Duration duration) async {
    _sleepTimer?.cancel();
    sleepRemainingSeconds = duration.inSeconds.clamp(1, 24 * 60 * 60);
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (sleepRemainingSeconds <= 1) {
        timer.cancel(); sleepRemainingSeconds = 0;
        try { await player.pause(); } catch (_) {}
        notifyListeners(); return;
      }
      sleepRemainingSeconds--; notifyListeners();
    });
    notifyListeners();
  }

  void cancelSleepTimer() { _sleepTimer?.cancel(); _sleepTimer = null; sleepRemainingSeconds = 0; notifyListeners(); }

  String get sleepTimerLabel {
    if (sleepRemainingSeconds <= 0) return 'Off';
    final hours = sleepRemainingSeconds ~/ 3600;
    final minutes = (sleepRemainingSeconds % 3600) ~/ 60;
    final seconds = sleepRemainingSeconds % 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    if (minutes > 0) return '${minutes}m ${seconds}s';
    return '${seconds}s';
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      speed = prefs.getDouble('playback_speed') ?? 1.0;
      pitch = prefs.getDouble('playback_pitch') ?? 1.0;
      normalizationEnabled = prefs.getBool('normalization_enabled') ?? false;
      targetLoudness = prefs.getDouble('target_loudness') ?? -14.0;
      await applyToActiveEngine();
      _lastSongId = music.currentSong?.id;
      _lastEngine = music.activeEngineLabel;
    } catch (e) { debugPrint('Playback settings load failed: $e'); }
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('playback_speed', speed);
      await prefs.setDouble('playback_pitch', pitch);
      await prefs.setBool('normalization_enabled', normalizationEnabled);
      await prefs.setDouble('target_loudness', targetLoudness);
    } catch (e) { debugPrint('Playback settings save failed: $e'); }
  }

  @override
  void dispose() { music.removeListener(_syncEngineIfNeeded); _sleepTimer?.cancel(); super.dispose(); }
}
