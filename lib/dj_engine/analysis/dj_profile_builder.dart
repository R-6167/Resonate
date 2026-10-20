import 'dart:math' as math;
import '../core/dj_types.dart';
import '../../models/dj_analysis.dart';
import 'dj_beat_grid_builder.dart';

/// Builds a useful V2 profile from the existing analysis row. Updated analysis bridge.
///
/// This is intentionally deterministic and cheap. Rich PCM-derived analyzers
/// can replace/augment these values later without changing the transition brain.
class DjProfileBuilder {
  const DjProfileBuilder();

  static const _beatGridBuilder = DjBeatGridBuilder();

  DjTrackProfile fromAnalysis(DjAnalysis a) {
    final duration = a.durationMs;
    final intro = a.introHintMs;
    final outroStart = duration != null && a.outroHintMs != null
        ? (duration - a.outroHintMs!).clamp(0, duration)
        : null;
    final energy = (a.energy ?? 0.5).clamp(0.0, 1.0).toDouble();
    final loudness = (a.loudness ?? energy).clamp(0.0, 1.0).toDouble();

    final sections = <DjSection>[
      if (intro != null && intro > 0)
        DjSection(
          type: _section(a.sectionHint, intro: true),
          startMs: 0,
          endMs: intro.clamp(0, duration ?? intro).toInt(),
          confidence: 0.55,
          energy: energy * 0.85,
        ),
      if (outroStart != null)
        DjSection(
          type: DjSectionType.outro,
          startMs: outroStart.toInt(),
          endMs: duration!,
          confidence: 0.60,
          energy: energy * 0.80,
        ),
    ];

    return DjTrackProfile(
      songId: a.songId,
      durationMs: duration,
      beatGrid: DjBeatGrid(
        bpm: a.hasUsableBpm ? a.bpm : null,
        confidence: a.bpmConfidence.clamp(0.0, 1.0).toDouble(),
        firstBeatMs: a.beatOffsetMs,
        beatsPerBar: 4,
        beatsPerPhrase: 16,
      ),
      keyRoot: a.hasUsableKey ? a.keyRoot : null,
      keyMode: a.hasUsableKey ? a.keyMode : null,
      keyConfidence: a.hasUsableKey ? 0.70 : 0,
      sections: sections,
      energyCurve: _energyCurve(a, energy, loudness),
      spectrum: DjSpectralProfile(
        bassDensity: (energy * 0.65 + 0.18).clamp(0.0, 1.0).toDouble(),
        bass: (energy * 0.75).clamp(0.0, 1.0).toDouble(),
        mids: (energy * 0.90).clamp(0.0, 1.0).toDouble(),
        highs: (loudness * 0.85).clamp(0.0, 1.0).toDouble(),
        centroid: (0.35 + loudness * 0.30).clamp(0.0, 1.0).toDouble(),
        spectralFlux: energy,
        confidence: a.hasUsableEnergy ? 0.30 : 0,
      ),
      transitions: DjTransitionMarkers(
        bestIntroMs: intro ?? 0,
        bestOutroMs: outroStart,
      ),
      analysisConfidence: _confidence(a),
      analysisVersion: a.analysisVersion,
    );
  }

  List<DjEnergyPoint> _energyCurve(DjAnalysis a, double energy, double loudness) {
    final duration = a.durationMs;
    if (duration == null || duration <= 0) {
      return [DjEnergyPoint(timeMs: 0, value: energy, loudness: loudness)];
    }
    final introEnd = (a.introHintMs ?? (duration * 0.08).round()).clamp(0, duration).toInt();
    final outroStart = a.outroHintMs == null
        ? (duration * 0.90).round()
        : (duration - a.outroHintMs!).clamp(0, duration).toInt();
    return [
      DjEnergyPoint(timeMs: 0, value: (energy * 0.80).clamp(0.0, 1.0).toDouble(), loudness: loudness),
      DjEnergyPoint(timeMs: introEnd, value: energy, loudness: loudness),
      DjEnergyPoint(timeMs: (duration * 0.50).round(), value: energy, loudness: loudness),
      DjEnergyPoint(timeMs: outroStart, value: (energy * 0.90).clamp(0.0, 1.0).toDouble(), loudness: loudness),
      DjEnergyPoint(timeMs: duration, value: (energy * 0.75).clamp(0.0, 1.0).toDouble(), loudness: loudness),
    ];
  }

  DjSectionType _section(String? hint, {required bool intro}) {
    if (hint == null) return intro ? DjSectionType.intro : DjSectionType.unknown;
    return switch (hint) {
      'build' => DjSectionType.build,
      'drop' => DjSectionType.drop,
      'chorus' => DjSectionType.chorus,
      'outro' || 'quiet_outro' => DjSectionType.outro,
      'intro' || 'quiet_intro' => DjSectionType.intro,
      _ => intro ? DjSectionType.intro : DjSectionType.unknown,
    };
  }

  double _confidence(DjAnalysis a) {
    var value = a.bpmConfidence * 0.45;
    if (a.hasUsableKey) value += 0.20;
    if (a.hasUsableEnergy) value += 0.20;
    if (a.introHintMs != null || a.outroHintMs != null) value += 0.10;
    if (a.durationMs != null) value += 0.05;
    return math.min(1.0, value);
  }
}
