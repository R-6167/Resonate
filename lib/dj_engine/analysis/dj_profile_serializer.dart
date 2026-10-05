import 'dart:convert';

import '../../models/dj_analysis.dart';
import '../core/dj_types.dart';

class DjProfileSerializer {
  const DjProfileSerializer();

  String encode(DjTrackProfile profile) => jsonEncode({
    'songId': profile.songId,
    'durationMs': profile.durationMs,
    'fingerprint': profile.fingerprint,
    'analysisVersion': profile.analysisVersion,
    'analysisConfidence': profile.analysisConfidence,
    'bpm': profile.beatGrid.bpm,
    'bpmConfidence': profile.beatGrid.confidence,
    'firstBeatMs': profile.beatGrid.firstBeatMs,
    'keyRoot': profile.keyRoot,
    'keyMode': profile.keyMode,
    'keyConfidence': profile.keyConfidence,
  });

  DjTrackProfile decode(String raw) {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return DjTrackProfile(
      songId: map['songId'] as String,
      durationMs: (map['durationMs'] as num?)?.toInt(),
      fingerprint: map['fingerprint'] as String?,
      beatGrid: DjBeatGrid(
        bpm: (map['bpm'] as num?)?.toDouble(),
        confidence: (map['bpmConfidence'] as num?)?.toDouble() ?? 0,
        firstBeatMs: (map['firstBeatMs'] as num?)?.toInt(),
      ),
      keyRoot: (map['keyRoot'] as num?)?.toInt(),
      keyMode: map['keyMode'] as String?,
      keyConfidence: (map['keyConfidence'] as num?)?.toDouble() ?? 0,
      analysisConfidence: (map['analysisConfidence'] as num?)?.toDouble() ?? 0,
      analysisVersion: (map['analysisVersion'] as num?)?.toInt() ?? 1,
    );
  }
}
