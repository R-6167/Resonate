import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/intelligence_recommendation.dart';
import '../models/listening_event.dart';
import '../models/song.dart';
import '../services/database_helper.dart';
import '../services/intelligence_settings_store.dart';
import 'music_provider.dart';

class IntelligenceProvider extends ChangeNotifier {
  final MusicProvider music;
  final DatabaseHelper _database = DatabaseHelper();

  bool _enabled = true;
  int _autonomy = 1;
  bool _autopilotGraduated = false;
  ListeningEvent? _activeEvent;
  String? _observedSongId;
  bool _lastPlaying = false;
  String? _lastRecommendationId;
  DateTime? _sessionStartedAt;
  int _activeEventPositionMs = 0;
  Future<void> _eventSerial = Future<void>.value();
  Map<String, double> _feedback = <String, double>{};
  List<IntelligenceRecommendation> _recommendations = const [];

  String _sessionMode = 'Fresh session';
  String _sessionSummary = 'Learning the shape of this listening session.';
  double _sessionCompletion = 0.0;
  int _sessionSkipStreak = 0;
  int _sessionCompletionStreak = 0;
  final List<String> _sessionArtists = <String>[];
  final Map<String, int> _sessionArtistCounts = <String, int>{};

  static const int _minimumLearningEvents = 40;
  static const int _minimumDistinctSongs = 12;
  static const double _graduationConfidence = .72;
  static const Duration _sessionGap = Duration(minutes: 30);
  static const int _sessionEventLimit = 12;

  IntelligenceProvider({required this.music}) {
    music.addListener(_observePlayback);
    unawaited(_loadSettings());
    _observePlayback();
    unawaited(refreshRecommendations());
  }

