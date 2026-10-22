import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/audio_effects_bridge.dart';

/// Shared settings and a single low-rate feed for the orb and main visualizer.
class AudioVisualizationProvider extends ChangeNotifier {
  bool enabled = true;
  String visualizationType = 'bars';
  double sensitivity = 0.65;
  double smoothing = 0.55;
  bool showWaveform = true;
  bool showParticles = false;
  bool mirror = false;
  bool reactToBass = true;
  bool orbAudioReactive = true;
  bool smoothAnimation = true;
  double frameRate = 24;
  List<double> frequencies = List<double>.filled(32, 0.0);

  Timer? _captureTimer;
  bool _playbackActive = false;
  bool _captureInFlight = false;
  bool _disposed = false;
  Listenable? _playbackListenable;
  VoidCallback? _playbackListener;
  bool Function()? _isPlaybackActive;

  AudioVisualizationProvider() { _load(); }

  /// Bind capture lifetime to the actual playback owner. Without this binding,
  /// the native spectrum poller never starts and both visual consumers stay flat.
  void bindPlayback({
    required Listenable listenable,
    required bool Function() isPlaying,
  }) {
    if (identical(_playbackListenable, listenable) &&
        _isPlaybackActive == isPlaying) {
      _syncPlaybackState();
      return;
    }
    if (_playbackListenable != null && _playbackListener != null) {
      _playbackListenable!.removeListener(_playbackListener!);
    }
    _playbackListenable = listenable;
    _isPlaybackActive = isPlaying;
    _playbackListener = _syncPlaybackState;
    listenable.addListener(_playbackListener!);
    _syncPlaybackState();
  }

  void _syncPlaybackState() {
    if (_disposed) return;
    setPlaybackActive(_isPlaybackActive?.call() ?? false);
  }

  void setEnabled(bool value) { enabled = value; _save(); _syncCapture(); notifyListeners(); }
  void setVisualizationType(String value) { if (['bars','circular','waveform','dots','wave'].contains(value)) { visualizationType = value; _save(); notifyListeners(); } }
  void setSensitivity(double value) { sensitivity = value.clamp(0.1, 1.0).toDouble(); _save(); notifyListeners(); }
  void setSmoothing(double value) { smoothing = value.clamp(0.0, 1.0).toDouble(); _save(); notifyListeners(); }
  void setShowWaveform(bool value) { showWaveform = value; _save(); notifyListeners(); }
  void setShowParticles(bool value) { showParticles = value; _save(); notifyListeners(); }
  void setMirror(bool value) { mirror = value; _save(); notifyListeners(); }
  void setReactToBass(bool value) { reactToBass = value; _save(); notifyListeners(); }
  void setOrbAudioReactive(bool value) { orbAudioReactive = value; _save(); notifyListeners(); }
  void setSmoothAnimation(bool value) { smoothAnimation = value; _save(); notifyListeners(); }
  void setFrameRate(double value) { frameRate = value.clamp(12, 30).toDouble(); _save(); notifyListeners(); }

  /// Called by the persistent shell orb, so capture continues even when the
  /// Now Playing visualization is not on screen.
  void setPlaybackActive(bool value) {
    if (_playbackActive == value) return;
    _playbackActive = value;
    if (!value) {
      frequencies = List<double>.filled(32, 0.0);
      notifyListeners();
    }
    _syncCapture();
  }

  void _syncCapture() {
    _captureTimer?.cancel();
    _captureTimer = null;
    if (_disposed || !enabled || !_playbackActive) return;
    // 15 Hz channel polling is sufficient for visual response and avoids
    // creating a high-frequency Dart/MethodChannel workload.
    _captureTimer = Timer.periodic(const Duration(milliseconds: 66), (_) => _captureSpectrum());
    _captureSpectrum();
  }

  Future<void> _captureSpectrum() async {
    if (_captureInFlight || _disposed || !enabled || !_playbackActive) return;
    _captureInFlight = true;
    try {
      final next = await AudioEffectsBridge.getAudioSpectrum();
      if (_disposed) return;
      if (next.isEmpty) {
        if (frequencies.any((value) => value != 0.0)) {
          frequencies = List<double>.filled(32, 0.0);
          notifyListeners();
        }
        return;
      }
      final count = next.length < frequencies.length ? next.length : frequencies.length;
      final alpha = 1.0 - smoothing * 0.88;
      final updated = List<double>.of(frequencies);
      for (var i = 0; i < count; i++) {
        updated[i] = frequencies[i] * (1.0 - alpha) + next[i] * alpha;
      }
      frequencies = updated;
      notifyListeners();
    } finally {
      _captureInFlight = false;
    }
  }

  Future<void> reset() async {
    enabled = true;
    visualizationType = 'bars';
    sensitivity = 0.65;
    smoothing = 0.55;
    showWaveform = true;
    showParticles = false;
    mirror = false;
    reactToBass = true;
    orbAudioReactive = true;
    smoothAnimation = true;
    frameRate = 24;
    await _save();
    _syncCapture();
    notifyListeners();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled = prefs.getBool('audio_viz_enabled') ?? true;
      visualizationType = prefs.getString('audio_viz_type') ?? 'bars';
      sensitivity = prefs.getDouble('audio_viz_sensitivity') ?? 0.65;
      smoothing = prefs.getDouble('audio_viz_smoothing') ?? 0.55;
      showWaveform = prefs.getBool('audio_viz_waveform') ?? true;
      showParticles = prefs.getBool('audio_viz_particles') ?? false;
      mirror = prefs.getBool('audio_viz_mirror') ?? false;
      reactToBass = prefs.getBool('audio_viz_bass') ?? true;
      orbAudioReactive = prefs.getBool('audio_viz_orb_reactive') ?? true;
      smoothAnimation = prefs.getBool('audio_viz_smooth') ?? true;
      frameRate = (prefs.getDouble('audio_viz_fps') ?? 24).clamp(12, 30).toDouble();
      _syncCapture();
      if (!_disposed) notifyListeners();
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('audio_viz_enabled', enabled);
      await prefs.setString('audio_viz_type', visualizationType);
      await prefs.setDouble('audio_viz_sensitivity', sensitivity);
      await prefs.setDouble('audio_viz_smoothing', smoothing);
      await prefs.setBool('audio_viz_waveform', showWaveform);
      await prefs.setBool('audio_viz_particles', showParticles);
      await prefs.setBool('audio_viz_mirror', mirror);
      await prefs.setBool('audio_viz_bass', reactToBass);
      await prefs.setBool('audio_viz_orb_reactive', orbAudioReactive);
      await prefs.setBool('audio_viz_smooth', smoothAnimation);
      await prefs.setDouble('audio_viz_fps', frameRate);
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    if (_playbackListenable != null && _playbackListener != null) {
      _playbackListenable!.removeListener(_playbackListener!);
    }
    _playbackListenable = null;
    _playbackListener = null;
    _isPlaybackActive = null;
    _captureTimer?.cancel();
    _captureTimer = null;
    super.dispose();
  }
}
