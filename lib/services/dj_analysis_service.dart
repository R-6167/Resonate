import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/dj_analysis.dart';
import '../models/song.dart';
import 'database_helper.dart';
import 'dj_bpm_estimator.dart';

/// Loads and computes BPM / key hints for library tracks (DJ Mode).
///
/// Analysis is cached permanently in SQLite with [DjAnalysis.analysisVersion].
/// Playback never blocks on analysis; missing or stale rows degrade gracefully.
class DjAnalysisService {
  DjAnalysisService({DatabaseHelper? database, DjBpmEstimator? estimator})
      : _db = database ?? DatabaseHelper(),
        _estimator = estimator ?? DjBpmEstimator();

  final DatabaseHelper _db;
  final DjBpmEstimator _estimator;
  final Map<String, DjAnalysis> _memory = {};
  final Set<String> _inFlight = {};

  Future<DjAnalysis?> getAnalysis(String songId) async {
    final cached = _memory[songId];
    if (cached != null) return cached;
    try {
      final row = await _db.getDjAnalysis(songId);
      if (row != null) {
        _memory[songId] = row;
        return row;
      }
    } catch (e) {
      debugPrint('DjAnalysisService.getAnalysis: $e');
    }
    return null;
  }

  Future<void> saveAnalysis(DjAnalysis analysis) async {
    try {
      await _db.upsertDjAnalysis(analysis);
      _memory[analysis.songId] = analysis;
    } catch (e) {
      debugPrint('DjAnalysisService.saveAnalysis: $e');
    }
  }

  /// Whether cached analysis is still valid for this song file.
  bool _identityMatches(DjAnalysis existing, Song song, int? sizeBytes) {
    if (existing.durationMs != null &&
        song.duration.inMilliseconds > 0 &&
        (existing.durationMs! - song.duration.inMilliseconds).abs() > 1500) {
      return false;
    }
    if (sizeBytes != null &&
        existing.fileSizeBytes != null &&
        existing.fileSizeBytes != sizeBytes) {
      return false;
    }
    return true;
  }

  Future<int?> _fileSize(String path) async {
    try {
      if (path.startsWith('content://') || path.startsWith('file://')) {
        return null; // size optional for content URIs
      }
      final f = File(path);
      if (await f.exists()) return await f.length();
    } catch (_) {}
    return null;
  }

  /// Ensure we have a cached row. Safe to call from preload / idle (async).
  ///
  /// Re-analyzes when [force] is true, version is stale, or file identity changed.
  Future<DjAnalysis> analyzeSong(Song song, {bool force = false}) async {
    if (!force) {
      final existing = await getAnalysis(song.id);
      if (existing != null) {
        final size = await _fileSize(song.filePath);
        final identityOk = _identityMatches(existing, song, size);
        final usable = existing.hasUsableBpm ||
            existing.hasUsableKey ||
            existing.bpmConfidence > 0;
        if (!existing.isStale && identityOk && usable) {
          return existing;
        }
        // Stale version or identity mismatch → fall through to re-analyze.
        // Empty prior attempt with current version: skip re-work unless forced.
        if (!existing.isStale &&
            identityOk &&
            existing.analyzedAt != null &&
            !usable) {
          return existing;
        }
      }
    }

    if (_inFlight.contains(song.id)) {
      final existing = await getAnalysis(song.id);
      return existing ??
          DjAnalysis(
            songId: song.id,
            bpmConfidence: 0.0,
            analysisVersion: DjAnalysis.currentVersion,
          );
    }
    _inFlight.add(song.id);
    try {
      final size = await _fileSize(song.filePath);
      final estimate = await _estimator.estimateFile(song.filePath);
      final analysis = estimate == null
          ? DjAnalysis(
              songId: song.id,
              bpmConfidence: 0.0,
              analyzedAt: DateTime.now(),
              analysisVersion: DjAnalysis.currentVersion,
              bpmSource: 'none',
              fileSizeBytes: size,
              durationMs: song.duration.inMilliseconds > 0
                  ? song.duration.inMilliseconds
                  : null,
            )
          : DjAnalysis(
              songId: song.id,
              bpm: (estimate.bpm > 40 && estimate.bpm < 240)
                  ? estimate.bpm
                  : null,
              bpmConfidence: estimate.confidence,
              beatOffsetMs: estimate.beatOffsetMs,
              keyRoot: estimate.keyRoot,
              keyMode: estimate.keyMode,
              analyzedAt: DateTime.now(),
              analysisVersion: DjAnalysis.currentVersion,
              bpmSource: estimate.source,
              fileSizeBytes: size,
              durationMs: song.duration.inMilliseconds > 0
                  ? song.duration.inMilliseconds
                  : null,
            );
      await saveAnalysis(analysis);
      return analysis;
    } catch (e) {
      debugPrint('DjAnalysisService.analyzeSong: $e');
      return DjAnalysis(
        songId: song.id,
        bpmConfidence: 0.0,
        analyzedAt: DateTime.now(),
        analysisVersion: DjAnalysis.currentVersion,
        bpmSource: 'error',
      );
    } finally {
      _inFlight.remove(song.id);
    }
  }

  /// Fire-and-forget analysis for preload / idle.
  void scheduleAnalyze(Song song) {
    final cached = _memory[song.id];
    if (_inFlight.contains(song.id)) return;
    if (cached != null &&
        !cached.isStale &&
        (cached.hasUsableBpm || cached.hasUsableKey)) {
      return;
    }
    // ignore: unawaited_futures
    analyzeSong(song);
  }

  void forget(String songId) => _memory.remove(songId);

  void clearMemory() => _memory.clear();
}
