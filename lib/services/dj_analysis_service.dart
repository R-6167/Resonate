import 'package:flutter/foundation.dart';

import '../models/dj_analysis.dart';
import '../models/song.dart';
import 'database_helper.dart';
import 'dj_bpm_estimator.dart';

/// Loads and computes BPM hints for library tracks (DJ Mode).
///
/// Analysis is cached in SQLite and never blocks the play() hot path for long:
/// callers should treat missing analysis as "skip beat align".
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

  /// Ensure we have a cached row. Safe to call from preload (async).
  Future<DjAnalysis> analyzeSong(Song song, {bool force = false}) async {
    if (!force) {
      final existing = await getAnalysis(song.id);
      if (existing != null && (existing.hasUsableBpm || existing.bpmConfidence > 0)) {
        return existing;
      }
      if (existing != null && existing.analyzedAt != null && existing.bpm == null) {
        // Fall through to try metadata once.
      } else if (existing != null && existing.bpm != null) {
        return existing;
      }
    }

    if (_inFlight.contains(song.id)) {
      final existing = await getAnalysis(song.id);
      return existing ?? DjAnalysis(songId: song.id, bpmConfidence: 0.0);
    }
    _inFlight.add(song.id);
    try {
      final estimate = await _estimator.estimateFile(song.filePath);
      final analysis = estimate == null
          ? DjAnalysis(
              songId: song.id,
              bpmConfidence: 0.0,
              analyzedAt: DateTime.now(),
            )
          : DjAnalysis(
              songId: song.id,
              bpm: estimate.bpm,
              bpmConfidence: estimate.confidence,
              beatOffsetMs: estimate.beatOffsetMs,
              analyzedAt: DateTime.now(),
            );
      await saveAnalysis(analysis);
      return analysis;
    } catch (e) {
      debugPrint('DjAnalysisService.analyzeSong: $e');
      return DjAnalysis(songId: song.id, bpmConfidence: 0.0, analyzedAt: DateTime.now());
    } finally {
      _inFlight.remove(song.id);
    }
  }

  /// Fire-and-forget analysis for preload / idle.
  void scheduleAnalyze(Song song) {
    if (_inFlight.contains(song.id) || _memory[song.id]?.hasUsableBpm == true) {
      return;
    }
    // ignore: unawaited_futures
    analyzeSong(song);
  }

  void forget(String songId) => _memory.remove(songId);

  void clearMemory() => _memory.clear();
}
