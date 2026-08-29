import 'package:flutter/material.dart';

class AudioEffectsProvider extends ChangeNotifier {
  // Placeholder for effects like reverb, bass boost, etc.
  bool _reverbEnabled = false;
  bool get reverbEnabled => _reverbEnabled;

  void setReverb(bool enabled) {
    _reverbEnabled = enabled;
    notifyListeners();
  }
}
