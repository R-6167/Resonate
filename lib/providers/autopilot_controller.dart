import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/intelligence_recommendation.dart';
import '../models/song.dart';
import '../services/intelligence_decision_engine.dart';
import '../services/intelligence_settings_store.dart';
import '../services/resonate_diagnostics.dart';
import '../services/companion_decision_log.dart';
import '../services/playback_authority.dart';
import 'intelligence_provider.dart';
import 'music_provider.dart';

/// Bridges Intelligence decisions into the existing MusicProvider playback
/// engine. MusicProvider remains authoritative for playback and queue state.
/// PlaybackAuthority events wake this controller for command-sensitive work;
/// the provider listener remains only as a state-boundary fallback.
class AutopilotController extends ChangeNotifier {
  final MusicProvider music;
  final IntelligenceProvider intelligence;
  final IntelligenceDecisionEngine _decisionEngine = const IntelligenceDecisionEngine();
  final PlaybackAuthority _authority = PlaybackAuthority.instance;
  bool _queueDecisionInFlight = false;
  bool _transitionInFlight = false;
  String? _transitionSongId;
  String? _pendingSongId;
  String? _declinedForSongId;
  bool _pendingTakeover = false;
  bool _consentLoaded = false;
  bool _consentGranted = false;
  DateTime? _lastEvaluation;
  bool _evaluationScheduled = false;

  AutopilotController({required this.music, required this.intelligence}) {
    music.addListener(_onPlaybackChanged);
    intelligence.addListener(_onIntelligenceChanged);
    _authority.addListener(_onAuthorityEvent);
    unawaited(_loadConsentAndEvaluate());
  }

  bool get hasPendingTakeover => _pendingTakeover && _pendingSongId != null;
  String? get pendingSongId => _pendingSongId;
  bool get consentGranted => _consentGranted;

  /// Home card / settings — user explicitly allows or revokes track control.
  Future<void> setConsent(bool value) async {
    _consentGranted = value;
    await IntelligenceSettingsStore.setAutopilotConsent(value);
    if (!value) {
      _pendingTakeover = false;
      _pendingSongId = null;
    }
    notifyListeners();
    await ResonateDiagnostics.record('intelligence_notification_action', {
      'action': value ? 'consent_granted' : 'consent_revoked',
      'mode': intelligence.autonomyLabel,
    });
    unawaited(CompanionDecisionLog.record(
      source: 'autopilot',
      action: value ? 'consent_granted' : 'consent_revoked',
      detail: value
          ? 'You allowed Autopilot to change tracks.'
          : 'Autopilot is advisory only until you consent again.',
    ));
    if (value) await _evaluate();
  }

  void _onPlaybackChanged() => _scheduleEvaluate();
  void _onIntelligenceChanged() => _scheduleEvaluate();

  void _onAuthorityEvent() {
    final event = _authority.lastEvent;
    if (event == null) return;
    if (event.kind == PlaybackEventKind.userCommand || event.kind == PlaybackEventKind.automaticCommand) {
      _scheduleEvaluate();
    }
  }

  void _scheduleEvaluate() {
    if (_evaluationScheduled) return;
    _evaluationScheduled = true;
    scheduleMicrotask(() async {
      _evaluationScheduled = false;
      await _evaluate();
    });
  }

  Future<void> _loadConsentAndEvaluate() async {
    _consentGranted = await IntelligenceSettingsStore.autopilotConsent();
    _consentLoaded = true;
    await _evaluate();
  }

  Future<void> allowPendingTakeover() async {
    if (!hasPendingTakeover) return;
    final pending = _pendingSongId;
    _consentGranted = true;
    _pendingTakeover = false;
    _pendingSongId = null;
    await CompanionDecisionLog.record(
      source: 'autopilot',
      action: 'takeover_allowed',
      detail: 'You allowed the pending Autopilot takeover.',
      songId: pending,
    );
    await ResonateDiagnostics.record('intelligence_notification_action', {
      'action': 'accepted', 'songId': pending, 'mode': intelligence.autonomyLabel,
    });
    await IntelligenceSettingsStore.setAutopilotConsent(true);
    notifyListeners();
    await _evaluate(forceTransition: true);
  }

