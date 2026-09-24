import 'dart:math' as math;
import 'dart:typed_data';

/// Soft key + section hints from a PCM window (never required for playback).
class DjPcmFeatures {
  final int? keyRoot;
  final String? keyMode;
  final double keyConfidence;
  final String keySource;
  /// Estimated quiet-intro length from head energy, ms (null = unknown).
  final int? introHintMs;
  /// Estimated quiet-outro length when analyzing an end window.
  final int? outroHintMs;
  final double? headEnergy;
  final double? bodyEnergy;
  final String sectionHint; // quiet_intro | energetic | quiet_outro | unknown

  const DjPcmFeatures({
    this.keyRoot,
    this.keyMode,
    this.keyConfidence = 0.0,
    this.keySource = 'none',
    this.introHintMs,
    this.outroHintMs,
    this.headEnergy,
    this.bodyEnergy,
    this.sectionHint = 'unknown',
  });
}

/// Lightweight chroma + energy-shape features for DJ Mode.
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
      final section = _sectionFromMono(mono, rate, windowRole: windowRole);
      final key = _softKeyFromMono(mono, rate);

      return DjPcmFeatures(
        keyRoot: key.$1,
        keyMode: key.$2,
        keyConfidence: key.$3,
        keySource: key.$3 >= 0.28 ? 'pcm_chroma' : 'none',
        introHintMs: section.introHintMs,
        outroHintMs: section.outroHintMs,
        headEnergy: section.headEnergy,
        bodyEnergy: section.bodyEnergy,
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
    double? headEnergy,
    double? bodyEnergy,
    String sectionHint,
  }) _sectionFromMono(Float64List mono, int rate,
      {required String windowRole}) {
    if (mono.length < rate) {
      return (
        introHintMs: null,
        outroHintMs: null,
        headEnergy: null,
        bodyEnergy: null,
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
    if (env.length < 20) {
      return (
        introHintMs: null,
        outroHintMs: null,
        headEnergy: null,
        bodyEnergy: null,
        sectionHint: 'unknown',
      );
    }
    final headN = math.max(3, env.length ~/ 5);
    final bodyStart = env.length ~/ 3;
    final bodyEnd = (env.length * 2) ~/ 3;
    var head = 0.0;
    for (var i = 0; i < headN; i++) {
      head += env[i];
    }
    head /= headN;
    var body = 0.0;
    final bodyCount = math.max(1, bodyEnd - bodyStart);
    for (var i = bodyStart; i < bodyEnd; i++) {
      body += env[i];
    }
    body /= bodyCount;

    int? introHint;
    int? outroHint;
    var hint = 'unknown';
    if (windowRole == 'start' && body > 1e-6 && head < body * 0.55) {
      var rise = headN;
      for (var i = headN; i < env.length ~/ 2; i++) {
        if (env[i] >= body * 0.7) {
          rise = i;
          break;
        }
      }
      introHint = (rise * 20).clamp(500, 20000).toInt();
      hint = 'quiet_intro';
    } else if (windowRole == 'start' && body > 1e-6 && head >= body * 0.85) {
      hint = 'energetic';
    }
    if (windowRole == 'end' && body > 1e-6) {
      final tailN = math.max(3, env.length ~/ 5);
      var tail = 0.0;
      for (var i = env.length - tailN; i < env.length; i++) {
        tail += env[i];
      }
      tail /= tailN;
      if (tail < body * 0.55) {
        var fall = tailN;
        for (var i = env.length - tailN; i > env.length ~/ 2; i--) {
          if (env[i] >= body * 0.7) {
            fall = env.length - i;
            break;
          }
        }
        outroHint = (fall * 20).clamp(500, 25000).toInt();
        hint = 'quiet_outro';
      }
    }
    return (
      introHintMs: introHint,
      outroHintMs: outroHint,
      headEnergy: head,
      bodyEnergy: body,
      sectionHint: hint,
    );
  }

  /// Returns (root 0–11, mode, confidence).
  (int?, String?, double) _softKeyFromMono(Float64List mono, int rate) {
    const frame = 2048;
    if (mono.length < frame * 2) return (null, null, 0.0);
    final chroma = List<double>.filled(12, 0.0);
    final frameCount = math.min(10, mono.length ~/ frame);
    for (var f = 0; f < frameCount; f++) {
      final off = f * (mono.length ~/ frameCount);
      if (off + frame > mono.length) break;
      for (var pc = 0; pc < 12; pc++) {
        var energy = 0.0;
        for (var oct = 2; oct <= 5; oct++) {
          final midi = 12 * oct + pc + 12;
          final freq = 440.0 * math.pow(2.0, (midi - 69) / 12.0);
          if (freq >= rate / 2.0 - 20) continue;
          energy += _goertzel(mono, off, frame, rate, freq.toDouble());
        }
        chroma[pc] += energy;
      }
    }
    var sum = chroma.fold<double>(0.0, (a, b) => a + b);
    if (sum < 1e-9) return (null, null, 0.0);
    for (var i = 0; i < 12; i++) {
      chroma[i] /= sum;
    }
    const major = [
      6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88
    ];
    const minor = [
      6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17
    ];
    var bestRoot = 0;
    var bestMode = 'major';
    var best = -1.0;
    for (var root = 0; root < 12; root++) {
      for (final entry in [('major', major), ('minor', minor)]) {
        final profile = entry.$2;
        var corr = 0.0;
        for (var i = 0; i < 12; i++) {
          corr += chroma[i] * profile[(i - root + 12) % 12];
        }
        if (corr > best) {
          best = corr;
          bestRoot = root;
          bestMode = entry.$1;
        }
      }
    }
    final conf = ((best - 2.5) / 4.0).clamp(0.0, 0.55).toDouble();
    if (conf < 0.28) return (null, null, conf);
    return (bestRoot, bestMode, conf);
  }

  double _goertzel(
    Float64List x,
    int offset,
    int n,
    int rate,
    double freq,
  ) {
    final w = 2.0 * math.pi * freq / rate;
    final coeff = 2.0 * math.cos(w);
    var s0 = 0.0;
    var s1 = 0.0;
    var s2 = 0.0;
    for (var i = 0; i < n; i++) {
      s0 = x[offset + i] + coeff * s1 - s2;
      s2 = s1;
      s1 = s0;
    }
    final power = s1 * s1 + s2 * s2 - coeff * s1 * s2;
    return power < 0 ? 0.0 : power;
  }
}
