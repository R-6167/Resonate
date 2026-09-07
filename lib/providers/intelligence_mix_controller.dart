import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/intelligence_mix.dart';
import '../models/song.dart';
import '../services/database_helper.dart';
import '../services/intelligence_mix_memory.dart';
import '../services/intelligence_mix_service.dart';
import '../services/intelligence_mix_settings_store.dart';
import 'intelligence_provider.dart';
import 'music_provider.dart';

/// Coordinates generated mixes and long-form listening analysis for the UI.
/// Playback remains owned by MusicProvider; this controller only asks
/// Intelligence for a plan and exposes the result to views.
class IntelligenceMixController extends ChangeNotifier {
  final MusicProvider music;
  final IntelligenceProvider intelligence;
  final IntelligenceMixService _service;
  final IntelligenceMixMemory _memory = IntelligenceMixMemory();
  final DatabaseHelper _database = DatabaseHelper();
  IntelligenceMix? _currentMix;
  IntelligenceMixAnalysis? _currentAnalysis;
  Map<String, dynamic>? _currentContinuity;
  bool _loading = false;
  String? _analyzingSongId;
  String? _lastObservedSongId;

  IntelligenceMixController({required this.music, required this.intelligence, IntelligenceMixService? service}) : _service = service ?? IntelligenceMixService() {
    music.addListener(_observeMixPlayback);
    unawaited(_restoreLatestMix());
  }

  IntelligenceMix? get currentMix => _currentMix;
  IntelligenceMixAnalysis? get currentAnalysis => _currentAnalysis;
  Map<String, dynamic>? get currentContinuity => _currentContinuity;
  bool get isLoading => _loading;
  String? get analyzingSongId => _analyzingSongId;

  Future<IntelligenceMix?> generateMix({Duration? targetDuration, String? title}) async {
    if (!intelligence.isEnabled || intelligence.recommendations.isEmpty) return null;
    _loading = true;
    notifyListeners();
    try {
      final minutes = targetDuration?.inMinutes ?? await IntelligenceMixSettingsStore.targetMinutes();
      final mix = await _service.generateMix(
        recommendations: intelligence.recommendations,
        currentSong: music.currentSong,
        sessionMode: intelligence.sessionMode,
        sessionSkipStreak: intelligence.sessionSkipStreak,
        sessionCompletionStreak: intelligence.sessionCompletionStreak,
        sessionArtistCounts: intelligence.sessionArtistCounts,
        targetDuration: Duration(minutes: minutes.clamp(15, 120)),
        title: title ?? _defaultTitle(),
      );
      _currentMix = mix;
      _currentContinuity = null;
      return mix;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<IntelligenceMix?> evolveCurrentMix() async {
    final previous = _currentMix;
    if (previous == null || !intelligence.isEnabled || intelligence.recommendations.isEmpty) return null;
    if (!await IntelligenceMixSettingsStore.autoEvolutionEnabled()) return null;
    _loading = true;
    notifyListeners();
    try {
      final mix = await _service.evolveMix(
        previousMix: previous,
        recommendations: intelligence.recommendations,
        currentSong: music.currentSong,
        sessionMode: intelligence.sessionMode,
        sessionSkipStreak: intelligence.sessionSkipStreak,
        sessionCompletionStreak: intelligence.sessionCompletionStreak,
        sessionArtistCounts: intelligence.sessionArtistCounts,
      );
      _currentMix = mix;
      _currentContinuity = await _service.evaluateMix(previous);
      return mix;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<IntelligenceMixAnalysis?> analyzeLongMix(Song song, {int? minimumDurationMinutes}) async {
    if (!await IntelligenceMixSettingsStore.longFormEnabled()) return null;
    _analyzingSongId = song.id;
    notifyListeners();
    try {
      final minimum = minimumDurationMinutes ?? await IntelligenceMixSettingsStore.minimumLongFormMinutes();
      final analysis = await _service.analyzeLongMix(song, minimumDurationMinutes: minimum);
      _currentAnalysis = analysis;
      return analysis;
    } finally {
      _analyzingSongId = null;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>?> evaluateCurrentMix() async {
    final mix = _currentMix;
    if (mix == null) return null;
    final assessment = await _service.evaluateMix(mix);
    if (assessment != null) { _currentContinuity = assessment; notifyListeners(); }
    return assessment;
  }

  Future<List<Map<String, dynamic>>> recentMixContinuity() => _service.recentMixContinuity();
  Future<List<Map<String, dynamic>>> recentGeneratedMixes() => _service.recentGeneratedMixes();

  void clearMix() { _currentMix = null; _currentContinuity = null; notifyListeners(); }

  Future<void> _restoreLatestMix() async {
    try {
      final entries = await _memory.recent();
      if (entries.isEmpty) return;
      final latest = entries.first;
      final rawSongIds = latest['songIds'] as List?;
      final songIds = rawSongIds?.whereType<String>().toList(growable: false);
      if (songIds == null || songIds.isEmpty) return;
      final allSongs = await _database.getAllSongs();
      final byId = <String, Song>{for (final song in allSongs) song.id: song};
      final songs = <Song>[];
      final restoredIds = <String>{};
      for (final id in songIds) { if (!restoredIds.add(id)) continue; final song = byId[id]; if (song != null) songs.add(song); }
      if (songs.isEmpty) return;
      final id = latest['id'] as String?;
      final title = latest['title'] as String?;
      final description = latest['description'] as String?;
      final reason = latest['reason'] as String?;
      final createdAt = DateTime.tryParse(latest['createdAt'] as String? ?? '');
      final targetMinutes = (latest['targetMinutes'] as num?)?.toInt();
      if (id == null || title == null || description == null || reason == null || createdAt == null || targetMinutes == null) return;
      _currentMix = IntelligenceMix(id: id, title: title, description: description, songs: List.unmodifiable(songs), targetDuration: Duration(minutes: targetMinutes), createdAt: createdAt, reason: reason, parentMixId: latest['parentMixId'] as String?, edition: (latest['edition'] as num?)?.toInt() ?? 1, previousContinuityScore: (latest['previousContinuityScore'] as num?)?.toDouble());
      notifyListeners();
    } catch (_) {}
  }

  void _observeMixPlayback() {
    final mix = _currentMix;
    final songId = music.currentSong?.id;
    if (mix == null || songId == null || songId == _lastObservedSongId) return;
    _lastObservedSongId = songId;
    if (mix.songs.any((song) => song.id == songId)) evaluateCurrentMix();
  }

  @override void dispose() { music.removeListener(_observeMixPlayback); super.dispose(); }

  String _defaultTitle() {
    if (intelligence.sessionSkipStreak >= 2) return 'A Fresh Turn';
    if (intelligence.sessionCompletionStreak >= 2) return 'Keep The Flow';
    switch (intelligence.sessionMode) { case 'Exploring': return 'Open The Search'; case 'Familiar flow': return 'Your Familiar Flow'; default: return 'Your Resonate Mix'; }
  }
}
