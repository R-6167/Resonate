/// Cached on-device DJ analysis for a single library track.
///
/// Null / low-confidence fields mean "unknown" — playback must never depend on
/// these being present. DJ Mode only *uses* analysis when enabled and confidence
/// is high enough (later steps).
class DjAnalysis {
  final String songId;
  final double? bpm;
  final double bpmConfidence;
  final int? beatOffsetMs;
  /// Pitch class 0–11 (C=0 … B=11). Null when unknown.
  final int? keyRoot;
  /// `major`, `minor`, or null.
  final String? keyMode;
  final DateTime? analyzedAt;

  const DjAnalysis({
    required this.songId,
    this.bpm,
    this.bpmConfidence = 0.0,
    this.beatOffsetMs,
    this.keyRoot,
    this.keyMode,
    this.analyzedAt,
  });

  bool get hasUsableBpm =>
      bpm != null && bpm! > 40 && bpm! < 240 && bpmConfidence >= 0.35;

  bool get hasUsableKey =>
      keyRoot != null && keyRoot! >= 0 && keyRoot! <= 11 && keyMode != null;

  factory DjAnalysis.fromMap(Map<String, dynamic> map) {
    return DjAnalysis(
      songId: map['song_id'] as String,
      bpm: (map['bpm'] as num?)?.toDouble(),
      bpmConfidence: (map['bpm_confidence'] as num?)?.toDouble() ?? 0.0,
      beatOffsetMs: (map['beat_offset_ms'] as num?)?.toInt(),
      keyRoot: (map['key_root'] as num?)?.toInt(),
      keyMode: map['key_mode'] as String?,
      analyzedAt: map['analyzed_at'] != null
          ? DateTime.tryParse(map['analyzed_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'song_id': songId,
      'bpm': bpm,
      'bpm_confidence': bpmConfidence,
      'beat_offset_ms': beatOffsetMs,
      'key_root': keyRoot,
      'key_mode': keyMode,
      'analyzed_at': analyzedAt?.toIso8601String(),
    };
  }

  DjAnalysis copyWith({
    double? bpm,
    double? bpmConfidence,
    int? beatOffsetMs,
    int? keyRoot,
    String? keyMode,
    DateTime? analyzedAt,
  }) {
    return DjAnalysis(
      songId: songId,
      bpm: bpm ?? this.bpm,
      bpmConfidence: bpmConfidence ?? this.bpmConfidence,
      beatOffsetMs: beatOffsetMs ?? this.beatOffsetMs,
      keyRoot: keyRoot ?? this.keyRoot,
      keyMode: keyMode ?? this.keyMode,
      analyzedAt: analyzedAt ?? this.analyzedAt,
    );
  }
}
