import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Per-song / per-artist remembered EQ preset name (local only).
class EqLeanStore {
  static const _songKey = 'eq_lean_song_v1';
  static const _artistKey = 'eq_lean_artist_v1';

  static Future<void> rememberSong(String songId, String preset) async {
    if (songId.isEmpty || preset.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final map = _decode(prefs.getString(_songKey));
    map[songId] = preset;
    await prefs.setString(_songKey, jsonEncode(map));
  }

  static Future<void> rememberArtist(String artist, String preset) async {
    final key = artist.trim().toLowerCase();
    if (key.isEmpty || preset.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final map = _decode(prefs.getString(_artistKey));
    map[key] = preset;
    await prefs.setString(_artistKey, jsonEncode(map));
  }

  static Future<String?> presetFor({required String songId, String? artist}) async {
    final prefs = await SharedPreferences.getInstance();
    final songs = _decode(prefs.getString(_songKey));
    if (songs[songId] is String) return songs[songId] as String;
    final artists = _decode(prefs.getString(_artistKey));
    final a = artist?.trim().toLowerCase() ?? '';
    if (a.isNotEmpty && artists[a] is String) return artists[a] as String;
    return null;
  }

  static Map<String, dynamic> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final m = jsonDecode(raw);
      if (m is Map) return Map<String, dynamic>.from(m);
    } catch (_) {}
    return {};
  }
}
