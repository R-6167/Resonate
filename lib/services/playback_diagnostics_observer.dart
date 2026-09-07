import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../providers/music_provider.dart';
import 'playback_authority.dart';
import 'resonate_diagnostics.dart';

class PlaybackDiagnosticsObserver extends ChangeNotifier {
  final MusicProvider music;
  final PlaybackAuthority authority = PlaybackAuthority.instance;
  Timer? _heartbeat;
  bool _lastPlaying = false;
  String? _lastSongId;
  int _lastQueueIndex = -1;
  ProcessingState _lastProcessingState = ProcessingState.idle;
  DateTime? _lastStateWrite;

  PlaybackDiagnosticsObserver({required this.music}) {
    music.addListener(_observe);
    _heartbeat = Timer.periodic(const Duration(seconds: 5), (_) => _heartbeatTick());
    _observe();
  }

  void _observe() {
    final player = music.audioPlayer;
    final state = player.playerState;
    final songId = music.currentSong?.id;
    final changed = _lastPlaying != music.isPlaying || _lastSongId != songId || _lastQueueIndex != music.queueIndex || _lastProcessingState != state.processingState;
    if (!changed) return;
    _lastPlaying = music.isPlaying;
    _lastSongId = songId;
    _lastQueueIndex = music.queueIndex;
    _lastProcessingState = state.processingState;
    _recordState(state, event: 'playback_state_changed');
  }

  void _heartbeatTick() {
    final state = music.audioPlayer.playerState;
    if (!music.isPlaying && state.processingState == ProcessingState.idle) return;
    _recordState(state, event: 'playback_heartbeat');
  }

  void _recordState(PlayerState state, {required String event}) {
    final now = DateTime.now();
    if (event == 'playback_state_changed' && _lastStateWrite != null && now.difference(_lastStateWrite!) < const Duration(milliseconds: 350)) return;
    _lastStateWrite = now;
    unawaited(ResonateDiagnostics.record(event, {
      'playing': music.isPlaying,
      'playerPlaying': state.playing,
      'processingState': state.processingState.name,
      'engine': authority.engineLabel(music),
      'lastCommandSource': authority.lastSource,
      'lastCommand': authority.lastCommand,
      'userCommandGeneration': authority.userGeneration,
      'queueIndex': music.queueIndex,
      'queueLength': music.queue.length,
      'queueSongIds': music.queue.map((song) => song.id).toList(),
      'currentSongId': music.currentSong?.id,
      'currentSongTitle': music.currentSong?.title,
      'currentSongArtist': music.currentSong?.artist,
      'positionMs': music.currentPosition.inMilliseconds,
      'playerPositionMs': music.audioPlayer.position.inMilliseconds,
      'bufferedPositionMs': music.audioPlayer.bufferedPosition.inMilliseconds,
      'durationMs': (music.currentDuration ?? music.currentSong?.duration)?.inMilliseconds,
      'playerDurationMs': music.audioPlayer.duration?.inMilliseconds,
      'shuffle': music.shuffleEnabled,
      'repeat': music.repeatMode.name,
      'crossfadeEnabled': music.crossfadeEnabled,
      'crossfadeInProgress': music.transitionInProgress,
      'hasCurrentSong': music.currentSong != null,
    }));
  }

  @override
  void dispose() {
    music.removeListener(_observe);
    _heartbeat?.cancel();
    _heartbeat = null;
    super.dispose();
  }
}
