import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/listening_event.dart';
import '../models/song.dart';

/// Small, local-only memory of when and how the user tends to listen.
///
/// The store intentionally keeps compact aggregates instead of raw listening
/// history. Each weekday/3-hour bucket remembers outcomes, songs, artists and
/// a derived behavioral state. A second compact profile learns recurring
/// behavioral states across contexts and keeps a small amount of momentum so
/// Intelligence can recognize a continuing pattern without copying history.
class IntelligencePatternStore {
  static const _key = 'intelligence_listening_patterns_v1';
  static const _learnedEventsKey = 'intelligence_pattern_learned_events_v1';
  static const _statesKey = 'intelligence_listening_states_v1';
  static const _maxSongsPerBucket = 40;
  static const _maxArtistsPerBucket = 24;
  static const _maxLearnedEventIds = 300;

  static Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  static String bucketKey(DateTime time) => '${time.weekday}_${time.hour ~/ 3}';

  static Future<Map<String, dynamic>> readBucket(DateTime time) async {
    try {
      final prefs = await _prefs();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, dynamic>{};
      final bucket = decoded[bucketKey(time)];
      if (bucket is! Map) return <String, dynamic>{};
      return Map<String, dynamic>.from(bucket);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static String stateFor(Map<String, dynamic> bucket) {
    final events = (bucket['events'] as num?)?.toInt() ?? 0;
    if (events < 3) return 'Learning';
    final completed = (bucket['completed'] as num?)?.toInt() ?? 0;
    final skipped = (bucket['skipped'] as num?)?.toInt() ?? 0;
    final completionRate = completed / events;
    final skipRate = skipped / events;
    if (completionRate >= .72 && completed >= skipped + 2) return 'Familiar flow';
    if (skipRate >= .45 && skipped >= completed) return 'Exploration';
    return 'Balanced';
  }

  static String explanationFor(String state, Map<String, dynamic> bucket) {
    final events = (bucket['events'] as num?)?.toInt() ?? 0;
    if (state == 'Familiar flow') return 'This time window often settles into tracks you finish.';
    if (state == 'Exploration') return 'You tend to move through tracks quickly in this time window.';
    if (state == 'Balanced') return 'This time window usually mixes familiar and fresh choices.';
    return events == 0 ? 'I am still learning this listening window.' : 'I need a few more sessions to recognize this window.';
  }

  /// Returns the learned global behavioral state and confidence. The profile
  /// is intentionally tiny and does not duplicate the listening history.
  static Future<Map<String, dynamic>> readStateProfile() async {
    try {
      final prefs = await _prefs();
      final raw = prefs.getString(_statesKey);
      if (raw == null || raw.isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, dynamic>{};
      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static String globalState(Map<String, dynamic> profile) {
    final total = (profile['total_events'] as num?)?.toInt() ?? 0;
    if (total < 12) return 'Learning';
    final counts = <String, int>{
      'Familiar flow': (profile['familiar'] as num?)?.toInt() ?? 0,
      'Exploration': (profile['exploration'] as num?)?.toInt() ?? 0,
      'Balanced': (profile['balanced'] as num?)?.toInt() ?? 0,
    };
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  static double stateConfidence(Map<String, dynamic> profile) {
    final total = (profile['total_events'] as num?)?.toInt() ?? 0;
    if (total <= 0) return 0.0;
    final state = globalState(profile);
    if (state == 'Learning') return 0.0;
    final key = state == 'Familiar flow' ? 'familiar' : state == 'Exploration' ? 'exploration' : 'balanced';
    final count = (profile[key] as num?)?.toInt() ?? 0;
    return (count / total).clamp(0.0, 1.0).toDouble();
  }

  /// A small measure of whether the most recently learned states are settling
  /// into one mode. It is intentionally capped and only acts as a tie-breaker
  /// in the decision engine.
  static double stateMomentum(Map<String, dynamic> profile) {
    final streak = (profile['streak'] as num?)?.toInt() ?? 0;
    return (streak.clamp(0, 4) / 4.0).toDouble();
  }

  static Future<void> _learnState(String state) async {
    if (state == 'Learning') return;
    try {
      final prefs = await _prefs();
      final raw = prefs.getString(_statesKey);
      final decoded = raw == null || raw.isEmpty ? <String, dynamic>{} : jsonDecode(raw);
      final profile = decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
      final key = state == 'Familiar flow' ? 'familiar' : state == 'Exploration' ? 'exploration' : 'balanced';
      final previousState = profile['last_state']?.toString() ?? '';
      final previousStreak = (profile['streak'] as num?)?.toInt() ?? 0;
      profile['total_events'] = (profile['total_events'] as num? ?? 0).toInt() + 1;
      profile[key] = (profile[key] as num? ?? 0).toInt() + 1;
      profile['last_state'] = state;
      profile['streak'] = previousState == state ? previousStreak + 1 : 1;
      profile['last_learned_at'] = DateTime.now().toIso8601String();
      await prefs.setString(_statesKey, jsonEncode(profile));
    } catch (_) {}
  }

  /// Imports newly finished history rows once. Re-running is safe because
  /// event IDs are remembered locally, preventing pattern inflation.
  static Future<void> learnFromRecentEvents(
    List<ListeningEvent> events,
    Map<String, Song> songsById,
  ) async {
    if (events.isEmpty) return;
    try {
      final prefs = await _prefs();
      final learnedRaw = prefs.getString(_learnedEventsKey);
      final decoded = learnedRaw == null || learnedRaw.isEmpty ? <dynamic>[] : jsonDecode(learnedRaw);
      final learned = decoded is List ? decoded.map((e) => e.toString()).toSet() : <String>{};
      var changed = false;
      for (final event in events.reversed) {
        if (event.endedAt == null || learned.contains(event.id)) continue;
        final song = songsById[event.songId];
        await record(
          time: event.startedAt,
          songId: event.songId,
          artist: song?.artist?.trim().toLowerCase() ?? '',
          completed: event.completed,
          completionRatio: event.completionRatio,
        );
        learned.add(event.id);
        changed = true;
      }
      if (changed) {
        final ids = learned.toList()..sort();
        final trimmed = ids.length > _maxLearnedEventIds ? ids.sublist(ids.length - _maxLearnedEventIds) : ids;
        await prefs.setString(_learnedEventsKey, jsonEncode(trimmed));
      }
    } catch (_) {
      // Pattern memory must never interfere with playback.
    }
  }

  static Future<void> record({
    required DateTime time,
    required String songId,
    required String artist,
    required bool completed,
    required double completionRatio,
  }) async {
    if (songId.trim().isEmpty) return;
    try {
      final prefs = await _prefs();
      final raw = prefs.getString(_key);
      final decoded = raw == null || raw.isEmpty ? <String, dynamic>{} : jsonDecode(raw);
      final root = decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
      final key = bucketKey(time);
      final existing = root[key];
      final bucket = existing is Map ? Map<String, dynamic>.from(existing) : <String, dynamic>{};

      final wasEvents = (bucket['events'] as num? ?? 0).toInt();
      final wasCompleted = (bucket['completed'] as num? ?? 0).toInt();
      final wasSkipped = (bucket['skipped'] as num? ?? 0).toInt();
      bucket['events'] = wasEvents + 1;
      bucket['completed'] = wasCompleted + (completed ? 1 : 0);
      bucket['skipped'] = wasSkipped + (!completed && completionRatio > 0 ? 1 : 0);
      bucket['completion_sum'] = (bucket['completion_sum'] as num? ?? 0).toDouble() + completionRatio;

      final songs = _counts(bucket['songs']);
      songs[songId] = (songs[songId] ?? 0) + (completed ? 2 : 1);
      bucket['songs'] = _trim(songs, _maxSongsPerBucket);

      if (artist.trim().isNotEmpty) {
        final artists = _counts(bucket['artists']);
        artists[artist] = (artists[artist] ?? 0) + (completed ? 2 : 1);
        bucket['artists'] = _trim(artists, _maxArtistsPerBucket);
      }

      root[key] = bucket;
      await prefs.setString(_key, jsonEncode(root));
      final stateBefore = stateFor({
        ...bucket,
        'events': wasEvents,
        'completed': wasCompleted,
        'skipped': wasSkipped,
      });
      final stateAfter = stateFor(bucket);
      if (stateAfter != 'Learning' && stateAfter != stateBefore) await _learnState(stateAfter);
    } catch (_) {
      // Pattern memory must never interfere with playback.
    }
  }

  static Map<String, int> _counts(dynamic value) {
    if (value is! Map) return <String, int>{};
    return value.map((key, item) => MapEntry(key.toString(), (item as num?)?.toInt() ?? 0));
  }

  static Map<String, int> _trim(Map<String, int> values, int limit) {
    final entries = values.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Map<String, int>.fromEntries(entries.take(limit));
  }

  static Future<void> clear() async {
    try {
      final prefs = await _prefs();
      await prefs.remove(_key);
      await prefs.remove(_learnedEventsKey);
      await prefs.remove(_statesKey);
    } catch (_) {}
  }
}
