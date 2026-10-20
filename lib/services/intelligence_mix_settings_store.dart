import 'package:shared_preferences/shared_preferences.dart';

/// Local-only controls for Deep Companion mix generation and long-form memory.
class IntelligenceMixSettingsStore {
  static const _durationKey = 'intelligence_mix_target_minutes';
  static const _longMixKey = 'intelligence_mix_long_form_enabled';
  static const _minimumKey = 'intelligence_mix_long_form_minimum_minutes';
  static const _replayKey = 'intelligence_mix_replay_sensitivity';
  static const _evolutionKey = 'intelligence_mix_auto_evolution_enabled';

  static Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  static Future<int> targetMinutes() async => (await _prefs()).getInt(_durationKey) ?? 60;
  static Future<bool> longFormEnabled() async => (await _prefs()).getBool(_longMixKey) ?? true;
  static Future<int> minimumLongFormMinutes() async => (await _prefs()).getInt(_minimumKey) ?? 20;
  static Future<int> replaySensitivity() async => (await _prefs()).getInt(_replayKey) ?? 2;
  static Future<bool> autoEvolutionEnabled() async => (await _prefs()).getBool(_evolutionKey) ?? true;

  static Future<void> setTargetMinutes(int value) async => (await _prefs()).setInt(_durationKey, value.clamp(15, 120));
  static Future<void> setLongFormEnabled(bool value) async => (await _prefs()).setBool(_longMixKey, value);
  static Future<void> setMinimumLongFormMinutes(int value) async => (await _prefs()).setInt(_minimumKey, value.clamp(10, 60));
  static Future<void> setReplaySensitivity(int value) async => (await _prefs()).setInt(_replayKey, value.clamp(1, 5));
  static Future<void> setAutoEvolutionEnabled(bool value) async => (await _prefs()).setBool(_evolutionKey, value);

  static Future<void> reset() async {
    final prefs = await _prefs();
    for (final key in const [_durationKey, _longMixKey, _minimumKey, _replayKey, _evolutionKey]) {
      await prefs.remove(key);
    }
  }
}
