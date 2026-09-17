import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local-only flight recorder for Resonate.
///
/// Diagnostics must never be on the critical playback path. Recording is
/// serialized and failures are swallowed so telemetry can never stop music.
class ResonateDiagnostics {
  static const _eventsKey = 'resonate_diagnostics_events_v3';
  static const _feedbackKey = 'resonate_diagnostics_feedback_v2';
  static const _crashesKey = 'resonate_diagnostics_crashes_v3';
  static const _sessionKey = 'resonate_diagnostics_session_id';
  static const _sequenceKey = 'resonate_diagnostics_sequence';
  static const _maxEvents = 4000;
  static const _maxCrashes = 100;
  static const _maxFeedback = 100;
  static const _maxStackTraceChars = 24000;
  static const _maxValueChars = 4000;
  static const _mediaStoreChannel = MethodChannel('com.example.resonate/media_store');
  static Future<void> _writeSerial = Future<void>.value();
  static String? _sessionId;
  static int _sequence = 0;
  static final List<Map<String, dynamic>> _pendingEvents = <Map<String, dynamic>>[];
  static Timer? _flushTimer;
  static Future<void> _flushInFlight = Future<void>.value();

  static Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  static Future<String> _getSessionId() async {
    if (_sessionId != null) return _sessionId!;
    try {
      final prefs = await _prefs();
      _sessionId = prefs.getString(_sessionKey);
      if (_sessionId == null || _sessionId!.isEmpty) {
        _sessionId = '${DateTime.now().microsecondsSinceEpoch}_${Platform.operatingSystem}';
        await prefs.setString(_sessionKey, _sessionId!);
      }
    } catch (_) {
      _sessionId ??= '${DateTime.now().microsecondsSinceEpoch}_fallback';
    }
    return _sessionId!;
  }

