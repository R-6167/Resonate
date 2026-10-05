import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Local-only memory of DJ transition outcomes.
///
/// V2 keeps outcomes at both pair and pair+strategy level. This matters because
/// the same two tracks may be fine with a phrase blend but poor with beat blend.
/// Learning never blocks playback; storage failures are swallowed.
class DjTransitionMemory {
  static const _key = 'dj_transition_memory_v2';
  static const _legacyKey = 'dj_transition_memory_v1';
  static const _maxPairs = 400;

  /// Aggregate pair score in roughly [-1, 1].
  static Future<double> pairBias(String fromId, String toId) async {
    try {
      final row = (await _load())[_pairKey(fromId, toId)];
      if (row == null) return 0.0;

      final strategies = _strategyRows(row);
      if (strategies.isNotEmpty) {
        var ok = 0;
        var bad = 0;
        for (final strategy in strategies.values) {
          ok += _count(strategy['ok']);
          bad += _count(strategy['bad']);
        }
        return _bias(ok, bad);
      }

      return _bias(_count(row['ok']), _count(row['bad']));
    } catch (_) {
      return 0.0;
    }
  }

  /// Score for one pair under one specific strategy.
  static Future<double> pairStrategyBias(
    String fromId,
    String toId,
    String strategy,
  ) async {
    if (fromId.isEmpty || toId.isEmpty || strategy.isEmpty) return 0.0;
    try {
      final row = (await _load())[_pairKey(fromId, toId)];
      if (row == null) return 0.0;
      final strategyRow = _strategyRows(row)[strategy];
      if (strategyRow == null) return 0.0;
      return _bias(_count(strategyRow['ok']), _count(strategyRow['bad']));
    } catch (_) {
      return 0.0;
    }
  }

  /// Global strategy score in roughly [-1, 1].
  static Future<double> strategyBias(String strategy) async {
    if (strategy.isEmpty) return 0.0;
    try {
      final map = await _load();
      var ok = 0;
      var bad = 0;
      for (final row in map.values) {
        final strategyRow = _strategyRows(row)[strategy];
        if (strategyRow != null) {
          ok += _count(strategyRow['ok']);
          bad += _count(strategyRow['bad']);
        } else if (row['strategy']?.toString() == strategy) {
          // Read legacy v1 rows during migration.
          ok += _count(row['ok']);
          bad += _count(row['bad']);
        }
      }
      return _bias(ok, bad);
    } catch (_) {
      return 0.0;
    }
  }

  /// Records an outcome for a pair and a specific transition strategy.
  static Future<void> recordOutcome({
    required String fromId,
    required String toId,
    required String strategy,
    required bool successful,
    int weight = 1,
  }) async {
    if (fromId.isEmpty || toId.isEmpty || strategy.isEmpty) return;
    final w = weight.clamp(1, 5);
    try {
      final map = await _load();
      final key = _pairKey(fromId, toId);
      final row = Map<String, dynamic>.from(
        map[key] ?? <String, dynamic>{},
      );
      final strategies = _strategyRows(row);
      final strategyRow = Map<String, dynamic>.from(
        strategies[strategy] ?? <String, dynamic>{},
      );

      if (successful) {
        strategyRow['ok'] = _count(strategyRow['ok']) + w;
      } else {
        strategyRow['bad'] = _count(strategyRow['bad']) + w;
      }
      strategyRow['updatedAt'] = DateTime.now().toIso8601String();
      strategies[strategy] = strategyRow;

      // Keep pair-level totals for compact aggregate learning/diagnostics.
      if (successful) {
        row['ok'] = _count(row['ok']) + w;
      } else {
        row['bad'] = _count(row['bad']) + w;
      }
      row['strategies'] = strategies;
      row['updatedAt'] = strategyRow['updatedAt'];
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

  static int _count(dynamic value) => value is num ? value.toInt() : 0;

  static double _bias(int ok, int bad) {
    final total = ok + bad;
    if (total <= 0) return 0.0;
    return ((ok - bad) / total).clamp(-1.0, 1.0);
  }

  static String _pairKey(String fromId, String toId) => '$fromId>$toId';

  static Map<String, Map<String, dynamic>> _strategyRows(
    Map<String, dynamic> row,
  ) {
    final raw = row['strategies'];
    if (raw is! Map) return <String, Map<String, dynamic>>{};
    final out = <String, Map<String, dynamic>>{};
    raw.forEach((key, value) {
      if (value is Map) {
        out[key.toString()] = Map<String, dynamic>.from(value);
      }
    });
    return out;
  }

  static Future<Map<String, Map<String, dynamic>>> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var raw = prefs.getString(_key);

      // One-time, lossless migration of the old pair rows. The legacy row is
      // retained under a neutral strategy so existing learning still counts.
      if (raw == null || raw.isEmpty) {
        final legacy = prefs.getString(_legacyKey);
        if (legacy != null && legacy.isNotEmpty) {
          final migrated = _decode(legacy);
          if (migrated.isNotEmpty) {
            final map = <String, Map<String, dynamic>>{};
            for (final entry in migrated.entries) {
              final row = Map<String, dynamic>.from(entry.value);
              final legacyStrategy = row['strategy']?.toString();
              if (legacyStrategy != null && legacyStrategy.isNotEmpty) {
                row['strategies'] = {
                  legacyStrategy: {
                    'ok': _count(row['ok']),
                    'bad': _count(row['bad']),
                    'updatedAt': row['updatedAt'],
                  },
                };
              }
              map[entry.key] = row;
            }
            await prefs.setString(_key, jsonEncode(map));
            raw = jsonEncode(map);
          }
        }
      }

      if (raw == null || raw.isEmpty) return {};
      return _decode(raw);
    } catch (_) {
      return {};
    }
  }

  static Map<String, Map<String, dynamic>> _decode(String raw) {
    try {
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
