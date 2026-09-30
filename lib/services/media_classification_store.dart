import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/media_type.dart';

/// Persists user media-type overrides (never lost under automatic reclassify).
class MediaClassificationStore {
  static const _key = 'media_classification_user_overrides_v1';

  Future<Map<String, MediaClassification>> loadAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <String, MediaClassification>{};
      for (final e in decoded.entries) {
        final v = e.value;
        if (v is Map) {
          out[e.key.toString()] = MediaClassification.fromJson(
            v.map((k, val) => MapEntry(k.toString(), val)),
          );
        }
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<void> saveAll(Map<String, MediaClassification> map) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = {
        for (final e in map.entries) e.key: e.value.toJson(),
      };
      await prefs.setString(_key, jsonEncode(encoded));
    } catch (_) {}
  }

  Future<void> setOverride(String songId, MediaType type) async {
    final all = await loadAll();
    all[songId] = MediaClassification(
      type: type,
      confidence: 1.0,
      source: ClassificationSource.user,
      reason: 'User override',
    );
    await saveAll(all);
  }

  Future<void> clearOverride(String songId) async {
    final all = await loadAll();
    all.remove(songId);
    await saveAll(all);
  }
}