  static Future<int> _nextSequence() async {
    _sequence += 1;
    if (_sequence < 2) {
      try {
        final prefs = await _prefs();
        _sequence = prefs.getInt(_sequenceKey) ?? _sequence;
      } catch (_) {}
    }
    try {
      final prefs = await _prefs();
      await prefs.setInt(_sequenceKey, _sequence);
    } catch (_) {}
    return _sequence;
  }

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
    try {
      final entry = await _entry(type, data);
      _pendingEvents.add(entry);
      _flushTimer ??= Timer.periodic(const Duration(milliseconds: 750), (_) => unawaited(_flushPendingEvents()));
      if (_pendingEvents.length >= 32) await _flushPendingEvents();
    } catch (_) {}
  }

  static Future<void> _flushPendingEvents() async {
    if (_pendingEvents.isEmpty) return;
    _flushInFlight = _flushInFlight.then((_) async {
      if (_pendingEvents.isEmpty) return;
      try {
        final batch = List<Map<String, dynamic>>.from(_pendingEvents);
        _pendingEvents.clear();
        final prefs = await _prefs();
        final items = _decodeList(prefs.getString(_eventsKey));
        items.addAll(batch);
        if (items.length > _maxEvents) items.removeRange(0, items.length - _maxEvents);
        await prefs.setString(_eventsKey, jsonEncode(items));
      } catch (_) {}
    });
    await _flushInFlight;
  }

  /// High-value playback checkpoint. Call this at commands, state changes,
  /// source-load boundaries, completion, queue changes and interruptions.
  static Future<void> recordPlaybackCheckpoint({
    required String stage,
    String? command,
    String? source,
    String? songId,
    String? songTitle,
    int? positionMs,
    int? durationMs,
    bool? playing,
    String? processingState,
    int? queueIndex,
    int? queueLength,
    int? upcomingCount,
    bool? shuffle,
    String? repeatMode,
    bool? crossfadeEnabled,
    bool? transitionInProgress,
    String? engine,
    int? intentToken,
    Map<String, dynamic> extra = const {},
  }) async {
    await record('playback_checkpoint', {
      'stage': stage,
      if (command != null) 'command': command,
      if (source != null) 'source': source,
      if (songId != null) 'songId': songId,
      if (songTitle != null) 'songTitle': songTitle,
      if (positionMs != null) 'positionMs': positionMs,
      if (durationMs != null) 'durationMs': durationMs,
      if (playing != null) 'playing': playing,
      if (processingState != null) 'processingState': processingState,
      if (queueIndex != null) 'queueIndex': queueIndex,
      if (queueLength != null) 'queueLength': queueLength,
      if (upcomingCount != null) 'upcomingCount': upcomingCount,
      if (shuffle != null) 'shuffle': shuffle,
      if (repeatMode != null) 'repeatMode': repeatMode,
      if (crossfadeEnabled != null) 'crossfadeEnabled': crossfadeEnabled,
      if (transitionInProgress != null) 'transitionInProgress': transitionInProgress,
      if (engine != null) 'engine': engine,
      if (intentToken != null) 'intentToken': intentToken,
      ...extra,
    });
  }

  /// Dense native+app playback snapshot for silent-load / auto-next bugs.
  static Future<void> recordPlayerSnapshot({
    required String stage,
    String? command,
    String? source,
    String? songId,
    String? songTitle,
    String? filePath,
    int? positionMs,
    int? durationMs,
    bool? appIsPlaying,
    bool? nativePlaying,
    bool? userWantsPlaying,
    bool? loadingSource,
    String? processingState,
    int? queueIndex,
    int? queueLength,
    int? androidAudioSessionId,
    int? intentToken,
    String? engine,
    String? error,
    Map<String, dynamic> extra = const {},
  }) async {
    final mismatch = (appIsPlaying == true && nativePlaying == false) ||
        (userWantsPlaying == true && nativePlaying == false);
    await record('player_snapshot', {
      'stage': stage,
      if (command != null) 'command': command,
      if (source != null) 'source': source,
      if (songId != null) 'songId': songId,
      if (songTitle != null) 'songTitle': songTitle,
      if (filePath != null) 'filePath': filePath.length > 180 ? filePath.substring(0, 180) : filePath,
      if (positionMs != null) 'positionMs': positionMs,
      if (durationMs != null) 'durationMs': durationMs,
      if (appIsPlaying != null) 'appIsPlaying': appIsPlaying,
      if (nativePlaying != null) 'nativePlaying': nativePlaying,
      if (userWantsPlaying != null) 'userWantsPlaying': userWantsPlaying,
      if (loadingSource != null) 'loadingSource': loadingSource,
      if (processingState != null) 'processingState': processingState,
      if (queueIndex != null) 'queueIndex': queueIndex,
      if (queueLength != null) 'queueLength': queueLength,
      if (androidAudioSessionId != null) 'androidAudioSessionId': androidAudioSessionId,
      if (intentToken != null) 'intentToken': intentToken,
      if (engine != null) 'engine': engine,
      if (error != null) 'error': error,
      'wantPlayMismatch': mismatch,
      ...extra,
    });
  }

  static Future<void> recordQueueSnapshot({
    required String reason,
    required List<String> songIds,
    required int currentIndex,
    String? currentSongId,
    Map<String, dynamic> extra = const {},
  }) async {
    await record('queue_snapshot', {
      'reason': reason,
      'songIds': songIds.take(100).toList(),
      'songCount': songIds.length,
      'currentIndex': currentIndex,
      if (currentSongId != null) 'currentSongId': currentSongId,
      'upcomingSongIds': currentIndex >= 0 && currentIndex + 1 < songIds.length
          ? songIds.skip(currentIndex + 1).take(50).toList()
          : const <String>[],
      ...extra,
    });
  }

  static Future<void> recordPlaybackCommand({
    required String source,
    required String command,
    required int generation,
    Map<String, dynamic> data = const {},
  }) async {
    await record('playback_command', {
      'source': source,
      'command': command,
      'generation': generation,
      ...data,
    });
  }

  static Future<void> recordIntelligence({
    required String stage,
    String? songId,
    double? score,
    double? confidence,
    List<String>? reasons,
    String? action,
    String? outcome,
    Map<String, dynamic> extra = const {},
  }) async {
    await record('intelligence_event', {
      'stage': stage,
      if (songId != null) 'songId': songId,
      if (score != null) 'score': score,
      if (confidence != null) 'confidence': confidence,
      if (reasons != null) 'reasons': reasons.take(12).toList(),
      if (action != null) 'action': action,
      if (outcome != null) 'outcome': outcome,
      ...extra,
    });
  }

  static Future<void> recordCrash(Object error, StackTrace stack, {String source = 'unknown'}) async {
    final stackText = stack.toString();
    final entry = await _entry('crash', {
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
        await file.writeAsString(const JsonEncoder.withIndent('  ').convert({
          'reportVersion': 5,
          'app': 'Resonate',
          'createdAt': DateTime.now().toIso8601String(),
          ...entry,
        }), flush: true);
      }
    } catch (_) {}
    await record('crash_recorded', {
      'source': source,
      'errorType': error.runtimeType.toString(),
      'error': error.toString(),
    });
  }

  static Future<void> recordFeedback({required String category, required String message, bool includeDiagnostics = true}) async {
    _writeSerial = _writeSerial.then((_) async {
      try {
        final prefs = await _prefs();
        final items = _decodeList(prefs.getString(_feedbackKey));
        items.add(await _entry('feedback', {
          'category': category,
          'message': message.trim(),
          'includeDiagnostics': includeDiagnostics,
        }));
        if (items.length > _maxFeedback) items.removeRange(0, items.length - _maxFeedback);
        await prefs.setString(_feedbackKey, jsonEncode(items));
      } catch (_) {}
    });
    await _writeSerial;
    await record('feedback_submitted', {'category': category, 'includeDiagnostics': includeDiagnostics});
  }

  static Future<Map<String, dynamic>> snapshot() async {
    await _flushPendingEvents();
    await _writeSerial;
    final prefs = await _prefs();
    final events = _decodeList(prefs.getString(_eventsKey));
    final crashes = _decodeList(prefs.getString(_crashesKey));
    final feedback = _decodeList(prefs.getString(_feedbackKey));
    return {
      'reportVersion': 5,
      'createdAt': DateTime.now().toIso8601String(),
      'app': 'Resonate',
      'diagnosticsSessionId': await _getSessionId(),
      'sequence': prefs.getInt(_sequenceKey) ?? _sequence,
      'buildMode': kDebugMode ? 'debug' : kProfileMode ? 'profile' : 'release',
      'platform': Platform.operatingSystem,
      'platformVersion': Platform.operatingSystemVersion,
      'locale': Platform.localeName,
      'isAndroid': Platform.isAndroid,
      'isIOS': Platform.isIOS,
      'summary': _buildSummary(events, crashes),
      'events': events,
      'crashes': crashes,
      'feedback': feedback,
    };
  }

  static Map<String, dynamic> _buildSummary(List<Map<String, dynamic>> events, List<Map<String, dynamic>> crashes) {
    final counts = <String, int>{};
    final errorCounts = <String, int>{};
    final transitionOutcomes = <String, int>{};
    final intelligenceStages = <String, int>{};
    final playSteps = <String, int>{};
    final playTimeouts = <String, int>{};
    final handoffPlaying = <String, int>{'true': 0, 'false': 0};
    var playbackCheckpoints = 0;
    var completedSignals = 0;
    var stopWhileUpcomingSignals = 0;
    var playerSnapshots = 0;
    var wantPlayMismatches = 0;
    var playCommands = 0;
    var completionAdvanceAttempts = 0;
    var completionAdvanceResults = 0;
    var engineHandoffs = 0;
    String? lastPlayStep;
    String? lastHandoffPlaying;
    String? lastMismatchStage;

    for (final event in events) {
      final type = event['type']?.toString() ?? 'unknown';
      counts[type] = (counts[type] ?? 0) + 1;
      final data = event['data'];
      if (data is Map) {
        final error = data['error']?.toString();
        if (error != null && error.isNotEmpty) {
          final short = error.length > 120 ? error.substring(0, 120) : error;
          errorCounts[short] = (errorCounts[short] ?? 0) + 1;
        }
        if (type == 'playback_checkpoint') {
          playbackCheckpoints++;
          if (data['stage'] == 'completion_detected') completedSignals++;
          if (data['playing'] == false && (data['upcomingCount'] as num? ?? 0) > 0) {
            stopWhileUpcomingSignals++;
          }
        }
        if (type == 'completion_detected') completedSignals++;
        if (type == 'completion_advance_attempt') completionAdvanceAttempts++;
        if (type == 'completion_advance_result') completionAdvanceResults++;
        if (type == 'playback_engine_handoff') {
          engineHandoffs++;
          final p = data['playing'] == true ? 'true' : 'false';
          handoffPlaying[p] = (handoffPlaying[p] ?? 0) + 1;
          lastHandoffPlaying = p;
        }
        if (type == 'playback_command' || type == 'playback_command_accepted') {
          if (data['command'] == 'play') playCommands++;
        }
        if (type == 'playback_play_step') {
          final step = data['step']?.toString() ?? data['label']?.toString() ?? 'unknown';
          playSteps[step] = (playSteps[step] ?? 0) + 1;
          lastPlayStep = step;
          if (step == 'timeout_or_error') {
            final label = data['label']?.toString() ?? 'unknown';
            playTimeouts[label] = (playTimeouts[label] ?? 0) + 1;
          }
        }
        if (type == 'player_snapshot') {
          playerSnapshots++;
          if (data['wantPlayMismatch'] == true) {
            wantPlayMismatches++;
            lastMismatchStage = data['stage']?.toString();
          }
        }
        if (type == 'crossfade_committed' || type == 'crossfade_failed' || type == 'crossfade_cancelled') {
          final outcome = type.replaceFirst('crossfade_', '');
          transitionOutcomes[outcome] = (transitionOutcomes[outcome] ?? 0) + 1;
        }
        if (type == 'intelligence_event' || type == 'intelligence_recommendations_generated') {
          final stage = data['stage']?.toString() ?? type;
          intelligenceStages[stage] = (intelligenceStages[stage] ?? 0) + 1;
        }
      }
    }
    final rankedErrors = errorCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return {
      'eventCount': events.length,
      'crashCount': crashes.length,
      'eventTypes': counts,
      'playbackCheckpointCount': playbackCheckpoints,
      'completionDetectedCount': completedSignals,
      'completionAdvanceAttempts': completionAdvanceAttempts,
      'completionAdvanceResults': completionAdvanceResults,
      'engineHandoffs': engineHandoffs,
      'handoffPlaying': handoffPlaying,
      'lastHandoffPlaying': lastHandoffPlaying,
      'playCommands': playCommands,
      'playSteps': playSteps,
      'playTimeouts': playTimeouts,
      'lastPlayStep': lastPlayStep,
      'playerSnapshots': playerSnapshots,
      'wantPlayMismatches': wantPlayMismatches,
      'lastMismatchStage': lastMismatchStage,
      'stopsWithUpcomingSongs': stopWhileUpcomingSignals,
      'transitionOutcomes': transitionOutcomes,
      'intelligenceStages': intelligenceStages,
      'topErrors': Map<String, int>.fromEntries(rankedErrors.take(25)),
      'playbackHealthHint': _playbackHealthHint(
        playCommands: playCommands,
        engineHandoffs: engineHandoffs,
        completionAdvanceAttempts: completionAdvanceAttempts,
        completionAdvanceResults: completionAdvanceResults,
        wantPlayMismatches: wantPlayMismatches,
        playTimeouts: playTimeouts,
        lastHandoffPlaying: lastHandoffPlaying,
      ),
      'diagnosticPurpose': 'Reconstruct playback, queue, transition, interruption, Intelligence and lifecycle behaviour without requiring manual memory. Focus on playSteps, playTimeouts, player_snapshot.wantPlayMismatch, engineHandoffs, completionAdvance*.',
    };
  }

  static String _playbackHealthHint({
    required int playCommands,
    required int engineHandoffs,
    required int completionAdvanceAttempts,
    required int completionAdvanceResults,
    required int wantPlayMismatches,
    required Map<String, int> playTimeouts,
    required String? lastHandoffPlaying,
  }) {
    if (playCommands > 0 && engineHandoffs == 0) {
      return 'play_started_but_no_handoff — _playSongInternal likely hung or failed before finish';
    }
    if (completionAdvanceAttempts > completionAdvanceResults) {
      return 'auto_next_advance_incomplete — completion advance did not finish';
    }
    if (playTimeouts.isNotEmpty) {
      return 'play_path_timeouts — see summary.playTimeouts for which await hung';
    }
    if (wantPlayMismatches > 0) {
      return 'want_play_but_native_silent — app wanted audio but player.playing was false';
    }
    if (lastHandoffPlaying == 'false') {
      return 'handoff_with_playing_false — source loaded but native play did not stick';
    }
    if (lastHandoffPlaying == 'true') {
      return 'handoffs_look_ok — if still silent, check OS audio focus / session outside app logic';
    }
    return 'insufficient_playback_signal — play a track then export again';
  }

  static Future<String?> exportReport() async {
    final report = await snapshot();
    final json = const JsonEncoder.withIndent('  ').convert(report);
    final directory = await _documentsDirectory();
    if (directory == null) throw StateError('Could not access a local Documents directory.');
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final fileName = 'resonate-diagnostics-$stamp.json';
    final file = File('${directory.path}/$fileName');
    await file.writeAsString(json, flush: true);

    if (!Platform.isAndroid) {
      await record('report_exported_local', {
        'eventCount': (report['events'] as List).length,
        'crashCount': (report['crashes'] as List).length,
        'feedbackCount': (report['feedback'] as List).length,
        'path': file.path,
      });
      return file.path;
    }

    try {
      final savedUri = await _mediaStoreChannel.invokeMethod<String>('saveDiagnosticReport', {
        'fileName': fileName,
        'bytes': Uint8List.fromList(utf8.encode(json)),
      });
      if (savedUri == null || savedUri.isEmpty) {
        await record('report_save_cancelled', {'fileName': fileName});
        return null;
      }
      await record('report_saved_to_device', {
        'uri': savedUri,
        'suggestedFileName': fileName,
        'eventCount': (report['events'] as List).length,
        'crashCount': (report['crashes'] as List).length,
        'feedbackCount': (report['feedback'] as List).length,
      });
      return savedUri;
    } on PlatformException catch (e) {
      await record('report_device_save_failed', {'code': e.code, 'message': e.message});
      rethrow;
    } catch (e) {
      await record('report_device_save_failed', {'error': e.toString()});
      rethrow;
    }
  }

  static Future<void> clearDiagnostics() async {
    await _flushPendingEvents();
    await _writeSerial;
    final prefs = await _prefs();
    await prefs.remove(_eventsKey);
    await prefs.remove(_crashesKey);
    await prefs.remove(_feedbackKey);
  }

  static Future<int> eventCount() async { final report = await snapshot(); return (report['events'] as List).length; }
  static Future<int> crashCount() async { final report = await snapshot(); return (report['crashes'] as List).length; }
  static Future<int> feedbackCount() async { final report = await snapshot(); return (report['feedback'] as List).length; }

  static Future<Map<String, dynamic>> _entry(String type, Map<String, dynamic> data) async {
    final sanitized = _sanitize(data);
    return {
      'at': DateTime.now().toIso8601String(),
      'type': type,
      'sessionId': await _getSessionId(),
      'sequence': await _nextSequence(),
      'data': sanitized,
    };
  }

  static Map<String, dynamic> _sanitize(Map<String, dynamic> input) {
    dynamic clean(dynamic value) {
      if (value == null || value is num || value is bool || value is String) {
        if (value is String && value.length > _maxValueChars) return '${value.substring(0, _maxValueChars)}…[truncated]';
        return value;
      }
      if (value is Map) return {for (final e in value.entries) e.key.toString(): clean(e.value)};
      if (value is Iterable) return value.take(200).map(clean).toList();
      return value.toString().length > _maxValueChars ? '${value.toString().substring(0, _maxValueChars)}…[truncated]' : value.toString();
    }
    return Map<String, dynamic>.from(clean(input) as Map);
  }

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
