import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../providers/music_provider.dart';
import 'playback_authority.dart';
import 'resonate_diagnostics.dart';

/// Watches both app-level MusicProvider state and native just_audio state.
/// Emphasizes silent-load / auto-next failures: app wants play but native is not playing.
class PlaybackDiagnosticsObserver extends ChangeNotifier {
  final MusicProvider music;
  final PlaybackAuthority authority = PlaybackAuthority.instance;
  Timer? _heartbeat;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<PlaybackEvent>? _playbackEventSub;

  bool _lastAppPlaying = false;
  bool _lastNativePlaying = false;
  String? _lastSongId;
  int _lastQueueIndex = -1;
  ProcessingState _lastProcessingState = ProcessingState.idle;
  bool _terminalRecoveryInFlight = false;
  DateTime? _lastMismatchAt;

  PlaybackDiagnosticsObserver({required this.music}) {
    music.addListener(_observeApp);
    _bindNativeStreams();
    _heartbeat = Timer.periodic(const Duration(seconds: 4), (_) => _heartbeatTick());
    _observeApp();
  }

  void _bindNativeStreams() {
    _playerStateSub?.cancel();
    _playbackEventSub?.cancel();
    final player = music.audioPlayer;
    _playerStateSub = player.playerStateStream.listen((state) {
      _onNativeState(state);
    }, onError: (Object e, StackTrace st) {
      unawaited(ResonateDiagnostics.record('player_stream_error', {
        'stream': 'playerStateStream',
        'error': e.toString(),
        'stack': st.toString().length > 500 ? st.toString().substring(0, 500) : st.toString(),
        'songId': music.currentSong?.id,
      }));
    });
    _playbackEventSub = player.playbackEventStream.listen((event) {
      // Capture rare but useful native errors / icy metadata gaps.
      if (event.processingState == ProcessingState.idle && music.currentSong != null) {
        // ignore routine idle
      }
    }, onError: (Object e, StackTrace st) {
      unawaited(ResonateDiagnostics.record('player_stream_error', {
        'stream': 'playbackEventStream',
        'error': e.toString(),
        'songId': music.currentSong?.id,
      }));
    });
  }

  void _observeApp() {
    final player = music.audioPlayer;
    final state = player.playerState;
    final songId = music.currentSong?.id;
    final nativePlaying = player.playing;
    final changed = _lastAppPlaying != music.isPlaying ||
        _lastNativePlaying != nativePlaying ||
        _lastSongId != songId ||
        _lastQueueIndex != music.queueIndex ||
        _lastProcessingState != state.processingState;
    if (!changed) return;

    final previousAppPlaying = _lastAppPlaying;
    final previousNativePlaying = _lastNativePlaying;
    final previousSongId = _lastSongId;

    _lastAppPlaying = music.isPlaying;
    _lastNativePlaying = nativePlaying;
    _lastSongId = songId;
    _lastQueueIndex = music.queueIndex;
    _lastProcessingState = state.processingState;

    unawaited(_writeSnapshot(
      stage: 'app_state_changed',
      state: state,
      extra: {
        'previousAppPlaying': previousAppPlaying,
        'previousNativePlaying': previousNativePlaying,
        'previousSongId': previousSongId,
      },
    ));

    _maybeFlagMismatch(state);
    _maybeTerminalRecovery(state);
  }

  void _onNativeState(PlayerState state) {
    final nativePlaying = state.playing;
    final changed = _lastNativePlaying != nativePlaying ||
        _lastProcessingState != state.processingState;
    if (!changed) return;

    final previousNative = _lastNativePlaying;
    final previousProcessing = _lastProcessingState;
    _lastNativePlaying = nativePlaying;
    _lastProcessingState = state.processingState;

    unawaited(_writeSnapshot(
      stage: 'native_state_changed',
      state: state,
      extra: {
        'previousNativePlaying': previousNative,
        'previousProcessingState': previousProcessing.name,
      },
    ));

    _maybeFlagMismatch(state);
    _maybeTerminalRecovery(state);
  }

