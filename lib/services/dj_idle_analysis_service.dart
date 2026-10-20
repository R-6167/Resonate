import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/song.dart';
import 'database_helper.dart';
import 'dj_analysis_service.dart';
import 'resonate_diagnostics.dart';

/// Background BPM/key tag scan when DJ Mode "Analyze library when idle" is on.
///
/// Idle analysis deliberately awaits each song to completion. A Future.timeout
/// does not cancel the native decode/analyzer underneath it; timing out and
/// advancing the loop can leave orphaned work running alongside later songs.
/// Playback/stop requests therefore take effect between songs, not by
/// abandoning a still-running analysis operation.
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

          // Do not wrap this in Future.timeout: Dart timeout only stops waiting,
          // not the native decode. Keep the scan serial until the analyzer
          // really completes so the next song cannot overlap orphaned work.
          final after = await _analysis.analyzeSong(
            song,
            force: needsFullProfile,
          );

          // Cancellation is not a completed analysis attempt. The analyzer may
          // return an empty placeholder when its generation is invalidated;
          // do not mislabel that as missing tags or suppress a later retry.
          if (_stopRequested) {
            await ResonateDiagnostics.recordDj(
              stage: 'idle_scan_song',
              songId: song.id,
              outcome: 'cancelled',
              extra: {'stopRequestedDuringAnalysis': true},
            );
          } else {
            _lastProfileAttemptAt[song.id] = DateTime.now();
            final gained =
                (after.hasUsableBpm && !(before?.hasUsableBpm ?? false)) ||
                (after.hasUsableKey && !(before?.hasUsableKey ?? false));
            if (gained) _updated++;
            await ResonateDiagnostics.recordDj(
              stage: 'idle_scan_song',
              songId: song.id,
              outcome: gained ? 'updated' : 'no_tags',
              extra: {
                'bpm': after.bpm,
                'hasKey': after.hasUsableKey,
                'stopRequestedDuringAnalysis': false,
              },
            );
          }
        } catch (e) {
          if (_stopRequested) {
            // A stop racing with a thrown platform error is still a
            // cancellation, not a failed analysis and not a retry cooldown.
            await ResonateDiagnostics.recordDj(
              stage: 'idle_scan_song',
              songId: song.id,
              outcome: 'cancelled',
              extra: {'stopRequestedDuringAnalysis': true},
            );
          } else {
            _failed++;
            _lastProfileAttemptAt[song.id] = DateTime.now();
            await ResonateDiagnostics.recordDj(
              stage: 'idle_scan_error',
              songId: song.id,
              outcome: 'failed',
              reason: e.toString(),
            );
          }
        }
        // Yield to the UI and re-check stop state before the next song.
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

  /// Stops after the currently awaited song analysis completes.
  ///
  /// Native decoding does not currently expose cancellation, so this method
  /// must not pretend it can interrupt an in-flight platform operation.
  void stop() {
    _stopRequested = true;
    _analysis.cancelCurrentAnalysis();
  }
}
