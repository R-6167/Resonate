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
  bool _terminalRecoveryInFlight = false;

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

    final previousPlaying = _lastPlaying;
    final previousSongId = _lastSongId;
    final previousQueueIndex = _lastQueueIndex;
    final previousProcessingState = _lastProcessingState;

    _lastPlaying = music.isPlaying;
    _lastSongId = songId;
    _lastQueueIndex = music.queueIndex;
    _lastProcessingState = state.processingState;
    _recordState(state, event: 'playback_state_changed');

    final upcoming = music.queue.length - music.queueIndex - 1;
    final command = authority.lastCommand ?? '';
    final commandSource = authority.lastSource ?? '';

    if (state.processingState == ProcessingState.completed) {
      unawaited(ResonateDiagnostics.recordPlaybackCheckpoint(
        stage: 'completion_detected', source: commandSource, songId: songId, songTitle: music.currentSong?.title,
        positionMs: music.currentPosition.inMilliseconds, durationMs: (music.currentDuration ?? music.currentSong?.duration)?.inMilliseconds,
        playing: music.isPlaying, processingState: state.processingState.name, queueIndex: music.queueIndex,
        queueLength: music.queue.length, upcomingCount: upcoming, shuffle: music.shuffleEnabled, repeatMode: music.repeatMode.name,
        crossfadeEnabled: music.crossfadeEnabled, transitionInProgress: music.transitionInProgress, engine: authority.engineLabel(music),
        extra: {'previousPlaying': previousPlaying, 'previousSongId': previousSongId, 'previousQueueIndex': previousQueueIndex, 'previousProcessingState': previousProcessingState.name, 'lastCommand': command},
      ));
    }

    final explicitUserStop = command == 'pause' || command == 'stop' || command == 'toggle';
    final becameStopped = previousPlaying && !music.isPlaying;
    if (becameStopped && upcoming > 0 && !explicitUserStop) {
      unawaited(ResonateDiagnostics.recordPlaybackCheckpoint(
        stage: 'unexpected_stop_with_upcoming', source: commandSource, songId: songId, songTitle: music.currentSong?.title,
        positionMs: music.currentPosition.inMilliseconds, durationMs: (music.currentDuration ?? music.currentSong?.duration)?.inMilliseconds,
        playing: music.isPlaying, processingState: state.processingState.name, queueIndex: music.queueIndex, queueLength: music.queue.length,
        upcomingCount: upcoming, shuffle: music.shuffleEnabled, repeatMode: music.repeatMode.name, crossfadeEnabled: music.crossfadeEnabled,
        transitionInProgress: music.transitionInProgress, engine: authority.engineLabel(music),
        extra: {
          'previousPlaying': previousPlaying, 'previousSongId': previousSongId, 'previousQueueIndex': previousQueueIndex,
          'previousProcessingState': previousProcessingState.name, 'lastCommand': command, 'lastCommandSource': commandSource,
          'bufferedPositionMs': player.bufferedPosition.inMilliseconds, 'playerPositionMs': player.position.inMilliseconds,
          'playerDurationMs': player.duration?.inMilliseconds,
        },
      ));
      _scheduleTerminalRecovery(
        expectedSongId: songId,
        expectedQueueIndex: music.queueIndex,
        expectedIntent: authority.userGeneration,
        processingState: state.processingState,
      );
    }
  }

  void _scheduleTerminalRecovery({required String? expectedSongId, required int expectedQueueIndex, required int expectedIntent, required ProcessingState processingState}) {
    if (_terminalRecoveryInFlight) return;
    _terminalRecoveryInFlight = true;
    unawaited(() async {
      try {
        // Give a legitimate crossfade/terminal transition time to finish. The
        // recovery is deliberately outside MusicProvider's playback path so it
        // cannot interfere with a transition that is still committing.
        for (var i = 0; i < 40; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          if (music.currentSong?.id != expectedSongId || music.queueIndex != expectedQueueIndex) return;
          if (music.isPlaying) return;
          if (authority.userGeneration != expectedIntent) return;
          if (music.transitionInProgress) continue;
          final currentState = music.audioPlayer.playerState.processingState;
          if (currentState != ProcessingState.completed && currentState != ProcessingState.idle) return;
          break;
        }

        if (music.currentSong?.id != expectedSongId || music.queueIndex != expectedQueueIndex || music.isPlaying) return;
        if (authority.userGeneration != expectedIntent) return;
        final upcoming = music.queue.length - music.queueIndex - 1;
        if (upcoming <= 0) return;

        await ResonateDiagnostics.recordPlaybackCheckpoint(
          stage: 'terminal_recovery_attempt', source: 'diagnostics_recovery', command: 'next',
          songId: expectedSongId, songTitle: music.currentSong?.title,
          positionMs: music.currentPosition.inMilliseconds, durationMs: (music.currentDuration ?? music.currentSong?.duration)?.inMilliseconds,
          playing: music.isPlaying, processingState: music.audioPlayer.playerState.processingState.name,
          queueIndex: music.queueIndex, queueLength: music.queue.length, upcomingCount: upcoming,
          shuffle: music.shuffleEnabled, repeatMode: music.repeatMode.name, crossfadeEnabled: music.crossfadeEnabled,
          transitionInProgress: music.transitionInProgress, engine: authority.engineLabel(music), intentToken: expectedIntent,
          extra: {'reason': processingState.name, 'expectedSongId': expectedSongId},
        );

        await music.nextSong(source: 'diagnostics_recovery');

        await ResonateDiagnostics.recordPlaybackCheckpoint(
          stage: 'terminal_recovery_result', source: 'diagnostics_recovery', command: 'next',
          songId: music.currentSong?.id, songTitle: music.currentSong?.title,
          positionMs: music.currentPosition.inMilliseconds, durationMs: (music.currentDuration ?? music.currentSong?.duration)?.inMilliseconds,
          playing: music.isPlaying, processingState: music.audioPlayer.playerState.processingState.name,
          queueIndex: music.queueIndex, queueLength: music.queue.length,
          upcomingCount: music.queue.length - music.queueIndex - 1,
          shuffle: music.shuffleEnabled, repeatMode: music.repeatMode.name, crossfadeEnabled: music.crossfadeEnabled,
          transitionInProgress: music.transitionInProgress, engine: authority.engineLabel(music), intentToken: authority.userGeneration,
          extra: {'recoveredFromSongId': expectedSongId},
        );
      } catch (e, stack) {
        await ResonateDiagnostics.record('terminal_recovery_failed', {
          'songId': expectedSongId,
          'queueIndex': expectedQueueIndex,
          'error': e.toString(),
          'stack': stack.toString(),
        });
      } finally {
        _terminalRecoveryInFlight = false;
      }
    }());
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
    unawaited(ResonateDiagnostics.recordPlaybackCheckpoint(
      stage: event, source: authority.lastSource, command: authority.lastCommand, songId: music.currentSong?.id, songTitle: music.currentSong?.title,
      positionMs: music.currentPosition.inMilliseconds, durationMs: (music.currentDuration ?? music.currentSong?.duration)?.inMilliseconds,
      playing: music.isPlaying, processingState: state.processingState.name, queueIndex: music.queueIndex, queueLength: music.queue.length,
      upcomingCount: (music.queue.length - music.queueIndex - 1).clamp(0, music.queue.length).toInt(), shuffle: music.shuffleEnabled,
      repeatMode: music.repeatMode.name, crossfadeEnabled: music.crossfadeEnabled, transitionInProgress: music.transitionInProgress,
      engine: authority.engineLabel(music), intentToken: authority.userGeneration,
      extra: {
        'playerPlaying': state.playing, 'bufferedPositionMs': music.audioPlayer.bufferedPosition.inMilliseconds,
        'playerPositionMs': music.audioPlayer.position.inMilliseconds, 'playerDurationMs': music.audioPlayer.duration?.inMilliseconds,
        'lastCommandSource': authority.lastSource, 'lastCommand': authority.lastCommand, 'userCommandGeneration': authority.userGeneration,
        'hasCurrentSong': music.currentSong != null,
      },
    ));
  }

  @override
  void dispose() {
    music.removeListener(_observe);
    _heartbeat?.cancel();
    _heartbeat = null;
    super.dispose();
  }
}
