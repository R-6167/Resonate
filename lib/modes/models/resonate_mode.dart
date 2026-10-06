/// Resonate listening modes — policy + interaction profiles, not playlists.
enum ResonateMode {
  normal,
  running,
  driving,
  work,
  podcast,
  motivation,
  audiobook,
}

extension ResonateModeX on ResonateMode {
  String get id => name;

  String get label => switch (this) {
        ResonateMode.normal => 'Normal',
        ResonateMode.running => 'Running',
        ResonateMode.driving => 'Driving',
        ResonateMode.work => 'Work',
        ResonateMode.podcast => 'Podcast',
        ResonateMode.motivation => 'Motivation',
        ResonateMode.audiobook => 'Audiobook',
      };

  String get emoji => switch (this) {
        ResonateMode.normal => '🎵',
        ResonateMode.running => '🏃',
        ResonateMode.driving => '🚗',
        ResonateMode.work => '💼',
        ResonateMode.podcast => '🎙️',
        ResonateMode.motivation => '🔥',
        ResonateMode.audiobook => '📚',
      };

  String get shortDescription => switch (this) {
        ResonateMode.normal => 'Full Resonate experience',
        ResonateMode.running => 'Large controls, music-first, fewer accidents',
        ResonateMode.driving => 'Minimal UI, Resonate supervises playback',
        ResonateMode.work => 'Long, calm background listening',
        ResonateMode.podcast => 'Speech-first, precise resume, no music crossfade',
        ResonateMode.motivation => 'Speech-aware transitions and queues',
        ResonateMode.audiobook => 'Chapters, precise position, sleep timer friendly',
      };

  static ResonateMode fromId(String? raw) {
    if (raw == null || raw.isEmpty) return ResonateMode.normal;
    return ResonateMode.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => ResonateMode.normal,
    );
  }
}
