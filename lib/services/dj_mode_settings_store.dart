import 'package:shared_preferences/shared_preferences.dart';

/// Persisted DJ Mode preferences.
///
/// Defaults keep **normal playback unchanged**: master switch is off, and
/// advanced sub-features stay off until later steps land.
class DjModeSettingsStore {
  static const _enabledKey = 'dj_mode_enabled';
  static const _beatAlignKey = 'dj_mode_beat_align';
  static const _tempoMatchKey = 'dj_mode_tempo_match';
  static const _harmonicMixKey = 'dj_mode_harmonic_mix';
  static const _maxStretchKey = 'dj_mode_max_stretch_percent';
  static const _analyzeIdleKey = 'dj_mode_analyze_idle';

  static Future<bool> enabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_enabledKey) ?? false;
  }

  static Future<void> setEnabled(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_enabledKey, value);
  }

  /// Step 2: start next track on a beat boundary when BPMs are close.
  static Future<bool> beatAlign() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_beatAlignKey) ?? true;
  }

  static Future<void> setBeatAlign(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_beatAlignKey, value);
  }

  /// Step 3: time-stretch during crossfade (off until stretch lands).
  static Future<bool> tempoMatch() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_tempoMatchKey) ?? false;
  }

  static Future<void> setTempoMatch(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_tempoMatchKey, value);
  }

  /// Step 4: harmonic queue bias / key-aware selection.
  static Future<bool> harmonicMix() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_harmonicMixKey) ?? false;
  }

  static Future<void> setHarmonicMix(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_harmonicMixKey, value);
  }

  /// Max |stretch − 1| as percent (e.g. 12 → ratio 0.88–1.12).
  static Future<int> maxStretchPercent() async {
    final p = await SharedPreferences.getInstance();
    return (p.getInt(_maxStretchKey) ?? 12).clamp(3, 20);
  }

  static Future<void> setMaxStretchPercent(int value) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_maxStretchKey, value.clamp(3, 20));
  }

  /// When true, idle analysis may run later (never blocks play).
  static Future<bool> analyzeIdle() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_analyzeIdleKey) ?? false;
  }

  static Future<void> setAnalyzeIdle(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_analyzeIdleKey, value);
  }
}
