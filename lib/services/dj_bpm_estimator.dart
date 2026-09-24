import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'dj_harmonic.dart';
import 'dj_pcm_bpm.dart';

/// BPM / key hints for DJ Mode.
///
/// Sources (in order):
/// 1. ID3v2 TBPM + TKEY frames (file path or content:// head via native)
/// 2. Native MediaExtractor/MediaCodec PCM window (MP3 / M4A / content://)
/// 3. Light PCM energy BPM for uncompressed WAV
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
  /// Relative energy 0–1 from PCM window (null when ID3-only / unknown).
  final double? energy;
  /// Approximate loudness 0–1 from PCM window.
  final double? loudness;

  const DjBpmEstimate({
    required this.bpm,
    required this.confidence,
    this.beatOffsetMs = 0,
    this.source = 'unknown',
    this.keyRoot,
    this.keyMode,
    this.keyConfidence = 0.0,
    this.energy,
    this.loudness,
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
  static const MethodChannel _channel =
      MethodChannel('com.aetherion.resonate/media_store');

  Future<DjBpmEstimate?> estimateFile(String filePath) async {
    try {
      if (filePath.isEmpty) return null;

      // 1) Prefer local File read when the path is a real filesystem path.
      final isContent = filePath.startsWith('content://');
      final isFileUri = filePath.startsWith('file://');
      Uint8List? head;

      if (!isContent) {
        try {
          final path = isFileUri ? Uri.parse(filePath).toFilePath() : filePath;
          final file = File(path);
          if (await file.exists()) {
            final len = await file.length();
            if (len > 0) {
              final raf = await file.open();
              try {
                final n = math.min(_scanBytes, len);
                head = await raf.read(n);
              } finally {
                await raf.close();
              }
            }
          }
        } catch (e) {
          debugPrint('DjBpmEstimator file head: $e');
        }
      }

      // 2) content:// or unreadable path → native readMediaHead
      if (head == null || head.isEmpty) {
        head = await _readMediaHeadNative(filePath);
      }

      DjBpmEstimate? fromId3;
      DjKeyEstimate? key;
      if (head != null && head.isNotEmpty) {
        fromId3 = _parseId3Tbpm(head);
        key = _parseId3Tkey(head);
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
      }

      // 3) Native PCM decode for compressed / MediaStore tracks
      final nativePcm = await _estimateFromNativePcm(filePath);
      if (nativePcm != null) {
        if (key != null) {
          return DjBpmEstimate(
            bpm: nativePcm.bpm,
            confidence: nativePcm.confidence,
            beatOffsetMs: nativePcm.beatOffsetMs,
            source: nativePcm.source,
            keyRoot: key.keyRoot,
            keyMode: key.keyMode,
            keyConfidence: key.confidence,
            energy: nativePcm.energy,
            loudness: nativePcm.loudness,
          );
        }
        return nativePcm;
      }

      // 4) WAV local PCM fallback
      final pathForWav = isFileUri
          ? Uri.parse(filePath).toFilePath()
          : (isContent ? null : filePath);
      if (pathForWav != null) {
        final pcm = await DjPcmBpmAnalyzer().analyzeWav(pathForWav);
        if (pcm != null) {
          return DjBpmEstimate(
            bpm: pcm.bpm,
            confidence: pcm.confidence,
            beatOffsetMs: pcm.beatOffsetMs,
            source: 'pcm_wav',
            keyRoot: key?.keyRoot,
            keyMode: key?.keyMode,
            keyConfidence: key?.confidence ?? 0.0,
            energy: pcm.energy,
            loudness: pcm.loudness,
          );
        }
      }

      // Key-only result (no BPM)
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
    } catch (e) {
      debugPrint('DjBpmEstimator: $e');
    }
    return null;
  }

  Future<Uint8List?> _readMediaHeadNative(String uri) async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('readMediaHead', {
        'uri': uri,
        'maxBytes': _scanBytes,
      });
      if (raw is Uint8List) return raw;
      if (raw is List<int>) return Uint8List.fromList(raw);
    } catch (e) {
      debugPrint('DjBpmEstimator readMediaHead: $e');
    }
    return null;
  }

  Future<DjBpmEstimate?> _estimateFromNativePcm(String uri) async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('extractPcmWindow', {
        'uri': uri,
        'maxSeconds': 12.0,
      });
      if (raw is! Map) return null;
      final sampleRate = (raw['sampleRate'] as num?)?.toInt();
      final channels = (raw['channels'] as num?)?.toInt() ?? 2;
      final pcmRaw = raw['pcm'];
      if (sampleRate == null || sampleRate < 8000) return null;
      Uint8List? pcm;
      if (pcmRaw is Uint8List) {
        pcm = pcmRaw;
      } else if (pcmRaw is List<int>) {
        pcm = Uint8List.fromList(pcmRaw);
      }
      if (pcm == null || pcm.length < sampleRate) return null;
      final est = DjPcmBpmAnalyzer().estimateFromPcm16(
        pcm,
        sampleRate,
        channels,
        sourceConfidence: 0.48,
      );
      if (est == null) return null;
      return DjBpmEstimate(
        bpm: est.bpm,
        confidence: est.confidence,
        beatOffsetMs: est.beatOffsetMs,
        source: 'pcm_native',
        energy: est.energy,
        loudness: est.loudness,
      );
    } catch (e) {
      debugPrint('DjBpmEstimator native pcm: $e');
      return null;
    }
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

  DjBpmEstimate? _scanTbpmFrame(Uint8List bytes, int start,
      {int? end, int id3v2 = 3}) {
    final limit = end ?? bytes.length;
    for (var i = start; i + 10 < limit; i++) {
      if (bytes[i] == 0x54 &&
          bytes[i + 1] == 0x42 &&
          bytes[i + 2] == 0x50 &&
          bytes[i + 3] == 0x4D) {
        final size = id3v2 >= 4
            ? _synchsafe(bytes, i + 4)
            : ((bytes[i + 4] << 24) |
                (bytes[i + 5] << 16) |
                (bytes[i + 6] << 8) |
                bytes[i + 7]);
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
            : ((bytes[i + 4] << 24) |
                (bytes[i + 5] << 16) |
                (bytes[i + 6] << 8) |
                bytes[i + 7]);
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

/// Align incoming start so the next *phrase* boundary on the outgoing track
/// lands on a phrase boundary of the incoming track (soft; may no-op).
Duration? computePhraseAlignedSeekMs({
  required double bpmA,
  required int beatOffsetMsA,
  required double bpmB,
  required int beatOffsetMsB,
  required int outgoingPositionMs,
  int beatsPerPhrase = 4,
  double maxRelativeDelta = 0.08,
}) {
  if (beatsPerPhrase < 2) beatsPerPhrase = 4;
  if (bpmA < 40 || bpmB < 40 || bpmA > 240 || bpmB > 240) return null;
  final rel = (bpmA - bpmB).abs() / bpmA;
  if (rel > maxRelativeDelta) return null;

  final periodA = 60000.0 / bpmA;
  final periodB = 60000.0 / bpmB;
  final phraseA = periodA * beatsPerPhrase;
  final phraseB = periodB * beatsPerPhrase;

  final phaseA = _mod(outgoingPositionMs - beatOffsetMsA, phraseA);
  final msToNextPhraseA = phaseA < 1e-6 ? 0.0 : (phraseA - phaseA);

  var seek = beatOffsetMsB - msToNextPhraseA;
  seek = _mod(seek, phraseB);

  // Keep seek near the top of the incoming track (first few phrases).
  while (seek > phraseB * 2) {
    seek -= phraseB;
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
