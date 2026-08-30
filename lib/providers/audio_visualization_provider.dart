import 'package:flutter/material.dart';

class AudioVisualizationProvider extends ChangeNotifier {
  bool enabled = false;

  void setEnabled(bool v) {
    enabled = v;
    notifyListeners();
  }
}
