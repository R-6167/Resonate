import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/intelligence_recommendation.dart';
import '../models/listening_event.dart';
import '../models/song.dart';
import '../services/database_helper.dart';
import 'music_provider.dart';

/// Lightweight, on-device listening memory and recommendation engine.
///
/// Intelligence is deliberately best-effort: database failures never affect
/// playback. Recommendations are scored from local listening behaviour and
/// every visible recommendation has a human-readable reason.
class IntelligenceProvider extends ChangeNotifier {
  final MusicProvider music;
  final DatabaseHelper _database = DatabaseHelper();

  bool _enabled = true;
  ListeningEvent? _activeEvent;
  String? _observedSongId;
  bool _lastPlaying = false;
  String? _lastRecommendationId;
  List<IntelligenceRecommendation> _recommendations = const [];

  IntelligenceProvider({required this.music}) {
    music.addListener(_observePlayback);
    _loadEnabled();
    _observePlayback();
    unawaited(refreshRecommendations());
  }

  bool get isEnabled => _enabled;
  List<IntelligenceRecommendation> get recommendations => List.unmodifiable(_recommendations);
  bool get hasLearningData => _activeEvent != null || _recommendations.isNotEmpty;

  Future<void> _loadEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool('intelligence_enabled') ?? true;
      if (_enabled) await refreshRecommendations(notify: false);
      notifyListeners();
    } catch (e) {
      debugPrint('Intelligence settings load failed: $e');
    }
  }

  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('intelligence_enabled', enabled);
    } catch (e) {
      debugPrint('Intelligence settings save failed: $e');
    }
    if (!enabled) {
      await _finishActiveEvent();
      _recommendations = const [];
    } else {
      await refreshRecommendations(notify: false);
    }
    notifyListeners();
  }

  void _observePlayback() {
    if (!_enabled) return;
    final song = music.currentSong;
    final songId = song?.id;
    final playing = music.isPlaying;

    if (songId != _observedSongId) {
      unawaited(_finishActiveEvent());
      _observedSongId = songId;
      if (song != null && playing) unawaited(_startEvent(song));
      unawaited(refreshRecommendations());
    } else if (playing && !_lastPlaying && song != null) {
      unawaited(_startEvent(song));
    } else if (!playing && _lastPlaying) {
      unawaited(_finishActiveEvent());
    }
    _lastPlaying = playing;
  }

  Future<void> _startEvent(Song song) async {
    if (!_enabled || _activeEvent?.songId == song.id) return;
    await _finishActiveEvent();
    final event = ListeningEvent(
      id: '${DateTime.now().microsecondsSinceEpoch}_${song.id}',
      songId: song.id,
      previousSongId: _previousSongId(song.id),
      startedAt: DateTime.now(),
      durationPlayedMs: 0,
      songDurationMs: song.duration.inMilliseconds,
      completionRatio: 0.0,
      completed: false,
      skipped: false,
    );
    _activeEvent = event;
    try {
      await _database.insertListeningEvent(event);
    } catch (e) {
      debugPrint('Intelligence event insert failed: $e');
    }
  }

  String? _previousSongId(String currentId) {
    final queueIndex = music.queueIndex;
    if (queueIndex > 0 && queueIndex < music.queue.length) {
      return music.queue[queueIndex - 1].id;
    }
    return _lastRecommendationId == currentId ? null : _lastRecommendationId;
  }

  Future<void> _finishActiveEvent() async {
    final event = _activeEvent;
    if (event == null) return;
    final duration = music.currentSong?.id == event.songId
        ? music.currentPosition.inMilliseconds
        : event.durationPlayedMs;
    final songDuration = event.songDurationMs > 0
        ? event.songDurationMs
        : music.currentDuration?.inMilliseconds ?? 0;
    final ratio = songDuration <= 0 ? 0.0 : (duration / songDuration).clamp(0.0, 1.0).toDouble();
    final completed = ratio >= 0.90;
    final updated = event.copyWith(
      endedAt: DateTime.now(),
      durationPlayedMs: duration,
      songDurationMs: songDuration,
      completionRatio: ratio,
      completed: completed,
      skipped: !completed && duration > 0,
      skipPositionMs: !completed && duration > 0 ? duration : null,
    );
    _activeEvent = null;
    try {
      await _database.updateListeningEvent(updated);
    } catch (e) {
      debugPrint('Intelligence event update failed: $e');
    }
    _lastRecommendationId = event.songId;
  }

  Future<void> recordListeningEvent(ListeningEvent event) async {
    if (!_enabled) return;
    try {
      await _database.insertListeningEvent(event);
    } catch (e) {
      debugPrint('Intelligence event recording failed: $e');
    }
  }

  Future<Song?> getNextRecommendation() async {
    if (!_enabled || music.currentSong == null) return null;
    await refreshRecommendations(notify: false);
    return _recommendations.isEmpty ? null : _recommendations.first.song;
  }

  Future<void> refreshRecommendations({int limit = 8, bool notify = true}) async {
    if (!_enabled) {
      _recommendations = const [];
      if (notify) notifyListeners();
      return;
    }
    try {
      final songs = await _database.getAllSongs();
      final currentId = music.currentSong?.id;
      final events = await _database.getRecentListeningEvents(limit: 160);
      final transitionCounts = <String, int>{};
      if (currentId != null) {
        final rows = await _database.getTransitionCounts(currentId);
        for (final row in rows) {
          final id = row['next_song_id']?.toString();
          if (id != null) transitionCounts[id] = (row['transition_count'] as num?)?.toInt() ?? 0;
        }
      }

      final completedBySong = <String, int>{};
      final skippedBySong = <String, int>{};
      final playsBySong = <String, int>{};
      final artistAffinity = <String, double>{};
      for (final event in events) {
        playsBySong[event.songId] = (playsBySong[event.songId] ?? 0) + 1;
        if (event.completed) completedBySong[event.songId] = (completedBySong[event.songId] ?? 0) + 1;
        if (event.skipped) skippedBySong[event.songId] = (skippedBySong[event.songId] ?? 0) + 1;
      }

      final byId = {for (final song in songs) song.id: song};
      for (final event in events) {
        final artist = byId[event.songId]?.artist.trim();
        if (artist == null || artist.isEmpty) continue;
        final signal = event.completed ? 1.0 : event.skipped ? -0.8 : event.completionRatio * 0.5;
        artistAffinity[artist] = (artistAffinity[artist] ?? 0) + signal;
      }

      final ranked = <IntelligenceRecommendation>[];
      for (final song in songs) {
        if (song.id == currentId || song.filePath.trim().isEmpty) continue;
        final transitions = transitionCounts[song.id] ?? 0;
        final plays = playsBySong[song.id] ?? 0;
        final completions = completedBySong[song.id] ?? 0;
        final skips = skippedBySong[song.id] ?? 0;
        final completionRate = plays == 0 ? 0.0 : completions / plays;
        final artistScore = artistAffinity[song.artist.trim()] ?? 0.0;
        final score = transitions * 5.0 + completionRate * 4.0 + artistScore * 1.5 - skips * 2.0;

        String reason;
        if (transitions > 0) {
          reason = 'You often play this after ${music.currentSong?.title ?? 'your current track'}.';
        } else if (completions > 0 && completionRate >= 0.65) {
          reason = 'You tend to finish this one.';
        } else if (artistScore > 0) {
          reason = 'You have been enjoying more from ${song.artist}.';
        } else {
          reason = 'A fresh pick from your local library.';
        }
        ranked.add(IntelligenceRecommendation(song: song, score: score, reason: reason));
      }
      ranked.sort((a, b) => b.score.compareTo(a.score));
      _recommendations = ranked.take(limit).toList(growable: false);
      if (notify) notifyListeners();
    } catch (e) {
      debugPrint('Intelligence refresh failed: $e');
    }
  }

  Future<Map<String, dynamic>> analyzeCurrentSession() async {
    final events = await _database.getRecentListeningEvents(limit: 30);
    final completed = events.where((event) => event.completed).length;
    final skipped = events.where((event) => event.skipped).length;
    return {
      'events': events.length,
      'completed': completed,
      'skipped': skipped,
      'completionRate': events.isEmpty ? 0.0 : completed / events.length,
    };
  }

  @override
  void dispose() {
    music.removeListener(_observePlayback);
    _activeEvent = null;
    super.dispose();
  }
}

extension on ListeningEvent {
  ListeningEvent copyWith({
    DateTime? endedAt,
    int? durationPlayedMs,
    int? songDurationMs,
    double? completionRatio,
    bool? completed,
    bool? skipped,
    int? skipPositionMs,
  }) {
    return ListeningEvent(
      id: id,
      songId: songId,
      previousSongId: previousSongId,
      startedAt: startedAt,
      endedAt: endedAt ?? this.endedAt,
      durationPlayedMs: durationPlayedMs ?? this.durationPlayedMs,
      songDurationMs: songDurationMs ?? this.songDurationMs,
      completionRatio: completionRatio ?? this.completionRatio,
      completed: completed ?? this.completed,
      skipped: skipped ?? this.skipped,
      skipPositionMs: skipPositionMs ?? this.skipPositionMs,
    );
  }
}
