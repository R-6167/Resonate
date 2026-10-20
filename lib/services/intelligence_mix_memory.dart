import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/intelligence_mix.dart';

/// Small local memory for generated mixes. Metadata only — never audio bytes.
class IntelligenceMixMemory {
  static const _key = 'intelligence_generated_mix_memory_v1';
  static const _maxMixes = 16;

  Future<void> remember(IntelligenceMix mix) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getStringList(_key) ?? <String>[];
      final entry = jsonEncode({
        'id': mix.id,
        'title': mix.title,
        'description': mix.description,
        'reason': mix.reason,
        'targetMinutes': mix.targetDuration.inMinutes,
        'createdAt': mix.createdAt.toIso8601String(),
        'songIds': mix.songs.map((song) => song.id).toList(),
        'parentMixId': mix.parentMixId,
        'edition': mix.edition,
        'previousContinuityScore': mix.previousContinuityScore,
        'artistHints': mix.songs.map((s) => s.artist).toSet().take(4).toList(),
      });
      final updated = <String>[
        entry,
        ...existing.where((item) {
          try {
            final m = jsonDecode(item);
            return m is Map && m['id'] != mix.id;
          } catch (_) {
            return true;
          }
        }),
      ];
      await prefs.setStringList(_key, updated.take(_maxMixes).toList());
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> recent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final values = prefs.getStringList(_key) ?? const <String>[];
      return values.map((value) {
        try {
          final decoded = jsonDecode(value);
          return decoded is Map<String, dynamic>
              ? Map<String, dynamic>.from(decoded)
              : <String, dynamic>{};
        } catch (_) {
          return <String, dynamic>{};
        }
      }).where((item) => item.isNotEmpty).toList(growable: false);
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  /// Walk parentMixId chain for the journey surface (newest first).
  Future<List<Map<String, dynamic>>> lineageFor(String? mixId) async {
    if (mixId == null || mixId.isEmpty) return const [];
    final all = await recent();
    final byId = <String, Map<String, dynamic>>{
      for (final m in all)
        if (m['id'] is String) m['id'] as String: m,
    };
    final chain = <Map<String, dynamic>>[];
    var current = byId[mixId];
    final seen = <String>{};
    while (current != null) {
      final id = current['id'] as String?;
      if (id == null || !seen.add(id)) break;
      chain.add(current);
      final parent = current['parentMixId'] as String?;
      current = parent == null ? null : byId[parent];
    }
    return chain;
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
