import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/dj_analysis.dart';
import '../models/song.dart';
import 'database_helper.dart';
import 'dj_bpm_estimator.dart';
import '../dj_engine/analysis/dj_pcm_profile_analyzer.dart';
import '../dj_engine/analysis/dj_profile_serializer.dart';
import '../dj_engine/core/dj_types.dart';

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
  final DjPcmProfileAnalyzer _profileAnalyzer = const DjPcmProfileAnalyzer();
  final DjProfileSerializer _profileSerializer = const DjProfileSerializer();
  final Map<String, DjTrackProfile> _profileMemory = {};
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

  Future<DjTrackProfile?> getProfile(String songId) async {
    final cached = _profileMemory[songId];
    if (cached != null) return cached;
    try {
      final raw = await _db.getDjProfileJson(songId);
      if (raw == null || raw.isEmpty) return null;
      final profile = _profileSerializer.decode(raw);
      _profileMemory[songId] = profile;
      return profile;
    } catch (e) {
      debugPrint('DjAnalysisService.getProfile: $e');
      return null;
    }
  }

  Future<void> saveProfile(DjTrackProfile profile) async {
    try {
      _profileMemory[profile.songId] = profile;
      await _db.upsertDjProfileJson(
        songId: profile.songId,
        fingerprint: profile.fingerprint,
        durationMs: profile.durationMs,
        analyzedAt: DateTime.now(),
        analysisVersion: profile.analysisVersion,
        profileJson: _profileSerializer.encode(profile),
      );
    } catch (e) {
      debugPrint('DjAnalysisService.saveProfile: $e');
    }
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
      final legacyEstimate = await _estimator.estimateFile(
        song.filePath,
        durationMs: song.duration.inMilliseconds,
      );
      final estimate = await _estimateWithV2Profile(song, legacyEstimate);
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
              energy: estimate.energy,
              loudness: estimate.loudness,
              introHintMs: estimate.introHintMs,
              outroHintMs: estimate.outroHintMs,
              sectionHint: estimate.sectionHint,
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

  Future<DjBpmEstimate?> _estimateWithV2Profile(
    Song song,
    DjBpmEstimate? legacy,
  ) async {
    final durationMs = song.duration.inMilliseconds;
    if (durationMs <= 0) return legacy;

    final windows = <DjDecodedPcmWindow>[];
    Future<void> addWindow(int startMs, String role, double seconds) async {
      final decoded = await _estimator.extractDecodedPcmWindow(
        song.filePath,
        maxSeconds: seconds,
        startMs: startMs,
      );
      if (decoded == null) return;
      windows.add(
        DjDecodedPcmWindow(
          pcm: decoded.pcm,
          sampleRate: decoded.sampleRate,
          channels: decoded.channels,
          startMs: startMs,
          role: role,
        ),
      );
    }

    await addWindow(0, 'start', 15.0);
    if (durationMs > 60000) {
      await addWindow(durationMs ~/ 2, 'mid', 15.0);
    }
    if (durationMs > 45000) {
      await addWindow(
        (durationMs - 15000).clamp(0, durationMs - 1000),
        'end',
        15.0,
      );
    }

    if (windows.isEmpty) return legacy;

    final profile = _profileAnalyzer.analyze(
      songId: song.id,
      durationMs: durationMs,
      windows: windows,
      analysisVersion: DjAnalysis.currentVersion,
    );
    await saveProfile(profile);

    final bpm = profile.beatGrid.bpm ?? legacy?.bpm ?? 0;
    final bpmConfidence = profile.hasTempo
        ? profile.beatGrid!.confidence
        : legacy?.confidence ?? 0;
    final keyRoot = profile.hasKey ? profile.keyRoot : legacy?.keyRoot;
    final keyMode = profile.hasKey ? profile.keyMode : legacy?.keyMode;
    final keyConfidence = profile.hasKey
        ? profile.keyConfidence
        : legacy?.keyConfidence ?? 0;
    final beatOffset = profile.beatGrid.firstBeatMs ?? legacy?.beatOffsetMs ?? 0;

    return DjBpmEstimate(
      bpm: bpm,
      confidence: bpmConfidence,
      beatOffsetMs: beatOffset,
      source: profile.hasTempo ? 'pcm_profile_v2' : legacy?.source ?? 'none',
      keyRoot: keyRoot,
      keyMode: keyMode,
      keyConfidence: keyConfidence,
      energy: profile.energyCurve.isNotEmpty
          ? profile.energyCurve.first.value
          : legacy?.energy,
      loudness: profile.energyCurve.isNotEmpty
          ? profile.energyCurve.first.loudness
          : legacy?.loudness,
      introHintMs: profile.transitions.bestIntroMs ?? legacy?.introHintMs,
      outroHintMs: profile.transitions.bestOutroMs != null
          ? durationMs - profile.transitions.bestOutroMs!
          : legacy?.outroHintMs,
      sectionHint: profile.sections.isNotEmpty
          ? profile.sections.first.type.name
          : legacy?.sectionHint,
    );
  }

  /// Fire-and-forget analysis for preload / idle.

  /// Prefer cache; only recompute when missing/stale. Safe for handoff path.
  Future<DjAnalysis> analyzeSongCachedFirst(Song song) async {
    final existing = await getAnalysis(song.id);
    if (existing != null &&
        !existing.isStale &&
        (existing.hasUsableBpm ||
            existing.hasUsableKey ||
            existing.hasUsableEnergy)) {
      return existing;
    }
    return analyzeSong(song);
  }
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

  void forget(String songId) {
    _memory.remove(songId);
    _profileMemory.remove(songId);
  }

  void clearMemory() {
    _memory.clear();
    _profileMemory.clear();
  }
}
