import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/media_type.dart';

class MediaClassificationStore {
  static const _key = 'resonate_modes_media_classification_overrides_v1';

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
            v.map((k, value) => MapEntry(k.toString(), value)),
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
      await prefs.setString(
        _key,
        jsonEncode({for (final e in map.entries) e.key: e.value.toJson()}),
      );
    } catch (_) {}
  }

  Future<void> setOverride(String id, MediaType type) async {
    final all = await loadAll();
    all[id] = MediaClassification(
      type: type, confidence: 1.0,
      source: ClassificationSource.user, reason: 'User override',
    );
    await saveAll(all);
  }

  Future<void> clearOverride(String id) async {
    final all = await loadAll();
    all.remove(id);
    await saveAll(all);
  }
}
