import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';

/// Owns the play-queue list, current index, shuffle flag, and ID persistence.
///
/// Extracted from [MusicProvider] (first structural split). Playback transport,
/// engines, and UI notification stay on the provider; this type is the single
/// source of truth for queue contents and index.
class QueueStore {
  static const savedQueueIdsKey = 'playback_queue_song_ids';
  static const savedQueueIndexKey = 'playback_queue_index';
  static const shuffleEnabledKey = 'playback_shuffle_enabled';

  List<Song> _songs = <Song>[];
  int _index = 0;
  bool shuffleEnabled = false;
  bool restoreInProgress = false;

  /// Live list used by the playback coordinator. Prefer [replace] / mutators
  /// when replacing the whole queue; direct mutation is allowed for in-place
  /// edits that already existed on MusicProvider.
  List<Song> get songs => _songs;

  int get index => _index;

  set index(int value) {
    if (_songs.isEmpty) {
      _index = 0;
      return;
    }
    _index = value.clamp(0, _songs.length - 1).toInt();
  }

  int get length => _songs.length;

  bool get isEmpty => _songs.isEmpty;

  bool get isNotEmpty => _songs.isNotEmpty;

  Song? get current {
    if (_songs.isEmpty || _index < 0 || _index >= _songs.length) return null;
    return _songs[_index];
  }

  List<Song> get upcoming {
    if (_songs.isEmpty || _index >= _songs.length - 1) return const <Song>[];
    return List<Song>.unmodifiable(_songs.skip(_index + 1));
  }

  List<Song> get unmodifiable => List<Song>.unmodifiable(_songs);

  /// Replace the entire queue and clamp [index].
  void replace(List<Song> songs, {int index = 0}) {
    _songs = List<Song>.from(songs);
    if (_songs.isEmpty) {
      _index = 0;
    } else {
      _index = index.clamp(0, _songs.length - 1).toInt();
    }
  }

  void clear() {
    _songs = <Song>[];
    _index = 0;
  }

  void append(List<Song> additions) {
    if (additions.isEmpty) return;
    _songs = [..._songs, ...additions];
  }

  void insertAt(int at, Song song) {
    final insertAt = at.clamp(0, _songs.length).toInt();
    _songs = [..._songs]..insert(insertAt, song);
  }

  /// Removes a non-current entry. Returns false if [index] is invalid or is
  /// the current index (same rule as MusicProvider.removeFromQueue).
  bool removeAt(int index) {
    if (index < 0 || index >= _songs.length || index == _index) return false;
    _songs = [..._songs]..removeAt(index);
    if (index < _index) _index -= 1;
    return true;
  }

  /// Reorder only among upcoming items (indices strictly after current).
  bool reorderUpcoming(int oldIndex, int newIndex) {
    if (oldIndex <= _index || oldIndex >= _songs.length) return false;
    var target = newIndex;
    if (target > oldIndex) target--;
    target = target.clamp(_index + 1, _songs.length - 1).toInt();
    final next = [..._songs];
    final item = next.removeAt(oldIndex);
    next.insert(target, item);
    _songs = next;
    return true;
  }

  void clearUpcoming() {
    if (_index >= _songs.length - 1) return;
    _songs = [..._songs.take(_index + 1)];
  }

  /// Shuffle only the tail after the current index; keep current pinned.
  void shuffleUpcoming([math.Random? random]) {
    if (_songs.length <= 1 || _index >= _songs.length - 1) return;
    final current = _songs[_index];
    final upcoming = _songs.sublist(_index + 1)..shuffle(random ?? math.Random());
    _songs = [..._songs.take(_index + 1), ...upcoming];
    _index = _songs.indexWhere((song) => song.id == current.id);
    if (_index < 0) _index = 0;
  }

  bool containsId(String id) => _songs.any((q) => q.id == id);

  Future<void> persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_songs.isEmpty) {
        await prefs.remove(savedQueueIdsKey);
        await prefs.remove(savedQueueIndexKey);
      } else {
        await prefs.setStringList(
          savedQueueIdsKey,
          _songs.map((song) => song.id).toList(),
        );
        await prefs.setInt(savedQueueIndexKey, _index);
      }
    } catch (e) {
      debugPrint('Playback queue persistence failed: $e');
    }
  }

  Future<void> persistShuffleFlag() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(shuffleEnabledKey, shuffleEnabled);
    } catch (e) {
      debugPrint('Playback shuffle save failed: $e');
    }
  }

  Future<void> loadShuffleFlag() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      shuffleEnabled = prefs.getBool(shuffleEnabledKey) ?? false;
    } catch (e) {
      debugPrint('Playback shuffle load failed: $e');
    }
  }

  /// Loads persisted song ids + index. Does not resolve [Song] objects —
  /// the coordinator maps ids through the library / visibility filter.
  Future<({List<String> ids, int index})?> loadPersistedIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = prefs.getStringList(savedQueueIdsKey) ?? const <String>[];
      if (ids.isEmpty) return null;
      final savedIndex = prefs.getInt(savedQueueIndexKey) ?? 0;
      return (ids: ids, index: savedIndex);
    } catch (e) {
      debugPrint('Playback queue id load failed: $e');
      return null;
    }
  }
}
