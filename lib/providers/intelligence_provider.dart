import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/listening_event.dart';
import '../models/song.dart';
import '../services/database_helper.dart';
import 'music_provider.dart';

/// Lightweight, on-device listening memory for Resonate.
///
/// Intelligence is deliberately best-effort: database failures never affect
/// playback, and recommendations fall back to the library when there is not
/// enough listening history yet.
class IntelligenceProvider extends ChangeNotifier {
  final MusicProvider music;
  final DatabaseHelper _database = DatabaseHelper();

  bool _enabled = true;
  ListeningEvent? _activeEvent;
  String? _observedSongId;
  bool _lastPlaying = false;
  String? _lastRecommendationId;
  List<Song> _recommendations = const [];
  StreamSubscription<void>? _noop;

  IntelligenceProvider({required this.music}) {
    music.addListener(_observePlayback);
    _observePlayback();
    unawaited(refreshRecommendations());
  }

  bool get isEnabled => _enabled;
  List<Song> get recommendations => List.unmodifiable(_recommendations);
  bool get hasLearningData => _activeEvent != null || _recommendations.isNotEmpty;

  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    if (!enabled) await _finishActiveEvent();
    if (enabled) await refreshRecommendations();
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

    final previous = _previousSongId(song.id);
    final event = ListeningEvent(
      id: '${DateTime.now().microsecondsSinceEpoch}_${song.id}',
      songId: song.id,
      previousSongId: previous,
      startedAt: DateTime.now(),
      songDurationMs: song.duration.inMilliseconds,
    );
    _activeEvent = event;
    await _database.insertListeningEvent(event);
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
    final ratio = songDuration <= 0
        ? 0.0
        : (duration / songDuration).clamp(0.0, 1.0).toDouble();
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
    await _database.updateListeningEvent(updated);
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
    try {
      final counts = await _database.getTransitionCounts(music.currentSong!.id);
      if (counts.isEmpty) return null;
      final songs = await _database.getAllSongs();
      final byId = {for (final song in songs) song.id: song};
      for (final row in counts) {
        final id = row['next_song_id']?.toString();
        final candidate = id == null ? null : byId[id];
        if (candidate != null && candidate.filePath.trim().isNotEmpty) return candidate;
      }
    } catch (e) {
      debugPrint('Intelligence recommendation failed: $e');
    }
    return null;
  }

  Future<void> refreshRecommendations({int limit = 8}) async {
    if (!_enabled) {
      _recommendations = const [];
      notifyListeners();
      return;
    }
    try {
      final songs = await _database.getAllSongs();
      final currentId = music.currentSong?.id;
      final scores = <String, int>{};
      if (currentId != null) {
        final counts = await _database.getTransitionCounts(currentId);
        for (final row in counts) {
          final id = row['next_song_id']?.toString();
          final count = (row['transition_count'] as num?)?.toInt() ?? 0;
          if (id != null) scores[id] = count;
        }
      }
      final ranked = songs.where((song) => song.id != currentId && song.filePath.trim().isNotEmpty).toList();
      ranked.sort((a, b) => (scores[b.id] ?? 0).compareTo(scores[a.id] ?? 0));
      _recommendations = ranked.take(limit).toList(growable: false);
      notifyListeners();
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
    _noop?.cancel();
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
