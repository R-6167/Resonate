import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/intelligence_mix.dart';

/// Small local memory for generated mixes. It stores only mix metadata and
/// song ids, never audio bytes or external analytics.
class IntelligenceMixMemory {
  static const _key = 'intelligence_generated_mix_memory_v1';
  static const _maxMixes = 12;

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
      });
      final updated = <String>[entry, ...existing.where((item) => item != entry)];
      await prefs.setStringList(_key, updated.take(_maxMixes).toList());
    } catch (_) {
      // Mix memory is optional; it must never affect playback.
    }
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

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
