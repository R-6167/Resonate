import 'dart:convert';

import '../core/dj_types.dart';

/// Stable JSON boundary for persisted V2 track profiles.
class DjProfileSerializer {
  const DjProfileSerializer();

  String encode(DjTrackProfile profile) => jsonEncode({
        'songId': profile.songId,
        'durationMs': profile.durationMs,
        'fingerprint': profile.fingerprint,
        'analysisVersion': profile.analysisVersion,
        'analysisConfidence': profile.analysisConfidence,
        'beatGrid': {
          'bpm': profile.beatGrid.bpm,
          'confidence': profile.beatGrid.confidence,
          'firstBeatMs': profile.beatGrid.firstBeatMs,
          'beatMs': profile.beatGrid.beatMs,
          'downbeatMs': profile.beatGrid.downbeatMs,
          'downbeatConfidence': profile.beatGrid.downbeatConfidence,
          'barConfidence': profile.beatGrid.barConfidence,
          'phraseConfidence': profile.beatGrid.phraseConfidence,
          'beatsPerBar': profile.beatGrid.beatsPerBar,
          'beatsPerPhrase': profile.beatGrid.beatsPerPhrase,
        },
        'keyRoot': profile.keyRoot,
        'keyMode': profile.keyMode,
        'keyConfidence': profile.keyConfidence,
        'harmonicChanges': profile.harmonicChanges
            .map((p) => {'timeMs': p.timeMs, 'confidence': p.confidence})
            .toList(),
        'sections': profile.sections
            .map((s) => {
                  'type': s.type.name,
                  'startMs': s.startMs,
                  'endMs': s.endMs,
                  'confidence': s.confidence,
                  'energy': s.energy,
                })
            .toList(),
        'energyCurve': profile.energyCurve
            .map((p) => {
                  'timeMs': p.timeMs,
                  'value': p.value,
                  'loudness': p.loudness,
                  'bass': p.bass,
                  'mids': p.mids,
                  'highs': p.highs,
                  'slope': p.slope,
                })
            .toList(),
        'spectrum': {
          'bass': profile.spectrum.bass,
          'mids': profile.spectrum.mids,
          'highs': profile.spectrum.highs,
          'centroid': profile.spectrum.centroid,
          'bassDensity': profile.spectrum.bassDensity,
          'spectralFlux': profile.spectrum.spectralFlux,
          'confidence': profile.spectrum.confidence,
        },
        'transitions': {
          'bestIntroMs': profile.transitions.bestIntroMs,
          'bestOutroMs': profile.transitions.bestOutroMs,
          'safeMixIns': _encodePoints(profile.transitions.safeMixIns),
          'safeMixOuts': _encodePoints(profile.transitions.safeMixOuts),
          'riskyPoints': _encodePoints(profile.transitions.riskyPoints),
        },
      });

