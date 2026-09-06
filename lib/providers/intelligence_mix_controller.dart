import 'package:flutter/foundation.dart';

import '../models/intelligence_mix.dart';
import '../models/song.dart';
import '../services/intelligence_mix_service.dart';
import '../services/intelligence_seek_memory.dart';
import 'intelligence_provider.dart';
import 'music_provider.dart';

/// Coordinates generated mixes and long-form listening analysis for the UI.
/// Playback remains owned by MusicProvider; this controller only asks
/// Intelligence for a plan and exposes the result to views.
class IntelligenceMixController extends ChangeNotifier {
  final MusicProvider music;
  final IntelligenceProvider intelligence;
  final IntelligenceMixService _service;
  final IntelligenceSeekMemory _seekMemory;

  IntelligenceMix? _currentMix;
  IntelligenceMixAnalysis? _currentAnalysis;
  Map<String, dynamic>? _currentContinuity;
  bool _loading = false;
  String? _analyzingSongId;
  String? _lastObservedSongId;
  int _lastPositionMs = 0;
  bool _trackingPosition = false;

  IntelligenceMixController({
    required this.music,
    required this.intelligence,
    IntelligenceMixService? service,
    IntelligenceSeekMemory? seekMemory,
  })  : _service = service ?? IntelligenceMixService(),
        _seekMemory = seekMemory ?? IntelligenceSeekMemory() {
    music.addListener(_observeMixPlayback);
    _observeMixPlayback();
  }

  IntelligenceMix? get currentMix => _currentMix;
  IntelligenceMixAnalysis? get currentAnalysis => _currentAnalysis;
  Map<String, dynamic>? get currentContinuity => _currentContinuity;
  bool get isLoading => _loading;
  String? get analyzingSongId => _analyzingSongId;

  Future<IntelligenceMix?> generateMix({Duration targetDuration = const Duration(minutes: 60), String? title}) async {
    if (!intelligence.isEnabled || intelligence.recommendations.isEmpty) return null;
    _loading = true;
    notifyListeners();
    try {
      final mix = await _service.generateMix(
        recommendations: intelligence.recommendations,
        currentSong: music.currentSong,
        sessionMode: intelligence.sessionMode,
        sessionSkipStreak: intelligence.sessionSkipStreak,
        sessionCompletionStreak: intelligence.sessionCompletionStreak,
        sessionArtistCounts: intelligence.sessionArtistCounts,
        targetDuration: targetDuration,
        title: title ?? _defaultTitle(),
      );
      _currentMix = mix;
      _currentContinuity = null;
      return mix;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<IntelligenceMixAnalysis?> analyzeLongMix(Song song, {int minimumDurationMinutes = 20}) async {
    _analyzingSongId = song.id;
    notifyListeners();
    try {
      final analysis = await _service.analyzeLongMix(song, minimumDurationMinutes: minimumDurationMinutes);
      _currentAnalysis = analysis;
      return analysis;
    } finally {
      _analyzingSongId = null;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>?> evaluateCurrentMix() async {
    final mix = _currentMix;
    if (mix == null) return null;
    final assessment = await _service.evaluateMix(mix);
    if (assessment != null) {
      _currentContinuity = assessment;
      notifyListeners();
    }
    return assessment;
  }

  Future<List<Map<String, dynamic>>> recentMixContinuity() => _service.recentMixContinuity();

  void clearMix() {
    _currentMix = null;
    _currentContinuity = null;
    notifyListeners();
  }

  void _observeMixPlayback() {
    if (_trackingPosition) return;
    _trackingPosition = true;
    try {
      final songId = music.currentSong?.id;
      final position = music.currentPosition.inMilliseconds.clamp(0, 86400000).toInt();
      if (songId != _lastObservedSongId) {
        _lastObservedSongId = songId;
        _lastPositionMs = position;
        final mix = _currentMix;
        if (mix != null && songId != null && mix.songs.any((song) => song.id == songId)) evaluateCurrentMix();
        return;
      }
      final from = _lastPositionMs;
      _lastPositionMs = position;
      if (songId != null && from > 0 && from - position >= 5000) {
        _seekMemory.record(songId: songId, fromMs: from, toMs: position);
      }
    } finally {
      _trackingPosition = false;
    }
  }

  @override
  void dispose() {
    music.removeListener(_observeMixPlayback);
    super.dispose();
  }

  String _defaultTitle() {
    if (intelligence.sessionSkipStreak >= 2) return 'A Fresh Turn';
    if (intelligence.sessionCompletionStreak >= 2) return 'Keep The Flow';
    switch (intelligence.sessionMode) {
      case 'Exploring': return 'Open The Search';
      case 'Familiar flow': return 'Your Familiar Flow';
      default: return 'Your Resonate Mix';
    }
  }
}
