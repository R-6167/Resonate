import '../models/resonate_mode.dart';

enum PodcastIntentType {
  sessionStarted,
  sessionPaused,
  sessionResumed,
  sessionCompleted,
  sessionExited,
  resumePositionRequired,
  speedControlsElevated,
}

class PodcastIntent {
  final PodcastIntentType type;
  final DateTime at;
  final ResonateMode mode;
  final Duration? position;

  const PodcastIntent({
    required this.type,
    required this.at,
    this.mode = ResonateMode.podcast,
    this.position,
  });

  bool get isResumeBoundary =>
      type == PodcastIntentType.resumePositionRequired;
}
