import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight on-device memory of DJ transition outcomes.
///
/// Used to learn which strategies felt good (full listen) vs bad (early skip).
/// Never blocks playback; failures are swallowed.
class DjTransitionMemory {
  static const _key = 'dj_transition_memory_v1';
  static const _maxPairs = 400;

  /// Soft score in roughly [-1, 1]. Positive = more completes than early skips.
  static Future<double> pairBias(String fromId, String toId) async {
    try {
      final map = await _load();
      final row = map[_pairKey(fromId, toId)];
      if (row == null) return 0.0;
      final ok = (row['ok'] as num?)?.toInt() ?? 0;
      final bad = (row['bad'] as num?)?.toInt() ?? 0;
      final total = ok + bad;
      if (total <= 0) return 0.0;
      return ((ok - bad) / total).clamp(-1.0, 1.0);
    } catch (_) {
      return 0.0;
    }
  }

  static Future<double> strategyBias(String strategy) async {
    try {
      final map = await _load();
      var ok = 0;
      var bad = 0;
      for (final row in map.values) {
        if (row['strategy']?.toString() != strategy) continue;
        ok += (row['ok'] as num?)?.toInt() ?? 0;
        bad += (row['bad'] as num?)?.toInt() ?? 0;
      }
      final total = ok + bad;
      if (total <= 0) return 0.0;
      return ((ok - bad) / total).clamp(-1.0, 1.0);
    } catch (_) {
      return 0.0;
    }
  }

  static Future<void> recordOutcome({
    required String fromId,
    required String toId,
    required String strategy,
    required bool successful,
    int weight = 1,
  }) async {
    if (fromId.isEmpty || toId.isEmpty) return;
    final w = weight.clamp(1, 5);
    try {
      final map = await _load();
      final key = _pairKey(fromId, toId);
      final row = Map<String, dynamic>.from(map[key] ?? <String, dynamic>{});
      row['strategy'] = strategy;
      if (successful) {
        row['ok'] = ((row['ok'] as num?)?.toInt() ?? 0) + w;
      } else {
        row['bad'] = ((row['bad'] as num?)?.toInt() ?? 0) + w;
      }
      row['updatedAt'] = DateTime.now().toIso8601String();
      map[key] = row;
      while (map.length > _maxPairs) {
        String? oldestKey;
        DateTime? oldest;
        for (final e in map.entries) {
          final t = DateTime.tryParse(e.value['updatedAt']?.toString() ?? '');
          if (t == null) {
            oldestKey = e.key;
            break;
          }
          if (oldest == null || t.isBefore(oldest)) {
            oldest = t;
            oldestKey = e.key;
          }
        }
        if (oldestKey == null) break;
        map.remove(oldestKey);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(map));
    } catch (_) {}
  }

  static String _pairKey(String fromId, String toId) => '$fromId>$toId';

  static Future<Map<String, Map<String, dynamic>>> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <String, Map<String, dynamic>>{};
      decoded.forEach((k, v) {
        if (v is Map) {
          out[k.toString()] = Map<String, dynamic>.from(v);
        }
      });
      return out;
    } catch (_) {
      return {};
    }
  }
}
