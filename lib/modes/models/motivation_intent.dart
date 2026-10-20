import '../models/media_type.dart';
import '../models/resonate_mode.dart';

enum MotivationIntentType {
  sessionStarted,
  sessionPaused,
  sessionResumed,
  sessionCompleted,
  sessionExited,
  speechStarted,
  speechCompleted,
  musicFollowupSuggested,
}

class MotivationIntent {
  final MotivationIntentType type;
  final DateTime at;
  final ResonateMode mode;
  final MediaType? mediaType;

  const MotivationIntent({
    required this.type,
    required this.at,
    this.mode = ResonateMode.motivation,
    this.mediaType,
  });

  bool get isSessionLifecycleEvent => switch (type) {
        MotivationIntentType.sessionStarted ||
        MotivationIntentType.sessionPaused ||
        MotivationIntentType.sessionResumed ||
        MotivationIntentType.sessionCompleted ||
        MotivationIntentType.sessionExited => true,
        _ => false,
      };

  bool get isSpeechTransition =>
      type == MotivationIntentType.speechCompleted ||
      type == MotivationIntentType.musicFollowupSuggested;
}
