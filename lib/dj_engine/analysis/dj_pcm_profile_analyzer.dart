import 'dart:math' as math;
import 'dart:typed_data';

import '../../services/dj_pcm_bpm.dart';
import '../../services/dj_pcm_features.dart';
import '../core/dj_types.dart';

/// Decoded PCM window. Codec decoding stays outside the DJ engine.
class DjDecodedPcmWindow {
  final Uint8List pcm;
  final int sampleRate;
  final int channels;
  final int startMs;
  final String role;

  const DjDecodedPcmWindow({
    required this.pcm,
    required this.sampleRate,
    required this.channels,
    required this.startMs,
    this.role = 'mid',
  });
}

/// Aggregates multiple PCM windows so BPM/key/structure are not trusted from
/// one arbitrary part of a track. Analysis failure never blocks playback.
class DjPcmProfileAnalyzer {
  final DjPcmBpmAnalyzer _bpm;
  final DjPcmFeatureAnalyzer _features;

  const DjPcmProfileAnalyzer({
    DjPcmBpmAnalyzer bpm = const DjPcmBpmAnalyzer(),
    DjPcmFeatureAnalyzer features = DjPcmFeatureAnalyzer(),
  }) : _bpm = bpm, _features = features;

  DjTrackProfile analyze({
    required String songId,
    required int durationMs,
    required List<DjDecodedPcmWindow> windows,
    String? fingerprint,
    int analysisVersion = 1,
  }) {
    if (windows.isEmpty || durationMs <= 0) {
      return DjTrackProfile(
        songId: songId,
        durationMs: durationMs,
        fingerprint: fingerprint,
        analysisVersion: analysisVersion,
      );
    }

    final bpmSamples = <_BpmSample>[];
    final featureSamples = <_FeatureSample>[];

    for (final window in windows) {
      final bpm = _bpm.estimateFromPcm16(
        window.pcm,
        window.sampleRate,
        window.channels,
        sourceConfidence: window.role == 'mid' ? 0.44 : 0.48,
      );
      if (bpm != null) bpmSamples.add(_BpmSample(window, bpm));

      final features = _features.analyze(
        window.pcm,
        window.sampleRate,
        window.channels,
        windowRole: window.role == 'end' ? 'end' : 'start',
      );
      if (features.keyConfidence > 0 ||
          features.headEnergy != null ||
          features.bodyEnergy != null ||
          features.peakEnergy != null ||
          features.introHintMs != null ||
          features.outroHintMs != null) {
        featureSamples.add(_FeatureSample(window, features));
      }
    }

    final tempo = _aggregateTempo(bpmSamples);
    final key = _aggregateKey(featureSamples);
    final energy = _buildEnergyCurve(durationMs, bpmSamples, featureSamples);
    final sections = _buildSections(durationMs, featureSamples);
    final markers = _buildMarkers(durationMs, featureSamples, sections);

    final energyConfidence = energy.isEmpty ? 0.0 : 0.65;
    final structureConfidence = featureSamples.isEmpty ? 0.0 : 0.65;
    final confidence = _overallConfidence(
      tempo.confidence,
      key.confidence,
      energyConfidence,
      structureConfidence,
    );

    final meanEnergy = energy.isEmpty
        ? 0.5
        : energy.fold<double>(0, (s, p) => s + p.value) / energy.length;
    final meanLoudness = energy.isEmpty
        ? 0.5
        : energy.fold<double>(0, (s, p) => s + p.loudness) / energy.length;

    return DjTrackProfile(
      songId: songId,
      durationMs: durationMs,
      fingerprint: fingerprint,
      beatGrid: DjBeatGrid(
        bpm: tempo.bpm,
        confidence: tempo.confidence,
        firstBeatMs: tempo.beatOffsetMs,
        beatsPerBar: 4,
        beatsPerPhrase: 16,
      ),
      keyRoot: key.root,
      keyMode: key.mode,
      keyConfidence: key.confidence,
      sections: sections,
      energyCurve: energy,
      spectrum: DjSpectralProfile(
        bass: (meanEnergy * 0.82).clamp(0.0, 1.0).toDouble(),
        mids: (meanEnergy * 0.94).clamp(0.0, 1.0).toDouble(),
        highs: (meanLoudness * 0.88).clamp(0.0, 1.0).toDouble(),
        bassDensity: (meanEnergy * 0.70 + 0.12).clamp(0.0, 1.0).toDouble(),
        centroid: (0.30 + meanLoudness * 0.35).clamp(0.0, 1.0).toDouble(),
        spectralFlux: _flux(energy),
        confidence: energy.isEmpty ? 0.0 : 0.45,
      ),
      transitions: markers,
      analysisConfidence: confidence,
      analysisVersion: analysisVersion,
    );
  }

