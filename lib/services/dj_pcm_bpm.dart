import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// PCM energy BPM for uncompressed WAV only. Compressed formats stay on tags.
class DjPcmBpmEstimate {
  final double bpm;
  final double confidence;
  final int beatOffsetMs;

  const DjPcmBpmEstimate({
    required this.bpm,
    required this.confidence,
    this.beatOffsetMs = 0,
  });
}

class DjPcmBpmAnalyzer {
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
        if (header[0] != 0x52 || header[1] != 0x49 || header[2] != 0x46 || header[3] != 0x46) {
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
            sampleRate = body[4] | (body[5] << 8) | (body[6] << 16) | (body[7] << 24);
            bits = body[14] | (body[15] << 8);
          } else if (id == 'data') {
            final maxBytes = (sampleRate * channels * (bits ~/ 8) * maxSeconds).round();
            pcm = body.length > maxBytes ? Uint8List.sublistView(body, 0, maxBytes) : body;
            break;
          }
          if (size.isOdd) await raf.read(1);
        }
        if (pcm == null || bits != 16 || sampleRate < 8000) return null;
        return _estimateFromPcm16(pcm, sampleRate, channels);
      } finally {
        await raf.close();
      }
    } catch (e) {
      debugPrint('DjPcmBpmAnalyzer: $e');
      return null;
    }
  }

  DjPcmBpmEstimate? _estimateFromPcm16(Uint8List pcm, int sampleRate, int channels) {
    final samples = pcm.length ~/ 2;
    if (samples < sampleRate) return null;
    final hop = math.max(1, sampleRate ~/ 100);
    final env = <double>[];
    final bd = ByteData.sublistView(pcm);
    for (var i = 0; i + hop * channels <= samples; i += hop) {
      var acc = 0.0;
      final n = hop * channels;
      for (var j = 0; j < n && (i + j) * 2 + 1 < pcm.length; j++) {
        acc += bd.getInt16((i + j) * 2, Endian.little).abs().toDouble();
      }
      env.add(acc / n);
    }
    if (env.length < 40) return null;

    final minLag = (60 * 100 / 180).round();
    final maxLag = (60 * 100 / 60).round();
    var bestLag = minLag;
    var best = -1.0;
    for (var lag = minLag; lag <= maxLag && lag < env.length ~/ 2; lag++) {
      var corr = 0.0;
      final limit = env.length - lag;
      for (var i = 0; i < limit; i++) {
        corr += env[i] * env[i + lag];
      }
      if (corr > best) {
        best = corr;
        bestLag = lag;
      }
    }
    if (best <= 0) return null;
    final bpm = (60.0 * 100.0) / bestLag;
    if (bpm < 60 || bpm > 180) return null;
    return DjPcmBpmEstimate(bpm: bpm, confidence: 0.42, beatOffsetMs: 0);
  }
}
