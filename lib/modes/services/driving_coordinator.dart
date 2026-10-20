import '../integration/mode_context_port.dart';
import '../models/driving_intent.dart';
import '../models/resonate_mode.dart';

/// Deterministic Driving Mode context coordinator.
///
/// It translates host-provided audio context into a small intent stream.
/// It does not start playback, access sensors, or change the active mode.
class DrivingCoordinator {
  ResonateMode _mode;
  ModeAudioContext _context = ModeAudioContext.unknown;

  DrivingCoordinator({ResonateMode mode = ResonateMode.normal}) : _mode = mode;

  ResonateMode get mode => _mode;
  ModeAudioContext get context => _context;

  List<DrivingIntent> ingestContext(
    ModeAudioContext context,
    DateTime now, {
    bool autoEnterEnabled = false,
  }) {
    final changed = _context != context;
    _context = context;
    if (!changed) return const [];

    if (context == ModeAudioContext.car) {
      final intents = <DrivingIntent>[
        DrivingIntent(
          type: DrivingIntentType.carContextDetected,
          at: now,
          context: context,
          mode: _mode,
        ),
      ];

      if (_mode == ResonateMode.driving) {
        intents.add(DrivingIntent(
          type: DrivingIntentType.drivingActive,
          at: now,
          context: context,
          mode: _mode,
        ));
      } else if (autoEnterEnabled) {
        intents.add(DrivingIntent(
          type: DrivingIntentType.suggestDriving,
          at: now,
          context: context,
          mode: _mode,
        ));
      } else {
        intents.add(DrivingIntent(
          type: DrivingIntentType.suggestDriving,
          at: now,
          context: context,
          mode: _mode,
        ));
      }
      return intents;
    }

    if (_mode == ResonateMode.driving) {
      return [
        DrivingIntent(
          type: DrivingIntentType.carContextLost,
          at: now,
          context: context,
          mode: _mode,
        ),
        DrivingIntent(
          type: DrivingIntentType.drivingInactive,
          at: now,
          context: context,
          mode: _mode,
        ),
      ];
    }

    return [
      DrivingIntent(
        type: DrivingIntentType.carContextLost,
        at: now,
        context: context,
        mode: _mode,
      ),
    ];
  }

  void setMode(ResonateMode mode) => _mode = mode;
}