  _TempoAggregate _aggregateTempo(List<_BpmSample> samples) {
    if (samples.isEmpty) return const _TempoAggregate();

    final values = samples.map((s) => s.estimate.bpm).toList()..sort();
    final median = values[values.length ~/ 2];
    final deviations = values.map((v) => (v - median).abs()).toList();
    final meanDeviation = deviations.isEmpty
        ? 0.0
        : deviations.reduce((a, b) => a + b) / deviations.length;
    final agreement =
        (1.0 - meanDeviation / 12.0).clamp(0.0, 1.0).toDouble();
    final source = samples.fold<double>(
          0,
          (sum, sample) => sum + sample.estimate.confidence,
        ) /
        samples.length;
    final confidence =
        (source * 0.62 + agreement * 0.38).clamp(0.0, 0.90).toDouble();

    final period = math.max(1, (60000 / median).round());
    final offsets = samples
        .map((s) => ((s.estimate.beatOffsetMs % period) + period) % period)
        .toList()
      ..sort();

    return _TempoAggregate(
      bpm: median,
      confidence: confidence,
      beatOffsetMs: offsets[offsets.length ~/ 2],
    );
  }

  _KeyAggregate _aggregateKey(List<_FeatureSample> samples) {
    final weighted = <String, double>{};
    final roots = <String, int>{};
    final modes = <String, String>{};

    for (final sample in samples) {
      final f = sample.features;
      if (f.keyRoot == null || f.keyMode == null || f.keyConfidence <= 0) {
        continue;
      }
      final k = '\${f.keyRoot}:\${f.keyMode}';
      weighted[k] = (weighted[k] ?? 0) + f.keyConfidence;
      roots[k] = f.keyRoot!;
      modes[k] = f.keyMode!;
    }

    if (weighted.isEmpty) return const _KeyAggregate();
    final ranked = weighted.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final best = ranked.first;
    final total = weighted.values.fold<double>(0, (a, b) => a + b);
    final dominance = total <= 0 ? 0.0 : best.value / total;
    final confidence = (best.value / math.max(1, samples.length) * 0.65 +
            dominance * 0.35)
        .clamp(0.0, 0.95)
        .toDouble();

    return _KeyAggregate(
      root: roots[best.key],
      mode: modes[best.key],
      confidence: confidence,
    );
  }

  List<DjEnergyPoint> _buildEnergyCurve(
    int durationMs,
    List<_BpmSample> bpmSamples,
    List<_FeatureSample> featureSamples,
  ) {
    final points = <DjEnergyPoint>[];

    for (final sample in featureSamples) {
      final f = sample.features;
      final raw = f.bodyEnergy ?? f.headEnergy ?? f.peakEnergy;
      if (raw == null || !raw.isFinite) continue;
      final value = _normalizeEnergy(raw);
      final loudness = _normalizeEnergy(f.bodyEnergy ?? raw);
      points.add(DjEnergyPoint(
        timeMs: sample.window.startMs.clamp(0, durationMs),
        value: value,
        loudness: loudness,
        bass: (value * 0.80).clamp(0.0, 1.0).toDouble(),
        mids: (value * 0.95).clamp(0.0, 1.0).toDouble(),
        highs: (loudness * 0.90).clamp(0.0, 1.0).toDouble(),
      ));
    }

    for (final sample in bpmSamples) {
      if (points.any((p) => p.timeMs == sample.window.startMs)) continue;
      final value = (sample.estimate.energy ?? 0.5).clamp(0.0, 1.0).toDouble();
      points.add(DjEnergyPoint(
        timeMs: sample.window.startMs.clamp(0, durationMs),
        value: value,
        loudness: (sample.estimate.loudness ?? value).clamp(0.0, 1.0).toDouble(),
      ));
    }

    points.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return points;
  }