  void _maybeFlagMismatch(PlayerState state) {
    // App or user wants audio, native is silent, and we are not mid-load.
    final wants = music.isPlaying;
    final silent = !state.playing &&
        state.processingState != ProcessingState.loading &&
        state.processingState != ProcessingState.buffering;
    if (!wants || !silent || music.currentSong == null) return;

    final now = DateTime.now();
    if (_lastMismatchAt != null && now.difference(_lastMismatchAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastMismatchAt = now;

    unawaited(_writeSnapshot(
      stage: 'want_play_native_silent',
      state: state,
      extra: {
        'hint': 'app_isPlaying_true_but_native_playing_false',
      },
    ));
  }

  void _maybeTerminalRecovery(PlayerState state) {
    if (state.processingState != ProcessingState.completed) return;
    final upcoming = music.queue.length - music.queueIndex - 1;
    if (upcoming <= 0 && music.repeatMode.name == 'off') return;

    _scheduleTerminalRecovery(
      expectedSongId: music.currentSong?.id,
      expectedQueueIndex: music.queueIndex,
      expectedIntent: authority.userGeneration,
      processingState: state.processingState,
    );
  }

  void _scheduleTerminalRecovery({
    required String? expectedSongId,
    required int expectedQueueIndex,
    required int expectedIntent,
    required ProcessingState processingState,
  }) {
    if (_terminalRecoveryInFlight) return;
    _terminalRecoveryInFlight = true;
    unawaited(() async {
      try {
        // Give the normal completion path time to advance first.
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        if (music.currentSong?.id != expectedSongId) return;
        if (music.queueIndex != expectedQueueIndex) return;
        final upcoming = music.queue.length - music.queueIndex - 1;
        if (upcoming <= 0 && music.repeatMode.name == 'off') return;
        // Still stuck on completed track with upcoming songs.
        if (music.audioPlayer.processingState != ProcessingState.completed) return;

        await ResonateDiagnostics.recordPlaybackCheckpoint(
          stage: 'terminal_recovery_attempt',
          source: 'diagnostics_recovery',
          command: 'next',
          songId: expectedSongId,
          songTitle: music.currentSong?.title,
          positionMs: music.currentPosition.inMilliseconds,
          durationMs: (music.currentDuration ?? music.currentSong?.duration)?.inMilliseconds,
          playing: music.isPlaying,
          processingState: music.audioPlayer.playerState.processingState.name,
          queueIndex: music.queueIndex,
          queueLength: music.queue.length,
          upcomingCount: upcoming,
          shuffle: music.shuffleEnabled,
          repeatMode: music.repeatMode.name,
          crossfadeEnabled: music.crossfadeEnabled,
          transitionInProgress: music.transitionInProgress,
          engine: authority.engineLabel(music),
          intentToken: expectedIntent,
          extra: {'reason': processingState.name, 'expectedSongId': expectedSongId},
        );

        await music.nextSong(source: 'diagnostics_recovery');

        await ResonateDiagnostics.recordPlaybackCheckpoint(
          stage: 'terminal_recovery_result',
          source: 'diagnostics_recovery',
          command: 'next',
          songId: music.currentSong?.id,
          songTitle: music.currentSong?.title,
          positionMs: music.currentPosition.inMilliseconds,
          durationMs: (music.currentDuration ?? music.currentSong?.duration)?.inMilliseconds,
          playing: music.isPlaying,
          processingState: music.audioPlayer.playerState.processingState.name,
          queueIndex: music.queueIndex,
          queueLength: music.queue.length,
          upcomingCount: music.queue.length - music.queueIndex - 1,
          shuffle: music.shuffleEnabled,
          repeatMode: music.repeatMode.name,
          crossfadeEnabled: music.crossfadeEnabled,
          transitionInProgress: music.transitionInProgress,
          engine: authority.engineLabel(music),
          intentToken: authority.userGeneration,
          extra: {
            'recoveredFromSongId': expectedSongId,
            'nativePlaying': music.audioPlayer.playing,
          },
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
    // Always heartbeat when there is a current song or app thinks it is playing.
    if (music.currentSong == null && !music.isPlaying && state.processingState == ProcessingState.idle) {
      return;
    }
    unawaited(_writeSnapshot(stage: 'heartbeat', state: state));
    _maybeFlagMismatch(state);
  }

  Future<void> _writeSnapshot({
    required String stage,
    required PlayerState state,
    Map<String, dynamic> extra = const {},
  }) async {
    final song = music.currentSong;
    await ResonateDiagnostics.recordPlayerSnapshot(
      stage: stage,
      command: authority.lastCommand,
      source: authority.lastSource,
      songId: song?.id,
      songTitle: song?.title,
      filePath: song?.filePath,
      positionMs: music.currentPosition.inMilliseconds,
      durationMs: (music.currentDuration ?? song?.duration)?.inMilliseconds,
      appIsPlaying: music.isPlaying,
      nativePlaying: state.playing,
      userWantsPlaying: music.isPlaying, // proxy; detailed flag is inside provider steps
      processingState: state.processingState.name,
      queueIndex: music.queueIndex,
      queueLength: music.queue.length,
      androidAudioSessionId: music.audioPlayer.androidAudioSessionId,
      intentToken: authority.userGeneration,
      engine: authority.engineLabel(music),
      extra: {
        ...extra,
        'bufferedPositionMs': music.audioPlayer.bufferedPosition.inMilliseconds,
        'playerVolume': music.audioPlayer.volume,
        'appVolume': music.volume,
        'activeEngineA': true,
      },
    );
  }

  @override
  void dispose() {
    music.removeListener(_observeApp);
    _heartbeat?.cancel();
    _playerStateSub?.cancel();
    _playbackEventSub?.cancel();
    super.dispose();
  }
}
