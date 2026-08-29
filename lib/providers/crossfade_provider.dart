import 'package:flutter/material.dart';

class CrossfadeProvider extends ChangeNotifier {
  Duration _duration = const Duration(seconds: 3);
  Duration get duration => _duration;

  void setDuration(Duration d) {
    _duration = d;
    notifyListeners();
  }
}
