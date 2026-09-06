import 'package:shared_preferences/shared_preferences.dart';

/// Local-only memory of seek/replay positions. It stores bounded events,
/// never audio or raw media data.
class IntelligenceSeekMemory {
  static const String _key = 'intelligence_seek_memory_v1';
  static const int _maxEntries = 300;

  Future<void> record({required String songId, required int fromMs, required int toMs}) async {
    if (songId.isEmpty || fromMs < 0 || toMs < 0) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_key) ?? <String>[];
      raw.add('$songId|$fromMs|$toMs');
      final start = raw.length > _maxEntries ? raw.length - _maxEntries : 0;
      await prefs.setStringList(_key, raw.sublist(start));
    } catch (_) {}
  }

  Future<List<Map<String, int>>> forSong(String songId) async {
    final result = <Map<String, int>>[];
    if (songId.isEmpty) return result;
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final value in prefs.getStringList(_key) ?? const <String>[]) {
        final parts = value.split('|');
        if (parts.length != 3 || parts[0] != songId) continue;
        final fromMs = int.tryParse(parts[1]);
        final toMs = int.tryParse(parts[2]);
        if (fromMs == null || toMs == null) continue;
        result.add(<String, int>{'fromMs': fromMs, 'toMs': toMs});
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