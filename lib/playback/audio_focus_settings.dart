import 'package:shared_preferences/shared_preferences.dart';

/// User preferences for audio-focus automation (not runtime duck/unduck state).
///
/// Runtime interruption handling (`_isDucked`, focus-loss timers, fade) stays
/// on [MusicProvider]. This store owns enabled + aggressiveness level and their
/// SharedPreferences keys.
///
/// Level semantics (existing MusicProvider behavior):
/// - 1: deeper duck (0.18)
/// - 2: default duck (0.32)
/// - 3+: allow auto-resume after focus loss (with longer limit at 3)
/// - 4: most aggressive automation
class AudioFocusSettings {
  static const automationKey = 'audio_focus_automation_enabled';
  static const levelKey = 'audio_focus_automation_level';

  static const int defaultLevel = 2;
  static const int minLevel = 1;
  static const int maxLevel = 4;

  bool automationEnabled = true;
  int level = defaultLevel;

  int get clampedLevel => level.clamp(minLevel, maxLevel).toInt();

  /// Deeper duck when level is 1; otherwise MusicProvider's default duck.
  bool get useDeepDuck => clampedLevel == 1;

  /// Levels 3–4 may auto-resume after transient focus loss.
  bool get mayAutoResume => automationEnabled && clampedLevel >= 3;

  void setAutomationEnabled(bool value) {
    automationEnabled = value;
  }

  void setLevel(int value) {
    level = value.clamp(minLevel, maxLevel).toInt();
  }

  Future<void> load(SharedPreferences prefs) async {
    automationEnabled = prefs.getBool(automationKey) ?? true;
    level = (prefs.getInt(levelKey) ?? defaultLevel)
        .clamp(minLevel, maxLevel)
        .toInt();
  }

  Future<void> persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(automationKey, automationEnabled);
      await prefs.setInt(levelKey, clampedLevel);
    } catch (_) {}
  }
}
