import 'dart:async';

import 'intelligence_provider.dart';
import 'music_provider.dart';

/// Bridges Intelligence decisions into the existing MusicProvider playback
/// engine. Playback remains owned by MusicProvider; this controller only
/// decides when Autopilot should extend or transition the queue.
class AutopilotController {
  final MusicProvider music;
  final IntelligenceProvider intelligence;
  bool _queueDecisionInFlight = false;
  bool _crossfadeInFlight = false;
  String? _transitionSongId;

  AutopilotController({required this.music, required this.intelligence}) {
    music.addListener(_onPlaybackChanged);
    intelligence.addListener(_onIntelligenceChanged);
    unawaited(_evaluate());
  }

  void _onPlaybackChanged() => unawaited(_evaluate());
  void _onIntelligenceChanged() => unawaited(_evaluate());

  Future<void> _evaluate() async {
    if (!intelligence.isAutopilot || !music.isPlaying || music.currentSong == null) return;

    final duration = music.currentDuration;
    final remaining = duration == null ? null : duration - music.currentPosition;

    // Keep a short runway of predicted tracks so the decision is made well
    // before the current song ends.
    if (remaining == null || remaining <= const Duration(seconds: 25)) {
      await _ensurePredictedQueue();
    }

    if (!music.isPlaying || _crossfadeInFlight) return;
    final currentDuration = music.currentDuration;
    if (currentDuration == null) return;
    final currentRemaining = currentDuration - music.currentPosition;
    if (currentRemaining > const Duration(seconds: 6)) return;
    if (music.queueIndex >= music.queue.length - 1) return;

    final next = music.queue[music.queueIndex + 1];
    final matching = intelligence.recommendations.where((r) => r.song.id == next.id);
    final recommendation = matching.isEmpty ? null : matching.first;
    if (recommendation == null || recommendation.confidence < .65) return;
    if (_transitionSongId == music.currentSong?.id) return;

    _transitionSongId = music.currentSong?.id;
    _crossfadeInFlight = true;
    try {
      await music.performTrueCrossfade(milliseconds: 5000, fadeType: 'ease_in_out');
    } finally {
      _crossfadeInFlight = false;
    }
  }

  Future<void> _ensurePredictedQueue() async {
    if (_queueDecisionInFlight) return;
    _queueDecisionInFlight = true;
    try {
      await intelligence.refreshRecommendations(notify: false);
      final queued = music.queue.map((song) => song.id).toSet();
      final candidates = intelligence.recommendations
          .where((r) => r.confidence >= .45 && !queued.contains(r.song.id))
          .take(2)
          .map((r) => r.song)
          .toList(growable: false);
      if (candidates.isNotEmpty) await music.enqueueSongs(candidates);
    } finally {
      _queueDecisionInFlight = false;
    }
  }

  void dispose() {
    music.removeListener(_onPlaybackChanged);
    intelligence.removeListener(_onIntelligenceChanged);
  }
}
