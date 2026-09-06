import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

/// Privacy-first local diagnostics for development and real-device testing.
/// Crash capture is mandatory for the current development build. Nothing is
/// uploaded automatically; the user exports a report when they choose.
class ResonateDiagnostics {
  static const _eventsKey = 'resonate_diagnostics_events_v1';
  static const _feedbackKey = 'resonate_diagnostics_feedback_v1';
  static const _crashesKey = 'resonate_diagnostics_crashes_v1';
  static const _maxEvents = 250;
  static const _maxCrashes = 25;
  static const _maxFeedback = 50;

  static Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  static Future<void> record(String type, [Map<String, dynamic> data = const {}]) async {
    try {
      final prefs = await _prefs();
      final items = _decodeList(prefs.getString(_eventsKey));
      items.add(_entry(type, data));
      if (items.length > _maxEvents) items.removeRange(0, items.length - _maxEvents);
      await prefs.setString(_eventsKey, jsonEncode(items));
    } catch (_) {}
  }

  static Future<void> recordCrash(Object error, StackTrace stack, {String source = 'unknown'}) async {
    try {
      final prefs = await _prefs();
      final items = _decodeList(prefs.getString(_crashesKey));
      items.add(_entry('crash', {
        'source': source,
        'error': error.toString(),
        'stackTrace': stack.toString(),
      }));
      if (items.length > _maxCrashes) items.removeRange(0, items.length - _maxCrashes);
      await prefs.setString(_crashesKey, jsonEncode(items));
      await record('crash_recorded', {'source': source, 'error': error.toString()});
    } catch (_) {}
  }

  static Future<void> recordFeedback({required String category, required String message, bool includeDiagnostics = true}) async {
    try {
      final prefs = await _prefs();
      final items = _decodeList(prefs.getString(_feedbackKey));
      items.add(_entry('feedback', {
        'category': category,
        'message': message.trim(),
        'includeDiagnostics': includeDiagnostics,
      }));
      if (items.length > _maxFeedback) items.removeRange(0, items.length - _maxFeedback);
      await prefs.setString(_feedbackKey, jsonEncode(items));
      await record('feedback_submitted', {'category': category, 'includeDiagnostics': includeDiagnostics});
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> snapshot() async {
    final prefs = await _prefs();
    return {
      'reportVersion': 1,
      'createdAt': DateTime.now().toIso8601String(),
      'app': 'Resonate',
      'buildMode': kDebugMode ? 'debug' : kProfileMode ? 'profile' : 'release',
      'platform': Platform.operatingSystem,
      'platformVersion': Platform.operatingSystemVersion,
      'events': _decodeList(prefs.getString(_eventsKey)),
      'crashes': _decodeList(prefs.getString(_crashesKey)),
      'feedback': _decodeList(prefs.getString(_feedbackKey)),
    };
  }

  static Future<String> exportReport() async {
    final report = await snapshot();
    final directory = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = File('${directory.path}/resonate-diagnostics-$stamp.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(report), flush: true);
    await Share.shareXFiles([XFile(file.path)], subject: 'Resonate diagnostic report');
    unawaited(record('report_exported', {'eventCount': (report['events'] as List).length, 'crashCount': (report['crashes'] as List).length}));
    return file.path;
  }

  static Future<void> clearDiagnostics() async {
    final prefs = await _prefs();
    await prefs.remove(_eventsKey);
    await prefs.remove(_crashesKey);
    await prefs.remove(_feedbackKey);
  }

  static Future<int> eventCount() async => (await snapshot())['events'] is List ? ((await snapshot())['events'] as List).length : 0;
  static Future<int> crashCount() async => (await snapshot())['crashes'] is List ? ((await snapshot())['crashes'] as List).length : 0;
  static Future<int> feedbackCount() async => (await snapshot())['feedback'] is List ? ((await snapshot())['feedback'] as List).length : 0;

  static Map<String, dynamic> _entry(String type, Map<String, dynamic> data) => {
        'at': DateTime.now().toIso8601String(),
        'type': type,
        'data': data,
      };

  static List<Map<String, dynamic>> _decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }
}
