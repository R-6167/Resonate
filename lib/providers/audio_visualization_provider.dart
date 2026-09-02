import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AudioVisualizationProvider extends ChangeNotifier {
  bool enabled = true;
  String visualizationType = 'bars';
  double sensitivity = 0.65;
  double smoothing = 0.55;
  bool showWaveform = true;
  bool showParticles = true;
  bool mirror = false;
  bool reactToBass = true;
  bool smoothAnimation = true;
  double frameRate = 60;
  List<double> frequencies = List<double>.filled(32, 0.0);

  AudioVisualizationProvider() { _load(); }

  void setEnabled(bool value) { enabled = value; _save(); notifyListeners(); }
  void setVisualizationType(String value) { if (['bars','circular','waveform','dots','wave'].contains(value)) { visualizationType = value; _save(); notifyListeners(); } }
  void setSensitivity(double value) { sensitivity = value.clamp(0.1, 1.0); _save(); notifyListeners(); }
  void setSmoothing(double value) { smoothing = value.clamp(0.0, 1.0); _save(); notifyListeners(); }
  void setShowWaveform(bool value) { showWaveform = value; _save(); notifyListeners(); }
  void setShowParticles(bool value) { showParticles = value; _save(); notifyListeners(); }
  void setMirror(bool value) { mirror = value; _save(); notifyListeners(); }
  void setReactToBass(bool value) { reactToBass = value; _save(); notifyListeners(); }
  void setSmoothAnimation(bool value) { smoothAnimation = value; _save(); notifyListeners(); }
  void setFrameRate(double value) { frameRate = value.clamp(30, 120); _save(); notifyListeners(); }

  void updateFrequencies(List<double> values) { frequencies = List<double>.from(values); notifyListeners(); }

  void generateDemoFrequencies() {
    final random = Random();
    frequencies = List<double>.generate(32, (i) => 0.15 + random.nextDouble() * 0.85);
    notifyListeners();
  }

  Future<void> reset() async {
    enabled = true;
    visualizationType = 'bars';
    sensitivity = 0.65;
    smoothing = 0.55;
    showWaveform = true;
    showParticles = true;
    mirror = false;
    reactToBass = true;
    smoothAnimation = true;
    frameRate = 60;
    await _save();
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
      showParticles = prefs.getBool('audio_viz_particles') ?? true;
      mirror = prefs.getBool('audio_viz_mirror') ?? false;
      reactToBass = prefs.getBool('audio_viz_bass') ?? true;
      smoothAnimation = prefs.getBool('audio_viz_smooth') ?? true;
      frameRate = prefs.getDouble('audio_viz_fps') ?? 60;
      notifyListeners();
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
      await prefs.setBool('audio_viz_smooth', smoothAnimation);
      await prefs.setDouble('audio_viz_fps', frameRate);
    } catch (_) {}
  }
}
