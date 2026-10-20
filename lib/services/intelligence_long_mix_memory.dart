import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/intelligence_mix.dart';

/// Bounded local memory of long-form listening signals.
/// Stores section-level metadata only; never stores audio or raw media.
class IntelligenceLongMixMemory {
  static const _key = 'intelligence_long_mix_memory_v1';
  static const _maxEntries = 16;

  Future<void> remember(IntelligenceMixAnalysis analysis) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final entry = jsonEncode({
        'songId': analysis.source.id,
        'observations': analysis.observations,
        'averageCompletion': analysis.averageCompletion,
        'preferredCoverage': analysis.preferredCoverage,
        'commonExitMs': analysis.commonExitPoint?.inMilliseconds,
        'replayEvents': analysis.replayEvents,
        'replayedSegments': analysis.replayedSegments,
        'preferredSegments': analysis.preferredSegments.map((segment) => {
          'startMs': segment.startMs,
          'endMs': segment.endMs,
          'preference': segment.preference,
          'replayCount': segment.replayCount,
        }).toList(),
        'updatedAt': DateTime.now().toIso8601String(),
      });
      final existing = prefs.getStringList(_key) ?? <String>[];
      final updated = <String>[entry, ...existing.where((value) {
        try {
          return jsonDecode(value)['songId']?.toString() != analysis.source.id;
        } catch (_) {
          return true;
        }
      })];
      await prefs.setStringList(_key, updated.take(_maxEntries).toList());
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> forSong(String songId) async {
    if (songId.isEmpty) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final value in prefs.getStringList(_key) ?? const <String>[]) {
        final decoded = jsonDecode(value);
        if (decoded is Map && decoded['songId']?.toString() == songId) {
          return Map<String, dynamic>.from(decoded);
        }
      }
    } catch (_) {}
    return null;
  }

  Future<List<Map<String, dynamic>>> recent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_key) ?? const <String>[]).map((value) {
        try {
          final decoded = jsonDecode(value);
          return decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
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
