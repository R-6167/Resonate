import 'package:flutter/material.dart';

class EqualizerProvider extends ChangeNotifier {
  // Placeholder equalizer state. Real equalizer requires platform-specific plugins.
  Map<int, double> _bands = {0: 0.0, 1: 0.0, 2: 0.0, 3: 0.0, 4: 0.0};

  Map<int, double> get bands => _bands;

  void setBand(int index, double gain) {
    _bands[index] = gain;
    notifyListeners();
  }
}
