import 'package:flutter/material.dart';

class CrossfadeProvider extends ChangeNotifier {
  // crossfade duration in seconds
  double duration = 0.0;

  void setDuration(double seconds) {
    duration = seconds < 0 ? 0.0 : seconds;
    notifyListeners();
  }
}
