import 'package:flutter/material.dart';

class EqualizerProvider extends ChangeNotifier {
  final Map<String, double> bands = {
    '60Hz': 0.0,
    '250Hz': 0.0,
    '1kHz': 0.0,
    '4kHz': 0.0,
    '16kHz': 0.0,
  };

  void setGain(String band, double gain) {
    if (bands.containsKey(band)) {
      bands[band] = gain;
      notifyListeners();
    }
  }

  void reset() {
    bands.updateAll((key, value) => 0.0);
    notifyListeners();
  }
}
