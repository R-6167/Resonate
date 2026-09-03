import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/intelligence_recommendation.dart';
import '../models/listening_event.dart';
import '../models/song.dart';
import '../services/database_helper.dart';
import 'music_provider.dart';

/// Lightweight, local-first listening memory. Intelligence never interferes
/// with normal playback unless the user explicitly selects Autopilot.
class IntelligenceProvider extends ChangeNotifier {
  final MusicProvider music;
  final DatabaseHelper _database = DatabaseHelper();
  bool _enabled = true;
  int _autonomy = 1; // 0 suggest, 1 assist, 2 autopilot
  ListeningEvent? _activeEvent;
  String? _observedSongId;
  bool _lastPlaying = false;
  bool _autoDecisionInFlight = false;
  String? _lastRecommendationId;
  DateTime? _sessionStartedAt;
  Map<String, double> _feedback = <String, double>{};
  List<IntelligenceRecommendation> _recommendations = const [];

  IntelligenceProvider({required this.music}) {
    music.addListener(_observePlayback);
    _loadSettings();
    _observePlayback();
    unawaited(refreshRecommendations());
  }

  bool get isEnabled => _enabled;
  int get autonomy => _autonomy;
  bool get isAutopilot => _enabled && _autonomy == 2;
  String get autonomyLabel => const ['Suggestions only', 'Assist me', 'Autopilot'][_autonomy.clamp(0, 2)];
  List<IntelligenceRecommendation> get recommendations => List.unmodifiable(_recommendations);
  IntelligenceRecommendation? get anticipatedNext => _recommendations.isEmpty ? null : _recommendations.first;

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool('intelligence_enabled') ?? true;
      _autonomy = (prefs.getInt('intelligence_autonomy') ?? 1).clamp(0, 2);
      final rawFeedback = prefs.getString('intelligence_feedback');
      if (rawFeedback != null && rawFeedback.isNotEmpty) {
        final decoded = jsonDecode(rawFeedback);
        if (decoded is Map) {
          _feedback = decoded.map(
            (key, value) => MapEntry(key.toString(), (value as num).toDouble()),
          );
        }
      }
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