  Future<void> denyPendingTakeover() async {
    final pending = _pendingSongId;
    _pendingTakeover = false;
    _pendingSongId = null;
    if (pending != null) _declinedForSongId = pending;
    await ResonateDiagnostics.record('intelligence_notification_action', {
      'action': 'rejected', 'songId': pending, 'mode': intelligence.autonomyLabel,
    });
    notifyListeners();
  }

  Future<void> _evaluate({bool forceTransition = false}) async {
    // Phase 5: Intelligence off or not in Autopilot mode → never drive playback.
    if (!_consentLoaded || !intelligence.isEnabled || !intelligence.isAutopilot) return;
    if (music.currentSong == null) return;
    if (!music.isPlaying && !forceTransition) return;

    final now = DateTime.now();
    if (!forceTransition &&
        _lastEvaluation != null &&
        now.difference(_lastEvaluation!) < const Duration(milliseconds: 250)) {
      return;
    }
    _lastEvaluation = now;

    final automaticQueue = await IntelligenceSettingsStore.automaticQueue();
    final threshold = await IntelligenceSettingsStore.confidenceThreshold();
    final useCrossfade = await IntelligenceSettingsStore.autopilotCrossfade();

    // Keep the queue topped up early — Phase 5: only with explicit consent.
    final duration = music.currentDuration;
    final remaining = duration == null ? null : duration - music.currentPosition;
    if (_consentGranted && automaticQueue && (remaining == null || remaining <= const Duration(seconds: 30))) {
      await _ensurePredictedQueue(threshold);
    }

    if (_transitionInFlight) return;

    final currentDuration = music.currentDuration;
    if (currentDuration == null) return;
    final currentRemaining = currentDuration - music.currentPosition;

    // Only act when we are close to the end (or forced)
    if (!forceTransition && currentRemaining > const Duration(seconds: 10)) return;
    if (_transitionSongId == music.currentSong?.id) return;

    // Prefer the highest-confidence recommendation that is not the current song
    final candidates = intelligence.recommendations
        .where((r) => r.song.id != music.currentSong?.id && r.confidence >= threshold)
        .toList();

    Song? nextSong;
    IntelligenceRecommendation? recommendation;

    if (candidates.isNotEmpty) {
      recommendation = candidates.first;
      nextSong = recommendation.song;
    } else if (intelligence.isAutopilotGraduated) {
      // Prefer existing queue next. Phase 5: only enqueue with consent.
      if (music.queueIndex < music.queue.length - 1) {
        nextSong = music.queue[music.queueIndex + 1];
      } else if (_consentGranted) {
        await _ensurePredictedQueue(threshold);
        final top = intelligence.anticipatedNext?.song;
        if (top != null && top.id != music.currentSong?.id) {
          await music.enqueueSongs([top]);
          nextSong = top;
        }
      }
    }

    if (nextSong == null) return;

    // Phase 5 consent gate: no play APIs without consent (forceTransition only
    // after allowPendingTakeover which sets _consentGranted = true).
    if (!_consentGranted) {
      if (_declinedForSongId == nextSong.id) return;
      if (!_pendingTakeover) {
        _pendingTakeover = true;
        _pendingSongId = nextSong.id;
        await ResonateDiagnostics.record('intelligence_notification_action', {
          'action': 'shown',
          'songId': nextSong.id,
          'mode': intelligence.autonomyLabel,
          'confidence': recommendation?.confidence ?? 0,
          'reason': recommendation?.reason ?? 'graduated_autopilot',
          'consentGranted': false,
        });
        notifyListeners();
      }
      return;
    }

    // Consent granted – may call public play APIs only
    _pendingTakeover = false;
    _pendingSongId = null;
    _transitionSongId = music.currentSong?.id;
    _transitionInFlight = true;

    await ResonateDiagnostics.record('intelligence_transition', {
      'stage': 'started',
      'mode': intelligence.autonomyLabel,
      'fromSongId': music.currentSong?.id,
      'toSongId': nextSong.id,
      'confidence': recommendation?.confidence ?? 0,
      'reason': recommendation?.reason ?? 'graduated_autopilot',
    });

    final userGeneration = _authority.userGeneration;
    final automaticGeneration = _authority.beginAutomatic('intelligence_transition');

    try {
      if (_authority.isStale(automaticGeneration) ||
          userGeneration != _authority.userGeneration) {
        return;
      }

      // Make sure the chosen song is the immediate next item in the queue
      final upcoming = music.queue.skip(music.queueIndex + 1).toList();
      final alreadyNext = upcoming.isNotEmpty && upcoming.first.id == nextSong.id;
      if (!alreadyNext) {
        await music.playNext(nextSong);
      }

      if (useCrossfade && music.canCrossfadeNext && music.isPlaying) {
        final ms = await IntelligenceSettingsStore.autopilotCrossfadeMs();
        if (_authority.isStale(automaticGeneration)) return;
        final ok = await music.performTrueCrossfade(milliseconds: ms, fadeType: 'ease_in_out');
        if (!ok) await music.nextSong(source: 'intelligence');
      } else {
        if (_authority.isStale(automaticGeneration)) return;
        await music.nextSong(source: 'intelligence');
      }

      await ResonateDiagnostics.record('intelligence_transition', {
        'stage': 'completed',
        'mode': intelligence.autonomyLabel,
        'fromSongId': music.currentSong?.id,
        'queueIndex': music.queueIndex,
      });
    } catch (e) {
      await ResonateDiagnostics.record('intelligence_transition', {
        'stage': 'failed',
        'mode': intelligence.autonomyLabel,
        'error': e.toString(),
      });
      debugPrint('Autopilot transition failed: $e');
    } finally {
      _transitionInFlight = false;
      _transitionSongId = null;
      unawaited(_ensurePredictedQueue(threshold));
    }
  }