  List<DjSection> _buildSections(
    int durationMs,
    List<_FeatureSample> samples,
  ) {
    final sections = <DjSection>[];
    for (final sample in samples) {
      final type = _mapSection(sample.features.sectionHint);
      if (type == DjSectionType.unknown) continue;
      final start = sample.window.startMs.clamp(0, durationMs);
      final frames = sample.window.pcm.length ~/
          math.max(1, 2 * sample.window.channels);
      final length = math.max(
        1000,
        math.min(durationMs - start, frames * 1000 ~/ sample.window.sampleRate),
      );
      final end = (start + length).clamp(start, durationMs);
      final energy = _featureEnergy(sample.features);
      sections.add(DjSection(
        type: type,
        startMs: start,
        endMs: end,
        confidence:
            math.max(sample.features.keyConfidence, 0.45).clamp(0.0, 0.90).toDouble(),
        energy: energy,
      ));
    }
    sections.sort((a, b) => a.startMs.compareTo(b.startMs));
    return sections;
  }

  DjTransitionMarkers _buildMarkers(
    int durationMs,
    List<_FeatureSample> samples,
    List<DjSection> sections,
  ) {
    int? intro;
    int? outroStart;

    for (final sample in samples) {
      final f = sample.features;
      if (sample.window.role == 'start' && f.introHintMs != null) {
        intro = math.max(intro ?? 0, f.introHintMs!);
      }
      if (sample.window.role == 'end' && f.outroHintMs != null) {
        outroStart = (durationMs - f.outroHintMs!).clamp(0, durationMs);
      }
    }

    return DjTransitionMarkers(
      bestIntroMs: intro,
      bestOutroMs: outroStart,
      safeMixIns: [
        if (intro != null) DjTimePoint(intro!, confidence: 0.55),
      ],
      safeMixOuts: [
        if (outroStart != null) DjTimePoint(outroStart, confidence: 0.60),
      ],
      riskyPoints: [
        for (final section in sections)
          if (section.type == DjSectionType.drop ||
              section.type == DjSectionType.chorus)
            DjTimePoint(section.startMs, confidence: section.confidence),
      ],
    );
  }

  double _featureEnergy(DjPcmFeatures f) {
    return _normalizeEnergy(f.bodyEnergy ?? f.headEnergy ?? f.peakEnergy ?? 0.5);
  }

  double _normalizeEnergy(double value) {
    if (!value.isFinite || value <= 0) return 0.0;
    return (math.log(1 + value) / math.log(1 + 12000))
        .clamp(0.0, 1.0)
        .toDouble();
  }

  double _flux(List<DjEnergyPoint> points) {
    if (points.length < 2) return 0.5;
    var sum = 0.0;
    for (var i = 1; i < points.length; i++) {
      sum += (points[i].value - points[i - 1].value).abs();
    }
    return (sum / (points.length - 1)).clamp(0.0, 1.0).toDouble();
  }

  double _overallConfidence(
    double tempo,
    double key,
    double energy,
    double structure,
  ) {
    final values = <double>[
      if (tempo > 0) tempo,
      if (key > 0) key,
      if (energy > 0) energy,
      if (structure > 0) structure,
    ];
    if (values.isEmpty) return 0;
    return (values.reduce((a, b) => a + b) / values.length)
        .clamp(0.0, 0.95)
        .toDouble();
  }

  DjSectionType _mapSection(String hint) {
    return switch (hint) {
      'intro' || 'quiet_intro' => DjSectionType.intro,
      'build' => DjSectionType.build,
      'drop' => DjSectionType.drop,
      'chorus' => DjSectionType.chorus,
      'breakdown' => DjSectionType.breakdown,
      'outro' || 'quiet_outro' => DjSectionType.outro,
      'energetic' => DjSectionType.instrumental,
      _ => DjSectionType.unknown,
    };
  }
}

class _BpmSample {
  final DjDecodedPcmWindow window;
  final DjPcmBpmEstimate estimate;
  const _BpmSample(this.window, this.estimate);
}

class _FeatureSample {
  final DjDecodedPcmWindow window;
  final DjPcmFeatures features;
  const _FeatureSample(this.window, this.features);
}

class _TempoAggregate {
  final double? bpm;
  final double confidence;
  final int beatOffsetMs;
  const _TempoAggregate({
    this.bpm,
    this.confidence = 0,
    this.beatOffsetMs = 0,
  });
}

class _KeyAggregate {
  final int? root;
  final String? mode;
  final double confidence;
  const _KeyAggregate({
    this.root,
    this.mode,
    this.confidence = 0,
  });
}
