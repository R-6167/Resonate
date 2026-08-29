import 'package:flutter/material.dart';

class AudioVisualizationProvider extends ChangeNotifier {
  // Placeholder: real visualization requires analyzing the audio buffer.
  double _level = 0.0;
  double get level => _level;

  void updateLevel(double v) {
    _level = v;
    notifyListeners();
  }
}
