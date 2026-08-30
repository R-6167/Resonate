import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AudioVisualizationProvider extends ChangeNotifier {
  bool enabled = false;

  String visualizationType = 'bars';

  List<double> frequencies = List<double>.filled(32, 0.0);

  AudioVisualizationProvider() {
    _load();
  }

  void setEnabled(bool value) {
    enabled = value;
    _save();
    notifyListeners();
  }

  void setVisualizationType(String value) {
    const validTypes = [
      'bars',
      'circular',
      'waveform',
      'dots',
      'wave',
    ];

    if (validTypes.contains(value)) {
      visualizationType = value;
      _save();
      notifyListeners();
    }
  }

  void updateFrequencies(List<double> values) {
    frequencies = List<double>.from(values);
    notifyListeners();
  }

  void generateDemoFrequencies() {
    final random = Random();

    frequencies = List<double>.generate(
      32,
      (index) => 0.15 + random.nextDouble() * 0.85,
    );

    notifyListeners();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      enabled = prefs.getBool('audio_viz_enabled') ?? false;
      visualizationType =
          prefs.getString('audio_viz_type') ?? 'bars';

      notifyListeners();
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setBool(
        'audio_viz_enabled',
        enabled,
      );

      await prefs.setString(
        'audio_viz_type',
        visualizationType,
      );
    } catch (_) {}
  }
}
