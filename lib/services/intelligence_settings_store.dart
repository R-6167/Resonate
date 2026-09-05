import 'package:shared_preferences/shared_preferences.dart';

/// Persistent, local-only tuning controls for Resonate Intelligence.
///
/// Defaults are intentionally conservative so existing playback behavior is
/// unchanged until the user opts into stronger automation.
class IntelligenceSettingsStore {
  static const _explorationKey = 'intelligence_exploration';
  static const _confidenceKey = 'intelligence_confidence_threshold';
  static const _autoQueueKey = 'intelligence_automatic_queue';
  static const _artistRepeatKey = 'intelligence_artist_repeat';
  static const _sessionKey = 'intelligence_session_enabled';
  static const _explanationsKey = 'intelligence_explanations';
  static const _learnedEqKey = 'intelligence_learned_eq';
  static const _crossfadeKey = 'intelligence_autopilot_crossfade';
  static const _crossfadeDurationKey = 'intelligence_autopilot_crossfade_ms';

  static Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  static Future<int> exploration() async => (await _prefs()).getInt(_explorationKey) ?? 35;
  static Future<double> confidenceThreshold() async => (await _prefs()).getDouble(_confidenceKey) ?? .65;
  static Future<bool> automaticQueue() async => (await _prefs()).getBool(_autoQueueKey) ?? true;
  static Future<bool> artistRepeat() async => (await _prefs()).getBool(_artistRepeatKey) ?? false;
  static Future<bool> sessionIntelligence() async => (await _prefs()).getBool(_sessionKey) ?? true;
  static Future<bool> explanations() async => (await _prefs()).getBool(_explanationsKey) ?? true;
  static Future<bool> learnedEq() async => (await _prefs()).getBool(_learnedEqKey) ?? false;
  static Future<bool> autopilotCrossfade() async => (await _prefs()).getBool(_crossfadeKey) ?? true;
  static Future<int> autopilotCrossfadeMs() async => (await _prefs()).getInt(_crossfadeDurationKey) ?? 5000;

  static Future<void> setExploration(int value) async => (await _prefs()).setInt(_explorationKey, value.clamp(0, 100));
  static Future<void> setConfidenceThreshold(double value) async => (await _prefs()).setDouble(_confidenceKey, value.clamp(.45, .90));
  static Future<void> setAutomaticQueue(bool value) async => (await _prefs()).setBool(_autoQueueKey, value);
  static Future<void> setArtistRepeat(bool value) async => (await _prefs()).setBool(_artistRepeatKey, value);
  static Future<void> setSessionIntelligence(bool value) async => (await _prefs()).setBool(_sessionKey, value);
  static Future<void> setExplanations(bool value) async => (await _prefs()).setBool(_explanationsKey, value);
  static Future<void> setLearnedEq(bool value) async => (await _prefs()).setBool(_learnedEqKey, value);
  static Future<void> setAutopilotCrossfade(bool value) async => (await _prefs()).setBool(_crossfadeKey, value);
  static Future<void> setAutopilotCrossfadeMs(int value) async => (await _prefs()).setInt(_crossfadeDurationKey, value.clamp(1000, 12000));

  static Future<void> reset() async {
    final prefs = await _prefs();
    for (final key in const [
      _explorationKey, _confidenceKey, _autoQueueKey, _artistRepeatKey,
      _sessionKey, _explanationsKey, _learnedEqKey, _crossfadeKey,
      _crossfadeDurationKey,
    ]) {
      await prefs.remove(key);
    }
  }
}
