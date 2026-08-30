import 'package:flutter/material.dart';

class CrossfadeProvider extends ChangeNotifier {
  double duration = 0.0;
  bool isEnabled = false;
  String fadeType = 'linear';

  CrossfadeProvider() {
    duration = 0.0;
    isEnabled = false;
    fadeType = 'linear';
  }

  void setDuration(double value) {
    duration = value.clamp(0.0, 5000.0);
    
    // Automatically enable crossfade when duration is greater than zero.
    if (duration > 0 && !isEnabled) {
      isEnabled = true;
    }

    // Disable when duration is zero.
    if (duration == 0) {
      isEnabled = false;
    }

    notifyListeners();
  }

  void toggleCrossfade(bool value) {
    isEnabled = value;

    if (!isEnabled) {
      duration = 0.0;
    } else if (duration == 0.0) {
      duration = 3000.0;
    }

    notifyListeners();
  }

  String getDurationString() {
    if (duration <= 0) {
      return 'Off';
    }

    if (duration < 1000) {
      return '${duration.round()}ms';
    }

    final seconds = duration / 1000;

    if (seconds == seconds.roundToDouble()) {
      return '${seconds.toInt()}s';
    }

    return '${seconds.toStringAsFixed(1)}s';
  }

  void applyPreset(double value) {
    setDuration(value);
  }

  void setFadeType(String value) {
    const validTypes = [
      'linear',
      'ease_in',
      'ease_out',
      'ease_in_out',
    ];

    if (validTypes.contains(value)) {
      fadeType = value;
      notifyListeners();
    }
  }

  void reset() {
    duration = 0.0;
    isEnabled = false;
    fadeType = 'linear';
    notifyListeners();
  }
}
