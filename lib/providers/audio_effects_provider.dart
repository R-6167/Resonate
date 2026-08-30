import 'package:flutter/material.dart';

class AudioEffectsProvider extends ChangeNotifier {
  double reverb = 0.0; // 0.0 - 1.0
  double bassBoost = 0.0; // 0.0 - 1.0

  void setReverb(double v) {
    reverb = v.clamp(0.0, 1.0);
    notifyListeners();
  }

  void setBassBoost(double v) {
    bassBoost = v.clamp(0.0, 1.0);
    notifyListeners();
  }
}