  Future<void> _ensurePredictedQueue(double threshold) async {
    // Phase 5: queue mutation is a playback API — require consent + autopilot.
    if (!_consentGranted || !intelligence.isEnabled || !intelligence.isAutopilot) return;
    if (_queueDecisionInFlight) return;
    _queueDecisionInFlight = true;
    try {
      await intelligence.refreshRecommendations(notify: false);
      final futureQueued = music.queue.skip(music.queueIndex + 1).map((song) => song.id).toSet();
      final candidates = await _decisionEngine.chooseSequence(
        recommendations: intelligence.recommendations,
        queuedIds: futureQueued,
        currentSong: music.currentSong,
        sessionMode: intelligence.sessionMode,
        sessionSkipStreak: intelligence.sessionSkipStreak,
        sessionCompletionStreak: intelligence.sessionCompletionStreak,
        sessionArtistCounts: intelligence.sessionArtistCounts,
        count: 2,
      );
      if (candidates.isNotEmpty) {
        final added = await music.enqueueSongs(candidates);
        await ResonateDiagnostics.record('intelligence_queue_decision', {
          'mode': intelligence.autonomyLabel,
          'candidates': candidates.map((song) => song.id).toList(),
          'added': added,
          'queueLength': music.queue.length,
          'queueIndex': music.queueIndex,
        });
        if (added > 0) {
          unawaited(CompanionDecisionLog.record(
            source: 'autopilot',
            action: 'enqueue',
            detail: 'Queued $added predicted track(s) under your consent.',
            songId: candidates.first.id,
          ));
        }
      }
    } finally {
      _queueDecisionInFlight = false;
    }
  }

  @override
  void dispose() {
    music.removeListener(_onPlaybackChanged);
    intelligence.removeListener(_onIntelligenceChanged);
    _authority.removeListener(_onAuthorityEvent);
    super.dispose();
  }
}
