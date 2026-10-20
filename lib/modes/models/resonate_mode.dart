/// Resonate listening modes — policy + interaction profiles, not playlists.
enum ResonateMode {
  normal,
  running,
  workout,
  driving,
  work,
  podcast,
  motivation,
  audiobook,
  sleep,
}

extension ResonateModeX on ResonateMode {
  String get id => name;

  String get label => switch (this) {
        ResonateMode.normal => 'Normal',
        ResonateMode.running => 'Running',
        ResonateMode.workout => 'Workout',
        ResonateMode.driving => 'Driving',
        ResonateMode.work => 'Work',
        ResonateMode.podcast => 'Podcast',
        ResonateMode.motivation => 'Motivation',
        ResonateMode.audiobook => 'Audiobook',
        ResonateMode.sleep => 'Sleep',
      };

  String get emoji => switch (this) {
        ResonateMode.normal => '🎵',
        ResonateMode.running => '🏃',
        ResonateMode.workout => '💪',
        ResonateMode.driving => '🚗',
        ResonateMode.work => '💼',
        ResonateMode.podcast => '🎙️',
        ResonateMode.motivation => '🔥',
        ResonateMode.audiobook => '📚',
        ResonateMode.sleep => '🌙',
      };

  String get shortDescription => switch (this) {
        ResonateMode.normal => 'Full Resonate experience',
        ResonateMode.running => 'Large controls, music-first, fewer accidents',
        ResonateMode.workout => 'Music-first; 120–160 BPM target guidance from available DJ analysis',
        ResonateMode.driving => 'Minimal UI, Resonate supervises playback',
        ResonateMode.work => 'Long, calm background listening',
        ResonateMode.podcast => 'Speech-first, precise resume, no music crossfade',
        ResonateMode.motivation => 'Speech-aware transitions and queues',
        ResonateMode.audiobook => 'Chapters, precise position, sleep timer friendly',
        ResonateMode.sleep => 'Gentle queue, no shuffle or crossfade, sleep timer suggested',
      };

  static ResonateMode fromId(String? raw) {
    if (raw == null || raw.isEmpty) return ResonateMode.normal;
    return ResonateMode.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => ResonateMode.normal,
    );
  }
}
