/// Runtime crossfade preference snapshot consumed by MusicProvider.
///
/// CrossfadeProvider remains the UI and persistence owner. This class contains
/// no storage access so playback preferences are not persisted a second time.
class CrossfadeSettings {
  static const int defaultDurationMs = 3000;
  static const int minDurationMs = 500;
  static const int maxDurationMs = 12000;
  static const List<String> allowedFadeTypes = [
    'linear',
    'ease_in',
    'ease_out',
    'ease_in_out',
  ];

  bool enabled = false;
  int durationMs = defaultDurationMs;
  String fadeType = 'linear';

  int get clampedDurationMs =>
      durationMs.clamp(minDurationMs, maxDurationMs).toInt();

  /// Returns true if [enabled] flipped from true → false.
  bool setEnabled(bool value) {
    final wasEnabled = enabled;
    enabled = value;
    if (value && durationMs <= 0) durationMs = defaultDurationMs;
    return wasEnabled && !value;
  }

  void setDurationMs(int milliseconds) {
    durationMs = milliseconds.clamp(minDurationMs, maxDurationMs).toInt();
    enabled = true;
  }

  /// Returns false if [value] is not an allowed fade type.
  bool setFadeType(String value) {
    if (!allowedFadeTypes.contains(value)) return false;
    fadeType = value;
    return true;
  }
}
