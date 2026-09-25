import 'dart:math' as math;
import 'dart:typed_data';

/// Soft key + structure hints from a PCM window (never required for playback).
class DjPcmFeatures {
  final int? keyRoot;
  final String? keyMode;
  final double keyConfidence;
  final String keySource;
  /// Estimated quiet-intro length from head energy, ms (null = unknown).
  final int? introHintMs;
  /// Estimated quiet-outro length when analyzing an end window.
  final int? outroHintMs;
  /// First strong energy peak (build	o drop / chorus entry), ms from window start.
  final int? dropHintMs;
  final double? headEnergy;
  final double? bodyEnergy;
  final double? peakEnergy;
  /// intro | build | drop | chorus | breakdown | outro | quiet_intro |
  /// quiet_outro | energetic | unknown
  final String sectionHint;

  const DjPcmFeatures({
    this.keyRoot,
    this.keyMode,
    this.keyConfidence = 0.0,
    this.keySource = 'none',
    this.introHintMs,
    this.outroHintMs,
    this.dropHintMs,
    this.headEnergy,
    this.bodyEnergy,
    this.peakEnergy,
    this.sectionHint = 'unknown',
  });
}

/// Lightweight structure + key features for DJ Mode.
///
/// Key: chroma with harmonic weighting + Krumhansl–Schmuckler profiles.
/// Structure: multi-segment energy envelope (intro/build/drop/chorus/outro).
class DjPcmFeatureAnalyzer {
  /// [windowRole] is `start` (default) or `end` (near-track-end extract).
  DjPcmFeatures analyze(
    Uint8List pcm,
    int sampleRate,
    int channels, {
    String windowRole = 'start',
  }) {
    try {
      if (sampleRate < 8000 || channels < 1 || pcm.length < sampleRate) {
        return const DjPcmFeatures();
      }

      final mono =
          _toMonoDownsampled(pcm, sampleRate, channels, targetRate: 11025);
      const rate = 11025;
      final section = _structureFromMono(mono, rate, windowRole: windowRole);
      final key = _keyFromMono(mono, rate);

      return DjPcmFeatures(
        keyRoot: key.$1,
        keyMode: key.$2,
        keyConfidence: key.$3,
        keySource: key.$3 >= 0.32 ? 'pcm_chroma_ks' : 'none',
        introHintMs: section.introHintMs,
        outroHintMs: section.outroHintMs,
        dropHintMs: section.dropHintMs,
        headEnergy: section.headEnergy,
        bodyEnergy: section.bodyEnergy,
        peakEnergy: section.peakEnergy,
        sectionHint: section.sectionHint,
      );
    } catch (_) {
      return const DjPcmFeatures();
    }
  }

  Float64List _toMonoDownsampled(
    Uint8List pcm,
    int sampleRate,
    int channels, {
    required int targetRate,
  }) {
    final bd = ByteData.sublistView(pcm);
    final totalFrames = pcm.length ~/ (2 * channels);
    final step = math.max(1, sampleRate ~/ targetRate);
    final outLen = totalFrames ~/ step;
    final out = Float64List(outLen);
    for (var i = 0; i < outLen; i++) {
      final frame = i * step;
      var acc = 0.0;
      for (var c = 0; c < channels; c++) {
        final idx = (frame * channels + c) * 2;
        if (idx + 1 >= pcm.length) break;
        acc += bd.getInt16(idx, Endian.little).toDouble();
      }
      out[i] = acc / channels;
    }
    return out;
  }

