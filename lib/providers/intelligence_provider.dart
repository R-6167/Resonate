import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/intelligence_recommendation.dart';
import '../models/listening_event.dart';
import '../models/song.dart';
import '../services/database_helper.dart';
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
  bool _autoDecisionInFlight = false;
  bool _queueDecisionInFlight = false;
  String? _lastRecommendationId;
  DateTime? _sessionStartedAt;
  Map<String, double> _feedback = <String, double>{};
  List<IntelligenceRecommendation> _recommendations = const [];

  // Session Intelligence state. These are deliberately small, local signals:
  // no model, embeddings, network calls or heavy ML are required.
  String _sessionMode = 'Fresh session';
  String _sessionSummary = 'Learning the shape of this listening session.';
  double _sessionCompletion = 0.0;
  final List<String> _sessionArtists = <String>[];

  static const int _minimumLearningEvents = 40;
  static const int _minimumDistinctSongs = 12;
  static const double _graduationConfidence = .72;

  IntelligenceProvider({required this.music}) {
    music.addListener(_observePlayback);
    _loadSettings();
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
  List<String> get sessionArtists => List.unmodifiable(_sessionArtists);

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool('intelligence_enabled') ?? true;
      _autonomy = (prefs.getInt('intelligence_autonomy') ?? 1).clamp(0, 2);
      _autopilotGraduated = prefs.getBool('intelligence_autopilot_graduated') ?? false;
      final rawFeedback = prefs.getString('intelligence_feedback');
      if (rawFeedback != null && rawFeedback.isNotEmpty) {
        final decoded = jsonDecode(rawFeedback);
        if (decoded is Map) _feedback = decoded.map((key, value) => MapEntry(key.toString(), (value as num).toDouble()));
      }
      if (_enabled) await refreshRecommendations(notify: false);
      notifyListeners();
    } catch (e) { debugPrint('Intelligence settings load failed: $e'); }
  }

  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('intelligence_enabled', enabled);
    } catch (e) { debugPrint('Intelligence settings save failed: $e'); }
    if (!enabled) {
      await _finishActiveEvent();
      _recommendations = const [];
      _sessionMode = 'Manual playback';
      _sessionSummary = 'Intelligence is off, so this session stays fully manual.';
      _sessionCompletion = 0.0;
      _sessionArtists.clear();
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
    } catch (e) { debugPrint('Intelligence autonomy save failed: $e'); }
    notifyListeners();
  }

  Future<void> _evaluateAutopilotGraduation() async {
    if (!_enabled || _autopilotGraduated || _autonomy == 2) return;
    try {
      final events = await _database.getRecentListeningEvents(limit: 200);
      if (events.length < _minimumLearningEvents) return;
      final distinctSongs = events.map((e) => e.songId).toSet().length;
      if (distinctSongs < _minimumDistinctSongs) return;
      final confident = _recommendations.where((r) => r.confidence >= _graduationConfidence).length;
      if (confident < 2) return;
      _autonomy = 2;
      _autopilotGraduated = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('intelligence_autonomy', 2);
      await prefs.setBool('intelligence_autopilot_graduated', true);
      debugPrint('Intelligence graduated to Autopilot: events=${events.length}, songs=$distinctSongs, confident=$confident');
      notifyListeners();
    } catch (e) { debugPrint('Intelligence graduation check failed: $e'); }
  }

  Future<void> rateRecommendation(String songId, bool liked) async {
    if (songId.trim().isEmpty) return;
    final previous = _feedback[songId] ?? 0.0;
    _feedback[songId] = (previous + (liked ? 1.0 : -1.0)).clamp(-3.0, 3.0).toDouble();
    await _persistFeedback();
    await refreshRecommendations(notify: false);
    notifyListeners();
  }

  double feedbackFor(String songId) => _feedback[songId] ?? 0.0;

  Future<void> clearRecommendationFeedback() async {
    _feedback = <String, double>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('intelligence_feedback');
    } catch (e) { debugPrint('Intelligence feedback reset failed: $e'); }
    await refreshRecommendations(notify: false);
    notifyListeners();
  }

  Future<void> _persistFeedback() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('intelligence_feedback', jsonEncode(_feedback));
    } catch (e) { debugPrint('Intelligence behavioral feedback save failed: $e'); }
  }

  Future<void> _learnFromFinishedEvent(ListeningEvent event, double ratio) async {
    // A pause is not a dislike. Feedback is only learned when a song actually
    // changes/stops, so ordinary pause/resume actions do not create a skip signal.
    final previous = _feedback[event.songId] ?? 0.0;
    final delta = ratio >= .90 ? .35 : ratio >= .55 ? .08 : -.30;
    final next = (previous + delta).clamp(-3.0, 3.0).toDouble();
    if (next == previous) return;
    _feedback[event.songId] = next;
    await _persistFeedback();
  }

  void _observePlayback() {
    if (!_enabled) return;
    final song = music.currentSong;
    final id = song?.id;
    final playing = music.isPlaying;
    if (id != _observedSongId) {
      unawaited(_finishActiveEvent());
      _observedSongId = id;
      if (song != null && playing) { _sessionStartedAt ??= DateTime.now(); unawaited(_startEvent(song)); }
      unawaited(refreshRecommendations());
    } else if (playing && !_lastPlaying && song != null) {
      _sessionStartedAt ??= DateTime.now();
      unawaited(_startEvent(song));
    } else if (!playing && _lastPlaying) {
      final total = music.currentDuration?.inMilliseconds ?? 0;
      final position = music.currentPosition.inMilliseconds;
      final completedNaturally = total > 0 && position >= (total * .98).round();
      // Do not finish an event merely because playback was paused.
      if (completedNaturally) {
        unawaited(_finishActiveEvent());
        if (isAutopilot && music.queueIndex >= music.queue.length - 1) unawaited(_chooseNextAutomatically());
      }
    }
    if (isAutopilot && playing && music.queue.length - music.queueIndex <= 2) {
      final duration = music.currentDuration;
      final remaining = duration == null ? null : duration - music.currentPosition;
      if (remaining == null || remaining <= const Duration(seconds: 25)) unawaited(_maintainAutopilotQueue());
    }
    _lastPlaying = playing;
  }

  /// Builds a short sequence using session context as well as recommendation
  /// confidence. The adjustment is intentionally conservative: it can steer a
  /// sequence toward the current flow, but it cannot override a strong dislike.
  List<IntelligenceRecommendation> _selectAutopilotSequence({required Set<String> queuedIds, int count = 2}) {
    final candidates = _recommendations.where((r) => r.confidence >= .45 && !queuedIds.contains(r.song.id)).toList(growable: false);
    if (candidates.isEmpty) return const [];
    final selected = <IntelligenceRecommendation>[];
    final usedArtists = <String>{};
    String lastArtist = music.queue.isNotEmpty ? music.queue.last.artist.trim().toLowerCase() : (music.currentSong?.artist.trim().toLowerCase() ?? '');
    while (selected.length < count && selected.length < candidates.length) {
      IntelligenceRecommendation? best;
      var bestAdjustedScore = double.negativeInfinity;
      for (final recommendation in candidates) {
        if (selected.any((item) => item.song.id == recommendation.song.id)) continue;
        final artist = recommendation.song.artist.trim().toLowerCase();
        var adjusted = recommendation.score;
        if (artist.isNotEmpty && artist == lastArtist) adjusted -= 1.5;
        if (artist.isNotEmpty && usedArtists.contains(artist)) adjusted -= 1.25;
        if (selected.isNotEmpty && artist.isNotEmpty && artist != lastArtist) adjusted += .6;
        // In a high-completion session, allow a little more novelty; in a
        // skip-heavy session, stay closer to established signals.
        if (_sessionMode == 'Exploring') adjusted += recommendation.confidence < .65 ? .55 : 0.0;
        if (_sessionMode == 'Familiar flow') adjusted += recommendation.confidence >= .65 ? .45 : 0.0;
        if (adjusted > bestAdjustedScore) { bestAdjustedScore = adjusted; best = recommendation; }
      }
      if (best == null) break;
      selected.add(best);
      final artist = best.song.artist.trim().toLowerCase();
      if (artist.isNotEmpty) usedArtists.add(artist);
      lastArtist = artist;
    }
    return selected;
  }

  Future<void> _maintainAutopilotQueue() async {
    if (_queueDecisionInFlight || !isAutopilot) return;
    _queueDecisionInFlight = true;
    try {
      await refreshRecommendations(notify: false);
      final queuedIds = music.queue.map((song) => song.id).toSet();
      final candidates = _selectAutopilotSequence(queuedIds: queuedIds, count: 2).map((r) => r.song).toList(growable: false);
      if (candidates.isNotEmpty) await music.enqueueSongs(candidates);
    } catch (e) { debugPrint('Intelligence queue decision failed: $e'); }
    finally { _queueDecisionInFlight = false; }
  }

  Future<void> _chooseNextAutomatically() async {
    if (_autoDecisionInFlight) return;
    _autoDecisionInFlight = true;
    try {
      await refreshRecommendations(notify: false);
      final sequence = _selectAutopilotSequence(queuedIds: music.queue.map((song) => song.id).toSet(), count: 2);
      if (sequence.isEmpty || sequence.first.confidence < .65) return;
      await music.playSong(sequence.first.song, queue: sequence.map((r) => r.song).toList(growable: false), startIndex: 0);
    } catch (e) { debugPrint('Intelligence automatic decision failed: $e'); }
    finally { _autoDecisionInFlight = false; }
  }

  Future<void> _startEvent(Song song) async {
    if (!_enabled || _activeEvent?.songId == song.id) return;
    await _finishActiveEvent();
    final event = ListeningEvent(id: '${DateTime.now().microsecondsSinceEpoch}_${song.id}', songId: song.id, previousSongId: _previousSongId(song.id), startedAt: DateTime.now(), durationPlayedMs: 0, songDurationMs: song.duration.inMilliseconds, completionRatio: 0, completed: false, skipped: false);
    _activeEvent = event;
    try { await _database.insertListeningEvent(event); } catch (e) { debugPrint('Intelligence event insert failed: $e'); }
  }

  String? _previousSongId(String currentId) {
    final i = music.queueIndex;
    if (i > 0 && i < music.queue.length) return music.queue[i - 1].id;
    return _lastRecommendationId == currentId ? null : _lastRecommendationId;
  }

  Future<void> _finishActiveEvent() async {
    final event = _activeEvent;
    if (event == null) return;
    final duration = music.currentSong?.id == event.songId ? music.currentPosition.inMilliseconds : event.durationPlayedMs;
    final total = event.songDurationMs > 0 ? event.songDurationMs : (music.currentDuration?.inMilliseconds ?? 0);
    final ratio = total <= 0 ? 0.0 : (duration / total).clamp(0.0, 1.0).toDouble();
    final updated = ListeningEvent(id: event.id, songId: event.songId, previousSongId: event.previousSongId, startedAt: event.startedAt, endedAt: DateTime.now(), durationPlayedMs: duration, songDurationMs: total, completionRatio: ratio, completed: ratio >= .90, skipped: ratio < .90 && duration > 0, skipPositionMs: ratio < .90 && duration > 0 ? duration : null);
    _activeEvent = null;
    try { await _database.updateListeningEvent(updated); } catch (e) { debugPrint('Intelligence event update failed: $e'); }
    await _learnFromFinishedEvent(updated, ratio);
    _lastRecommendationId = event.songId;
  }

  Future<Song?> getNextRecommendation() async {
    if (!_enabled || music.currentSong == null) return null;
    await refreshRecommendations(notify: false);
    return anticipatedNext?.song;
  }

  Future<void> refreshRecommendations({int limit = 8, bool notify = true}) async {
    if (!_enabled) { _recommendations = const []; if (notify) notifyListeners(); return; }
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

      final plays = <String, int>{}, completes = <String, int>{}, skips = <String, int>{};
      final artistAffinity = <String, double>{}, songHourAffinity = <String, double>{};
      final recentSongIds = <String>{};
      final byId = {for (final s in songs) s.id: s};
      final now = DateTime.now();
      final currentHourBucket = now.hour ~/ 3;
      final sessionEvents = events.take(8).toList(growable: false);
      final sessionSongIds = sessionEvents.map((e) => e.songId).toSet();
      final sessionArtistCounts = <String, int>{};
      var recentRank = 0;

      for (final e in events) {
        plays[e.songId] = (plays[e.songId] ?? 0) + 1;
        if (e.completed) completes[e.songId] = (completes[e.songId] ?? 0) + 1;
        if (e.skipped) skips[e.songId] = (skips[e.songId] ?? 0) + 1;
        final song = byId[e.songId];
        final artist = song?.artist.trim();
        if (artist != null && artist.isNotEmpty) artistAffinity[artist] = (artistAffinity[artist] ?? 0) + (e.completed ? 1 : e.skipped ? -.8 : e.completionRatio * .5);
        final age = now.difference(e.startedAt).inHours;
        if (age < 48 && e.startedAt.hour ~/ 3 == currentHourBucket) songHourAffinity[e.songId] = (songHourAffinity[e.songId] ?? 0) + (e.completed ? 1.0 : e.completionRatio * .5);
        if (recentRank < 12) recentSongIds.add(e.songId);
        recentRank++;
      }

      for (final e in sessionEvents) {
        final artist = byId[e.songId]?.artist.trim().toLowerCase() ?? '';
        if (artist.isNotEmpty) sessionArtistCounts[artist] = (sessionArtistCounts[artist] ?? 0) + 1;
      }
      final sessionCompleted = sessionEvents.where((e) => e.completed).length;
      final sessionSkipped = sessionEvents.where((e) => e.skipped).length;
      _sessionCompletion = sessionEvents.isEmpty ? 0.0 : sessionCompleted / sessionEvents.length;
      _sessionArtists
        ..clear()
        ..addAll(
          (sessionArtistCounts.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value)))
              .map((entry) => entry.key),
        )
        ..removeWhere((artist) => artist.isEmpty);
      if (sessionEvents.isEmpty) {
        _sessionMode = 'Fresh session';
        _sessionSummary = 'Learning the shape of this listening session.';
      } else if (sessionSkipped >= 3 && sessionSkipped > sessionCompleted) {
        _sessionMode = 'Exploring';
        _sessionSummary = 'You are moving through tracks quickly, so I am widening the search without repeating recent choices.';
      } else if (sessionCompleted >= 3 && sessionCompleted >= sessionSkipped + 2) {
        _sessionMode = 'Familiar flow';
        _sessionSummary = 'The session is settling into a strong flow, so I am favoring signals that already work for you.';
      } else {
        _sessionMode = 'Balanced';
        _sessionSummary = 'The session is mixed, so I am balancing familiar picks with a little exploration.';
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
        final sameArtistBoost = current != null && song.artist.trim().isNotEmpty && song.artist.trim().toLowerCase() == current.artist.trim().toLowerCase() ? .75 : 0.0;
        final songArtist = song.artist.trim().toLowerCase();
        final inSession = sessionSongIds.contains(song.id);
        final sessionArtistCount = sessionArtistCounts[songArtist] ?? 0;
        final sessionContinuity = sessionArtistCount > 0 ? sessionArtistCount * .7 : 0.0;
        final explorationBonus = _sessionMode == 'Exploring' && !inSession && !recentSongIds.contains(song.id) ? .9 : 0.0;
        final familiarityBonus = _sessionMode == 'Familiar flow' && (completion >= .65 || feedback > 0) ? .7 : 0.0;
        final sessionFatiguePenalty = sessionArtistCount >= 3 && songArtist.isNotEmpty ? (sessionArtistCount - 2) * .55 : 0.0;
        final score = t * 5.0 + completion * 4.0 + artist * 1.5 + timeAffinity * 1.25 + feedback * 3.0 + sameArtistBoost + sessionContinuity + explorationBonus + familiarityBonus - s * 2.0 - recencyPenalty - sessionFatiguePenalty;
        final evidence = t * 2.0 + completion * 2.0 + artist.abs() + timeAffinity + feedback.abs() + sessionContinuity + (p > 0 ? 1.0 : 0.0);
        final confidence = (evidence / (evidence + 4.0)).clamp(.08, .97).toDouble();

        String reason;
        String sessionReason;
        if (_sessionMode == 'Exploring' && explorationBonus > 0) {
          sessionReason = 'Keeping the session moving with a fresh direction.';
        } else if (_sessionMode == 'Familiar flow' && familiarityBonus > 0) {
          sessionReason = 'Keeping the strong flow you have established.';
        } else if (sessionContinuity > 0) {
          sessionReason = 'Fits the artists showing up in this session.';
        } else {
          sessionReason = 'A measured change of direction for this session.';
        }
        if (feedback >= 1) reason = 'You told me you like this.';
        else if (feedback <= -1) reason = 'Kept low because you previously passed on it.';
        else if (t > 0) reason = 'You often move to this after ${current?.title ?? 'your current track'}.';
        else if (timeAffinity > 0) reason = 'You tend to enjoy this around this time.';
        else if (completion >= .65) reason = 'You tend to finish this one.';
        else if (artist > 0) reason = 'You have been enjoying more from ${song.artist}.';
        else reason = 'A fresh local pick while I learn your pattern.';
        ranked.add(IntelligenceRecommendation(song: song, score: score, confidence: confidence, reason: reason, decision: _autonomy == 2 ? 'autopilot' : _autonomy == 1 ? 'assist' : 'suggest', sessionReason: sessionReason));
      }
      ranked.sort((a, b) => b.score.compareTo(a.score));
      _recommendations = ranked.take(limit).toList(growable: false);
      await _evaluateAutopilotGraduation();
      if (notify) notifyListeners();
    } catch (e) { debugPrint('Intelligence refresh failed: $e'); }
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
      'autopilotGraduated': _autopilotGraduated,
      'sessionMode': _sessionMode,
      'sessionSummary': _sessionSummary,
      'sessionArtists': List<String>.from(_sessionArtists),
    };
  }

  Future<void> recordListeningEvent(ListeningEvent event) async {
    if (!_enabled) return;
    try { await _database.insertListeningEvent(event); } catch (e) { debugPrint('Intelligence event recording failed: $e'); }
  }

  @override
  void dispose() { music.removeListener(_observePlayback); _activeEvent = null; super.dispose(); }
}