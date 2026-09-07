import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/intelligence_mix.dart';
import 'database_helper.dart';

/// Measures how a generated mix actually landed using local listening events.
/// It stores bounded metadata only; playback remains owned by MusicProvider.
class IntelligenceMixContinuity {
  static const _key = 'intelligence_mix_continuity_v1';
  static const _maxEntries = 12;
  final DatabaseHelper _database;

  IntelligenceMixContinuity({DatabaseHelper? database}) : _database = database ?? DatabaseHelper();

  Future<Map<String, dynamic>?> evaluate(IntelligenceMix mix) async {
    try {
      final events = await _database.getRecentListeningEvents(limit: 300);
      final ids = mix.songs.map((song) => song.id).toSet();
      final relevant = events
          .where((event) => ids.contains(event.songId) && event.startedAt.isAfter(mix.createdAt))
          .toList()
        ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
      if (relevant.isEmpty) return null;

      final playedIds = <String>{};
      var completed = 0;
      var skipped = 0;
      var completionTotal = 0.0;
      var sequenceHits = 0;
      String? previous;
      for (final event in relevant) {
        playedIds.add(event.songId);
        if (event.completed) completed++;
        if (event.skipped) skipped++;
        completionTotal += event.completionRatio.clamp(0.0, 1.0);
        if (previous != null) {
          final previousIndex = mix.songs.indexWhere((song) => song.id == previous);
          final currentIndex = mix.songs.indexWhere((song) => song.id == event.songId);
          if (previousIndex >= 0 && currentIndex == previousIndex + 1) sequenceHits++;
        }
        previous = event.songId;
      }

      final coverage = (playedIds.length / mix.songs.length.clamp(1, 100000)).clamp(0.0, 1.0).toDouble();
      final completion = (completionTotal / relevant.length).clamp(0.0, 1.0).toDouble();
      final skipRate = (skipped / relevant.length).clamp(0.0, 1.0).toDouble();
      final sequence = relevant.length <= 1 ? coverage : (sequenceHits / (relevant.length - 1)).clamp(0.0, 1.0).toDouble();
      final score = (coverage * .45 + completion * .35 + sequence * .20 - skipRate * .30).clamp(0.0, 1.0).toDouble();

      return {
        'mixId': mix.id,
        'coverage': coverage,
        'completion': completion,
        'skipRate': skipRate,
        'sequence': sequence,
        'score': score,
        'played': playedIds.length,
        'completed': completed,
        'skipped': skipped,
        'updatedAt': DateTime.now().toIso8601String(),
      };
    } catch (_) {
      return null;
    }
  }

  Future<void> remember(Map<String, dynamic> assessment) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getStringList(_key) ?? const <String>[];
      final id = assessment['mixId']?.toString();
      if (id == null || id.isEmpty) return;
      final updated = <String>[
        jsonEncode(assessment),
        ...existing.where((value) {
          try {
            return jsonDecode(value)['mixId']?.toString() != id;
          } catch (_) {
            return true;
          }
        }),
      ];
      await prefs.setStringList(_key, updated.take(_maxEntries).toList());
    } catch (_) {}
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

  Future<double> continuityPrior() async {
    final values = await recent();
    if (values.isEmpty) return .5;
    var weighted = 0.0;
    var weight = 0.0;
    for (var i = 0; i < values.length; i++) {
      final w = 1.0 / (i + 1);
      weighted += ((values[i]['score'] as num?)?.toDouble() ?? .5) * w;
      weight += w;
    }
    return weight == 0 ? .5 : (weighted / weight).clamp(0.0, 1.0).toDouble();
  }

  String explanation(double score) {
    if (score >= .72) return 'You stayed with this mix, so I can carry some of its flow forward.';
    if (score <= .35) return 'This mix did not quite land, so I will avoid leaning on it too heavily.';
    return 'I am still learning how this mix fits your listening.';
  }
}
