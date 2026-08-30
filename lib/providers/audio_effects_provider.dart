import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AudioEffectsProvider extends ChangeNotifier {
  double reverb = 0.0;
  double bassBoost = 0.0;

  AudioEffectsProvider() {
    _load();
  }

  void setReverb(double v) {
    reverb = v.clamp(0.0, 1.0);
    _save();
    notifyListeners();
  }

  void setBassBoost(double v) {
    bassBoost = v.clamp(0.0, 1.0);
    _save();
    notifyListeners();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      reverb = prefs.getDouble('reverb') ?? 0.0;
      bassBoost = prefs.getDouble('bassBoost') ?? 0.0;
      notifyListeners();
    } catch (e) {}
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('reverb', reverb);
      await prefs.setDouble('bassBoost', bassBoost);
    } catch (e) {}
  }
}
