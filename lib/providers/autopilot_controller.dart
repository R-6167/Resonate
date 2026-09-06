import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/intelligence_decision_engine.dart';
import '../services/intelligence_settings_store.dart';
import 'intelligence_provider.dart';
import 'music_provider.dart';

/// Bridges Intelligence decisions into the existing MusicProvider playback
/// engine. MusicProvider remains authoritative for playback and queue state.
class AutopilotController extends ChangeNotifier {
  final MusicProvider music;
  final IntelligenceProvider intelligence;
  final IntelligenceDecisionEngine _decisionEngine = const IntelligenceDecisionEngine();
  bool _queueDecisionInFlight = false;
  bool _transitionInFlight = false;
  String? _transitionSongId;
  String? _pendingSongId;
  String? _declinedForSongId;
  bool _pendingTakeover = false;
  bool _consentLoaded = false;
  bool _consentGranted = false;

  AutopilotController({required this.music, required this.intelligence}) {
    music.addListener(_onPlaybackChanged);
    intelligence.addListener(_onIntelligenceChanged);
    unawaited(_loadConsentAndEvaluate());
  }

  bool get hasPendingTakeover => _pendingTakeover && _pendingSongId != null;
  String? get pendingSongId => _pendingSongId;

  void _onPlaybackChanged() => unawaited(_evaluate());
  void _onIntelligenceChanged() => unawaited(_evaluate());

  Future<void> _loadConsentAndEvaluate() async {
    _consentGranted = await IntelligenceSettingsStore.autopilotConsent();
    _consentLoaded = true;
    await _evaluate();
  }

  Future<void> allowPendingTakeover() async {
    if (!hasPendingTakeover) return;
    _consentGranted = true;
    _pendingTakeover = false;
    _pendingSongId = null;
    await IntelligenceSettingsStore.setAutopilotConsent(true);
    notifyListeners();
    await _evaluate(forceTransition: true);
  }

  Future<void> denyPendingTakeover() async {
    final pending = _pendingSongId;
    _pendingTakeover = false;
    _pendingSongId = null;
    if (pending != null) _declinedForSongId = pending;
    notifyListeners();
  }

  Future<void> _evaluate({bool forceTransition = false}) async {
    if (!_consentLoaded || !intelligence.isAutopilot || !music.isPlaying || music.currentSong == null) return;

    final automaticQueue = await IntelligenceSettingsStore.automaticQueue();
    final threshold = await IntelligenceSettingsStore.confidenceThreshold();
    final useCrossfade = await IntelligenceSettingsStore.autopilotCrossfade();
    final duration = music.currentDuration;
    final remaining = duration == null ? null : duration - music.currentPosition;

    if (automaticQueue && (remaining == null || remaining <= const Duration(seconds: 25))) {
      await _ensurePredictedQueue(threshold);
    }

    if (_transitionInFlight || music.queueIndex >= music.queue.length - 1) return;
    final currentDuration = music.currentDuration;
    if (currentDuration == null) return;
    final currentRemaining = currentDuration - music.currentPosition;
    if (!forceTransition && currentRemaining > const Duration(seconds: 8)) return;

    final next = music.queue[music.queueIndex + 1];
    final matching = intelligence.recommendations.where((r) => r.song.id == next.id);
    final recommendation = matching.isEmpty ? null : matching.first;
    if (recommendation == null || recommendation.confidence < threshold) return;
    if (_transitionSongId == music.currentSong?.id) return;

    if (!_consentGranted && !forceTransition) {
      if (_declinedForSongId == next.id) return;
      if (!_pendingTakeover) {
        _pendingTakeover = true;
        _pendingSongId = next.id;
        notifyListeners();
      }
      return;
    }

    _pendingTakeover = false;
    _pendingSongId = null;
    _transitionSongId = music.currentSong?.id;
    _transitionInFlight = true;
    try {
      if (useCrossfade) {
        final milliseconds = await IntelligenceSettingsStore.autopilotCrossfadeMs();
        await music.performTrueCrossfade(milliseconds: milliseconds, fadeType: 'ease_in_out');
      } else {
        await music.nextSong();
      }
    } finally {
      _transitionInFlight = false;
      unawaited(_ensurePredictedQueue(threshold));
    }
  }

  Future<void> _ensurePredictedQueue(double threshold) async {
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
      if (candidates.isNotEmpty) await music.enqueueSongs(candidates);
    } finally {
      _queueDecisionInFlight = false;
    }
  }

  @override
  void dispose() {
    music.removeListener(_onPlaybackChanged);
    intelligence.removeListener(_onIntelligenceChanged);
    super.dispose();
  }
}
