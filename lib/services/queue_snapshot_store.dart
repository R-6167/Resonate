import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';

/// Persists the last non-empty queue so the user can restore it later.
class QueueSnapshotStore {
  static const _idsKey = 'last_queue_song_ids';
  static const _indexKey = 'last_queue_index';
  static const _savedAtKey = 'last_queue_saved_at';

  Future<void> save(List<Song> queue, int index) async {
    if (queue.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _idsKey,
        queue.map((s) => s.id).toList(growable: false),
      );
      await prefs.setInt(_indexKey, index.clamp(0, queue.length - 1).toInt());
      await prefs.setString(_savedAtKey, DateTime.now().toIso8601String());
    } catch (_) {}
  }

  Future<({List<String> ids, int index, DateTime? savedAt})?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = prefs.getStringList(_idsKey);
      if (ids == null || ids.isEmpty) return null;
      final index = prefs.getInt(_indexKey) ?? 0;
      final raw = prefs.getString(_savedAtKey);
      final savedAt = raw != null ? DateTime.tryParse(raw) : null;
      return (ids: ids, index: index, savedAt: savedAt);
    } catch (_) {
      return null;
    }
  }

  Future<bool> hasSnapshot() async {
    final snap = await load();
    return snap != null && snap.ids.isNotEmpty;
  }
}
