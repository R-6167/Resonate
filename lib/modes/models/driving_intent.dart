import '../integration/mode_context_port.dart';
import '../models/resonate_mode.dart';

/// Integration-neutral Driving Mode event.
///
/// Driving Mode is intentionally conservative: it reacts to a coarse car
/// context supplied by the host and never accesses location, Bluetooth,
/// sensors, or playback directly.
enum DrivingIntentType {
  carContextDetected,
  carContextLost,
  suggestDriving,
  drivingActive,
  drivingInactive,
}

class DrivingIntent {
  final DrivingIntentType type;
  final DateTime at;
  final ModeAudioContext context;
  final ResonateMode mode;

  const DrivingIntent({
    required this.type,
    required this.at,
    required this.context,
    required this.mode,
  });

  bool get isSuggestion => type == DrivingIntentType.suggestDriving;
}
