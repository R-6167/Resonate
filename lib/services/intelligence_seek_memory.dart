import 'package:shared_preferences/shared_preferences.dart';

/// Local-only memory of seek/replay positions. It stores bounded bucket counts,
/// never audio or raw media data.
class IntelligenceSeekMemory {
  static const String _key = 'intelligence_seek_memory_v1';
  static const int _bucketMs = 5 * 60 * 1000;
  static const int _maxEntries = 300;

  Future<void> record({required String songId, required int positionMs}) async {
    if (songId.isEmpty || positionMs < 0) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_key) ?? <String>[];
      final bucket = positionMs ~/ _bucketMs;
      raw.add('$songId|$bucket');
      final start = raw.length > _maxEntries ? raw.length - _maxEntries : 0;
      await prefs.setStringList(_key, raw.sublist(start));
    } catch (_) {
      // Seek memory must never interfere with playback.
    }
  }

  Future<Map<int, int>> countsFor(String songId) async {
    final result = <int, int>{};
    if (songId.isEmpty) return result;
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final value in prefs.getStringList(_key) ?? const <String>[]) {
        final parts = value.split('|');
        if (parts.length != 2 || parts[0] != songId) continue;
        final bucket = int.tryParse(parts[1]);
        if (bucket == null) continue;
        result[bucket] = (result[bucket] ?? 0) + 1;
      }
    } catch (_) {}
    return result;
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}