  Future<void> setAutonomy(int value) async {
    _autonomy = value.clamp(0, 2);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('intelligence_autonomy', _autonomy);
    } catch (e) {
      debugPrint('Intelligence autonomy save failed: $e');
    }
    notifyListeners();
  }

  /// Records a direct user correction to a recommendation without changing
  /// the listening database. Positive values reinforce; negative values repel.
  Future<void> rateRecommendation(String songId, bool liked) async {
    if (songId.trim().isEmpty) return;
    final previous = _feedback[songId] ?? 0.0;
    _feedback[songId] = (previous + (liked ? 1.0 : -1.0)).clamp(-3.0, 3.0).toDouble();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('intelligence_feedback', jsonEncode(_feedback));
    } catch (e) {
      debugPrint('Intelligence feedback save failed: $e');
    }
    await refreshRecommendations(notify: false);
    notifyListeners();
  }

  double feedbackFor(String songId) => _feedback[songId] ?? 0.0;

  Future<void> clearRecommendationFeedback() async {
    _feedback = <String, double>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('intelligence_feedback');
    } catch (e) {
      debugPrint('Intelligence feedback reset failed: $e');
    }
    await refreshRecommendations(notify: false);
    notifyListeners();
  }

  void _observePlayback() {
    if (!_enabled) return;
    final song = music.currentSong;
    final id = song?.id;
    final playing = music.isPlaying;
    if (id != _observedSongId) {
      unawaited(_finishActiveEvent());
      _observedSongId = id;
      if (song != null && playing) {
        _sessionStartedAt ??= DateTime.now();
        unawaited(_startEvent(song));
      }
      unawaited(refreshRecommendations());
    } else if (playing && !_lastPlaying && song != null) {
      _sessionStartedAt ??= DateTime.now();
      unawaited(_startEvent(song));
    } else if (!playing && _lastPlaying) {
      final total = music.currentDuration?.inMilliseconds ?? 0;
      final position = music.currentPosition.inMilliseconds;
      final completedNaturally = total > 0 && position >= (total * .98).round();
      unawaited(_finishActiveEvent());
      if (isAutopilot && completedNaturally && music.queueIndex >= music.queue.length - 1) {
        unawaited(_chooseNextAutomatically());
      }
    }
    _lastPlaying = playing;
  }

  Future<void> _chooseNextAutomatically() async {
    if (_autoDecisionInFlight) return;
    _autoDecisionInFlight = true;
    try {
      await refreshRecommendations(notify: false);
      final next = anticipatedNext;
      if (next == null || next.confidence < .65) return;
      await music.playSong(next.song, queue: [next.song], startIndex: 0);
    } catch (e) {
      debugPrint('Intelligence automatic decision failed: $e');
    } finally {
      _autoDecisionInFlight = false;
    }
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
      completionRatio: 0,
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
    final i = music.queueIndex;
    if (i > 0 && i < music.queue.length) return music.queue[i - 1].id;
    return _lastRecommendationId == currentId ? null : _lastRecommendationId;
  }

  Future<void> _finishActiveEvent() async {
    final event = _activeEvent;
    if (event == null) return;
    final duration = music.currentSong?.id == event.songId
        ? music.currentPosition.inMilliseconds
        : event.durationPlayedMs;
    final total = event.songDurationMs > 0
        ? event.songDurationMs
        : (music.currentDuration?.inMilliseconds ?? 0);
    final ratio = total <= 0 ? 0.0 : (duration / total).clamp(0.0, 1.0).toDouble();
    final updated = ListeningEvent(
      id: event.id,
      songId: event.songId,
      previousSongId: event.previousSongId,
      startedAt: event.startedAt,
      endedAt: DateTime.now(),
      durationPlayedMs: duration,
      songDurationMs: total,
      completionRatio: ratio,
      completed: ratio >= .90,
      skipped: ratio < .90 && duration > 0,
      skipPositionMs: ratio < .90 && duration > 0 ? duration : null,
    );
    _activeEvent = null;
    try {
      await _database.updateListeningEvent(updated);
    } catch (e) {
      debugPrint('Intelligence event update failed: $e');
    }
    _lastRecommendationId = event.songId;
  }

  Future<Song?> getNextRecommendation() async {
    if (!_enabled || music.currentSong == null) return null;
    await refreshRecommendations(notify: false);
    return anticipatedNext?.song;
  }

  Future<void> refreshRecommendations({int limit = 8, bool notify = true}) async {
    if (!_enabled) {
      _recommendations = const [];
      if (notify) notifyListeners();
      return;
    }
    try {
      final songs = await _database.getAllSongs();
      final current = music.currentSong;
      final events = await _database.getRecentListeningEvents(limit: 200);
      final transitions = <String, int>{};
      if (current != null) {
        for (final row in await _database.getTransitionCounts(current.id)) {
          final id = row['next_song_id']?.toString();
          if (id != null) transitions[id] = (row['transition_count'] as num?)?.toInt() ?? 0;
        }
      }

      final plays = <String, int>{};
      final completes = <String, int>{};
      final skips = <String, int>{};
      final artistAffinity = <String, double>{};
      final songHourAffinity = <String, double>{};
      final recentSongIds = <String>{};
      final byId = {for (final s in songs) s.id: s};
      final now = DateTime.now();
      final currentHourBucket = now.hour ~/ 3;
      var recentRank = 0;

      for (final e in events) {
        plays[e.songId] = (plays[e.songId] ?? 0) + 1;
        if (e.completed) completes[e.songId] = (completes[e.songId] ?? 0) + 1;
        if (e.skipped) skips[e.songId] = (skips[e.songId] ?? 0) + 1;
        final song = byId[e.songId];
        final artist = song?.artist.trim();
        if (artist != null && artist.isNotEmpty) {
          artistAffinity[artist] = (artistAffinity[artist] ?? 0) +
              (e.completed ? 1 : e.skipped ? -.8 : e.completionRatio * .5);
        }
        final age = now.difference(e.startedAt).inHours;
        if (age < 48 && e.startedAt.hour ~/ 3 == currentHourBucket) {
          songHourAffinity[e.songId] = (songHourAffinity[e.songId] ?? 0) +
              (e.completed ? 1.0 : e.completionRatio * .5);
        }
        if (recentRank < 12) recentSongIds.add(e.songId);
        recentRank++;
      }

      final ranked = <IntelligenceRecommendation>[];
      for (final song in songs) {
        if (song.id == current?.id || song.filePath.trim().isEmpty) continue;
        final t = transitions[song.id] ?? 0;
        final p = plays[song.id] ?? 0;
        final c = completes[song.id] ?? 0;
        final s = skips[song.id] ?? 0;
        final completion = p == 0 ? 0.0 : c / p;
        final artist = artistAffinity[song.artist.trim()] ?? 0;
        final timeAffinity = songHourAffinity[song.id] ?? 0;
        final recencyPenalty = recentSongIds.contains(song.id) ? 1.5 : 0.0;
        final feedback = _feedback[song.id] ?? 0.0;
        final sameArtistBoost = current != null &&
                song.artist.trim().isNotEmpty &&
                song.artist.trim().toLowerCase() == current.artist.trim().toLowerCase()
            ? .75
            : 0.0;

        final score = t * 5.0 +
            completion * 4.0 +
            artist * 1.5 +
            timeAffinity * 1.25 +
            feedback * 3.0 +
            sameArtistBoost -
            s * 2.0 -
            recencyPenalty;

        final evidence = t * 2.0 +
            completion * 2.0 +
            artist.abs() +
            timeAffinity +
            feedback.abs() +
            (p > 0 ? 1.0 : 0.0);
        final confidence = (evidence / (evidence + 4.0)).clamp(.08, .97).toDouble();

        String reason;
        if (feedback >= 1) {
          reason = 'You told me you like this.';
        } else if (feedback <= -1) {
          reason = 'Kept low because you previously passed on it.';
        } else if (t > 0) {
          reason = 'You often move to this after ${current?.title ?? 'your current track'}.';
        } else if (timeAffinity > 0) {
          reason = 'You tend to enjoy this around this time.';
        } else if (completion >= .65) {
          reason = 'You tend to finish this one.';
        } else if (artist > 0) {
          reason = 'You have been enjoying more from ${song.artist}.';
        } else {
          reason = 'A fresh local pick while I learn your pattern.';
        }

        ranked.add(IntelligenceRecommendation(
          song: song,
          score: score,
          confidence: confidence,
          reason: reason,
          decision: _autonomy == 2 ? 'autopilot' : _autonomy == 1 ? 'assist' : 'suggest',
        ));
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
    final completed = events.where((e) => e.completed).length;
    return {
      'events': events.length,
      'completed': completed,
      'skipped': events.where((e) => e.skipped).length,
      'completionRate': events.isEmpty ? 0.0 : completed / events.length,
      'sessionStartedAt': _sessionStartedAt?.toIso8601String(),
      'autonomy': autonomyLabel,
    };
  }

  Future<void> recordListeningEvent(ListeningEvent event) async {
    if (!_enabled) return;
    try {
      await _database.insertListeningEvent(event);
    } catch (e) {
      debugPrint('Intelligence event recording failed: $e');
    }
  }

  @override
  void dispose() {
    music.removeListener(_observePlayback);
    _activeEvent = null;
    super.dispose();
  }
}
