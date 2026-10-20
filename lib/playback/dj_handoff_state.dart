import '../dj_engine/core/dj_policy.dart';

/// DJ feature flags + last handoff snapshot (not async plan/apply logic).
///
/// [MusicProvider] still owns [DjEngine], analysis, SFX rack, and the
/// `_prepareDjHandoff` / `_applyV2DjHandoff` flows. This type is the state bag
/// those flows read and write.
class DjHandoffState {
  bool beatAlignActive = false;
  bool tempoMatchActive = false;
  int maxStretchPercent = 14;
  bool sfxActive = false;
  DjPolicy policy = DjPolicy.balanced;
  bool sfxEngaged = false;

  double? stretchSpeedOut;
  double? stretchSpeedIn;

  DateTime? lastHandoffAt;
  String? lastFromId;
  String? lastToId;
  String? lastStrategy;
  double? lastTransitionScore;
  double? lastTransitionConfidence;
  List<String> lastTransitionRisks = const <String>[];
  int? lastTransitionDurationMs;
  int lastRecoveryAttempts = 0;

  /// Soft energy-bridge bias applied to the next crossfade length (ms).
  int lastCrossfadeBiasMs = 0;
  double lastEnergyScore = 0.5;
  bool lastBassDuckNeeded = false;

  /// Track-wide beat grid used only for conservative runtime phase correction.
  List<int> lastIncomingBeatMs = const <int>[];
  double? lastIncomingBpm;
  int beatCorrectionAttempts = 0;
  double runtimeCorrectionBaseSpeed = 1.0;
  DateTime? runtimeCorrectionUntil;

  /// True when any DJ transition feature is armed.
  bool get anyFeatureActive =>
      beatAlignActive || tempoMatchActive || sfxActive;

  bool get hasRecentHandoff {
    final at = lastHandoffAt;
    if (at == null || lastStrategy == null) return false;
    return DateTime.now().difference(at) <= const Duration(seconds: 50);
  }

  void clearLastHandoff() {
    lastHandoffAt = null;
    lastFromId = null;
    lastToId = null;
    lastStrategy = null;
    lastTransitionScore = null;
    lastTransitionConfidence = null;
    lastTransitionRisks = const <String>[];
    lastTransitionDurationMs = null;
    lastRecoveryAttempts = 0;
  }

  void clearRuntimeCorrection() {
    lastBassDuckNeeded = false;
    lastIncomingBeatMs = const <int>[];
    lastIncomingBpm = null;
    beatCorrectionAttempts = 0;
    runtimeCorrectionUntil = null;
  }

  void recordHandoff({
    required String? fromId,
    required String? toId,
    required String strategy,
    double? score,
    double? confidence,
    List<String> risks = const <String>[],
    int? durationMs,
  }) {
    lastHandoffAt = DateTime.now();
    lastFromId = fromId;
    lastToId = toId;
    lastStrategy = strategy;
    lastTransitionScore = score;
    lastTransitionConfidence = confidence;
    lastTransitionRisks = List<String>.from(risks);
    lastTransitionDurationMs = durationMs;
    lastRecoveryAttempts = 0;
  }
}
