import 'package:shared_preferences/shared_preferences.dart';

/// User-facing crossfade preferences (not runtime transition state).
///
/// Runtime flags (`_crossfadeInProgress`, automatic generations, preload)
/// stay on [MusicProvider]. This store owns enabled / duration / fade curve
/// values. Persistence may also be driven by `CrossfadeProvider`; keys here
/// are the canonical names if MusicProvider is asked to own a copy.
class CrossfadeSettings {
  static const String enabledKey = 'playback_crossfade_enabled';
  static const String durationMsKey = 'playback_crossfade_duration_ms';
  static const String fadeTypeKey = 'playback_crossfade_fade_type';

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

  /// Returns true if [enabled] flipped from true → false (caller may need to
  /// invalidate in-flight transitions).
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

  Future<void> load(SharedPreferences prefs) async {
    enabled = prefs.getBool(enabledKey) ?? false;
    durationMs = (prefs.getInt(durationMsKey) ?? defaultDurationMs)
        .clamp(minDurationMs, maxDurationMs)
        .toInt();
    final stored = prefs.getString(fadeTypeKey);
    if (stored != null && allowedFadeTypes.contains(stored)) {
      fadeType = stored;
    }
  }

  Future<void> persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(enabledKey, enabled);
      await prefs.setInt(durationMsKey, clampedDurationMs);
      await prefs.setString(fadeTypeKey, fadeType);
    } catch (_) {}
  }
}
