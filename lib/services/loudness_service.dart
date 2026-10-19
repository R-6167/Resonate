import 'dart:math' as math;
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';
import 'dj_bpm_estimator.dart';

/// Local, codec-independent loudness scan based on decoded PCM16 samples.
///
/// This intentionally reports sampled RMS dBFS, not LUFS/true peak. A
/// BS.1770 K-weighted and gated integrated-loudness implementation is a
/// separate enhancement; this service must not label an RMS estimate as LUFS.
class LoudnessService {
  LoudnessService({DjBpmEstimator? estimator})
      : _estimator = estimator ?? DjBpmEstimator();

  final DjBpmEstimator _estimator;

  static const int analysisVersion = 1;
  static const String _cachePrefix = 'loudness_scan_v1_';
  static const double defaultTargetRmsDbfs = -18.0;
  static const double maxGainDb = 6.0;
  static const double maxCutDb = -12.0;

  /// Scans short windows spread across a track to keep idle work bounded.
  /// Returns null when the source cannot be decoded or has invalid PCM.
  Future<LoudnessScanResult?> scanSong(
    Song song, {
    double targetRmsDbfs = defaultTargetRmsDbfs,
    bool force = false,
    bool Function()? isCancelled,
  }) async {
    if (song.filePath.trim().isEmpty ||
        !targetRmsDbfs.isFinite ||
        targetRmsDbfs < -36.0 ||
        targetRmsDbfs > -6.0) {
      return null;
    }

    final cached = force ? null : await getCached(song);
    if (cached != null && cached.targetRmsDbfs == targetRmsDbfs) {
      return cached;
    }

    final durationMs = song.duration.inMilliseconds;
    if (durationMs <= 0) return null;
    const windowMs = 12000;
    final positions = <int>{0};
    if (durationMs > windowMs) {
      for (final fraction in const <double>[0.2, 0.4, 0.6, 0.8]) {
        positions.add((durationMs * fraction).round()
            .clamp(0, durationMs - 1000).toInt());
      }
      positions.add((durationMs - windowMs).clamp(0, durationMs - 1000));
    }

    var squaredSum = 0.0;
    var sampleCount = 0;
    var peak = 0.0;
    for (final startMs in (positions.toList()..sort())) {
      if (isCancelled?.call() ?? false) return null;
      final decoded = await _estimator.extractDecodedPcmWindow(
        song.filePath,
        maxSeconds: windowMs / 1000,
        startMs: startMs,
      );
      if (isCancelled?.call() ?? false) return null;
      if (decoded == null || decoded.pcm.length < 2) continue;
      final stats = _measurePcm16(decoded.pcm);
      if (stats.samples == 0) continue;
      squaredSum += stats.meanSquare * stats.samples;
      sampleCount += stats.samples;
      peak = math.max(peak, stats.peak);
    }
    if (sampleCount == 0 || !squaredSum.isFinite) return null;

    final rms = math.sqrt(squaredSum / sampleCount).clamp(0.0, 1.0);
    if (rms <= 0 || !rms.isFinite) return null;
    final rmsDbfs = 20.0 * math.log(rms) / math.ln10;
    final peakDbfs = peak <= 0 ? -120.0 : 20.0 * math.log(peak) / math.ln10;

    // Conservative gain calculation: target the sampled RMS, then limit the
    // requested gain so normalization cannot aggressively amplify quiet files.
    final requested = targetRmsDbfs - rmsDbfs;
    final gainDb = requested.clamp(maxCutDb, maxGainDb).toDouble();
    final result = LoudnessScanResult(
      songId: song.id,
      targetRmsDbfs: targetRmsDbfs,
      measuredRmsDbfs: rmsDbfs,
      sampledPeakDbfs: peakDbfs,
      gainDb: gainDb,
      sampleCount: sampleCount,
      analyzedAt: DateTime.now(),
      analysisVersion: analysisVersion,
    );
    await _save(result);
    return result;
  }

  Future<LoudnessScanResult?> getCached(Song song) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_cachePrefix${song.id}');
      if (raw == null) return null;
      final fields = raw.split('|');
      if (fields.length != 7) return null;
      final version = int.tryParse(fields[0]);
      final target = double.tryParse(fields[1]);
      final measured = double.tryParse(fields[2]);
      final peak = double.tryParse(fields[3]);
      final gain = double.tryParse(fields[4]);
      final count = int.tryParse(fields[5]);
      final at = DateTime.tryParse(fields[6]);
      if (version != analysisVersion ||
          target == null || measured == null || peak == null ||
          gain == null || count == null || at == null ||
          !target.isFinite || !measured.isFinite || !peak.isFinite ||
          !gain.isFinite || count <= 0) {
        return null;
      }
      return LoudnessScanResult(
        songId: song.id,
        targetRmsDbfs: target,
        measuredRmsDbfs: measured,
        sampledPeakDbfs: peak,
        gainDb: gain,
        sampleCount: count,
        analyzedAt: at,
        analysisVersion: version!,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _save(LoudnessScanResult result) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_cachePrefix${result.songId}',
        [
          result.analysisVersion,
          result.targetRmsDbfs,
          result.measuredRmsDbfs,
          result.sampledPeakDbfs,
          result.gainDb,
          result.sampleCount,
          result.analyzedAt.toIso8601String(),
        ].join('|'),
      );
    } catch (_) {
      // A cache write failure must never interrupt playback or analysis.
    }
  }

  static ({double meanSquare, double peak, int samples}) _measurePcm16(
    Uint8List pcm,
  ) {
    final byteData = ByteData.sublistView(pcm);
    final sampleCount = pcm.length ~/ 2;
    if (sampleCount == 0) {
      return (meanSquare: 0.0, peak: 0.0, samples: 0);
    }
    var sumSquares = 0.0;
    var peak = 0.0;
    for (var i = 0; i < sampleCount; i++) {
      final sample = byteData.getInt16(i * 2, Endian.little) / 32768.0;
      final magnitude = sample.abs();
      sumSquares += sample * sample;
      if (magnitude > peak) peak = magnitude;
    }
    return (
      meanSquare: sumSquares / sampleCount,
      peak: peak,
      samples: sampleCount,
    );
  }
}

class LoudnessScanResult {
  const LoudnessScanResult({
    required this.songId,
    required this.targetRmsDbfs,
    required this.measuredRmsDbfs,
    required this.sampledPeakDbfs,
    required this.gainDb,
    required this.sampleCount,
    required this.analyzedAt,
    required this.analysisVersion,
  });

  final String songId;
  final double targetRmsDbfs;
  final double measuredRmsDbfs;
  final double sampledPeakDbfs;
  final double gainDb;
  final int sampleCount;
  final DateTime analyzedAt;
  final int analysisVersion;

  /// Linear multiplier for a future playback-gain stage; not applied directly
  /// by this scanner, so it cannot interfere with crossfade/volume ownership.
  double get linearGain => math.pow(10.0, gainDb / 20.0).toDouble();
}
