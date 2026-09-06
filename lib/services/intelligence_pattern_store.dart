import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Small, local-only memory of when and how the user tends to listen.
///
/// The store intentionally keeps aggregates instead of raw listening history:
/// each weekday/3-hour bucket remembers song outcomes and artist affinity.
/// This lets Intelligence recognize recurring listening contexts after the
/// current session has ended without introducing a remote service or model.
class IntelligencePatternStore {
  static const _key = 'intelligence_listening_patterns_v1';
  static const _maxSongsPerBucket = 40;
  static const _maxArtistsPerBucket = 24;

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

      bucket['events'] = (bucket['events'] as num? ?? 0).toInt() + 1;
      bucket['completed'] = (bucket['completed'] as num? ?? 0).toInt() + (completed ? 1 : 0);
      bucket['skipped'] = (bucket['skipped'] as num? ?? 0).toInt() + (!completed && completionRatio > 0 ? 1 : 0);
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
      await (await _prefs()).remove(_key);
    } catch (_) {}
  }
}
