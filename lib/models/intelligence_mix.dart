import 'song.dart';

class IntelligenceMixSegment {
  final int startMs;
  final int endMs;
  final int listens;
  final double preference;
  final int replayCount;

  const IntelligenceMixSegment({
    required this.startMs,
    required this.endMs,
    required this.listens,
    required this.preference,
    this.replayCount = 0,
  });

  Duration get start => Duration(milliseconds: startMs);
  Duration get end => Duration(milliseconds: endMs);
  bool get hasReplayEvidence => replayCount > 0;
}

class IntelligenceMixAnalysis {
  final Song source;
  final int observations;
  final double averageCompletion;
  final double preferredCoverage;
  final List<IntelligenceMixSegment> preferredSegments;
  final Duration? commonExitPoint;
  final int replayEvents;
  final int replayedSegments;

  const IntelligenceMixAnalysis({
    required this.source,
    required this.observations,
    required this.averageCompletion,
    required this.preferredCoverage,
    required this.preferredSegments,
    this.commonExitPoint,
    this.replayEvents = 0,
    this.replayedSegments = 0,
  });

  bool get hasEnoughEvidence => observations >= 3 && preferredSegments.isNotEmpty;
  bool get hasReplayEvidence => replayEvents >= 2 && replayedSegments > 0;
}

class IntelligenceMix {
  final String id;
  final String title;
  final String description;
  final List<Song> songs;
  final Duration targetDuration;
  final DateTime createdAt;
  final String reason;
  final String? parentMixId;
  final int edition;
  final double? previousContinuityScore;

  const IntelligenceMix({
    required this.id,
    required this.title,
    required this.description,
    required this.songs,
    required this.targetDuration,
    required this.createdAt,
    required this.reason,
    this.parentMixId,
    this.edition = 1,
    this.previousContinuityScore,
  });

  bool get isEvolving => parentMixId != null || edition > 1;
  Duration get duration => songs.fold(Duration.zero, (total, song) => total + song.duration);
}
