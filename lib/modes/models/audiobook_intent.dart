import '../models/resonate_mode.dart';

enum AudiobookIntentType {
  sessionStarted,
  sessionPaused,
  sessionResumed,
  sessionCompleted,
  sessionExited,
  resumePositionRequired,
  speedControlsElevated,
  sleepTimerSuggested,
  chapterNavigationAvailable,
}

class AudiobookIntent {
  final AudiobookIntentType type;
  final DateTime at;
  final ResonateMode mode;
  final Duration? position;

  const AudiobookIntent({
    required this.type,
    required this.at,
    this.mode = ResonateMode.audiobook,
    this.position,
  });

  bool get isResumeBoundary =>
      type == AudiobookIntentType.resumePositionRequired;

  bool get isSessionLifecycleEvent => switch (type) {
        AudiobookIntentType.sessionStarted ||
        AudiobookIntentType.sessionPaused ||
        AudiobookIntentType.sessionResumed ||
        AudiobookIntentType.sessionCompleted ||
        AudiobookIntentType.sessionExited => true,
        _ => false,
      };
}
