import 'package:flutter/foundation.dart';

import '../models/dj_analysis.dart';
import '../models/song.dart';
import 'database_helper.dart';

/// Loads and (later) computes BPM / key for library tracks.
///
/// Step 1 is intentionally a **no-op analyzer**: it only reads/writes the
/// cache table. Playback and crossfade never call into heavy work here until
/// DJ Mode is enabled *and* later steps implement real analysis.
class DjAnalysisService {
  DjAnalysisService({DatabaseHelper? database}) : _db = database ?? DatabaseHelper();

  final DatabaseHelper _db;
  final Map<String, DjAnalysis> _memory = {};

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

  /// Step 1 stub — does not decode audio. Returns existing cache or a
  /// zero-confidence placeholder so callers can branch safely.
  Future<DjAnalysis> analyzeSong(Song song, {bool force = false}) async {
    if (!force) {
      final existing = await getAnalysis(song.id);
      if (existing != null) return existing;
    }
    // Real BPM/key detection arrives in Steps 2–4. Until then: no work, no block.
    return DjAnalysis(songId: song.id, bpmConfidence: 0.0);
  }

  void forget(String songId) => _memory.remove(songId);

  void clearMemory() => _memory.clear();
}