  DjTrackProfile decode(String raw) {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final beat = _map(map['beatGrid']);
    final spectrum = _map(map['spectrum']);
    final transition = _map(map['transitions']);
    return DjTrackProfile(
      songId: map['songId'] as String,
      durationMs: (map['durationMs'] as num?)?.toInt(),
      fingerprint: map['fingerprint'] as String?,
      analysisVersion: (map['analysisVersion'] as num?)?.toInt() ?? 1,
      analysisConfidence: (map['analysisConfidence'] as num?)?.toDouble() ?? 0,
      beatGrid: DjBeatGrid(
        bpm: (beat['bpm'] as num?)?.toDouble(),
        confidence: (beat['confidence'] as num?)?.toDouble() ?? 0,
        firstBeatMs: (beat['firstBeatMs'] as num?)?.toInt(),
        beatMs: _ints(beat['beatMs']),
        beatsPerBar: (beat['beatsPerBar'] as num?)?.toInt() ?? 4,
        beatsPerPhrase: (beat['beatsPerPhrase'] as num?)?.toInt() ?? 16,
        downbeatMs: _ints(beat['downbeatMs']),
        downbeatConfidence: (beat['downbeatConfidence'] as num?)?.toDouble() ?? 0,
        barConfidence: (beat['barConfidence'] as num?)?.toDouble() ?? 0,
        phraseConfidence: (beat['phraseConfidence'] as num?)?.toDouble() ?? 0,
      ),
      keyRoot: (map['keyRoot'] as num?)?.toInt(),
      keyMode: map['keyMode'] as String?,
      keyConfidence: (map['keyConfidence'] as num?)?.toDouble() ?? 0,
      harmonicChanges: _points(map['harmonicChanges']),
      sections: _sections(map['sections']),
      energyCurve: _energy(map['energyCurve']),
      spectrum: DjSpectralProfile(
        bass: (spectrum['bass'] as num?)?.toDouble() ?? 0.5,
        mids: (spectrum['mids'] as num?)?.toDouble() ?? 0.5,
        highs: (spectrum['highs'] as num?)?.toDouble() ?? 0.5,
        centroid: (spectrum['centroid'] as num?)?.toDouble() ?? 0.5,
        bassDensity: (spectrum['bassDensity'] as num?)?.toDouble() ?? 0.5,
        spectralFlux: (spectrum['spectralFlux'] as num?)?.toDouble() ?? 0.5,
        confidence: (spectrum['confidence'] as num?)?.toDouble() ?? 0,
      ),
      transitions: DjTransitionMarkers(
        bestIntroMs: (transition['bestIntroMs'] as num?)?.toInt(),
        bestOutroMs: (transition['bestOutroMs'] as num?)?.toInt(),
        safeMixIns: _points(transition['safeMixIns']),
        safeMixOuts: _points(transition['safeMixOuts']),
        riskyPoints: _points(transition['riskyPoints']),
      ),
    );
  }

  List<Map<String, dynamic>> _encodePoints(List<DjTimePoint> values) => values
      .map((p) => {
            'timeMs': p.timeMs,
            'confidence': p.confidence,
          })
      .toList();

  List<DjTimePoint> _points(List<dynamic>? values) => (values ?? [])
      .whereType<Map>()
      .map((p) => DjTimePoint(
            (p['timeMs'] as num?)?.toInt() ?? 0,
            confidence: (p['confidence'] as num?)?.toDouble() ?? 0,
          ))
      .toList();

  List<int> _ints(dynamic value) => (value is List ? value : const [])
      .whereType<num>()
      .map((v) => v.toInt())
      .toList();

  List<DjSection> _sections(dynamic value) => (value is List ? value : const [])
      .whereType<Map>()
      .map((s) => DjSection(
            type: _sectionType(s['type']?.toString()),
            startMs: (s['startMs'] as num?)?.toInt() ?? 0,
            endMs: (s['endMs'] as num?)?.toInt() ?? 0,
            confidence: (s['confidence'] as num?)?.toDouble() ?? 0,
            energy: (s['energy'] as num?)?.toDouble() ?? 0.5,
          ))
      .toList();

  List<DjEnergyPoint> _energy(dynamic value) =>
      (value is List ? value : const []).whereType<Map>().map((p) {
        return DjEnergyPoint(
          timeMs: (p['timeMs'] as num?)?.toInt() ?? 0,
          value: (p['value'] as num?)?.toDouble() ?? 0.5,
          loudness: (p['loudness'] as num?)?.toDouble() ?? 0.5,
          bass: (p['bass'] as num?)?.toDouble() ?? 0.5,
          mids: (p['mids'] as num?)?.toDouble() ?? 0.5,
          highs: (p['highs'] as num?)?.toDouble() ?? 0.5,
          slope: (p['slope'] as num?)?.toDouble() ?? 0.0,
        );
      }).toList();

  DjSectionType _sectionType(String? value) {
    for (final type in DjSectionType.values) {
      if (type.name == value) return type;
    }
    return DjSectionType.unknown;
  }

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
}
