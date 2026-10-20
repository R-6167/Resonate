import 'package:shared_preferences/shared_preferences.dart';

import '../services/loudness_service.dart';

/// User prefs for track loudness leveling (not runtime gain computation).
///
/// [MusicProvider] keeps [LoudnessService] and `_refreshTrackLevelingFor` /
/// `_eqPreampScale` application. This store owns enabled + target RMS and their
/// SharedPreferences keys.
class AudioLevelingSettings {
  static const enabledKey = 'audio_leveling_enabled_v1';
  static const targetKey = 'audio_leveling_target_rms_dbfs_v1';

  static const double minTargetRmsDbfs = -24.0;
  static const double maxTargetRmsDbfs = -12.0;
  static double get defaultTargetRmsDbfs =>
      LoudnessService.defaultTargetRmsDbfs;

  bool enabled = false;
  double targetRmsDbfs = LoudnessService.defaultTargetRmsDbfs;

  double get clampedTarget =>
      targetRmsDbfs.clamp(minTargetRmsDbfs, maxTargetRmsDbfs).toDouble();

  /// Returns true if the value changed.
  bool setEnabled(bool value) {
    if (enabled == value) return false;
    enabled = value;
    return true;
  }

  /// Returns true if the value changed after clamping.
  bool setTargetRmsDbfs(double target) {
    if (!target.isFinite) return false;
    final safe = target.clamp(minTargetRmsDbfs, maxTargetRmsDbfs).toDouble();
    if ((targetRmsDbfs - safe).abs() < 0.001) return false;
    targetRmsDbfs = safe;
    return true;
  }

  Future<void> load(SharedPreferences prefs) async {
    enabled = prefs.getBool(enabledKey) ?? false;
    targetRmsDbfs = (prefs.getDouble(targetKey) ?? defaultTargetRmsDbfs)
        .clamp(minTargetRmsDbfs, maxTargetRmsDbfs)
        .toDouble();
  }

  Future<void> persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(enabledKey, enabled);
      await prefs.setDouble(targetKey, clampedTarget);
    } catch (_) {}
  }
}
