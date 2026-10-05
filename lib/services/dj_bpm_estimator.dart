import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'dj_harmonic.dart';
import 'dj_pcm_bpm.dart';
import 'dj_pcm_features.dart';

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
  final int? introHintMs;
  final int? outroHintMs;
  final String? sectionHint;

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
    this.introHintMs,
    this.outroHintMs,
    this.sectionHint,
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

  Future<DjBpmEstimate?> estimateFile(String filePath, {int? durationMs}) async {
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
      }

      // 3) Native PCM decode for compressed / MediaStore tracks.
      // Always try PCM so energy / loudness / beatOffset exist even when ID3 has BPM.
      final nativePcm = await _estimateFromNativePcm(filePath);
      // Whole-track structure: second window near the end when duration is known.
      DjBpmEstimate? endPcm;
      final dur = durationMs ?? 0;
      if (dur > 45000) {
        final startMs = (dur - 18000).clamp(20000, dur - 8000);
        endPcm = await _estimateFromNativePcm(
          filePath,
          maxSeconds: 14.0,
          startMs: startMs,
          windowRole: 'end',
        );
      }
      final mergedNative = _mergeStructure(nativePcm, endPcm);
      // Whole-track structure: second window near the end when duration is known.
      DjBpmEstimate? endPcm;
      final dur = durationMs ?? 0;
      if (dur > 45000) {
        final startMs = (dur - 18000).clamp(20000, dur - 8000);
        endPcm = await _estimateFromNativePcm(
          filePath,
          maxSeconds: 14.0,
          startMs: startMs,
          windowRole: 'end',
        );
      }
      final mergedNative = _mergeStructure(nativePcm, endPcm);
      // Whole-track structure: second window near the end when duration is known.
      DjBpmEstimate? endPcm;
      final dur = durationMs ?? 0;
      if (dur > 45000) {
        final startMs = (dur - 18000).clamp(20000, dur - 8000);
        endPcm = await _estimateFromNativePcm(
          filePath,
          maxSeconds: 14.0,
          startMs: startMs,
          windowRole: 'end',
        );
      }
      final mergedNative = _mergeStructure(nativePcm, endPcm);
      if (mergedNative != null) {
        final nativePcm = mergedNative;
        // Prefer tagged BPM when present (higher trust), keep PCM energy/offset.
        if (fromId3 != null) {
          return DjBpmEstimate(
            bpm: fromId3.bpm,
            confidence: math.max(fromId3.confidence, 0.75),
            beatOffsetMs: nativePcm.beatOffsetMs,
            source: 'id3_tbpm+pcm',
            keyRoot: key?.keyRoot ?? nativePcm.keyRoot,
            keyMode: key?.keyMode ?? nativePcm.keyMode,
            keyConfidence: key != null
                ? key.confidence
                : nativePcm.keyConfidence,
            energy: nativePcm.energy,
            loudness: nativePcm.loudness,
            introHintMs: nativePcm.introHintMs,
            outroHintMs: nativePcm.outroHintMs,
            sectionHint: nativePcm.sectionHint,
          );
        }
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
            introHintMs: nativePcm.introHintMs,
            outroHintMs: nativePcm.outroHintMs,
            sectionHint: nativePcm.sectionHint,
          );
        }
        return nativePcm;
      }

      // ID3 BPM only (no PCM) — still better than nothing.
      if (fromId3 != null) {
        return DjBpmEstimate(
          bpm: fromId3.bpm,
          confidence: fromId3.confidence,
          beatOffsetMs: fromId3.beatOffsetMs,
          source: fromId3.source,
          keyRoot: key?.keyRoot,
          keyMode: key?.keyMode,
          keyConfidence: key?.confidence ?? 0.0,
        );
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


  /// Merge start-window estimate with end-window structure/outro hints.
  DjBpmEstimate? _mergeStructure(DjBpmEstimate? start, DjBpmEstimate? end) {
    if (start == null) return end;
    if (end == null) return start;
    final s = start.sectionHint;
    final e = end.sectionHint;
    String? section;
    if (e == 'quiet_outro' || e == 'outro') {
      if (s == 'build' || s == 'drop' || s == 'chorus' || s == 'intro' ||
          s == 'quiet_intro' || s == 'energetic') {
        section = s;
      } else {
        section = e;
      }
    } else {
      section = s ?? e;
    }
    return DjBpmEstimate(
      bpm: start.bpm > 0 ? start.bpm : end.bpm,
      confidence: start.confidence >= end.confidence
          ? start.confidence
          : end.confidence,
      beatOffsetMs: start.beatOffsetMs,
      source: start.source,
      keyRoot: start.keyRoot ?? end.keyRoot,
      keyMode: start.keyMode ?? end.keyMode,
      keyConfidence: start.keyConfidence >= end.keyConfidence
          ? start.keyConfidence
          : end.keyConfidence,
      energy: start.energy ?? end.energy,
      loudness: start.loudness ?? end.loudness,
      introHintMs: start.introHintMs,
      outroHintMs: end.outroHintMs ?? start.outroHintMs,
      sectionHint: section,
    );
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

  Future<DjBpmEstimate?> _estimateFromNativePcm(String uri, {double maxSeconds = 15.0, int startMs = 0, String windowRole = 'start'}) async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('extractPcmWindow', {
        'uri': uri,
        'maxSeconds': maxSeconds,
        'startMs': startMs,
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
      final feats = DjPcmFeatureAnalyzer().analyze(
        pcm,
        sampleRate,
        channels,
        windowRole: windowRole,
      );
      return DjBpmEstimate(
        bpm: est.bpm,
        confidence: est.confidence,
        beatOffsetMs: est.beatOffsetMs,
        source: 'pcm_native',
        energy: est.energy,
        loudness: est.loudness,
        keyRoot: feats.keyRoot,
        keyMode: feats.keyMode,
        keyConfidence: feats.keyConfidence,
        introHintMs: feats.introHintMs,
        outroHintMs: feats.outroHintMs,
        sectionHint: feats.sectionHint,
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

/// Prefer the BPM octave (1× / ½ / 2×) closest to [bpmA] for phase math.
double _effectiveBpmForAlign(double bpmA, double bpmB) {
  var best = bpmB;
  var bestRel = (bpmA - bpmB).abs() / math.max(bpmA, 1.0);
  for (final cand in [bpmB * 0.5, bpmB * 2.0]) {
    if (cand < 40 || cand > 240) continue;
    final r = (bpmA - cand).abs() / math.max(bpmA, 1.0);
    if (r < bestRel) {
      bestRel = r;
      best = cand;
    }
  }
  return best;
}

Duration? computeBeatAlignedSeekMs({
  required double bpmA,
  required int beatOffsetMsA,
  required double bpmB,
  required int beatOffsetMsB,
  required int outgoingPositionMs,
  double maxRelativeDelta = 0.09,
}) {
  if (bpmA < 40 || bpmB < 40 || bpmA > 240 || bpmB > 240) return null;
  // Half/double often looks like a huge delta but is the same pulse grid.
  final bpmBEff = _effectiveBpmForAlign(bpmA, bpmB);
  final rel = (bpmA - bpmBEff).abs() / math.max(bpmA, 1.0);
  if (rel > maxRelativeDelta) return null;

  final periodA = 60000.0 / bpmA;
  final periodB = 60000.0 / bpmBEff;
  // Clamp noisy offsets into one period (PCM peak can be off).
  final offA = _mod(beatOffsetMsA.toDouble(), periodA);
  final offB = _mod(beatOffsetMsB.toDouble(), periodB);

  final phaseA = _mod(outgoingPositionMs - offA, periodA);
  final msToNextBeatA = phaseA < 1.0 ? 0.0 : (periodA - phaseA);

  // Land incoming on a beat when outgoing hits its next beat.
  var seek = offB - msToNextBeatA;
  seek = _mod(seek, periodB);
  // Prefer the nearer phase (don't start almost a full bar in).
  if (seek > periodB * 0.5) {
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
  double maxRelativeDelta = 0.09,
}) {
  if (beatsPerPhrase < 2) beatsPerPhrase = 4;
  if (bpmA < 40 || bpmB < 40 || bpmA > 240 || bpmB > 240) return null;
  final bpmBEff = _effectiveBpmForAlign(bpmA, bpmB);
  final rel = (bpmA - bpmBEff).abs() / math.max(bpmA, 1.0);
  if (rel > maxRelativeDelta) return null;

  final periodA = 60000.0 / bpmA;
  final periodB = 60000.0 / bpmBEff;
  final phraseA = periodA * beatsPerPhrase;
  final phraseB = periodB * beatsPerPhrase;
  final offA = _mod(beatOffsetMsA.toDouble(), periodA);
  final offB = _mod(beatOffsetMsB.toDouble(), periodB);

  final phaseA = _mod(outgoingPositionMs - offA, phraseA);
  final msToNextPhraseA = phaseA < 1.0 ? 0.0 : (phraseA - phaseA);

  var seek = offB - msToNextPhraseA;
  seek = _mod(seek, phraseB);
  // At most one phrase into the incoming track (was 2 — felt late on cross-genre).
  if (seek > phraseB) {
    seek -= phraseB;
  }
  // Snap to nearest beat inside the phrase for tighter grids.
  final beatSnap = (seek / periodB).round() * periodB;
  if ((beatSnap - seek).abs() < periodB * 0.35) {
    seek = beatSnap;
  }
  if (seek < 0) seek = 0;
  if (seek >= phraseB) seek = 0;
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
  final maxDelta = (maxStretchPercent.clamp(3, 22)) / 100.0;
  bool within(double speed) => (speed - 1.0).abs() <= maxDelta + 1e-9;

  // Prefer direct match, then half/double (common cross-genre / wrong-octave BPM).
  DjTempoStretchPlan? best;
  void consider(double candidateBpmB, String mode) {
    if (candidateBpmB < 40 || candidateBpmB > 240) return;
    final matchIn = bpmA / candidateBpmB;
    if (!within(matchIn)) return;
    final plan = DjTempoStretchPlan(
      speedOutgoing: 1.0,
      speedIncoming: matchIn,
      effectiveBpm: bpmA,
      mode: mode,
    );
    if (best == null ||
        (matchIn - 1.0).abs() < (best!.speedIncoming - 1.0).abs()) {
      best = plan;
    }
  }

  consider(bpmB, 'match_incoming');
  consider(bpmB / 2.0, 'match_incoming_half');
  consider(bpmB * 2.0, 'match_incoming_double');
  return best;
}
