import 'package:shared_preferences/shared_preferences.dart';

import '../dj_engine/core/dj_policy.dart';

/// Persistence for optional DJ Mode preferences (defaults keep normal player).
class DjModeSettingsStore {
  static const _enabledKey = 'dj_mode_enabled';
  static const _beatAlignKey = 'dj_mode_beat_align';
  static const _tempoMatchKey = 'dj_mode_tempo_match';
  static const _harmonicMixKey = 'dj_mode_harmonic_mix';
  static const _maxStretchKey = 'dj_mode_max_stretch_percent';
  static const _analyzeIdleKey = 'dj_mode_analyze_idle';
  static const _transitionSfxKey = 'dj_mode_transition_sfx';
  static const _aggressivenessKey = 'dj_mode_aggressiveness';
  static const _minConfidenceKey = 'dj_mode_min_confidence';

  static Future<bool> enabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_enabledKey) ?? false;
  }

  static Future<void> setEnabled(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_enabledKey, value);
  }

  static Future<bool> beatAlign() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_beatAlignKey) ?? true;
  }

  static Future<void> setBeatAlign(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_beatAlignKey, value);
  }

  static Future<bool> tempoMatch() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_tempoMatchKey) ?? false;
  }

  static Future<void> setTempoMatch(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_tempoMatchKey, value);
  }

  static Future<bool> harmonicMix() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_harmonicMixKey) ?? false;
  }

  static Future<void> setHarmonicMix(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_harmonicMixKey, value);
  }

  static Future<int> maxStretchPercent() async {
    final p = await SharedPreferences.getInstance();
    return (p.getInt(_maxStretchKey) ?? 12).clamp(3, 20);
  }

  static Future<void> setMaxStretchPercent(int value) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_maxStretchKey, value.clamp(3, 20));
  }

  static Future<bool> analyzeIdle() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_analyzeIdleKey) ?? false;
  }

  static Future<void> setAnalyzeIdle(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_analyzeIdleKey, value);
  }

  static Future<bool> transitionSfx() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_transitionSfxKey) ?? true;
  }

  static Future<void> setTransitionSfx(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_transitionSfxKey, value);
  }

  static Future<DjAggressiveness> aggressiveness() async {
    final p = await SharedPreferences.getInstance();
    return DjAggressivenessX.fromId(p.getString(_aggressivenessKey));
  }

  static Future<void> setAggressiveness(DjAggressiveness value) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_aggressivenessKey, value.id);
  }

  /// Stored as 0–100 (percent). Default 40.
  static Future<double> minConfidence() async {
    final p = await SharedPreferences.getInstance();
    final pct = p.getInt(_minConfidenceKey) ?? 40;
    return (pct.clamp(20, 80) / 100.0).toDouble();
  }

  static Future<void> setMinConfidence(double value) async {
    final p = await SharedPreferences.getInstance();
    final pct = (value.clamp(0.20, 0.80) * 100).round();
    await p.setInt(_minConfidenceKey, pct);
  }
}
