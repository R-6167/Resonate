import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AudioVisualizationProvider extends ChangeNotifier {
  bool enabled = false;

  AudioVisualizationProvider() {
    _load();
  }

  void setEnabled(bool v) {
    enabled = v;
    _save();
    notifyListeners();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled = prefs.getBool('audio_viz_enabled') ?? false;
    } catch (e) {}
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('audio_viz_enabled', enabled);
    } catch (e) {}
  }
}
