import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'dj_harmonic.dart';
import 'dj_pcm_bpm.dart';

/// BPM / key hints for DJ Mode.
///
/// Sources (in order):
/// 1. ID3v2 TBPM + TKEY frames
/// 2. Light PCM energy BPM for uncompressed WAV only
///
/// Never throws into the playback path; failures return null.
class DjBpmEstimate {
  final double bpm;
  final double confidence;
  final int beatOffsetMs;
  final String source;
  final int? keyRoot;
  final String? keyMode;
  final double keyConfidence;

  const DjBpmEstimate({
    required this.bpm,
    required this.confidence,
    this.beatOffsetMs = 0,
    this.source = 'unknown',
    this.keyRoot,
    this.keyMode,
    this.keyConfidence = 0.0,
  });
}

class DjKeyEstimate {
  final int keyRoot;
  final String keyMode;
  final double confidence;
  final String source;

  const DjKeyEstimate({
    required this.keyRoot,
    required this.keyMode,
    required this.confidence,
    this.source = 'id3_tkey',
  });
}

class DjBpmEstimator {
  static const int _scanBytes = 512 * 1024;

  Future<DjBpmEstimate?> estimateFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      final len = await file.length();
      if (len <= 0) return null;
      final raf = await file.open();
      try {
        final n = math.min(_scanBytes, len);
        final bytes = await raf.read(n);
        final fromId3 = _parseId3Tbpm(bytes);
        final key = _parseId3Tkey(bytes);
        if (fromId3 != null) {
          if (key == null) return fromId3;
          return DjBpmEstimate(
            bpm: fromId3.bpm,
            confidence: fromId3.confidence,
            beatOffsetMs: fromId3.beatOffsetMs,
            source: fromId3.source,
            keyRoot: key.keyRoot,
            keyMode: key.keyMode,
            keyConfidence: key.confidence,
          );
        }
        if (key != null) {
          return DjBpmEstimate(
            bpm: 0,
            confidence: 0.0,
            source: 'id3_tkey_only',
            keyRoot: key.keyRoot,
            keyMode: key.keyMode,
            keyConfidence: key.confidence,
          );
        }
      } finally {
        await raf.close();
      }

      final pcm = await DjPcmBpmAnalyzer().analyzeWav(filePath);
      if (pcm != null) {
        return DjBpmEstimate(
          bpm: pcm.bpm,
          confidence: pcm.confidence,
          beatOffsetMs: pcm.beatOffsetMs,
          source: 'pcm_wav',
        );
      }
    } catch (e) {
      debugPrint('DjBpmEstimator: $e');
    }
    return null;
  }

  DjBpmEstimate? _parseId3Tbpm(Uint8List bytes) {
    if (bytes.length < 10) return null;
    if (bytes[0] != 0x49 || bytes[1] != 0x44 || bytes[2] != 0x33) {
      return _scanTbpmFrame(bytes, 0);
    }
    final version = bytes[3];
    final tagSize = _synchsafe(bytes, 6);
    final bodyEnd = math.min(bytes.length, 10 + tagSize);
    return _scanTbpmFrame(bytes, 10, end: bodyEnd, id3v2: version);
  }

  DjBpmEstimate? _scanTbpmFrame(Uint8List bytes, int start, {int? end, int id3v2 = 3}) {
    final limit = end ?? bytes.length;
    for (var i = start; i + 10 < limit; i++) {
      if (bytes[i] == 0x54 &&
          bytes[i + 1] == 0x42 &&
          bytes[i + 2] == 0x50 &&
          bytes[i + 3] == 0x4D) {
        final size = id3v2 >= 4
            ? _synchsafe(bytes, i + 4)
            : ((bytes[i + 4] << 24) | (bytes[i + 5] << 16) | (bytes[i + 6] << 8) | bytes[i + 7]);
        if (size <= 0 || size > 64) continue;
        final dataStart = i + 10;
        final dataEnd = math.min(limit, dataStart + size);
        if (dataStart >= dataEnd) continue;
        var textStart = dataStart;
        if (dataEnd - dataStart >= 2 && bytes[dataStart] <= 3) {
          textStart = dataStart + 1;
        }
        final text = String.fromCharCodes(bytes.sublist(textStart, dataEnd))
            .replaceAll(RegExp(r'[^\d.]'), ' ')
            .trim();
        final match = RegExp(r'(\d{2,3}(?:\.\d+)?)').firstMatch(text);
        if (match == null) continue;
        final bpm = double.tryParse(match.group(1)!);
        if (bpm == null || bpm < 40 || bpm > 240) continue;
        return DjBpmEstimate(
          bpm: bpm,
          confidence: 0.72,
          beatOffsetMs: 0,
          source: 'id3_tbpm',
        );
      }
    }
    return null;
  }

  /// ID3v2 TKEY — musical key text (e.g. Am, C major, 8A).
  DjKeyEstimate? _parseId3Tkey(Uint8List bytes) {
    if (bytes.length < 10) return null;
    int start = 0;
    int? end;
    int id3v2 = 3;
    if (bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) {
      id3v2 = bytes[3];
      final tagSize = _synchsafe(bytes, 6);
      start = 10;
      end = math.min(bytes.length, 10 + tagSize);
    }
    final limit = end ?? bytes.length;
    for (var i = start; i + 10 < limit; i++) {
      if (bytes[i] == 0x54 &&
          bytes[i + 1] == 0x4B &&
          bytes[i + 2] == 0x45 &&
          bytes[i + 3] == 0x59) {
        final size = id3v2 >= 4
            ? _synchsafe(bytes, i + 4)
            : ((bytes[i + 4] << 24) | (bytes[i + 5] << 16) | (bytes[i + 6] << 8) | bytes[i + 7]);
        if (size <= 0 || size > 64) continue;
        final dataStart = i + 10;
        final dataEnd = math.min(limit, dataStart + size);
        if (dataStart >= dataEnd) continue;
        var textStart = dataStart;
        if (dataEnd - dataStart >= 2 && bytes[dataStart] <= 3) {
          textStart = dataStart + 1;
        }
        final text = String.fromCharCodes(bytes.sublist(textStart, dataEnd))
            .replaceAll('\u0000', ' ')
            .trim();
        final parsed = parseKeyText(text);
        if (parsed == null) continue;
        return DjKeyEstimate(
          keyRoot: parsed.root,
          keyMode: parsed.mode,
          confidence: 0.7,
          source: 'id3_tkey',
        );
      }
    }
    return null;
  }

  int _synchsafe(Uint8List b, int i) {
    if (i + 3 >= b.length) return 0;
    return ((b[i] & 0x7f) << 21) |
        ((b[i + 1] & 0x7f) << 14) |
        ((b[i + 2] & 0x7f) << 7) |
        (b[i + 3] & 0x7f);
  }
}

