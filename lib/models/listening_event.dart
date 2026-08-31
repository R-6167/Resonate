class ListeningEvent {
  final String id;
  final String songId;
  final String? previousSongId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int durationPlayedMs;
  final int songDurationMs;
  final double completionRatio;
  final bool completed;
  final bool skipped;
  final int? skipPositionMs;

  const ListeningEvent({
    required this.id,
    required this.songId,
    this.previousSongId,
    required this.startedAt,
    this.endedAt,
    required this.durationPlayedMs,
    required this.songDurationMs,
    required this.completionRatio,
    required this.completed,
    required this.skipped,
    this.skipPositionMs,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'song_id': songId,
      'previous_song_id': previousSongId,
      'started_at': startedAt.toIso8601String(),
      'ended_at': endedAt?.toIso8601String(),
      'duration_played_ms': durationPlayedMs,
      'song_duration_ms': songDurationMs,
      'completion_ratio': completionRatio,
      'completed': completed ? 1 : 0,
      'skipped': skipped ? 1 : 0,
      'skip_position_ms': skipPositionMs,
    };
  }

  factory ListeningEvent.fromMap(Map<String, dynamic> map) {
    return ListeningEvent(
      id: map['id'] as String,
      songId: map['song_id'] as String,
      previousSongId: map['previous_song_id'] as String?,
      startedAt: DateTime.parse(
        map['started_at'] as String,
      ),
      endedAt: map['ended_at'] != null
          ? DateTime.parse(map['ended_at'] as String)
          : null,
      durationPlayedMs:
          (map['duration_played_ms'] as num?)?.toInt() ?? 0,
      songDurationMs:
          (map['song_duration_ms'] as num?)?.toInt() ?? 0,
      completionRatio:
          (map['completion_ratio'] as num?)?.toDouble() ?? 0.0,
      completed: (map['completed'] as int? ?? 0) == 1,
      skipped: (map['skipped'] as int? ?? 0) == 1,
      skipPositionMs:
          (map['skip_position_ms'] as num?)?.toInt(),
    );
  }
}
