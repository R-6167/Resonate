import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/intelligence_settings_store.dart';
import 'intelligence_provider.dart';
import 'music_provider.dart';

/// Bridges Intelligence decisions into the existing MusicProvider playback
/// engine. MusicProvider remains authoritative for playback and queue state.
class AutopilotController extends ChangeNotifier {
  final MusicProvider music;
  final IntelligenceProvider intelligence;
  bool _queueDecisionInFlight = false;
  bool _transitionInFlight = false;
  String? _transitionSongId;
  String? _pendingSongId;
  bool _pendingTakeover = false;

  AutopilotController({required this.music, required this.intelligence}) {
    music.addListener(_onPlaybackChanged);
    intelligence.addListener(_onIntelligenceChanged);
    unawaited(_evaluate());
  }

  bool get hasPendingTakeover => _pendingTakeover && _pendingSongId != null;
  String? get pendingSongId => _pendingSongId;

  void _onPlaybackChanged() => unawaited(_evaluate());
  void _onIntelligenceChanged() => unawaited(_evaluate());

  Future<void> allowPendingTakeover() async {
    if (!hasPendingTakeover) return;
    _pendingTakeover = false;
    notifyListeners();
    await _evaluate(forceTransition: true);
  }

  Future<void> denyPendingTakeover() async {
    final pending = _pendingSongId;
    _pendingTakeover = false;
    _pendingSongId = null;
    notifyListeners();
    if (pending == null) return;
    final index = music.queue.indexWhere((song) => song.id == pending);
    if (index > music.queueIndex) await music.removeFromQueue(index);
  }

  Future<void> _evaluate({bool forceTransition = false}) async {
    if (!intelligence.isAutopilot || !music.isPlaying || music.currentSong == null) return;

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

    if (!forceTransition && !_pendingTakeover) {
      _pendingTakeover = true;
      _pendingSongId = next.id;
      notifyListeners();
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
      final currentId = music.currentSong?.id;
      final candidates = intelligence.recommendations
          .where((r) => r.confidence >= threshold)
          .where((r) => r.song.id != currentId)
          .where((r) => !futureQueued.contains(r.song.id))
          .take(2)
          .map((r) => r.song)
          .toList(growable: false);
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
