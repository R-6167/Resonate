import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// Energy-envelope BPM estimate from raw PCM (any decoded source).
class DjPcmBpmEstimate {
  final double bpm;
  final double confidence;
  final int beatOffsetMs;
  /// Relative loudness energy in [0, 1] from the PCM window (null if unknown).
  final double? energy;
  /// Approximate RMS-based loudness in [0, 1] (null if unknown).
  final double? loudness;

  const DjPcmBpmEstimate({
    required this.bpm,
    required this.confidence,
    this.beatOffsetMs = 0,
    this.energy,
    this.loudness,
  });
}

class DjPcmBpmAnalyzer {
  /// Uncompressed WAV path helper (legacy).
  Future<DjPcmBpmEstimate?> analyzeWav(
    String path, {
    double maxSeconds = 25,
  }) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final lower = path.toLowerCase();
      if (!lower.endsWith('.wav') && !lower.endsWith('.wave')) return null;

      final raf = await file.open();
      try {
        final header = await raf.read(12);
        if (header.length < 12) return null;
        if (header[0] != 0x52 ||
            header[1] != 0x49 ||
            header[2] != 0x46 ||
            header[3] != 0x46) {
          return null;
        }
        int sampleRate = 44100;
        int channels = 1;
        int bits = 16;
        Uint8List? pcm;
        while (true) {
          final ch = await raf.read(8);
          if (ch.length < 8) break;
          final id = String.fromCharCodes(ch.sublist(0, 4));
          final size = ch[4] | (ch[5] << 8) | (ch[6] << 16) | (ch[7] << 24);
          if (size < 0 || size > 80 * 1024 * 1024) break;
          final body = await raf.read(size);
          if (body.length < size) break;
          if (id == 'fmt ' && body.length >= 16) {
            channels = body[2] | (body[3] << 8);
            sampleRate =
                body[4] | (body[5] << 8) | (body[6] << 16) | (body[7] << 24);
            bits = body[14] | (body[15] << 8);
          } else if (id == 'data') {
            final maxBytes =
                (sampleRate * channels * (bits ~/ 8) * maxSeconds).round();
            pcm = body.length > maxBytes
                ? Uint8List.sublistView(body, 0, maxBytes)
                : body;
            break;
          }
          if (size.isOdd) await raf.read(1);
        }
        if (pcm == null || bits != 16 || sampleRate < 8000) return null;
        return estimateFromPcm16(
          pcm,
          sampleRate,
          channels,
          sourceConfidence: 0.42,
        );
      } finally {
        await raf.close();
      }
    } catch (e) {
      debugPrint('DjPcmBpmAnalyzer: $e');
      return null;
    }
  }

  /// Shared energy BPM for any 16-bit little-endian PCM (mono or multi-channel).
  ///
  /// Returns relative [energy] / [loudness] and a real [beatOffsetMs] from the
  /// envelope phase at the strongest lag (not always 0).
  DjPcmBpmEstimate? estimateFromPcm16(
    Uint8List pcm,
    int sampleRate,
    int channels, {
    double sourceConfidence = 0.45,
  }) {
    if (sampleRate < 8000 || channels < 1) return null;
    final samples = pcm.length ~/ 2;
    if (samples < sampleRate) return null;
    // ~10 ms hop → 100 frames/sec (matches lag units used below).
    final hop = math.max(1, sampleRate ~/ 100);
    final env = <double>[];
    final bd = ByteData.sublistView(pcm);
    var sumSq = 0.0;
    var nSamples = 0;
    for (var i = 0; i + hop * channels <= samples; i += hop) {
      var acc = 0.0;
      final n = hop * channels;
      for (var j = 0; j < n && (i + j) * 2 + 1 < pcm.length; j++) {
        final s = bd.getInt16((i + j) * 2, Endian.little).toDouble();
        acc += s.abs();
        sumSq += s * s;
        nSamples++;
      }
      env.add(acc / n);
    }
    if (env.length < 40) return null;

    final minLag = (60 * 100 / 180).round(); // ~33
    final maxLag = (60 * 100 / 60).round(); // 100
    var bestLag = minLag;
    var best = -1.0;
    final corrAt = <int, double>{};
    for (var lag = minLag; lag <= maxLag && lag < env.length ~/ 2; lag++) {
      var corr = 0.0;
      final limit = env.length - lag;
      for (var i = 0; i < limit; i++) {
        corr += env[i] * env[i + lag];
      }
      corrAt[lag] = corr;
      if (corr > best) {
        best = corr;
        bestLag = lag;
      }
    }
    if (best <= 0) return null;

    // Soft octave correction: if half/double lag has nearly as strong correlation,
    // prefer the lag that lands BPM in a more typical dance range (90–140).
    var bpm = (60.0 * 100.0) / bestLag;
    void consider(int lag) {
      if (lag < minLag || lag > maxLag) return;
      final c = corrAt[lag];
      if (c == null || c < best * 0.92) return;
      final cand = (60.0 * 100.0) / lag;
      final betterRange = _danceScore(cand) > _danceScore(bpm);
      if (betterRange) {
        bestLag = lag;
        bpm = cand;
      }
    }

    consider(bestLag * 2);
    if (bestLag.isEven) consider(bestLag ~/ 2);

    if (bpm < 60 || bpm > 180) return null;
    var conf = sourceConfidence.clamp(0.35, 0.72).toDouble();
    // Slight confidence bump when octave choice was stable.
    if (bpm >= 90 && bpm <= 140) conf = (conf + 0.04).clamp(0.35, 0.78).toDouble();

    // Beat offset: position of strongest onset in the first period (ms).
    var peakIdx = 0;
    var peakVal = -1.0;
    final period = bestLag.clamp(1, env.length - 1).toInt();
    final scan = math.min(period, env.length);
    for (var i = 0; i < scan; i++) {
      if (env[i] > peakVal) {
        peakVal = env[i];
        peakIdx = i;
      }
    }
    // Each env step ≈ 10 ms.
    final beatOffsetMs = (peakIdx * 10).clamp(0, (60000.0 / bpm).round() - 1).toInt();

    final meanEnv = env.reduce((a, b) => a + b) / env.length;
    final energy =
        (math.log(1.0 + meanEnv) / math.log(1.0 + 12000.0)).clamp(0.0, 1.0);
    final rms = nSamples > 0 ? math.sqrt(sumSq / nSamples) : 0.0;
    final loudness =
        (math.log(1.0 + rms) / math.log(1.0 + 16000.0)).clamp(0.0, 1.0);

    return DjPcmBpmEstimate(
      bpm: bpm,
      confidence: conf,
      beatOffsetMs: beatOffsetMs,
      energy: energy,
      loudness: loudness,
    );
  }

  static double _danceScore(double bpm) {
    // Prefer 95–130, soft falloff outside.
    if (bpm >= 95 && bpm <= 130) return 1.0;
    if (bpm >= 85 && bpm <= 145) return 0.7;
    if (bpm >= 70 && bpm <= 160) return 0.4;
    return 0.1;
  }
}
