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
  final double bassEnergy;
  final double midsEnergy;
  final double highsEnergy;
  final double spectralCentroid;
  final double spectralFlux;
  final double bassDensity;
  /// Beat locations detected inside this decoded window, relative to its start.
  final List<int> beatMs;
  /// Confidence that the detected beat period/phase is stable across the window.
  final double beatConfidence;
  /// Phase stability of detected beats (1 = tightly locked to the inferred grid).
  final double beatPhaseStability;

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
    this.bassEnergy = 0.0,
    this.midsEnergy = 0.0,
    this.highsEnergy = 0.0,
    this.spectralCentroid = 0.0,
    this.spectralFlux = 0.0,
    this.bassDensity = 0.0,
    this.beatMs = const [],
    this.beatConfidence = 0.0,
    this.beatPhaseStability = 0.0,
  });
}

/// Lightweight structure + key features for DJ Mode.
///
/// Key: chroma with harmonic weighting + Krumhansl–Schmuckler profiles.
/// Structure: multi-segment energy envelope (intro/build/drop/chorus/outro).
class DjPcmFeatureAnalyzer {
  const DjPcmFeatureAnalyzer();

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
      final spectral = _spectralFromMono(mono, rate);
      final beats = _beatsFromMono(mono, rate);

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
        bassEnergy: spectral.bass,
        midsEnergy: spectral.mids,
        highsEnergy: spectral.highs,
        spectralCentroid: spectral.centroid,
        spectralFlux: spectral.flux,
        bassDensity: spectral.bassDensity,
        beatMs: beats.positions,
        beatConfidence: beats.confidence,
        beatPhaseStability: beats.phaseStability,
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
    } else {
      final early = means.take(2).fold<double>(0, (a, b) => a + b) / 2.0;
      final center = means.skip(3).take(2).fold<double>(0, (a, b) => a + b) / 2.0;
      final late = means.skip(6).fold<double>(0, (a, b) => a + b) / math.max(1, means.length - 6);
      if (peak > math.max(1e-9, body) * 1.22 && peakIdx > n ~/ 5) {
        hint = peakIdx > n * 0.55 ? 'drop' : 'chorus';
      } else if (center < early * 0.78 && center < late * 0.78) {
        hint = 'breakdown';
      } else if (late > early * 1.18 && late > center * 1.05) {
        hint = 'build';
      } else if (early > late * 1.20) {
        hint = 'outro';
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

  ({List<int> positions, double confidence, double phaseStability}) _beatsFromMono(
    Float64List mono,
    int rate,
  ) {
    // Estimate a dominant onset period, then measure how consistently the
    // observed onsets support that period and phase. We deliberately keep the
    // output conservative: uncertain windows contribute no beat grid.
    const hop = 256;
    if (mono.length < rate) {
      return (positions: const [], confidence: 0.0, phaseStability: 0.0);
    }
    final env = <double>[];
    for (var i = 0; i + hop <= mono.length; i += hop) {
      var sum = 0.0;
      for (var j = 0; j < hop; j++) sum += mono[i + j].abs();
      env.add(sum / hop);
    }
    if (env.length < 40) {
      return (positions: const [], confidence: 0.0, phaseStability: 0.0);
    }

    final onset = List<double>.filled(env.length, 0.0);
    var onsetEnergy = 0.0;
    for (var i = 1; i < env.length; i++) {
      onset[i] = math.max(0.0, env[i] - env[i - 1]);
      onsetEnergy += onset[i];
    }
    if (onsetEnergy <= 1e-9) {
      return (positions: const [], confidence: 0.0, phaseStability: 0.0);
    }

    final minLag = (rate / hop * 60 / 180).round().clamp(8, 200);
    final maxLag = (rate / hop * 60 / 55).round().clamp(minLag + 1, 260);
    var bestLag = 0;
    var bestScore = 0.0;
    var secondScore = 0.0;
    for (var lag = minLag; lag <= maxLag; lag++) {
      var score = 0.0;
      for (var i = lag; i < onset.length; i++) {
        score += onset[i] * onset[i - lag];
      }
      if (score > bestScore) {
        secondScore = bestScore;
        bestScore = score;
        bestLag = lag;
      } else if (score > secondScore) {
        secondScore = score;
      }
    }
    if (bestLag == 0 || bestScore <= 1e-9) {
      return (positions: const [], confidence: 0.0, phaseStability: 0.0);
    }

    final periodFrames = bestLag;
    final periodMs = periodFrames * hop * 1000 / rate;
    final normalizedPeak = bestScore /
        math.max(1e-9, onsetEnergy * onsetEnergy / math.max(1, onset.length));
    final peakStrength = (normalizedPeak / 2.5).clamp(0.0, 1.0).toDouble();
    final peakSeparation = secondScore <= 1e-12
        ? 1.0
        : (1.0 - secondScore / bestScore).clamp(0.0, 1.0).toDouble();

    // Find the strongest onset inside one period and use it as the phase seed.
    var seed = 0;
    var seedValue = 0.0;
    for (var i = 0; i < periodFrames && i < onset.length; i++) {
      if (onset[i] > seedValue) {
        seedValue = onset[i];
        seed = i;
      }
    }
    if (seedValue <= 1e-9) {
      return (positions: const [], confidence: 0.0, phaseStability: 0.0);
    }

    final phaseResiduals = <double>[];
    var supportingOnsets = 0;
    for (var i = seed; i < onset.length; i += periodFrames) {
      var bestResidual = double.infinity;
      var bestOnset = 0.0;
      final lo = math.max(0, i - periodFrames ~/ 5);
      final hi = math.min(onset.length - 1, i + periodFrames ~/ 5);
      for (var j = lo; j <= hi; j++) {
        if (onset[j] > bestOnset) {
          bestOnset = onset[j];
          bestResidual = (j - i).abs().toDouble();
        }
      }
      if (bestOnset > 0) {
        supportingOnsets++;
        phaseResiduals.add(bestResidual / math.max(1, periodFrames));
      }
    }

    final meanResidual = phaseResiduals.isEmpty
        ? 1.0
        : phaseResiduals.reduce((a, b) => a + b) / phaseResiduals.length;
    final phaseStability = (1.0 - meanResidual * 4.0).clamp(0.0, 1.0).toDouble();
    final support = (supportingOnsets / math.max(1, (onset.length - seed) ~/ periodFrames))
        .clamp(0.0, 1.0).toDouble();
    final confidence = (peakStrength * 0.35 + peakSeparation * 0.20 +
            phaseStability * 0.30 + support * 0.15)
        .clamp(0.0, 1.0).toDouble();

    // Only expose a grid when the phase is credible. This prevents a weak
    // autocorrelation peak from causing aggressive beat/phrase alignment.
    if (confidence < 0.38 || phaseStability < 0.35) {
      return (positions: const [], confidence: confidence, phaseStability: phaseStability);
    }

    final positions = <int>[];
    var frame = seed;
    while (frame < mono.length ~/ hop) {
      positions.add((frame * hop * 1000 ~/ rate));
      frame += periodFrames;
    }
    return (positions: positions, confidence: confidence, phaseStability: phaseStability);
  }

  ({double bass, double mids, double highs, double centroid, double flux, double bassDensity})
      _spectralFromMono(Float64List mono, int rate) {
    const frame = 512;
    const hop = 256;
    if (mono.length < frame) {
      return (bass: 0, mids: 0, highs: 0, centroid: 0, flux: 0, bassDensity: 0);
    }
    var bassSum = 0.0, midsSum = 0.0, highsSum = 0.0;
    var centroidSum = 0.0, fluxSum = 0.0;
    var frames = 0;
    var previous = List<double>.filled(frame ~/ 2, 0.0);
    for (var start = 0; start + frame <= mono.length; start += hop) {
      final real = Float64List(frame);
      final imag = Float64List(frame);
      for (var n = 0; n < frame; n++) {
        final w = 0.5 - 0.5 * math.cos(2 * math.pi * n / (frame - 1));
        real[n] = mono[start + n] * w;
      }
      _fft(real, imag);

      var total = 0.0, weighted = 0.0;
      final magnitudes = List<double>.filled(frame ~/ 2, 0.0);
      for (var k = 1; k < frame ~/ 2; k++) {
        final mag = math.sqrt(real[k] * real[k] + imag[k] * imag[k]);
        magnitudes[k] = mag;
        total += mag;
        weighted += mag * k;
      }
      if (total <= 1e-9) continue;

      var bass = 0.0, mids = 0.0, highs = 0.0, flux = 0.0;
      for (var k = 1; k < frame ~/ 2; k++) {
        final freq = k * rate / frame;
        final mag = magnitudes[k];
        if (freq < 180) bass += mag;
        else if (freq < 2000) mids += mag;
        else highs += mag;
        final current = mag / total;
        flux += math.max(0.0, current - previous[k]);
        previous[k] = current;
      }
      final norm = math.max(1e-9, bass + mids + highs);
      bassSum += bass / norm;
      midsSum += mids / norm;
      highsSum += highs / norm;
      centroidSum += weighted / total / (frame / 2);
      fluxSum += flux.clamp(0.0, 1.0).toDouble();
      frames++;
    }
    if (frames == 0) return (bass: 0, mids: 0, highs: 0, centroid: 0, flux: 0, bassDensity: 0);
    final bass = bassSum / frames, mids = midsSum / frames, highs = highsSum / frames;
    return (
      bass: bass.clamp(0.0, 1.0).toDouble(),
      mids: mids.clamp(0.0, 1.0).toDouble(),
      highs: highs.clamp(0.0, 1.0).toDouble(),
      centroid: (centroidSum / frames).clamp(0.0, 1.0).toDouble(),
      flux: (fluxSum / frames).clamp(0.0, 1.0).toDouble(),
      bassDensity: (bass / math.max(1e-9, bass + mids + highs)).clamp(0.0, 1.0).toDouble(),
    );
  }

  void _fft(Float64List real, Float64List imag) {
    final n = real.length;
    var j = 0;
    for (var i = 1; i < n; i++) {
      var bit = n >> 1;
      while ((j & bit) != 0) {
        j ^= bit;
        bit >>= 1;
      }
      j ^= bit;
      if (i < j) {
        final tr = real[i]; real[i] = real[j]; real[j] = tr;
        final ti = imag[i]; imag[i] = imag[j]; imag[j] = ti;
      }
    }
    for (var len = 2; len <= n; len <<= 1) {
      final angle = -2 * math.pi / len;
      final wLenR = math.cos(angle), wLenI = math.sin(angle);
      for (var i = 0; i < n; i += len) {
        var wr = 1.0, wi = 0.0;
        final half = len >> 1;
        for (var k = 0; k < half; k++) {
          final uR = real[i + k], uI = imag[i + k];
          final vR = real[i + k + half] * wr - imag[i + k + half] * wi;
          final vI = real[i + k + half] * wi + imag[i + k + half] * wr;
          real[i + k] = uR + vR;
          imag[i + k] = uI + vI;
          real[i + k + half] = uR - vR;
          imag[i + k + half] = uI - vI;
          final nextWr = wr * wLenR - wi * wLenI;
          wi = wr * wLenI + wi * wLenR;
          wr = nextWr;
        }
      }
    }
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
