import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Tiny local memory of meaningful manual seeks. It stores only song id and
/// playback positions; it never stores audio or personal data.
class IntelligenceSeekMemory {
  static const _key = 'intelligence_seek_memory_v1';
  static const _maxEntries = 240;

  Future<void> record({required String songId, required int fromMs, required int toMs}) async {
    if (songId.isEmpty || fromMs < 0 || toMs < 0 || (fromMs - toMs).abs() < 5000) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getStringList(_key) ?? const <String>[];
      final entry = jsonEncode({
        'songId': songId,
        'fromMs': fromMs,
        'toMs': toMs,
        'at': DateTime.now().toIso8601String(),
      });
      await prefs.setStringList(_key, [entry, ...existing].take(_maxEntries).toList());
    } catch (_) {
      // Seek memory is optional and must never affect playback.
    }
  }

  Future<List<Map<String, dynamic>>> forSong(String songId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_key) ?? const <String>[]).map((value) {
        try {
          final decoded = jsonDecode(value);
          return decoded is Map<String, dynamic> ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
        } catch (_) {
          return <String, dynamic>{};
        }
      }).where((item) => item['songId']?.toString() == songId).toList(growable: false);
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
