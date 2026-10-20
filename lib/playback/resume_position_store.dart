import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-song and last-session resume positions.
///
/// Extracted from [MusicProvider] so queue/transport code does not own prefs
/// keys or the JSON map. Callers still supply the *computed* millisecond
/// position (they know currentPosition / duration); this type stores, loads,
/// and looks up values.
class ResumePositionStore {
  static const positionKey = 'playback_resume_position_ms';
  static const songIdKey = 'playback_resume_song_id';
  static const mapKey = 'playback_resume_map_v1';

  /// Ignore positions shorter than this (false starts / buffering).
  static const minUsefulMs = 1500;

  /// Treat within this many ms of duration as finished (clear entry).
  static const nearEndMs = 2000;

  /// Throttle interval for non-forced persists.
  static const throttle = Duration(seconds: 3);

  final Map<String, int> bySongId = {};
  int lastPositionMs = 0;
  String? lastSongId;
  DateTime? lastPersistAt;

  /// Position to resume [songId], if useful.
  int? positionFor(String songId) {
    final mapped = bySongId[songId];
    if (mapped != null && mapped > minUsefulMs) return mapped;
    if (lastSongId == songId && lastPositionMs > minUsefulMs) {
      return lastPositionMs;
    }
    return null;
  }

  /// Whether last-session resume should apply to [songId] given [durationMs].
  bool shouldResumeLast(String songId, {int durationMs = 0}) {
    if (lastSongId != songId) return false;
    if (lastPositionMs < minUsefulMs) return false;
    if (durationMs > 0 && lastPositionMs >= durationMs - nearEndMs) {
      return false;
    }
    return true;
  }

  void clearSong(String songId) {
    bySongId.remove(songId);
    if (lastSongId == songId) {
      lastSongId = null;
      lastPositionMs = 0;
    }
  }

  /// Record a position for [songId]. If [durationMs] is known and the position
  /// is near the end, the entry is cleared instead.
  ///
  /// Returns whether a write to prefs should be scheduled.
  bool record({
    required String songId,
    required int positionMs,
    int durationMs = 0,
    bool force = false,
  }) {
    final now = DateTime.now();
    if (!force &&
        lastPersistAt != null &&
        now.difference(lastPersistAt!) < throttle) {
      return false;
    }
    lastPersistAt = now;

    final position = (durationMs > 0
            ? positionMs.clamp(0, durationMs)
            : positionMs)
        .toInt();

    if (!force && position < minUsefulMs) return false;

    if (durationMs > 0 && position >= durationMs - nearEndMs) {
      clearSong(songId);
      return true;
    }

    lastPositionMs = position;
    lastSongId = songId;
    bySongId[songId] = position;
    return true;
  }

  Future<void> load(SharedPreferences prefs) async {
    lastPositionMs = prefs.getInt(positionKey) ?? 0;
    lastSongId = prefs.getString(songIdKey);
    await loadMap(prefs);
  }

  Future<void> loadMap(SharedPreferences prefs) async {
    try {
      final raw = prefs.getString(mapKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      bySongId
        ..clear()
        ..addAll({
          for (final e in decoded.entries)
            if (e.key is String && e.value is num)
              e.key as String: (e.value as num).toInt(),
        });
    } catch (e) {
      debugPrint('Resume map load failed: $e');
    }
  }

  Future<void> persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (lastSongId != null) {
        await prefs.setInt(positionKey, lastPositionMs);
        await prefs.setString(songIdKey, lastSongId!);
      }
      await prefs.setString(mapKey, jsonEncode(bySongId));
    } catch (e) {
      debugPrint('Playback resume save failed: $e');
    }
  }

  Future<void> persistMapOnly() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(mapKey, jsonEncode(bySongId));
    } catch (_) {}
  }
}
