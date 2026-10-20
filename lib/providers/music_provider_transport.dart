part of 'music_provider.dart';

/// Serialized transport commands separated from the core provider body.
/// Kept in the same Dart library to preserve access to private transport state.
extension MusicProviderTransport on MusicProvider {
Future<bool> playSong(Song song, {List<Song>? queue, int startIndex = 0, bool resumeIfPossible = false, int? resumeAtMs}) {
    final intentToken = _playbackIntentGate.issue();
    final wasXf = _crossfadeInProgress || _automaticCrossfadeInFlight;
    _cancelAutomaticPlaybackWork();
    if (wasXf) {
      unawaited(ResonateDiagnostics.record('crossfade_preempted_by_user', {
        'stage': 'play_song',
        'requestedSongId': song.id,
        'wasSongId': currentSong?.id,
        'queueIndex': _queueIndex,
      }));
    }
    _lastCompletionSongId = null;
    if (resumeAtMs != null && resumeAtMs > 1500) {
      _resumeSongId = song.id;
      _resumePositionMs = resumeAtMs;
      _resumeStore.bySongId[song.id] = resumeAtMs;
    } else if (resumeIfPossible) {
      final mapped = resumePositionFor(song.id);
      if (mapped != null) {
        _resumeSongId = song.id;
        _resumePositionMs = mapped;
      }
    }
    // Precise resume is a Mode playback policy. Normal/routine modes keep
    // the existing start-from-zero behavior; content/session modes that
    // explicitly require precise resume may restore the saved position.
    final shouldResume = _modePreciseResume &&
        resumeIfPossible &&
        _resumeSongId == song.id &&
        _resumePositionMs > 1500;
    return _serializePlayback(
      () => _playSongInternal(song, queue: queue, startIndex: startIndex, resume: shouldResume, playbackIntentToken: intentToken),
      command: 'play', source: 'normal_player', userInitiated: true, intentToken: intentToken,
      onSuperseded: () async => false,
    );
  }

Future<void> pause({String source = 'normal_player'}) {
    final intentToken = _playbackIntentGate.issue();
    final fromSystemFocus = source == 'system';
    final fromNoisy = source == 'becoming_noisy';
    // Clear user intent immediately (before async lane) so stream listeners and
    // ensureAudiblePlayback cannot race a late play() back in.
    if (!fromSystemFocus) {
      _userWantsPlaying = false;
      isPlaying = false;
      _lastUserPauseAt = DateTime.now();
      _volumeFadeGen++;
      _cancelAutomaticPlaybackWork();
      _crossfadeInProgress = false;
      _automaticCrossfadeInFlight = false;
      _repeatSelfHandoffInFlight = false;
      notifyListeners();
      _publishServiceState();
    }
    return _serializePlayback(() async {
      try {
        if (!fromSystemFocus) {
          _userWantsPlaying = false;
        }
        final midTransition =
            _crossfadeInProgress || _repeatSelfHandoffInFlight;
        try {
          await audioPlayer.pause();
        } catch (_) {}
        try {
          await inactivePlayer.pause();
        } catch (_) {}
        try {
          await _playerA.pause();
        } catch (_) {}
        try {
          await _playerB.pause();
        } catch (_) {}
        if (!midTransition) {
          try {
            await audioPlayer.setVolume(_effectiveCrossfadeMaster.clamp(0.0, 1.0));
          } catch (_) {}
          try {
            await inactivePlayer.setVolume(0.0);
          } catch (_) {}
        }
        isPlaying = false;
        _isDucked = false;
        _persistResumePosition(force: true);
        _podcastSession.onPaused(currentPosition);
    _audiobookSession.onPaused(currentPosition);
        _modes?.onPlaybackPaused();
        _publishServiceState();
        notifyListeners();
        await ResonateDiagnostics.record('audio_focus_pause', {
          'source': source,
          'userWantsPlaying': _userWantsPlaying,
          'preservedIntent': fromSystemFocus,
          'hardStop': true,
          'noisy': fromNoisy,
        });
      } catch (_) {}
    }, command: 'pause', source: source, userInitiated: !fromSystemFocus, intentToken: intentToken);
  }

Future<void> nextSong({String source = 'normal_player'}) {
    // Manual Next supersedes an automatic DJ/crossfade transition. The intent
    // token below invalidates the in-flight fade so it cannot commit afterward.
    // Keep queueing only for unrelated transport/load contention.
    if (_transportInFlight || _loadingSource) {
      _pendingNextSteps = (_pendingNextSteps + 1).clamp(0, 12);
      return Future<void>.value();
    }
    final wasCrossfadeActive = _crossfadeInProgress || _automaticCrossfadeInFlight;
    final intentToken = _playbackIntentGate.issue();
    _cancelAutomaticPlaybackWork();
    if (wasCrossfadeActive) {
      unawaited(ResonateDiagnostics.record('automatic_transition_preempted', {
        'command': 'next',
        'source': source,
        'songId': currentSong?.id,
        'queueIndex': _queueIndex,
      }));
    }

    return _serializePlayback(
      () async {
        if (_queue.isEmpty) return;
        final extra = _pendingNextSteps;
        _pendingNextSteps = 0;
        final steps = 1 + extra;
        // Phase 7: early skip after a DJ handoff → soft negative signal.
        try {
          final handoffAt = _lastDjHandoffAt;
          final fromId = _lastDjFromId;
          final toId = _lastDjToId;
          final strategy = _lastDjStrategy;
          if (handoffAt != null &&
              fromId != null &&
              toId != null &&
              strategy != null &&
              currentSong?.id == toId) {
            final age = DateTime.now().difference(handoffAt);
            final posMs = currentPosition.inMilliseconds;
            final durMs = (currentDuration ?? currentSong?.duration)?.inMilliseconds ?? 0;
            final earlyByTime = age < const Duration(seconds: 120) && posMs < 45000;
            final earlyByRatio =
                durMs > 0 && posMs < (durMs * 0.35).round() && age < const Duration(minutes: 3);
            if (earlyByTime || earlyByRatio) {
              // Heavier penalty the earlier the skip (deeper transition memory).
              final weight = posMs < 5000
                  ? 4
                  : posMs < 15000
                      ? 3
                      : posMs < 30000
                          ? 2
                          : 1;
              unawaited(DjTransitionMemory.recordOutcome(
                fromId: fromId,
                toId: toId,
                strategy: strategy,
                successful: false,
                weight: weight,
                score: _lastDjTransitionScore,
                confidence: _lastDjTransitionConfidence,
                risks: _lastDjTransitionRisks,
                transitionDurationMs: _lastDjTransitionDurationMs,
                recoveryAttempts: _lastDjRecoveryAttempts,
              ));
              unawaited(ResonateDiagnostics.recordDj(
                stage: 'learn',
                outcome: 'early_skip',
                reason: strategy,
                songId: toId,
                extra: {
                  'fromId': fromId,
                  'positionMs': posMs,
                  'weight': weight,
                  'ageMs': age.inMilliseconds,
                },
              ));
              _lastDjHandoffAt = null;
            }
          }
        } catch (_) {}
        _transportInFlight = true;
        try {
          var stepsLeft = steps.clamp(1, 12);
          while (stepsLeft > 0) {
            stepsLeft--;
            if (_queue.isEmpty) break;
            if (_queueIndex >= _queue.length - 1) {
              if (_repeatMode == PlaybackRepeatMode.all) {
                await _playSongInternal(_queue.first, queue: _queue, startIndex: 0, playbackIntentToken: intentToken);
              } else if (_repeatMode == PlaybackRepeatMode.one && currentSong != null) {
                await _playSongInternal(currentSong!, queue: _queue, startIndex: _queueIndex, playbackIntentToken: intentToken);
              }
              break;
            }
            final nextIndex = _queueIndex + 1;
            if (await _tryGaplessSeekToQueueIndex(nextIndex)) {
              if (_pendingNextSteps > 0 && stepsLeft == 0) {
                stepsLeft = _pendingNextSteps.clamp(0, 12);
                _pendingNextSteps = 0;
              }
              continue;
            }
            await _playSongInternal(
              _queue[nextIndex],
              queue: _queue,
              startIndex: nextIndex,
              playbackIntentToken: intentToken,
            );
            if (_pendingNextSteps > 0 && stepsLeft == 0) {
              stepsLeft = _pendingNextSteps.clamp(0, 12);
              _pendingNextSteps = 0;
            }
          }
        } finally {
          _transportInFlight = false;
          unawaited(_refreshTrackLevelingFor(currentSong));
          if (_pendingNextSteps > 0) {
            final again = _pendingNextSteps;
            _pendingNextSteps = 0;
            unawaited(Future<void>.delayed(const Duration(milliseconds: 40), () {
              for (var i = 0; i < again; i++) {
                unawaited(this.nextSong(source: source));
              }
            }));
          }
        }
      },
      command: 'next',
      source: source,
      userInitiated: true,
      intentToken: intentToken,
      onSuperseded: () async {},
    );
  }

Future<void> previousSong({String source = 'normal_player'}) {
    final intentToken = _playbackIntentGate.issue();
    _cancelAutomaticPlaybackWork();

    return _serializePlayback(
      () async {
        _transportInFlight = true;
        try {
          if (_queueIndex > 0) {
            final previousIndex = _queueIndex - 1;
            if (await _tryGaplessSeekToQueueIndex(previousIndex)) return;
            await _playSongInternal(
              _queue[previousIndex],
              queue: _queue,
              startIndex: previousIndex,
              playbackIntentToken: intentToken,
            );
          } else {
            await audioPlayer.seek(Duration.zero);
            currentPosition = Duration.zero;
            if (_historySession.activeEvent != null) _historySession.positionMs = 0;
            _persistResumePosition(force: true);
            notifyListeners();
            _publishServiceState();
          }
        } finally {
          _transportInFlight = false;
          unawaited(_refreshTrackLevelingFor(currentSong));
        }
      },
      command: 'previous',
      source: source,
      userInitiated: true,
      intentToken: intentToken,
      onSuperseded: () async {},
    );
  }

Future<void> seek(Duration position, {String source = 'normal_player'}) {
    final intentToken = _playbackIntentGate.issue();
    _cancelAutomaticPlaybackWork();
    return _serializePlayback(
      () async {
        if (!_playbackIntentGate.isCurrent(intentToken)) return;
        try {
          final duration = audioPlayer.duration ?? currentDuration ?? Duration.zero;
          final fromMs = currentPosition.inMilliseconds;
          final safe = Duration(
            milliseconds: position.inMilliseconds.clamp(0, duration.inMilliseconds).toInt(),
          );
          await audioPlayer.seek(safe);
          currentPosition = safe;
          if (_historySession.activeEvent != null) {
            _historySession.positionMs = safe.inMilliseconds;
          }
          // Local seek/replay evidence for Intelligence ranking (no audio content).
          final songId = currentSong?.id;
          if (songId != null && (fromMs - safe.inMilliseconds).abs() > 2500) {
            unawaited(IntelligenceSeekMemory().record(
              songId: songId,
              fromMs: fromMs,
              toMs: safe.inMilliseconds,
            ));
          }
          _persistResumePosition(force: true);
          _publishServiceState();
          notifyListeners();
        } catch (e) {
          debugPrint('Seek failed: $e');
        }
      },
      command: 'seek',
      source: source,
      userInitiated: true,
      intentToken: intentToken,
    );
  }
}