  ({
    int? introHintMs,
    int? outroHintMs,
    int? dropHintMs,
    double? headEnergy,
    double? bodyEnergy,
    double? peakEnergy,
    String sectionHint,
  }) _structureFromMono(
    Float64List mono,
    int rate, {
    required String windowRole,
  }) {
    if (mono.length < rate ~/ 2) {
      return (
        introHintMs: null,
        outroHintMs: null,
        dropHintMs: null,
        headEnergy: null,
        bodyEnergy: null,
        peakEnergy: null,
        sectionHint: 'unknown',
      );
    }

    final hop = math.max(1, rate ~/ 50);
    final env = <double>[];
    for (var i = 0; i + hop <= mono.length; i += hop) {
      var acc = 0.0;
      for (var j = 0; j < hop; j++) {
        acc += mono[i + j].abs();
      }
      env.add(acc / hop);
    }
    if (env.length < 24) {
      return (
        introHintMs: null,
        outroHintMs: null,
        dropHintMs: null,
        headEnergy: null,
        bodyEnergy: null,
        peakEnergy: null,
        sectionHint: 'unknown',
      );
    }

    final sm = List<double>.from(env);
    for (var i = 1; i < sm.length - 1; i++) {
      sm[i] = (env[i - 1] + env[i] * 2 + env[i + 1]) / 4.0;
    }

    final n = sm.length;
    final means = <double>[];
    for (var s = 0; s < 8; s++) {
      final a = (s * n / 8).floor();
      final b = (((s + 1) * n) / 8).floor().clamp(a + 1, n);
      var acc = 0.0;
      for (var i = a; i < b; i++) {
        acc += sm[i];
      }
      means.add(acc / (b - a));
    }

    final headN = math.max(3, n ~/ 6);
    var head = 0.0;
    for (var i = 0; i < headN; i++) {
      head += sm[i];
    }
    head /= headN;

    final bodyStart = n ~/ 3;
    final bodyEnd = (n * 2) ~/ 3;
    var body = 0.0;
    for (var i = bodyStart; i < bodyEnd; i++) {
      body += sm[i];
    }
    body /= math.max(1, bodyEnd - bodyStart);

    var peak = 0.0;
    var peakIdx = 0;
    for (var i = 0; i < n; i++) {
      if (sm[i] > peak) {
        peak = sm[i];
        peakIdx = i;
      }
    }

    int? introHint;
    int? outroHint;
    int? dropHint;
    var hint = 'unknown';

    if (peak > body * 1.15 && peakIdx > headN) {
      dropHint = (peakIdx * 20).clamp(400, 28000).toInt();
    }

    if (windowRole == 'start') {
      final early = means.take(3).fold<double>(0, (a, b) => a + b) / 3.0;
      final mid = means.skip(3).take(2).fold<double>(0, (a, b) => a + b) / 2.0;
      final late = means.skip(5).fold<double>(0, (a, b) => a + b) /
          math.max(1, means.length - 5);

      if (body > 1e-9 && head < body * 0.5) {
        var rise = headN;
        for (var i = headN; i < n ~/ 2; i++) {
          if (sm[i] >= body * 0.7) {
            rise = i;
            break;
          }
        }
        introHint = (rise * 20).clamp(500, 24000).toInt();
        hint = 'quiet_intro';
        if (late > mid * 1.2 && late > early * 1.35) {
          hint = 'build';
        }
      } else if (peak > body * 1.25 && peakIdx > n ~/ 4) {
        hint = peakIdx > (n * 0.55) ? 'drop' : 'chorus';
      } else if (mid > early * 1.2 && late < mid * 0.85) {
        hint = 'breakdown';
      } else if (head >= body * 0.9 && peak <= body * 1.2) {
        hint = 'energetic';
      } else if (late > early * 1.25) {
        hint = 'build';
      } else if (head < body * 0.7) {
        hint = 'intro';
      }
    } else if (windowRole == 'end') {
      final tailN = math.max(3, n ~/ 5);
      var tail = 0.0;
      for (var i = n - tailN; i < n; i++) {
        tail += sm[i];
      }
      tail /= tailN;
      final earlyEnd =
          means.take(3).fold<double>(0, (a, b) => a + b) / 3.0;

      if (tail < body * 0.55) {
        var fall = tailN;
        for (var i = n - tailN; i > n ~/ 2; i--) {
          if (sm[i] >= body * 0.7) {
            fall = n - i;
            break;
          }
        }
        outroHint = (fall * 20).clamp(500, 28000).toInt();
        hint = 'quiet_outro';
      } else if (earlyEnd > tail * 1.25 && tail < body * 0.9) {
        hint = 'outro';
        outroHint = ((n ~/ 4) * 20).clamp(800, 20000).toInt();
      } else if (tail < earlyEnd * 0.75) {
        hint = 'breakdown';
      } else {
        hint = 'energetic';
      }
    }

    return (
      introHintMs: introHint,
      outroHintMs: outroHint,
      dropHintMs: dropHint,
      headEnergy: head.isFinite ? head : null,
      bodyEnergy: body.isFinite ? body : null,
      peakEnergy: peak.isFinite ? peak : null,
      sectionHint: hint,
    );
  }

