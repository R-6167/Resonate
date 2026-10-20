import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persistent, local-only tuning controls for Resonate Intelligence.
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
  static const _autopilotConsentKey = 'intelligence_autopilot_consent';

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
  static Future<bool> autopilotConsent() async => (await _prefs()).getBool(_autopilotConsentKey) ?? false;

  static Future<void> setExploration(int value) async => (await _prefs()).setInt(_explorationKey, value.clamp(0, 100));
  static Future<void> setConfidenceThreshold(double value) async => (await _prefs()).setDouble(_confidenceKey, value.clamp(.45, .90));
  static Future<void> setAutomaticQueue(bool value) async => (await _prefs()).setBool(_autoQueueKey, value);
  static Future<void> setArtistRepeat(bool value) async => (await _prefs()).setBool(_artistRepeatKey, value);
  static Future<void> setSessionIntelligence(bool value) async => (await _prefs()).setBool(_sessionKey, value);
  static Future<void> setExplanations(bool value) async => (await _prefs()).setBool(_explanationsKey, value);
  static Future<void> setLearnedEq(bool value) async => (await _prefs()).setBool(_learnedEqKey, value);
  static Future<void> setAutopilotCrossfade(bool value) async => (await _prefs()).setBool(_crossfadeKey, value);
  static Future<void> setAutopilotCrossfadeMs(int value) async => (await _prefs()).setInt(_crossfadeDurationKey, value.clamp(1000, 12000));
  static Future<void> setAutopilotConsent(bool value) async => (await _prefs()).setBool(_autopilotConsentKey, value);

  static Future<Map<String, dynamic>> exportSettings() async => {
        'format': 'resonate_intelligence_settings',
        'version': 1,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'settings': {
          'exploration': await exploration(),
          'confidenceThreshold': await confidenceThreshold(),
          'automaticQueue': await automaticQueue(),
          'artistRepeat': await artistRepeat(),
          'sessionIntelligence': await sessionIntelligence(),
          'explanations': await explanations(),
          'learnedEq': await learnedEq(),
          'autopilotCrossfade': await autopilotCrossfade(),
          'autopilotCrossfadeMs': await autopilotCrossfadeMs(),
          'autopilotConsent': await autopilotConsent(),
        },
      };

  /// Imports only recognized Intelligence tuning fields. Unknown fields are ignored
  /// so newer/older Resonate versions can exchange settings safely.
  static Future<void> importSettings(Map<String, dynamic> document) async {
    final raw = document['settings'];
    if (raw is! Map) throw const FormatException('Missing Intelligence settings.');
    final s = raw.map((key, value) => MapEntry(key.toString(), value));
    final prefs = await _prefs();
    Future<void> intValue(String key, String prefKey, int min, int max) async {
      final value = s[key];
      if (value is num) await prefs.setInt(prefKey, value.round().clamp(min, max));
    }
    Future<void> doubleValue(String key, String prefKey, double min, double max) async {
      final value = s[key];
      if (value is num) await prefs.setDouble(prefKey, value.toDouble().clamp(min, max));
    }
    Future<void> boolValue(String key, String prefKey) async {
      final value = s[key];
      if (value is bool) await prefs.setBool(prefKey, value);
    }
    await intValue('exploration', _explorationKey, 0, 100);
    await doubleValue('confidenceThreshold', _confidenceKey, .45, .90);
    await boolValue('automaticQueue', _autoQueueKey);
    await boolValue('artistRepeat', _artistRepeatKey);
    await boolValue('sessionIntelligence', _sessionKey);
    await boolValue('explanations', _explanationsKey);
    await boolValue('learnedEq', _learnedEqKey);
    await boolValue('autopilotCrossfade', _crossfadeKey);
    await intValue('autopilotCrossfadeMs', _crossfadeDurationKey, 1000, 12000);
    await boolValue('autopilotConsent', _autopilotConsentKey);
  }

  static String encode(Map<String, dynamic> document) => const JsonEncoder.withIndent('  ').convert(document);

  static Map<String, dynamic> decode(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map) throw const FormatException('Invalid Resonate settings file.');
    if (decoded['format'] != 'resonate_intelligence_settings') {
      throw const FormatException('This file is not a Resonate Intelligence settings export.');
    }
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }

  static Future<void> reset() async {
    final prefs = await _prefs();
    for (final key in const [
      _explorationKey, _confidenceKey, _autoQueueKey, _artistRepeatKey,
      _sessionKey, _explanationsKey, _learnedEqKey, _crossfadeKey,
      _crossfadeDurationKey, _autopilotConsentKey,
    ]) {
      await prefs.remove(key);
    }
  }
}