  bool get isEnabled => _enabled;
  int get autonomy => _autonomy;
  bool get isAutopilot => _enabled && _autonomy == 2;
  bool get isAutopilotGraduated => _autopilotGraduated;
  String get autonomyLabel => const ['Suggestions only', 'Assist me', 'Autopilot'][_autonomy.clamp(0, 2)];
  List<IntelligenceRecommendation> get recommendations => List.unmodifiable(_recommendations);
  IntelligenceRecommendation? get anticipatedNext => _recommendations.isEmpty ? null : _recommendations.first;
  String get sessionMode => _sessionMode;
  String get sessionSummary => _sessionSummary;
  double get sessionCompletion => _sessionCompletion;
  int get sessionSkipStreak => _sessionSkipStreak;
  int get sessionCompletionStreak => _sessionCompletionStreak;
  List<String> get sessionArtists => List.unmodifiable(_sessionArtists);
  Map<String, int> get sessionArtistCounts => Map.unmodifiable(_sessionArtistCounts);

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool('intelligence_enabled') ?? true;
      _autonomy = (prefs.getInt('intelligence_autonomy') ?? 1).clamp(0, 2);
      _autopilotGraduated = prefs.getBool('intelligence_autopilot_graduated') ?? false;
      final raw = prefs.getString('intelligence_feedback');
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _feedback = decoded.map((key, value) => MapEntry(key.toString(), (value as num).toDouble()));
        }
      }
      await refreshRecommendations(notify: false);
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
      debugPrint('Intelligence enabled save failed: $e');
    }
    if (!enabled) {
      _queueEventOperation(_finishActiveEvent);
      _recommendations = const [];
      _sessionMode = 'Manual playback';
      _sessionSummary = 'Intelligence is off, so this session stays fully manual.';
      _sessionCompletion = 0.0;
      _sessionSkipStreak = 0;
      _sessionCompletionStreak = 0;
      _sessionArtists.clear();
      _sessionArtistCounts.clear();
    } else {
      await refreshRecommendations(notify: false);
    }
    notifyListeners();
  }

  Future<void> setAutonomy(int value) async {
    _autonomy = value.clamp(0, 2);
    if (_autonomy < 2) _autopilotGraduated = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('intelligence_autonomy', _autonomy);
      await prefs.setBool('intelligence_autopilot_graduated', _autopilotGraduated);
    } catch (e) {
      debugPrint('Intelligence autonomy save failed: $e');
    }
    notifyListeners();
  }

  Future<void> _evaluateAutopilotGraduation() async {
    if (!_enabled || _autopilotGraduated || _autonomy == 2) return;
    try {
      final events = await _database.getRecentListeningEvents(limit: 200);
      if (events.length < _minimumLearningEvents) return;
      if (events.map((e) => e.songId).toSet().length < _minimumDistinctSongs) return;
      final confident = _recommendations.where((r) => r.confidence >= _graduationConfidence).length;
      if (confident < 2) return;
      _autonomy = 2;
      _autopilotGraduated = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('intelligence_autonomy', 2);
      await prefs.setBool('intelligence_autopilot_graduated', true);
      notifyListeners();
    } catch (e) {
      debugPrint('Intelligence graduation check failed: $e');
    }
  }

  Future<void> rateRecommendation(String songId, bool liked) async {
    if (songId.trim().isEmpty) return;
    _feedback[songId] = ((_feedback[songId] ?? 0.0) + (liked ? 1.0 : -1.0)).clamp(-3.0, 3.0).toDouble();
    await _persistFeedback();
    await refreshRecommendations(notify: false);
    notifyListeners();
  }

  double feedbackFor(String songId) => _feedback[songId] ?? 0.0;

  Future<void> clearRecommendationFeedback() async {
    _feedback = <String, double>{};
    try {
      await (await SharedPreferences.getInstance()).remove('intelligence_feedback');
    } catch (e) {
      debugPrint('Intelligence feedback reset failed: $e');
    }
    await refreshRecommendations(notify: false);
    notifyListeners();
  }

  Future<void> _persistFeedback() async {
    try {
      await (await SharedPreferences.getInstance()).setString('intelligence_feedback', jsonEncode(_feedback));
    } catch (e) {
      debugPrint('Intelligence feedback save failed: $e');
    }
  }

  String _artistKey(String? value) {
    final raw = value?.trim().toLowerCase() ?? '';
    const unknown = {
      '', 'unknown', 'unknown artist', 'unknown_artist', '<unknown>',
      'n/a', 'na', 'none', 'null', 'various artists', 'various artist',
    };
    return unknown.contains(raw) ? '' : raw;
  }

  void _observePlayback() {
    final song = music.currentSong;
    final id = song?.id;
    final playing = music.isPlaying;

    if (song != null && _activeEvent?.songId == song.id) {
      _activeEventPositionMs = music.currentPosition.inMilliseconds;
    }

    if (!_enabled) {
      _lastPlaying = playing;
      _observedSongId = id;
      return;
    }

    if (id != _observedSongId) {
      final previous = _observedSongId;
      _observedSongId = id;
      _queueEventOperation(() async {
        await _finishActiveEvent();
        if (song != null && music.isPlaying) {
          await _startEvent(song);
        }
      });
      if (previous != null) unawaited(refreshRecommendations());
    } else if (playing && !_lastPlaying && song != null) {
      _queueEventOperation(() => _startEvent(song));
    } else if (!playing && _lastPlaying) {
      final total = music.currentDuration?.inMilliseconds ?? 0;
      final position = music.currentPosition.inMilliseconds;
      final naturallyComplete = total > 0 && position >= (total * .98).round();
      if (naturallyComplete) _queueEventOperation(_finishActiveEvent);
    }

    _lastPlaying = playing;
  }

  void _queueEventOperation(Future<void> Function() operation) {
    _eventSerial = _eventSerial.then((_) => operation()).catchError((error, stack) {
      debugPrint('Intelligence event operation failed: $error');
      debugPrint('$stack');
    });
  }

  Future<void> _startEvent(Song song) async {
    if (!_enabled || _activeEvent?.songId == song.id) return;
    await _finishActiveEvent();
    _activeEventPositionMs = 0;
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
      await _database.updateSongPlayCount(song.id);
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
    final duration = _activeEventPositionMs.clamp(0, event.songDurationMs > 0 ? event.songDurationMs : 1);
    final total = event.songDurationMs > 0 ? event.songDurationMs : (music.currentSong?.id == event.songId ? music.currentDuration?.inMilliseconds ?? 0 : 0);
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
    _activeEventPositionMs = 0;
    try {
      await _database.updateListeningEvent(updated);
    } catch (e) {
      debugPrint('Intelligence event update failed: $e');
    }
    _updateSessionFromEvent(updated);
    await _learnFromFinishedEvent(updated, ratio);
    _lastRecommendationId = event.songId;
  }

  void _updateSessionFromEvent(ListeningEvent event) {
    final now = event.endedAt ?? DateTime.now();
    if (_sessionStartedAt == null || now.difference(_sessionStartedAt!) > _sessionGap) {
      _sessionStartedAt = event.startedAt;
      _sessionSkipStreak = 0;
      _sessionCompletionStreak = 0;
      _sessionArtistCounts.clear();
    }

    final artist = _artistKey(_songForId(event.songId)?.artist);
    if (artist.isNotEmpty) {
      _sessionArtistCounts[artist] = (_sessionArtistCounts[artist] ?? 0) + 1;
    }
    if (event.completed) {
      _sessionCompletionStreak++;
      _sessionSkipStreak = 0;
    } else if (event.skipped) {
      _sessionSkipStreak++;
      _sessionCompletionStreak = 0;
    }
  }

  Song? _songForId(String id) {
    if (music.currentSong?.id == id) return music.currentSong;
    for (final song in music.queue) {
      if (song.id == id) return song;
    }
    return null;
  }

  Future<void> _learnFromFinishedEvent(ListeningEvent event, double ratio) async {
    final previous = _feedback[event.songId] ?? 0.0;
    final delta = ratio >= .90 ? .35 : ratio >= .55 ? .08 : -.30;
    final next = (previous + delta).clamp(-3.0, 3.0).toDouble();
    if (next != previous) {
      _feedback[event.songId] = next;
      await _persistFeedback();
    }
  }

  Future<Song?> getNextRecommendation() async {
    if (!_enabled || music.currentSong == null) return null;
    await refreshRecommendations(notify: false);
    return anticipatedNext?.song;
  }

  List<ListeningEvent> _extractCurrentSession(List<ListeningEvent> events) {
    if (events.isEmpty) return const <ListeningEvent>[];
    final session = <ListeningEvent>[];
    DateTime? previousEnd;
    for (final event in events) {
      final eventEnd = event.endedAt ?? event.startedAt;
      if (previousEnd != null && previousEnd.difference(eventEnd) > _sessionGap) break;
      session.add(event);
      previousEnd = eventEnd;
      if (session.length >= _sessionEventLimit) break;
    }
    return session;
  }

  Future<void> _updateSessionContext(List<ListeningEvent> events, Map<String, Song> byId) async {
    final sessionEnabled = await IntelligenceSettingsStore.sessionIntelligence();
    if (!sessionEnabled) {
      _sessionMode = 'Session intelligence off';
      _sessionSummary = 'Using long-term listening signals without session steering.';
      _sessionCompletion = 0.0;
      _sessionSkipStreak = 0;
      _sessionCompletionStreak = 0;
      _sessionArtists.clear();
      _sessionArtistCounts.clear();
      return;
    }

    final sessionEvents = _extractCurrentSession(events);
    if (sessionEvents.isEmpty) {
      _sessionMode = 'Fresh session';
      _sessionSummary = 'Learning the shape of this listening session.';
      _sessionCompletion = 0.0;
      _sessionSkipStreak = 0;
      _sessionCompletionStreak = 0;
      _sessionArtists.clear();
      _sessionArtistCounts.clear();
      return;
    }

    _sessionStartedAt = sessionEvents.last.startedAt;
    _sessionArtistCounts.clear();
    for (final event in sessionEvents) {
      final artist = _artistKey(byId[event.songId]?.artist);
      if (artist.isNotEmpty) _sessionArtistCounts[artist] = (_sessionArtistCounts[artist] ?? 0) + 1;
    }
    _sessionArtists
      ..clear()
      ..addAll((_sessionArtistCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).map((entry) => entry.key));

    final completed = sessionEvents.where((e) => e.completed).length;
    final skipped = sessionEvents.where((e) => e.skipped).length;
    _sessionCompletion = completed / sessionEvents.length;
    _sessionSkipStreak = 0;
    _sessionCompletionStreak = 0;
    for (final event in sessionEvents) {
      if (event.completed) {
        _sessionCompletionStreak++;
        _sessionSkipStreak = 0;
      } else if (event.skipped) {
        _sessionSkipStreak++;
        _sessionCompletionStreak = 0;
      }
    }

    if (_sessionSkipStreak >= 3 || (skipped >= 3 && skipped > completed)) {
      _sessionMode = 'Exploring';
      _sessionSummary = 'You are moving through tracks quickly, so I am widening the search.';
    } else if (_sessionCompletionStreak >= 3 || (completed >= 3 && completed >= skipped + 2)) {
      _sessionMode = 'Familiar flow';
      _sessionSummary = 'The session is settling into a strong flow, so I am favoring proven signals.';
    } else {
      _sessionMode = 'Balanced';
      _sessionSummary = 'The session is mixed, so I am balancing familiar picks with exploration.';
    }
  }

  Future<void> _updateSessionArtistAndMode(List<ListeningEvent> events, Map<String, Song> byId) async {
    await _updateSessionContext(events, byId);
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
      final sessionEnabled = await IntelligenceSettingsStore.sessionIntelligence();
      final exploration = (await IntelligenceSettingsStore.exploration()) / 100.0;
      final familiarity = 1.0 - exploration;
      final explanationsEnabled = await IntelligenceSettingsStore.explanations();
      final sessionEvents = sessionEnabled ? _extractCurrentSession(events) : const <ListeningEvent>[];
      final sessionSongIds = sessionEvents.map((e) => e.songId).toSet();
      final sessionArtistCounts = <String, int>{};
      var recentRank = 0;

      for (final event in events) {
        plays[event.songId] = (plays[event.songId] ?? 0) + 1;
        if (event.completed) completes[event.songId] = (completes[event.songId] ?? 0) + 1;
        if (event.skipped) skips[event.songId] = (skips[event.songId] ?? 0) + 1;
        final artist = _artistKey(byId[event.songId]?.artist);
        if (artist.isNotEmpty) {
          artistAffinity[artist] = (artistAffinity[artist] ?? 0) + (event.completed ? 1 : event.skipped ? -.8 : event.completionRatio * .5);
        }
        final age = now.difference(event.startedAt).inHours;
        if (age < 48 && event.startedAt.hour ~/ 3 == currentHourBucket) {
          songHourAffinity[event.songId] = (songHourAffinity[event.songId] ?? 0) + (event.completed ? 1.0 : event.completionRatio * .5);
        }
        if (recentRank < 12) recentSongIds.add(event.songId);
        recentRank++;
      }

      for (final event in sessionEvents) {
        final artist = _artistKey(byId[event.songId]?.artist);
        if (artist.isNotEmpty) sessionArtistCounts[artist] = (sessionArtistCounts[artist] ?? 0) + 1;
      }
      await _updateSessionContext(events, byId);

      final ranked = <IntelligenceRecommendation>[];
      for (final song in songs) {
        if (song.id == current?.id || song.filePath.trim().isEmpty) continue;
        final t = transitions[song.id] ?? 0;
        final p = plays[song.id] ?? 0;
        final c = completes[song.id] ?? 0;
        final s = skips[song.id] ?? 0;
        final completion = p == 0 ? 0.0 : c / p;
        final artistKey = _artistKey(song.artist);
        final artist = artistKey.isEmpty ? 0.0 : (artistAffinity[artistKey] ?? 0.0);
        final timeAffinity = songHourAffinity[song.id] ?? 0.0;
        final recencyPenalty = recentSongIds.contains(song.id) ? 1.5 : 0.0;
        final feedback = _feedback[song.id] ?? 0.0;
        final currentArtist = _artistKey(current?.artist);
        final sameArtistBoost = currentArtist.isNotEmpty && artistKey.isNotEmpty && artistKey == currentArtist ? .75 * familiarity : 0.0;
        final inSession = sessionSongIds.contains(song.id);
        final sessionArtistCount = artistKey.isEmpty ? 0 : (sessionArtistCounts[artistKey] ?? 0);
        final sessionContinuity = sessionEnabled && sessionArtistCount > 0 ? sessionArtistCount * .7 * familiarity : 0.0;
        final explorationBonus = sessionEnabled && !inSession && !recentSongIds.contains(song.id) ? .9 * exploration : 0.0;
        final familiarityBonus = (completion >= .65 || feedback > 0) ? .7 * familiarity : 0.0;
        final repeatPenalty = await IntelligenceSettingsStore.artistRepeat() ? .15 : .55;
        final sessionFatiguePenalty = sessionEnabled && sessionArtistCount >= 3 && artistKey.isNotEmpty ? (sessionArtistCount - 2) * repeatPenalty : 0.0;
        final score = t * 5.0 * familiarity + completion * 4.0 * familiarity + artist * 1.5 * familiarity + timeAffinity * 1.25 + feedback * 3.0 + sameArtistBoost + sessionContinuity + explorationBonus + familiarityBonus - s * 2.0 - recencyPenalty - sessionFatiguePenalty;
        final evidence = t * 2.0 + completion * 2.0 + artist.abs() + timeAffinity + feedback.abs() + sessionContinuity + (p > 0 ? 1.0 : 0.0);
        final confidence = (evidence / (evidence + 4.0)).clamp(.08, .97).toDouble();

        String reason = '';
        String sessionReason = '';
        if (explanationsEnabled) {
          if (feedback >= 1) reason = 'You told me you like this.';
          else if (feedback <= -1) reason = 'Kept low because you previously passed on it.';
          else if (t > 0) reason = 'You often move to this after ${current?.title ?? 'your current track'}.';
          else if (timeAffinity > 0) reason = 'You tend to enjoy this around this time.';
          else if (completion >= .65) reason = 'You tend to finish this one.';
          else if (artist > 0) reason = 'You have been enjoying more from ${song.artist}.';
          else reason = 'A fresh local pick while I learn your pattern.';
          if (_sessionMode == 'Exploring' && explorationBonus > 0) sessionReason = 'Keeping the session moving with a fresh direction.';
          else if (_sessionMode == 'Familiar flow' && familiarityBonus > 0) sessionReason = 'Keeping the strong flow you have established.';
          else if (sessionContinuity > 0) sessionReason = 'Fits the listening pattern showing up in this session.';
          else sessionReason = 'A measured change of direction for this session.';
        }
        ranked.add(IntelligenceRecommendation(
          song: song,
          score: score,
          confidence: confidence,
          reason: reason,
          decision: _autonomy == 2 ? 'autopilot' : _autonomy == 1 ? 'assist' : 'suggest',
          sessionReason: sessionReason,
        ));
      }
      ranked.sort((a, b) => b.score.compareTo(a.score));
      _recommendations = ranked.take(limit).toList(growable: false);
      await _evaluateAutopilotGraduation();
      if (notify) notifyListeners();
    } catch (e, stack) {
      debugPrint('Intelligence refresh failed: $e');
      debugPrint('$stack');
    }
  }

  Future<Map<String, dynamic>> analyzeCurrentSession() async {
    final events = await _database.getRecentListeningEvents(limit: 30);
    final sessionEvents = _extractCurrentSession(events);
    final completed = sessionEvents.where((e) => e.completed).length;
    final skipped = sessionEvents.where((e) => e.skipped).length;
    return {
      'events': sessionEvents.length,
      'completed': completed,
      'skipped': skipped,
      'completionRate': sessionEvents.isEmpty ? 0.0 : completed / sessionEvents.length,
      'sessionStartedAt': sessionEvents.isEmpty ? null : sessionEvents.last.startedAt.toIso8601String(),
      'mode': _sessionMode,
      'summary': _sessionSummary,
      'skipStreak': _sessionSkipStreak,
      'completionStreak': _sessionCompletionStreak,
      'artists': List<String>.from(_sessionArtists),
      'autonomy': _autonomy,
      'autopilotGraduated': _autopilotGraduated,
    };
  }

  Future<void> recordListeningEvent(ListeningEvent event) async {
    await _database.insertListeningEvent(event);
  }

  @override
  void dispose() {
    music.removeListener(_observePlayback);
    super.dispose();
  }
}