  /// Chroma key with harmonic stack + Krumhansl–Schmuckler profiles.
  (int?, String?, double) _keyFromMono(Float64List mono, int rate) {
    if (mono.length < rate) return (null, null, 0.0);

    final start = mono.length ~/ 10;
    final end = mono.length - mono.length ~/ 10;
    final slice = Float64List.sublistView(mono, start, end);

    final chroma = List<double>.filled(12, 0.0);
    const baseHz = 55.0;
    for (var pc = 0; pc < 12; pc++) {
      var energy = 0.0;
      for (var oct = 2; oct <= 5; oct++) {
        final f0 = baseHz * math.pow(2.0, oct + pc / 12.0);
        if (f0 < 70 || f0 > 5000) continue;
        final e1 = _goertzel(slice, rate, f0);
        final e2 = _goertzel(slice, rate, f0 * 2.0);
        final e3 = _goertzel(slice, rate, f0 * 3.0);
        energy += e1 + 0.5 * e2 + 0.25 * e3;
      }
      chroma[pc] = energy;
    }

    var sum = chroma.fold<double>(0.0, (a, b) => a + b);
    if (sum < 1e-12) return (null, null, 0.0);
    for (var i = 0; i < 12; i++) {
      chroma[i] /= sum;
    }

    const major = [
      6.35, 2.23, 3.48, 2.33, 4.38, 4.09,
      2.52, 5.19, 2.39, 3.66, 2.29, 2.88,
    ];
    const minor = [
      6.33, 2.68, 3.52, 5.38, 2.60, 3.53,
      2.54, 4.75, 3.98, 2.69, 3.34, 3.17,
    ];

    var bestRoot = 0;
    var bestMode = 'major';
    var bestCorr = -1.0;
    var second = -1.0;

    for (final entry in [('major', major), ('minor', minor)]) {
      final mode = entry.$1;
      final profile = entry.$2;
      final pSum = profile.fold<double>(0.0, (a, b) => a + b);
      final pMean = pSum / 12.0;
      var pVar = 0.0;
      for (final v in profile) {
        final d = v - pMean;
        pVar += d * d;
      }
      if (pVar < 1e-9) continue;

      for (var root = 0; root < 12; root++) {
        var cMean = 0.0;
        final rotated = List<double>.filled(12, 0.0);
        for (var i = 0; i < 12; i++) {
          rotated[i] = profile[(i - root + 12) % 12];
          cMean += chroma[i];
        }
        cMean /= 12.0;
        var num = 0.0;
        var cVar = 0.0;
        for (var i = 0; i < 12; i++) {
          final cd = chroma[i] - cMean;
          final pd = rotated[i] - pMean;
          num += cd * pd;
          cVar += cd * cd;
        }
        if (cVar < 1e-12) continue;
        final corr = num / math.sqrt(cVar * pVar);
        if (corr > bestCorr) {
          second = bestCorr;
          bestCorr = corr;
          bestRoot = root;
          bestMode = mode;
        } else if (corr > second) {
          second = corr;
        }
      }
    }

    final sep = (bestCorr - second).clamp(0.0, 1.0);
    final conf = ((bestCorr.clamp(0.0, 1.0) * 0.7) + sep * 0.5)
        .clamp(0.0, 0.95)
        .toDouble();
    if (conf < 0.28) return (null, null, conf);
    return (bestRoot, bestMode, conf);
  }

  double _goertzel(Float64List samples, int rate, double freqHz) {
    if (freqHz <= 0 || freqHz >= rate / 2) return 0.0;
    final n = samples.length;
    final w = 2.0 * math.pi * freqHz / rate;
    final coeff = 2.0 * math.cos(w);
    var s0 = 0.0;
    var s1 = 0.0;
    var s2 = 0.0;
    for (var i = 0; i < n; i++) {
      s0 = samples[i] + coeff * s1 - s2;
      s2 = s1;
      s1 = s0;
    }
    final power = s1 * s1 + s2 * s2 - coeff * s1 * s2;
    return power.isFinite && power > 0 ? power : 0.0;
  }
}
