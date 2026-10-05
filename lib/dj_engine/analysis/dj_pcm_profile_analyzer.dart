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
        windowRole: window.role,
      );
      if (features.keyConfidence > 0 ||
          features.headEnergy != null ||
          features.bodyEnergy != null ||
          features.peakEnergy != null ||
          features.introHintMs != null ||
          features.outroHintMs != null ||
          features.spectralCentroid > 0 ||
          features.bassEnergy > 0 ||
          features.beatMs.isNotEmpty) {
        featureSamples.add(_FeatureSample(window, features));
      }
    }

    final tempo = _aggregateTempo(bpmSamples);
    final beatEvidence = _aggregateBeatEvidence(featureSamples);
    final beatPositions = _aggregateBeats(featureSamples, durationMs);
    final key = _aggregateKey(featureSamples);
    final energy = _buildEnergyCurve(durationMs, bpmSamples, featureSamples);
    final sections = _buildSections(durationMs, featureSamples);
    final markers = _buildMarkers(durationMs, featureSamples, sections);

    final energyConfidence = energy.isEmpty ? 0.0 : 0.65;
    final structureConfidence = featureSamples.isEmpty ? 0.0 : 0.65;
    final tempoConfidence = beatEvidence.hasEvidence
        ? (tempo.confidence * 0.58 + beatEvidence.confidence * 0.42)
            .clamp(0.0, 0.95)
            .toDouble()
        : tempo.confidence;
    final confidence = _overallConfidence(
      tempoConfidence,
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
    final spectrum = _aggregateSpectrum(featureSamples);

    return DjTrackProfile(
      songId: songId,
      durationMs: durationMs,
      fingerprint: fingerprint,
      beatGrid: DjBeatGrid(
        bpm: tempo.bpm,
        confidence: tempoConfidence,
        firstBeatMs: beatPositions.isEmpty ? tempo.beatOffsetMs : beatPositions.first,
        beatMs: beatPositions,
        beatsPerBar: 4,
        beatsPerPhrase: 16,
      ),
      keyRoot: key.root,
      keyMode: key.mode,
      keyConfidence: key.confidence,
      sections: sections,
      energyCurve: energy,
      spectrum: spectrum,
      transitions: markers,
      analysisConfidence: confidence,
      analysisVersion: analysisVersion,
    );
  }

  ({double confidence, double phaseStability, bool hasEvidence}) _aggregateBeatEvidence(
    List<_FeatureSample> samples,
  ) {
    final values = samples
        .where((s) => s.features.beatConfidence > 0)
        .map((s) => s.features.beatConfidence)
        .toList();
    if (values.isEmpty) {
      return (confidence: 0.0, phaseStability: 0.0, hasEvidence: false);
    }
    final confidence = values.reduce((a, b) => a + b) / values.length;
    final stabilityValues = samples
        .where((s) => s.features.beatPhaseStability > 0)
        .map((s) => s.features.beatPhaseStability)
        .toList();
    final stability = stabilityValues.isEmpty
        ? 0.0
        : stabilityValues.reduce((a, b) => a + b) / stabilityValues.length;
    return (
      confidence: confidence.clamp(0.0, 0.95).toDouble(),
      phaseStability: stability.clamp(0.0, 1.0).toDouble(),
      hasEvidence: true,
    );
  }

  List<int> _aggregateBeats(
    List<_FeatureSample> featureSamples,
    int durationMs,
  ) {
    final observations = <_BeatObservation>[];
    for (final sample in featureSamples) {
      final confidence = sample.features.beatConfidence;
      if (confidence <= 0 || sample.features.beatMs.isEmpty) continue;
      final local = sample.features.beatMs;
      final diffs = <double>[];
      for (var i = 1; i < local.length; i++) {
        final d = (local[i] - local[i - 1]).toDouble();
        if (d > 200 && d < 1500) diffs.add(d);
      }
      if (diffs.length < 3) continue;
      diffs.sort();
      final period = diffs[diffs.length ~/ 2];
      final first = sample.window.startMs + local.first;
      observations.add(_BeatObservation(first, period, confidence));
    }
    if (observations.isEmpty) return const [];

    // Prefer the period supported by the most confident windows. This avoids
    // concatenating incompatible local beat trains from overlapping windows.
    var best = observations.first;
    var bestSupport = -1.0;
    for (final candidate in observations) {
      var support = 0.0;
      for (final other in observations) {
        final periodDelta = (candidate.periodMs - other.periodMs).abs();
        final phase = _phaseDistance(candidate.firstMs, other.firstMs, candidate.periodMs);
        if (periodDelta <= candidate.periodMs * 0.045 ||
            periodDelta <= 18.0) {
          support += other.confidence * (1.0 - (phase / candidate.periodMs).clamp(0.0, 1.0));
        }
      }
      if (support > bestSupport) {
        bestSupport = support;
        best = candidate;
      }
    }

    final period = best.periodMs;
    final phaseSamples = observations
        .where((o) => (o.periodMs - period).abs() <= math.max(18.0, period * 0.045))
        .toList();
    if (phaseSamples.isEmpty) return const [];

    // Circular weighted phase average, referenced to the track timeline.
    var sinSum = 0.0;
    var cosSum = 0.0;
    for (final sample in phaseSamples) {
      final phase = (sample.firstMs % period) / period * 2 * math.pi;
      sinSum += math.sin(phase) * sample.confidence;
      cosSum += math.cos(phase) * sample.confidence;
    }
    final phaseAngle = math.atan2(sinSum, cosSum);
    final normalizedPhase = phaseAngle < 0 ? phaseAngle + 2 * math.pi : phaseAngle;
    final phaseMs = normalizedPhase / (2 * math.pi) * period;
    var firstBeat = phaseMs.round();
    while (firstBeat > 0) firstBeat -= period.round();
    firstBeat %= math.max(1, period.round());

    // Generate one continuous grid. It is intentionally bounded to the track;
    // this gives phrase alignment a stable global index instead of per-window
    // indices that can restart at every PCM sample.
    final positions = <int>[];
    var beat = firstBeat;
    while (beat < durationMs) {
      if (beat >= 0) positions.add(beat);
      beat += period.round();
    }
    return positions.length >= 4 ? positions : const [];
  }

  double _phaseDistance(int a, int b, double period) {
    if (period <= 0) return 1.0;
    final raw = ((a - b) % period).abs();
    return math.min(raw, period - raw);
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

  DjSpectralProfile _aggregateSpectrum(List<_FeatureSample> samples) {
    if (samples.isEmpty) return const DjSpectralProfile();
    var bass = 0.0, mids = 0.0, highs = 0.0, centroid = 0.0;
    var flux = 0.0, density = 0.0, count = 0;
    for (final sample in samples) {
      final f = sample.features;
      if (f.bassEnergy <= 0 && f.midsEnergy <= 0 && f.highsEnergy <= 0) continue;
      bass += f.bassEnergy;
      mids += f.midsEnergy;
      highs += f.highsEnergy;
      centroid += f.spectralCentroid;
      flux += f.spectralFlux;
      density += f.bassDensity;
      count++;
    }
    if (count == 0) return const DjSpectralProfile();
    return DjSpectralProfile(
      bass: (bass / count).clamp(0.0, 1.0).toDouble(),
      mids: (mids / count).clamp(0.0, 1.0).toDouble(),
      highs: (highs / count).clamp(0.0, 1.0).toDouble(),
      centroid: (centroid / count).clamp(0.0, 1.0).toDouble(),
      bassDensity: (density / count).clamp(0.0, 1.0).toDouble(),
      spectralFlux: (flux / count).clamp(0.0, 1.0).toDouble(),
      confidence: count >= 3 ? 0.78 : 0.58,
    );
  }

  List<DjSection> _buildSections(
    int durationMs,
    List<_FeatureSample> samples,
  ) {
    final raw = <DjSection>[];
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
      raw.add(DjSection(
        type: type,
        startMs: start,
        endMs: end,
        confidence: sample.features.keyConfidence > 0
            ? sample.features.keyConfidence.clamp(0.0, 0.90).toDouble()
            : 0.55,
        energy: _featureEnergy(sample.features),
      ));
    }

    raw.sort((a, b) => a.startMs.compareTo(b.startMs));
    if (raw.isEmpty) return const [];

    // Windows overlap. Merge compatible evidence instead of exposing a list of
    // overlapping 12–15 s "sections" to the transition brain.
    final merged = <DjSection>[];
    for (final section in raw) {
      if (merged.isEmpty) {
        merged.add(section);
        continue;
      }
      final previous = merged.last;
      final sameType = previous.type == section.type;
      final touches = section.startMs <= previous.endMs + 2500;
      if (sameType && touches) {
        final weightA = math.max(0.05, previous.confidence);
        final weightB = math.max(0.05, section.confidence);
        final confidence = ((previous.confidence * weightA +
                    section.confidence * weightB) /
                (weightA + weightB))
            .clamp(0.0, 0.95)
            .toDouble();
        final energy = ((previous.energy * weightA + section.energy * weightB) /
                (weightA + weightB))
            .clamp(0.0, 1.0)
            .toDouble();
        merged[merged.length - 1] = DjSection(
          type: previous.type,
          startMs: math.min(previous.startMs, section.startMs),
          endMs: math.max(previous.endMs, section.endMs),
          confidence: confidence,
          energy: energy,
        );
      } else {
        merged.add(section);
      }
    }
    return merged;
  }

  DjTransitionMarkers _buildMarkers(
    int durationMs,
    List<_FeatureSample> samples,
    List<DjSection> sections,
  ) {
    int? intro;
    int? outroStart;
    final safeIns = <DjTimePoint>[];
    final safeOuts = <DjTimePoint>[];
    final risky = <DjTimePoint>[];

    for (final sample in samples) {
      final f = sample.features;
      final base = sample.window.startMs.clamp(0, durationMs);

      if (sample.window.role == 'start') {
        if (f.introHintMs != null) {
          final point = (base + f.introHintMs!).clamp(0, durationMs);
          intro = intro == null ? point : math.min(intro, point);
          safeIns.add(DjTimePoint(point, confidence: 0.72));
        }
      }

      if (sample.window.role == 'end' && f.outroHintMs != null) {
        outroStart = (durationMs - f.outroHintMs!).clamp(0, durationMs);
        safeOuts.add(DjTimePoint(outroStart, confidence: 0.78));
      }

      // A detected local drop/peak is a musical boundary, but it is usually a
      // risky place to inject another full-energy track.
      if (f.dropHintMs != null) {
        final point = (base + f.dropHintMs!).clamp(0, durationMs);
        risky.add(DjTimePoint(point, confidence: 0.68));
      }
    }

    // Structural boundaries are useful candidate anchors. Breakdown/build
    // entries are generally safer mix-ins than drops/choruses.
    for (final section in sections) {
      final point = DjTimePoint(
        section.startMs,
        confidence: section.confidence.clamp(0.0, 0.95).toDouble(),
      );
      switch (section.type) {
        case DjSectionType.intro:
        case DjSectionType.build:
        case DjSectionType.breakdown:
          safeIns.add(point);
          break;
        case DjSectionType.outro:
          safeOuts.add(point);
          break;
        case DjSectionType.drop:
        case DjSectionType.chorus:
          risky.add(point);
          break;
        default:
          break;
      }
    }

    safeIns.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    safeOuts.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    risky.sort((a, b) => a.timeMs.compareTo(b.timeMs));

    return DjTransitionMarkers(
      bestIntroMs: intro,
      bestOutroMs: outroStart,
      safeMixIns: safeIns,
      safeMixOuts: safeOuts,
      riskyPoints: risky,
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

class _BeatObservation {
  final int firstMs;
  final double periodMs;
  final double confidence;
  const _BeatObservation(this.firstMs, this.periodMs, this.confidence);
}
