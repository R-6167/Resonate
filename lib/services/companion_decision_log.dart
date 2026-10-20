import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Bounded local log of Autopilot / Ask Resonate decisions (no audio content).
class CompanionDecisionEntry {
  final DateTime at;
  final String source; // autopilot | ask_resonate | system
  final String action;
  final String detail;
  final String? songId;

  const CompanionDecisionEntry({
    required this.at,
    required this.source,
    required this.action,
    required this.detail,
    this.songId,
  });

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'source': source,
        'action': action,
        'detail': detail,
        'songId': songId,
      };

  factory CompanionDecisionEntry.fromJson(Map<String, dynamic> m) {
    return CompanionDecisionEntry(
      at: DateTime.tryParse(m['at'] as String? ?? '') ?? DateTime.now(),
      source: m['source'] as String? ?? 'system',
      action: m['action'] as String? ?? '',
      detail: m['detail'] as String? ?? '',
      songId: m['songId'] as String?,
    );
  }
}

class CompanionDecisionLog {
  static const _key = 'companion_decision_log_v1';
  static const _max = 40;

  static Future<void> record({
    required String source,
    required String action,
    required String detail,
    String? songId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_key) ?? <String>[];
      final entry = jsonEncode(CompanionDecisionEntry(
        at: DateTime.now(),
        source: source,
        action: action,
        detail: detail,
        songId: songId,
      ).toJson());
      final next = <String>[entry, ...raw];
      await prefs.setStringList(_key, next.take(_max).toList());
    } catch (_) {}
  }

  static Future<List<CompanionDecisionEntry>> recent({int limit = 20}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_key) ?? const <String>[];
      final out = <CompanionDecisionEntry>[];
      for (final line in raw.take(limit)) {
        try {
          final m = jsonDecode(line);
          if (m is Map<String, dynamic>) {
            out.add(CompanionDecisionEntry.fromJson(m));
          } else if (m is Map) {
            out.add(CompanionDecisionEntry.fromJson(Map<String, dynamic>.from(m)));
          }
        } catch (_) {}
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
