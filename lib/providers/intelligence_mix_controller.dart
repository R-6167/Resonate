import 'package:flutter/foundation.dart';

import '../models/intelligence_mix.dart';
import '../models/song.dart';
import '../services/intelligence_mix_service.dart';
import 'intelligence_provider.dart';
import 'music_provider.dart';

/// Coordinates generated mixes and long-form listening analysis for the UI.
/// Playback remains owned by MusicProvider; this controller only asks
/// Intelligence for a plan and exposes the result to views.
class IntelligenceMixController extends ChangeNotifier {
  final MusicProvider music;
  final IntelligenceProvider intelligence;
  final IntelligenceMixService _service;

  IntelligenceMix? _currentMix;
  IntelligenceMixAnalysis? _currentAnalysis;
  bool _loading = false;
  String? _analyzingSongId;

  IntelligenceMixController({
    required this.music,
    required this.intelligence,
    IntelligenceMixService? service,
  }) : _service = service ?? IntelligenceMixService();

  IntelligenceMix? get currentMix => _currentMix;
  IntelligenceMixAnalysis? get currentAnalysis => _currentAnalysis;
  bool get isLoading => _loading;
  String? get analyzingSongId => _analyzingSongId;

  Future<IntelligenceMix?> generateMix({
    Duration targetDuration = const Duration(minutes: 60),
    String? title,
  }) async {
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
      return mix;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<IntelligenceMixAnalysis?> analyzeLongMix(
    Song song, {
    int minimumDurationMinutes = 20,
  }) async {
    _analyzingSongId = song.id;
    notifyListeners();
    try {
      final analysis = await _service.analyzeLongMix(
        song,
        minimumDurationMinutes: minimumDurationMinutes,
      );
      _currentAnalysis = analysis;
      return analysis;
    } finally {
      _analyzingSongId = null;
      notifyListeners();
    }
  }

  void clearMix() {
    _currentMix = null;
    notifyListeners();
  }

  String _defaultTitle() {
    if (intelligence.sessionSkipStreak >= 2) return 'A Fresh Turn';
    if (intelligence.sessionCompletionStreak >= 2) return 'Keep The Flow';
    switch (intelligence.sessionMode) {
      case 'Exploring':
        return 'Open The Search';
      case 'Familiar flow':
        return 'Your Familiar Flow';
      default:
        return 'Your Resonate Mix';
    }
  }
}
