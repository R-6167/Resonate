import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/song.dart';
import 'database_helper.dart';
import 'dj_analysis_service.dart';
import 'resonate_diagnostics.dart';

/// Background BPM/key tag scan when DJ Mode "Analyze library when idle" is on.
///
/// Hardened: one loop, yields between songs, skips usable cache, records fails.
/// The analysis pipeline may decode several windows on slower devices, so its
/// timeout is deliberately longer than a single short audio decode.
class DjIdleAnalysisService {
  DjIdleAnalysisService({
    DatabaseHelper? database,
    DjAnalysisService? analysis,
  })  : _db = database ?? DatabaseHelper(),
        _analysis = analysis ?? DjAnalysisService();

  final DatabaseHelper _db;
  final DjAnalysisService _analysis;

  bool _running = false;
  bool _stopRequested = false;
  int _scanned = 0;
  int _updated = 0;
  int _failed = 0;
  final Map<String, DateTime> _lastProfileAttemptAt = <String, DateTime>{};
  static const Duration _retryCooldown = Duration(hours: 6);

  bool get isRunning => _running;
  int get scanned => _scanned;
  int get updated => _updated;
  int get failed => _failed;

  Future<void> startIfNeeded({int maxSongs = 40}) async {
    if (_running) return;
    _running = true;
    _stopRequested = false;
    _scanned = 0;
    _updated = 0;
    _failed = 0;
    try {
      await ResonateDiagnostics.recordDj(
        stage: 'idle_scan_start',
        outcome: 'started',
        extra: {'maxSongs': maxSongs},
      );
      final songs = await _db.getAllSongs();
      for (final song in songs) {
        if (_stopRequested) break;
        if (_scanned >= maxSongs) break;
        if (song.filePath.trim().isEmpty) continue;
        try {
          final existing = await _analysis.getAnalysis(song.id);
          final hasUsableTags = existing != null &&
              (existing.hasUsableBpm || existing.hasUsableKey);
          final hasSectionProfile = existing?.sectionHint != null &&
              existing?.sectionHint != 'unknown';
          if (existing != null &&
              !existing.isStale &&
              hasUsableTags &&
              hasSectionProfile) {
            continue;
          }

          final now = DateTime.now();
          final lastAttempt = _lastProfileAttemptAt[song.id];
          if (lastAttempt != null &&
              now.difference(lastAttempt) < _retryCooldown) {
            continue;
          }
          // Persisted empty results also need a cooldown across app launches;
          // otherwise every unlock/route event would repeat expensive work.
          if (existing != null &&
              !existing.isStale &&
              !hasUsableTags &&
              existing.analyzedAt != null &&
              now.difference(existing.analyzedAt!) < _retryCooldown) {
            continue;
          }

          _scanned++;
          final before = existing;
          final needsFullProfile = before == null ||
              before.isStale ||
              !hasUsableTags ||
              !hasSectionProfile;
          final after = await _analysis
              .analyzeSong(song, force: needsFullProfile)
              .timeout(const Duration(seconds: 30), onTimeout: () {
            throw TimeoutException('dj idle analyze timeout');
          });
          _lastProfileAttemptAt[song.id] = DateTime.now();
          final gained = (after.hasUsableBpm && !(before?.hasUsableBpm ?? false)) ||
              (after.hasUsableKey && !(before?.hasUsableKey ?? false));
          if (gained) _updated++;
          await ResonateDiagnostics.recordDj(
            stage: 'idle_scan_song',
            songId: song.id,
            outcome: gained ? 'updated' : 'no_tags',
            extra: {
              'bpm': after.bpm,
              'hasKey': after.hasUsableKey,
            },
          );
        } catch (e) {
          _failed++;
          await ResonateDiagnostics.recordDj(
            stage: 'idle_scan_error',
            songId: song.id,
            outcome: 'failed',
            reason: e.toString(),
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      await ResonateDiagnostics.recordDj(
        stage: 'idle_scan_done',
        outcome: _stopRequested ? 'stopped' : 'completed',
        extra: {
          'scanned': _scanned,
          'updated': _updated,
          'failed': _failed,
        },
      );
    } catch (e) {
      await ResonateDiagnostics.recordDj(
        stage: 'idle_scan_error',
        outcome: 'failed',
        reason: e.toString(),
      );
    } finally {
      _running = false;
    }
  }

  void stop() {
    _stopRequested = true;
  }
}
