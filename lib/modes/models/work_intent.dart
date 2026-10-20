import '../models/resonate_mode.dart';

enum WorkIntentType {
  sessionStarted,
  sessionPaused,
  sessionResumed,
  sessionCompleted,
  sessionExited,
}

class WorkIntent {
  final WorkIntentType type;
  final DateTime at;
  final ResonateMode mode;

  const WorkIntent({
    required this.type,
    required this.at,
    this.mode = ResonateMode.work,
  });

  bool get isSessionLifecycleEvent => true;
}