Duration? computeBeatAlignedSeekMs({
  required double bpmA,
  required int beatOffsetMsA,
  required double bpmB,
  required int beatOffsetMsB,
  required int outgoingPositionMs,
  double maxRelativeDelta = 0.08,
}) {
  if (bpmA < 40 || bpmB < 40 || bpmA > 240 || bpmB > 240) return null;
  final rel = (bpmA - bpmB).abs() / bpmA;
  if (rel > maxRelativeDelta) return null;

  final periodA = 60000.0 / bpmA;
  final periodB = 60000.0 / bpmB;

  final phaseA = _mod(outgoingPositionMs - beatOffsetMsA, periodA);
  final msToNextBeatA = phaseA < 1e-6 ? 0.0 : (periodA - phaseA);

  var seek = beatOffsetMsB - msToNextBeatA;
  seek = _mod(seek, periodB);

  while (seek > periodB * 8) {
    seek -= periodB;
  }
  if (seek < 0) seek = 0;
  return Duration(milliseconds: seek.round());
}

double _mod(num x, double m) {
  final r = x.toDouble() % m;
  return r < 0 ? r + m : r;
}

class DjTempoStretchPlan {
  final double speedOutgoing;
  final double speedIncoming;
  final double effectiveBpm;
  final String mode;

  const DjTempoStretchPlan({
    required this.speedOutgoing,
    required this.speedIncoming,
    required this.effectiveBpm,
    required this.mode,
  });
}

DjTempoStretchPlan? computeTempoStretch({
  required double bpmA,
  required double bpmB,
  required int maxStretchPercent,
}) {
  if (bpmA < 40 || bpmB < 40 || bpmA > 240 || bpmB > 240) return null;
  final maxDelta = (maxStretchPercent.clamp(3, 20)) / 100.0;
  bool within(double speed) => (speed - 1.0).abs() <= maxDelta + 1e-9;

  final matchIn = bpmA / bpmB;
  if (within(matchIn)) {
    return DjTempoStretchPlan(
      speedOutgoing: 1.0,
      speedIncoming: matchIn,
      effectiveBpm: bpmA,
      mode: 'match_incoming',
    );
  }

  // meet_middle stretches the audible outgoing deck — skip for stability.
  return null;
}
