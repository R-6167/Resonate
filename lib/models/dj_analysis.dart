/// Cached on-device DJ analysis for a single library track.
///
/// Null / low-confidence fields mean "unknown" — playback must never depend on
/// these being present. DJ Mode only *uses* analysis when enabled and confidence
/// is high enough.
///
/// [analysisVersion] lets the engine re-analyze in the background when the
/// estimator improves, without discarding older rows or blocking playback.
class DjAnalysis {
  /// Bump when the analyzer pipeline changes in a meaningful way (native PCM, etc.).
  static const int currentVersion = 1;

  final String songId;
  final double? bpm;
  final double bpmConfidence;
  final int? beatOffsetMs;
  /// Pitch class 0–11 (C=0 … B=11). Null when unknown.
  final int? keyRoot;
  /// `major`, `minor`, or null.
  final String? keyMode;
  final DateTime? analyzedAt;
  /// Schema / pipeline version that produced this row.
  final int analysisVersion;
  /// Where BPM came from: id3_tbpm, pcm_native, pcm_wav, unknown, none.
  final String? bpmSource;
  /// Stable identity helpers — detect file replace without full fingerprint.
  final int? fileSizeBytes;
  final int? durationMs;

  const DjAnalysis({
    required this.songId,
    this.bpm,
    this.bpmConfidence = 0.0,
    this.beatOffsetMs,
    this.keyRoot,
    this.keyMode,
    this.analyzedAt,
    this.analysisVersion = currentVersion,
    this.bpmSource,
    this.fileSizeBytes,
    this.durationMs,
  });

  bool get hasUsableBpm =>
      bpm != null && bpm! > 40 && bpm! < 240 && bpmConfidence >= 0.35;

  bool get hasUsableKey =>
      keyRoot != null && keyRoot! >= 0 && keyRoot! <= 11 && keyMode != null;

  /// True when this row should be refreshed (old pipeline or missing identity).
  bool get isStale => analysisVersion < currentVersion;

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
      analysisVersion: (map['analysis_version'] as num?)?.toInt() ?? 0,
      bpmSource: map['bpm_source'] as String?,
      fileSizeBytes: (map['file_size_bytes'] as num?)?.toInt(),
      durationMs: (map['duration_ms'] as num?)?.toInt(),
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
      'analysis_version': analysisVersion,
      'bpm_source': bpmSource,
      'file_size_bytes': fileSizeBytes,
      'duration_ms': durationMs,
    };
  }

  DjAnalysis copyWith({
    double? bpm,
    double? bpmConfidence,
    int? beatOffsetMs,
    int? keyRoot,
    String? keyMode,
    DateTime? analyzedAt,
    int? analysisVersion,
    String? bpmSource,
    int? fileSizeBytes,
    int? durationMs,
  }) {
    return DjAnalysis(
      songId: songId,
      bpm: bpm ?? this.bpm,
      bpmConfidence: bpmConfidence ?? this.bpmConfidence,
      beatOffsetMs: beatOffsetMs ?? this.beatOffsetMs,
      keyRoot: keyRoot ?? this.keyRoot,
      keyMode: keyMode ?? this.keyMode,
      analyzedAt: analyzedAt ?? this.analyzedAt,
      analysisVersion: analysisVersion ?? this.analysisVersion,
      bpmSource: bpmSource ?? this.bpmSource,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      durationMs: durationMs ?? this.durationMs,
    );
  }
}
