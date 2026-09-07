import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

class ResonateDiagnostics {
  static const _eventsKey = 'resonate_diagnostics_events_v2';
  static const _feedbackKey = 'resonate_diagnostics_feedback_v1';
  static const _crashesKey = 'resonate_diagnostics_crashes_v2';
  static const _maxEvents = 600;
  static const _maxCrashes = 50;
  static const _maxFeedback = 50;
  static const _maxStackTraceChars = 12000;
  static const _mediaStoreChannel = MethodChannel('com.example.resonate/media_store');
  static Future<void> _writeSerial = Future<void>.value();

  static Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  static Future<Directory?> _documentsDirectory() async {
    try {
      final directories = await getExternalStorageDirectories(type: StorageDirectory.documents);
      if (directories != null && directories.isNotEmpty) {
        final directory = directories.first;
        await directory.create(recursive: true);
        return directory;
      }
    } catch (_) {}
    try {
      final directory = await getApplicationDocumentsDirectory();
      await directory.create(recursive: true);
      return directory;
    } catch (_) {
      return null;
    }
  }

  static Future<void> record(String type, [Map<String, dynamic> data = const {}]) async {
    _writeSerial = _writeSerial.then((_) async {
      try {
        final prefs = await _prefs();
        final items = _decodeList(prefs.getString(_eventsKey));
        items.add(_entry(type, data));
        if (items.length > _maxEvents) items.removeRange(0, items.length - _maxEvents);
        await prefs.setString(_eventsKey, jsonEncode(items));
      } catch (_) {}
    });
    await _writeSerial;
  }

  static Future<void> recordPlaybackCommand({required String source, required String command, required int generation, Map<String, dynamic> data = const {}}) async {
    await record('playback_command', {'source': source, 'command': command, 'generation': generation, ...data});
  }

  static Future<void> recordCrash(Object error, StackTrace stack, {String source = 'unknown'}) async {
    final stackText = stack.toString();
    final entry = _entry('crash', {
      'source': source,
      'errorType': error.runtimeType.toString(),
      'error': error.toString(),
      'stackTrace': stackText.length > _maxStackTraceChars ? '${stackText.substring(0, _maxStackTraceChars)}\n[stack trace truncated]' : stackText,
    });
    _writeSerial = _writeSerial.then((_) async {
      try {
        final prefs = await _prefs();
        final items = _decodeList(prefs.getString(_crashesKey));
        items.add(entry);
        if (items.length > _maxCrashes) items.removeRange(0, items.length - _maxCrashes);
        await prefs.setString(_crashesKey, jsonEncode(items));
      } catch (_) {}
    });
    await _writeSerial;
    try {
      final directory = await _documentsDirectory();
      if (directory != null) {
        final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
        final file = File('${directory.path}/resonate-crash-$stamp.json');
        await file.writeAsString(const JsonEncoder.withIndent('  ').convert({'reportVersion': 2, 'app': 'Resonate', 'createdAt': DateTime.now().toIso8601String(), ...entry}), flush: true);
      }
    } catch (_) {}
    await record('crash_recorded', {'source': source, 'errorType': error.runtimeType.toString(), 'error': error.toString()});
  }

  static Future<void> recordFeedback({required String category, required String message, bool includeDiagnostics = true}) async {
    _writeSerial = _writeSerial.then((_) async {
      try {
        final prefs = await _prefs();
        final items = _decodeList(prefs.getString(_feedbackKey));
        items.add(_entry('feedback', {'category': category, 'message': message.trim(), 'includeDiagnostics': includeDiagnostics}));
        if (items.length > _maxFeedback) items.removeRange(0, items.length - _maxFeedback);
        await prefs.setString(_feedbackKey, jsonEncode(items));
      } catch (_) {}
    });
    await _writeSerial;
    await record('feedback_submitted', {'category': category, 'includeDiagnostics': includeDiagnostics});
  }

  static Future<Map<String, dynamic>> snapshot() async {
    await _writeSerial;
    final prefs = await _prefs();
    return {
      'reportVersion': 2,
      'createdAt': DateTime.now().toIso8601String(),
      'app': 'Resonate',
      'buildMode': kDebugMode ? 'debug' : kProfileMode ? 'profile' : 'release',
      'platform': Platform.operatingSystem,
      'platformVersion': Platform.operatingSystemVersion,
      'locale': Platform.localeName,
      'isAndroid': Platform.isAndroid,
      'isIOS': Platform.isIOS,
      'events': _decodeList(prefs.getString(_eventsKey)),
      'crashes': _decodeList(prefs.getString(_crashesKey)),
      'feedback': _decodeList(prefs.getString(_feedbackKey)),
    };
  }

  static Future<String> exportReport() async {
    final report = await snapshot();
    final json = const JsonEncoder.withIndent('  ').convert(report);
    final directory = await _documentsDirectory();
    if (directory == null) throw StateError('Could not access a local Documents directory.');
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final fileName = 'resonate-diagnostics-$stamp.json';
    final file = File('${directory.path}/$fileName');
    await file.writeAsString(json, flush: true);
    if (Platform.isAndroid) {
      try {
        final savedUri = await _mediaStoreChannel.invokeMethod<String>('saveDiagnosticReport', {'fileName': fileName, 'bytes': Uint8List.fromList(utf8.encode(json))});
        if (savedUri != null && savedUri.isNotEmpty) {
          await record('report_saved_to_device', {'uri': savedUri, 'path': file.path});
          return savedUri;
        }
      } on PlatformException catch (e) {
        await record('report_device_save_failed', {'code': e.code, 'message': e.message});
      } catch (e) {
        await record('report_device_save_failed', {'error': e.toString()});
      }
    }
    await Share.shareXFiles([XFile(file.path, mimeType: 'application/json')], subject: 'Resonate diagnostic report');
    unawaited(record('report_exported', {'eventCount': (report['events'] as List).length, 'crashCount': (report['crashes'] as List).length, 'feedbackCount': (report['feedback'] as List).length, 'path': file.path}));
    return file.path;
  }

  static Future<void> clearDiagnostics() async {
    await _writeSerial;
    final prefs = await _prefs();
    await prefs.remove(_eventsKey);
    await prefs.remove(_crashesKey);
    await prefs.remove(_feedbackKey);
  }

  static Future<int> eventCount() async { final report = await snapshot(); return (report['events'] as List).length; }
  static Future<int> crashCount() async { final report = await snapshot(); return (report['crashes'] as List).length; }
  static Future<int> feedbackCount() async { final report = await snapshot(); return (report['feedback'] as List).length; }

  static Map<String, dynamic> _entry(String type, Map<String, dynamic> data) => {'at': DateTime.now().toIso8601String(), 'type': type, 'data': data};

  static List<Map<String, dynamic>> _decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
    } catch (_) { return <Map<String, dynamic>>[]; }
  }
}
