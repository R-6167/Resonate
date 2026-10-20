part of 'music_provider.dart';

/// Crossfade lifecycle operations kept in the provider library so they can
/// share its private playback state while staying out of the core provider file.
extension CrossfadeOrchestration on MusicProvider {
Future<void> this._preloadNextForCrossfade() async {
    if (!effectiveCrossfadeEnabled || _crossfadePreloadInFlight || !canCrossfadeNext) return;
    final next = _crossfadeTargetSong;
    if (next == null || _preloadedNextSongId == next.id) return;

    // A preload is automatic work too. Capture ownership so a Mode change,
    // crossfade toggle, or manual transport cannot let a stale async preload
    // overwrite the idle engine after a newer command has taken ownership.
    final generation = _automaticTransitionGeneration;
    final transportEpoch = _userTransportEpoch;
    bool stillOwnsPreload() =>
        generation == _automaticTransitionGeneration &&
        transportEpoch == _userTransportEpoch &&
        effectiveCrossfadeEnabled &&
        _crossfadeTargetSong?.id == next.id;
    _crossfadePreloadInFlight = true;

    // DJ Mode: priority-warm analysis for current + next queue head.
    if (_djAnalysis != null &&
        (_djBeatAlignActive || _djTempoMatchActive)) {
      final cur = currentSong;
      if (cur != null) _djAnalysis!.scheduleAnalyze(cur);
      _djAnalysis!.scheduleAnalyze(next);
      final start = _queueIndex + 1;
      final end = (start + 4).clamp(0, _queue.length);
      for (var i = start; i < end; i++) {
        if (i != _crossfadeTargetIndex) _djAnalysis!.scheduleAnalyze(_queue[i]);
      }
    }

    final outgoing = audioPlayer;
    double? outgoingVol;
    try {
      outgoingVol = outgoing.volume;
    } catch (_) {
      outgoingVol = _volume;
    }

    try {
      final incoming = inactivePlayer;
      final incomingEq = inactiveEqualizer;
      final incomingLoud = inactiveLoudnessEnhancer;

      await incoming.setLoopMode(LoopMode.off);
      if (!stillOwnsPreload()) return;
      try {
        await incoming.stop();
      } catch (_) {}
      if (!stillOwnsPreload()) return;
      await incoming.setVolume(0.0);
      if (!stillOwnsPreload()) return;
      await incoming.setAudioSource(AudioSource.uri(_audioUri(next.filePath), tag: next));
      if (!stillOwnsPreload()) return;

      unawaited(_enableEffects(incoming, incomingEq, incomingLoud));
      await incoming.setVolume(0.0);
      if (!stillOwnsPreload()) return;

      // Decode/warm muted. Re-check ownership after every delay before
      // issuing more commands to the shared player.
      try {
        incoming.play();
      } catch (_) {}
      for (var i = 0; i < 6 && !incoming.playing; i++) {
        await Future<void>.delayed(Duration(milliseconds: 30 + i * 15));
        if (!stillOwnsPreload()) return;
        try {
          await incoming.setVolume(0.0);
        } catch (_) {}
        if (!stillOwnsPreload()) return;
        if (i % 2 == 0) {
          try {
            incoming.play();
          } catch (_) {}
        }
      }
      if (!stillOwnsPreload()) return;
      try {
        await incoming.pause();
      } catch (_) {}
      if (!stillOwnsPreload()) return;
      try {
        await incoming.seek(Duration.zero);
      } catch (_) {}
      if (!stillOwnsPreload()) return;
      await incoming.setVolume(0.0);
      if (!stillOwnsPreload()) return;

      // Do not let a stale preload restore gain on an engine that has become
      // active for a newer transition.
      try {
        final targetOut = (outgoingVol ?? _volume).clamp(0.0, 1.0);
        if (identical(outgoing, audioPlayer) &&
            (outgoing.volume - targetOut).abs() > 0.02) {
          await outgoing.setVolume(targetOut);
        }
      } catch (_) {}
      if (!stillOwnsPreload()) return;

      _preloadedNextSongId = next.id;
      await ResonateDiagnostics.record('crossfade_preloaded', {
        'songId': next.id,
        'queueIndex': _crossfadeTargetIndex,
        'playing': incoming.playing,
        'repeatMode': _repeatMode.name,
        'outgoingVolume': outgoingVol,
      });
    } catch (e) {
      if (generation == _automaticTransitionGeneration &&
          transportEpoch == _userTransportEpoch) {
        if (_preloadedNextSongId == next.id) _preloadedNextSongId = null;
        debugPrint('crossfade preload failed: $e');
        await ResonateDiagnostics.record('crossfade_preload_failed', {
          'error': e.toString(),
          'songId': next.id,
        });
      }
    } finally {
      // A cancelled older preload must not clear the in-flight flag belonging
      // to a newer preload started after cancellation.
      if (generation == _automaticTransitionGeneration &&
          transportEpoch == _userTransportEpoch) {
        _crossfadePreloadInFlight = false;
      }
    }
  }

Future<void> this._runAutomaticCrossfade() async {
    // Do not even register automatic ownership if a user transport is queued.
    if (_transportInFlight || _loadingSource || _userTransportPending) {
      _automaticCrossfadeInFlight = false;
      _crossfadeInProgress = false;
      _transitionArmedAt = null;
      return;
    }
    final generation = _authority.beginAutomatic('automatic_crossfade');
    final transitionMarker = _automaticTransitionGeneration + 1;
    final epoch = _userTransportEpoch;
    final fromIndex = _queueIndex;
    final fromSongId = currentSong?.id;
    final transitionGuard = CrossfadeTransitionGuard(
      userTransportEpoch: epoch,
      transitionGeneration: transitionMarker,
      outgoingSongId: fromSongId,
      queueIndex: fromIndex,
    );
    if (_transportInFlight || _loadingSource || _userTransportPending) {
      _automaticCrossfadeInFlight = false;
      _crossfadeInProgress = false;
      _transitionArmedAt = null;
      return;
    }
    try {
      final djActive = _djBeatAlignActive || _djTempoMatchActive || _djSfxActive;
      final plannedBias = _lastDjCrossfadeBiasMs;
      final xfMs = (djActive
              ? (_crossfadeDurationMs + plannedBias).clamp(500, 6500)
              : _crossfadeDurationMs)
          .toInt();
      // Position events can become discontinuous around backgrounding/audio
      // service resumes. Revalidate the actual remaining time here instead of
      // trusting the earlier position-stream trigger to still be current.
      final durationNow = audioPlayer.duration;
      final remainingNowMs = durationNow == null
          ? null
          : durationNow.inMilliseconds - audioPlayer.position.inMilliseconds;
      final startMarginMs = (1200 + (xfMs ~/ 10)).clamp(1500, 3000);
      final safeTriggerMs = (xfMs + startMarginMs).clamp(2000, 16000);
      // Background/route changes can briefly invalidate timing signals. Fail
      // closed when the active engine has no trustworthy duration/position,
      // and never start a transition outside the near-end window.
      if (durationNow == null ||
          durationNow <= Duration.zero ||
          remainingNowMs == null ||
          remainingNowMs > safeTriggerMs ||
          remainingNowMs < 1200) {
        _automaticCrossfadeInFlight = false;
        _crossfadeInProgress = false;
        _transitionArmedAt = null;
        await ResonateDiagnostics.record('crossfade_aborted_timing_revalidation', {
          'remainingMs': remainingNowMs,
          'safeTriggerMs': safeTriggerMs,
          'durationMs': durationNow?.inMilliseconds,
          'positionMs': audioPlayer.position.inMilliseconds,
          'engine': _activeIsA ? 'A' : 'B',
          'reason': durationNow == null || durationNow <= Duration.zero
              ? 'duration_unavailable'
              : remainingNowMs == null
                  ? 'position_unavailable'
                  : remainingNowMs > safeTriggerMs
                      ? 'not_near_end'
                      : 'too_late',
          'outgoingSongId': fromSongId,
          'queueIndex': fromIndex,
        });
        return;
      }
      final timeout =
          Duration(milliseconds: (xfMs + 12000).clamp(12000, 30000));
      final ok = await this._performTrueCrossfade(
        milliseconds: xfMs,
        fadeType: _crossfadeFadeType,
        generation: generation,
      ).timeout(timeout, onTimeout: () {
        debugPrint('automatic crossfade timed out');
        // Future.timeout does not cancel the underlying Future. Invalidate its
        // ownership before fallback/cleanup so a delayed native player call
        // cannot later commit the handoff or restore stale gain.
        if (_userTransportEpoch == epoch &&
            _automaticTransitionGeneration == transitionMarker) {
          _automaticTransitionGeneration++;
          _preloadedNextSongId = null;
          _crossfadePreloadInFlight = false;
          _automaticCrossfadeInFlight = false;
          _crossfadeInProgress = false;
          _transitionArmedAt = null;
          unawaited(ResonateDiagnostics.record('crossfade_timeout_invalidated', {
            'transitionGeneration': transitionMarker,
            'currentGeneration': _automaticTransitionGeneration,
            'userTransportEpoch': _userTransportEpoch,
            'outgoingSongId': fromSongId,
            'queueIndex': fromIndex,
            'timeoutMs': timeout.inMilliseconds,
          }));
        }
        return false;
      });
      if (ok) return;
      if (!transitionGuard.matches(
            userTransportEpoch: _userTransportEpoch,
            transitionGeneration: _automaticTransitionGeneration,
            currentSongId: currentSong?.id,
            queueIndex: _queueIndex,
          ) ||
          _authority.isStale(generation)) {
        await ResonateDiagnostics.record('crossfade_fallback_skipped_already_advanced', {
          'preempted': _userTransportEpoch != epoch,
          'fromSongId': fromSongId,
          'fromIndex': fromIndex,
          'nowSongId': currentSong?.id,
          'nowIndex': _queueIndex,
        });
        try {
          await inactivePlayer.stop();
        } catch (_) {}
        return;
      }
      await ResonateDiagnostics.record('crossfade_fallback_soft', {
        'fromSongId': fromSongId,
        'queueIndex': fromIndex,
      });
      try {
        await inactivePlayer.stop();
      } catch (_) {}
      await this._softFadeOutActive(milliseconds: 500);
      if (!transitionGuard.matches(
            userTransportEpoch: _userTransportEpoch,
            transitionGeneration: _automaticTransitionGeneration,
            currentSongId: currentSong?.id,
            queueIndex: _queueIndex,
          ) ||
          _authority.isStale(generation)) {
        await ResonateDiagnostics.record('crossfade_preempted_by_user', {
          'stage': 'fallback_soft',
          'fromSongId': fromSongId,
        });
        return;
      }
      final nextIdx = CrossfadeFallbackTarget.nextIndex(
        currentIndex: fromIndex,
        queueLength: _queue.length,
        repeatAll: _repeatMode == PlaybackRepeatMode.all,
      );
      if (nextIdx >= 0) {
        final next = _queue[nextIdx];
        final token = _playbackIntentGate.issue();
        await _playSongInternal(next, queue: _queue, startIndex: nextIdx, playbackIntentToken: token);
      }
    } catch (e) {
      debugPrint('automatic crossfade error: $e');
      if (transitionGuard.matches(
            userTransportEpoch: _userTransportEpoch,
            transitionGeneration: _automaticTransitionGeneration,
            currentSongId: currentSong?.id,
            queueIndex: _queueIndex,
          ) &&
          !_authority.isStale(generation)) {
        try {
          await inactivePlayer.stop();
        } catch (_) {}
        try {
          await this._softFadeOutActive(milliseconds: 400);
        } catch (_) {}
        final nextIdx = CrossfadeFallbackTarget.nextIndex(
          currentIndex: fromIndex,
          queueLength: _queue.length,
          repeatAll: _repeatMode == PlaybackRepeatMode.all,
        );
        if (nextIdx >= 0) {
          try {
            final next = _queue[nextIdx];
            final token = _playbackIntentGate.issue();
            await _playSongInternal(next, queue: _queue, startIndex: nextIdx, playbackIntentToken: token);
          } catch (_) {}
        }
      }
    } finally {
      if (_automaticTransitionGeneration == transitionMarker) {
        _automaticCrossfadeInFlight = false;
        _crossfadeInProgress = false;
      }
    }
  }

Future<void> this._softFadeOutActive({int milliseconds = 500}) async {
    final player = audioPlayer;
    final steps = (milliseconds / 40).round().clamp(4, 40);
    double start = _eqPreampScale;
    try {
      start = player.volume.clamp(0.0, 1.0);
    } catch (_) {}
    if (start <= 0.02) {
      try {
        await player.pause();
      } catch (_) {}
      return;
    }
    for (var i = 1; i <= steps; i++) {
      final t = i / steps;
      final gain = CrossfadeFallbackFade.outgoingGain(t);
      try {
        await player.setVolume((start * gain).clamp(0.0, 1.0));
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    try {
      await player.setVolume(0.0);
    } catch (_) {}
    try {
      await player.pause();
    } catch (_) {}
  }

Future<bool> this._performTrueCrossfade({required int milliseconds, String fadeType = 'linear', required int generation, int? playbackIntentToken}) async {
    final intentToken = playbackIntentToken ?? _playbackIntentGate.currentToken;
    final transitionGeneration = ++_automaticTransitionGeneration;
    final transportEpoch = _userTransportEpoch;
    final bassDuckOriginal = <int, double>{};
    if (!_playbackIntentGate.isCurrent(intentToken)) return false;
    if (!canCrossfadeNext || currentSong == null || !audioPlayer.playing) return false;
    final nextIndex = _crossfadeTargetIndex;
    final nextSong = _crossfadeTargetSong;
    if (nextSong == null || nextSong.filePath.trim().isEmpty) return false;
    _crossfadeInProgress = true; _transitionArmedAt = DateTime.now(); final outgoing = audioPlayer; final outgoingSong = currentSong; final incoming = inactivePlayer; final incomingEq = inactiveEqualizer; final incomingLoud = inactiveLoudnessEnhancer; final master = _effectiveCrossfadeMaster.clamp(0.05, 1.0).toDouble();
    try {
      await _clearDjStretchSpeeds(outgoing: outgoing, incoming: incoming);
      await outgoing.setLoopMode(LoopMode.off);

      // Gapless concatenating source fights dual-engine crossfade (index jumps,
      // double-completion). Flatten outgoing to a single URI at current position.
      if (_gaplessWindow.active && outgoingSong != null) {
        final holdPos = outgoing.position;
        final wasPlaying = outgoing.playing;
        try {
          await _loadSingle(
            outgoing,
            equalizer,
            loudnessEnhancer,
            outgoingSong,
            start: false,
          );
          try {
            await outgoing.seek(holdPos);
          } catch (_) {}
          try {
            await outgoing.setVolume(_effectiveCrossfadeMaster.clamp(0.05, 1.0));
          } catch (_) {}
          if (wasPlaying) {
            try {
              outgoing.play();
            } catch (_) {}
          }
          unawaited(ResonateDiagnostics.record('crossfade_gapless_flattened', {
            'songId': outgoingSong.id,
            'positionMs': holdPos.inMilliseconds,
          }));
        } catch (e) {
          debugPrint('gapless flatten for crossfade: $e');
        }
        _gaplessWindow.active = false;
        _gaplessWindow.songIds = const [];
      }

      final alreadyPreloaded = _preloadedNextSongId == nextSong.id;
      if (!alreadyPreloaded) {
        try {
          await incoming.stop();
        } catch (_) {}
        await _loadSingle(incoming, incomingEq, incomingLoud, nextSong, start: false);
      } else {
        await ResonateDiagnostics.record('crossfade_using_preload', {
          'songId': nextSong.id,
        });
        try {
          await incoming.seek(Duration.zero);
        } catch (_) {}
      }
      await incoming.setVolume(0.0);
      // Hard-mute before play — prevents a one-frame blast / static on some OEMs.
      try {
        await outgoing.setVolume(outgoing.volume.clamp(0.0, 1.0));
      } catch (_) {}
      try {
        final session = await AudioSession.instance;
        await session.setActive(true);
      } catch (_) {}
      await _prepareDjHandoff(
        outgoing: outgoing,
        incoming: incoming,
        outgoingSong: outgoingSong,
        incomingSong: nextSong,
      );
      final djExecution = _activeDjExecutionPlan;
      final bassDuckNeeded = _lastDjBassDuckNeeded;
      if (_automaticTransitionGeneration != transitionGeneration ||
          _authority.isStale(generation) ||
          !_playbackIntentGate.isCurrent(intentToken)) {
        try { await incoming.stop(); } catch (_) {}
        await _clearDjStretchSpeeds(outgoing: outgoing, incoming: incoming);
        return false;
      }
      if (bassDuckNeeded) {
        final capturedBassDuck = await _audioEffectsController.duckBassForTransition(
          equalizer: incomingEq,
          attenuationDb: 4.0,
        );
        bassDuckOriginal
          ..clear()
          ..addAll(capturedBassDuck);
        unawaited(ResonateDiagnostics.record('dj_bass_duck', {
          'action': 'engage',
          'attenuationDb': 4.0,
          'bands': bassDuckOriginal.keys.toList(),
          'songId': nextSong.id,
        }));
      }
      final sfxStep = djExecution == null ? null : djExecution.steps.cast<DjExecutionStep?>().firstWhere(
        (step) => step?.action == 'trigger_sfx',
        orElse: () => null,
      );
      final plannedSfxMs = sfxStep?.atMs ?? 0;
      final fadeWindowMs = milliseconds.clamp(500, 12000);
      DjTrackProfile? outProfile;
      try {
        final id = outgoingSong?.id;
        if (id != null && _djAnalysis != null) {
          outProfile = await _djAnalysis!.getProfile(id);
        }
      } catch (_) {}
      await _engageDjTransitionSfx(
        energyScore: _lastDjEnergyScore,
        transitionKind: _djTransitionKindFromName(_lastDjStrategy),
        delay: _snapSfxDelayToPhrase(
          planned: Duration(milliseconds: plannedSfxMs),
          fadeMs: fadeWindowMs,
          outgoingProfile: outProfile,
        ),
        outgoingProfile: outProfile,
      );

      // A user can select a different Library track while preparation awaits
      // analysis/SFX work. Re-check ownership immediately before starting B;
      // the fade-loop guard alone is too late because B may already be audible.
      bool transitionWasPreempted() =>
          _userTransportEpoch != transportEpoch ||
          _automaticTransitionGeneration != transitionGeneration ||
          _authority.isStale(generation) ||
          !_playbackIntentGate.isCurrent(intentToken);

      if (transitionWasPreempted()) {
        // A newer transport now owns both reusable engines and their effects.
        // Do not stop/mute either engine here: the incoming engine may already
        // have been repurposed to play the user's newly selected track.
        await ResonateDiagnostics.record('crossfade_cancelled', {
          'stage': 'before_incoming_start',
          'preempted': _userTransportEpoch != transportEpoch,
          'outgoingSongId': outgoingSong?.id,
          'incomingSongId': nextSong.id,
          'intentToken': intentToken,
        });
        return false;
      }

      // Fire-and-poll play on B — await play() can hang and block auto-next forever.
      try {
        incoming.play();
      } catch (_) {}
      var incomingStarted = incoming.playing;
      for (var i = 0; i < 25 && !incomingStarted; i++) {
        // Do not retry play/seek on B after a manual transport supersedes us.
        if (transitionWasPreempted()) {
          // Engine instances are shared with manual playback. The new
          // transport owns cleanup; stale crossfade work must not touch them.
          await ResonateDiagnostics.record('crossfade_cancelled', {
            'stage': 'incoming_start_poll',
            'preempted': _userTransportEpoch != transportEpoch,
            'outgoingSongId': outgoingSong?.id,
            'incomingSongId': nextSong.id,
            'intentToken': intentToken,
          });
          return false;
        }
        if (incoming.playing) {
          incomingStarted = true;
          break;
        }
        if (i == 5 || i == 12 || i == 18) {
          try { await incoming.seek(Duration.zero); } catch (_) {}
          if (!transitionWasPreempted()) {
            try { incoming.play(); } catch (_) {}
          }
        }
        await Future<void>.delayed(Duration(milliseconds: 40 + i * 15));
        incomingStarted = incoming.playing;
      }
      if (!incomingStarted) {
        _preloadedNextSongId = null;
        await ResonateDiagnostics.record('crossfade_incoming_start_failed', {
          'outgoingSongId': outgoingSong?.id,
          'incomingSongId': nextSong.id,
        });
        throw StateError('crossfade incoming engine failed to start');
      }
      await Future<void>.delayed(const Duration(milliseconds: 60));
      // The selected track may have changed during the settle delay. Never let
      // this stale transition issue play/volume commands against a reused engine.
      if (transitionWasPreempted()) {
        await ResonateDiagnostics.record('crossfade_cancelled', {
          'stage': 'incoming_start_settle',
          'preempted': _userTransportEpoch != transportEpoch,
          'outgoingSongId': outgoingSong?.id,
          'incomingSongId': nextSong.id,
          'intentToken': intentToken,
        });
        return false;
      }
      try { if (!incoming.playing) incoming.play(); } catch (_) {}
      if (transitionWasPreempted()) {
        await ResonateDiagnostics.record('crossfade_cancelled', {
          'stage': 'incoming_start_settle_play',
          'preempted': _userTransportEpoch != transportEpoch,
          'outgoingSongId': outgoingSong?.id,
          'incomingSongId': nextSong.id,
          'intentToken': intentToken,
        });
        return false;
      }
      // Start from the *current* outgoing level — never boost to master mid-track
      // (that was the pre-crossfade "bump" on some files).
      double startOut = master;
      try {
        startOut = outgoing.volume.clamp(0.0, 1.0);
      } catch (_) {}
      if (startOut > master) startOut = master;
      // Cap base to master so we never fade from above user volume.
      // Preserve intentional silence/ducking; a near-zero level is not permission to jump to master.
      final base = startOut;
      try {
        await outgoing.setVolume(base);
      } catch (_) {}
      // Volume writes are asynchronous; the user may have selected another
      // track while the outgoing engine was applying its level.
      if (transitionWasPreempted()) {
        await ResonateDiagnostics.record('crossfade_cancelled', {
          'stage': 'initial_outgoing_volume',
          'preempted': _userTransportEpoch != transportEpoch,
          'outgoingSongId': outgoingSong?.id,
          'incomingSongId': nextSong.id,
          'intentToken': intentToken,
        });
        return false;
      }
      await incoming.setVolume(0.0);
      if (transitionWasPreempted()) {
        await ResonateDiagnostics.record('crossfade_cancelled', {
          'stage': 'initial_incoming_volume',
          'preempted': _userTransportEpoch != transportEpoch,
          'outgoingSongId': outgoingSong?.id,
          'incomingSongId': nextSong.id,
          'intentToken': intentToken,
        });
        return false;
      }

      // DJ Mode: long fades (8–12s) + stretch/SFX feel mushy and raise static risk.
      final djActive = _djBeatAlignActive || _djTempoMatchActive || _djSfxActive;
      final maxMs = djActive ? 6500 : 12000;
      final plannedMs =
          (milliseconds + _lastDjCrossfadeBiasMs).clamp(500, maxMs).toInt();
      if (_lastDjCrossfadeBiasMs != 0 || (djActive && milliseconds > maxMs)) {
        unawaited(ResonateDiagnostics.record('crossfade_energy_bridge', {
          'biasMs': _lastDjCrossfadeBiasMs,
          'baseMs': milliseconds,
          'plannedMs': plannedMs,
          'djCapped': djActive && milliseconds > maxMs,
          'outgoingSongId': outgoingSong?.id,
          'incomingSongId': nextSong.id,
        }));
      }
      int remainingMs = plannedMs;
      try {
        final d = outgoing.duration;
        final p = outgoing.position;
        if (d != null && d > Duration.zero) {
          final rem = d.inMilliseconds - p.inMilliseconds;
          if (rem < 1200) {
            await ResonateDiagnostics.record('crossfade_aborted_too_late', {
              'remainingMs': rem,
              'plannedMs': plannedMs,
            });
            try { await incoming.stop(); } catch (_) {}
            try { await outgoing.setVolume(base); } catch (_) {}
            await _clearDjStretchSpeeds(outgoing: outgoing, incoming: incoming);
            await _restoreDjTransitionSfx();
            return false;
          }
          remainingMs = (rem - 150).clamp(1200, plannedMs).toInt();
        }
      } catch (_) {}
      final total = remainingMs;
      // Snapshot analysis for this transition. A stale A/B loop must never
      // read a newer transition's beat grid while it is unwinding.
      final runtimeBeatMs = List<int>.from(_lastDjIncomingBeatMs);
      final runtimeBpm = _lastDjIncomingBpm;
      final gentle = Platform.isAndroid;
      final stepMs = gentle ? 36 : 24;
      final fadeStartedAt = DateTime.now();
      var lastOut = base;
      var lastIncomingPositionMs = incoming.position.inMilliseconds;
      var lastIncomingProgressAt = fadeStartedAt;
      var incomingRecoveryAttempts = 0;
      var monitorTick = 0;
      while (true) {
        if (_userTransportEpoch != transportEpoch ||
            _automaticTransitionGeneration != transitionGeneration ||
            _authority.isStale(generation) ||
            !_playbackIntentGate.isCurrent(intentToken)) {
          // Do not issue engine/effect commands after ownership changes.
          // The replacement transport may already be using either A or B.
          await ResonateDiagnostics.record('crossfade_cancelled', {
            'stage': 'fade',
            'preempted': _userTransportEpoch != transportEpoch,
            'outgoingSongId': outgoingSong?.id,
            'incomingSongId': nextSong.id,
            'intentToken': intentToken,
          });
          return false;
        }
        final elapsed = DateTime.now().difference(fadeStartedAt).inMilliseconds;
        // The runtime monitor and DJ FX sweep also use normalized progress.
        final linear = CrossfadeFrameProgress.calculate(
          elapsedMs: elapsed,
          totalMs: total,
        ).fraction;
        final gains = CrossfadeOrchestrator.gains(
          elapsedMs: elapsed,
          totalMs: total,
          fadeType: fadeType,
        );
        final outGain = gains.outgoing;
        final inGain = gains.incoming;
        // If focus is lost mid-fade, scale both engines down together. If focus
        // returns, _unduckAfterInterruption defers restoration until this fade ends.
        final frameMaster = _effectiveCrossfadeMaster.clamp(0.05, 1.0).toDouble();
        final frameVolumes = CrossfadeFrameVolumes.calculate(
          base: base,
          master: master,
          frameMaster: frameMaster,
          outgoingGain: outGain,
          incomingGain: inGain,
        );
        final outVol = frameVolumes.outgoing;
        final inVol = frameVolumes.incoming;
        lastOut = outVol;
        final stepStarted = DateTime.now();
        try {
          // Parallel volume writes so outgoing does not stall waiting on incoming.
          await Future.wait([
            outgoing.setVolume(outVol),
            incoming.setVolume(inVol),
          ]);
        } catch (_) {}

        // A manual transport can arrive while either native volume write is
        // awaiting completion. Re-check ownership before runtime monitoring,
        // which may call play() to recover the incoming engine.
        if (transitionWasPreempted()) {
          await ResonateDiagnostics.record('crossfade_cancelled', {
            'stage': 'fade_volume_write',
            'preempted': _userTransportEpoch != transportEpoch,
            'outgoingSongId': outgoingSong?.id,
            'incomingSongId': nextSong.id,
            'intentToken': intentToken,
          });
          return false;
        }

        // Runtime DJ monitor: the transition must adapt to the actual A/B
        // engines, not merely the planned timeline. A transient start delay is
        // recovered; a persistent stall falls back to ordinary playback.
        monitorTick++;
        if (monitorTick % 5 == 0) {
          try {
            if (!incoming.playing && linear < 0.92) {
              incomingRecoveryAttempts++;
              await ResonateDiagnostics.record('dj_runtime_monitor', {
                'event': 'incoming_not_playing',
                'attempt': incomingRecoveryAttempts,
                'linear': linear,
                'positionMs': incoming.position.inMilliseconds,
                'songId': nextSong.id,
              });
              if (transitionWasPreempted()) return false;
              if (incomingRecoveryAttempts <= 2) {
                incoming.play();
              } else {
                throw StateError('DJ incoming engine stalled during transition');
              }
            } else if (incoming.playing) {
              final incomingPos = incoming.position.inMilliseconds;
              // Continuous beat-phase correction: use a tiny temporary speed
              // change instead of seeking. This preserves audio continuity and
              // lets the incoming engine converge toward the detected beat grid.
              final now = DateTime.now();
              if (_djRuntimeCorrectionUntil != null && now.isAfter(_djRuntimeCorrectionUntil!)) {
                try { await incoming.setSpeed(_djRuntimeCorrectionBaseSpeed); } catch (_) {}
                if (transitionWasPreempted()) return false;
                _djRuntimeCorrectionUntil = null;
              }
              if (runtimeBeatMs.length >= 4 &&
                  _djBeatCorrectionAttempts < 2 &&
                  (runtimeBpm ?? 0) >= 40 &&
                  (runtimeBpm ?? 0) <= 240 &&
                  linear > 0.08 &&
                  linear < 0.92) {
                var nearest = runtimeBeatMs.first;
                var distance = (incomingPos - nearest).abs();
                for (final beat in runtimeBeatMs) {
                  final d = (incomingPos - beat).abs();
                  if (d < distance) {
                    distance = d;
                    nearest = beat;
                  }
                  if (beat > incomingPos + 250) break;
                }
                final driftMs = incomingPos - nearest;
                final decision = _djBeatDriftCorrector.decide(
                  driftMs: driftMs,
                  bpm: runtimeBpm!,
                  baseSpeed: _djRuntimeCorrectionBaseSpeed,
                );
                if (decision != null) {
                  _djBeatCorrectionAttempts++;
                  try {
                    await incoming.setSpeed(decision.speed);
                    if (transitionWasPreempted()) return false;
                    _djRuntimeCorrectionUntil = now.add(Duration(milliseconds: decision.holdMs));
                    await ResonateDiagnostics.record('dj_runtime_monitor', {
                      'event': 'beat_phase_speed_corrected',
                      'attempt': _djBeatCorrectionAttempts,
                      'fromPositionMs': incomingPos,
                      'targetBeatMs': nearest,
                      'driftMs': decision.driftMs,
                      'speed': decision.speed,
                      'baseSpeed': _djRuntimeCorrectionBaseSpeed,
                      'holdMs': decision.holdMs,
                      'linear': linear,
                      'songId': nextSong.id,
                    });
                    if (transitionWasPreempted()) return false;
                  } catch (_) {}
                }
              }
              if (incomingPos > lastIncomingPositionMs + 20) {
                lastIncomingPositionMs = incomingPos;
                lastIncomingProgressAt = DateTime.now();
                incomingRecoveryAttempts = 0;
              } else if (DateTime.now().difference(lastIncomingProgressAt).inMilliseconds > 900 &&
                  linear < 0.92) {
                incomingRecoveryAttempts++;
                await ResonateDiagnostics.record('dj_runtime_monitor', {
                  'event': 'incoming_position_stalled',
                  'attempt': incomingRecoveryAttempts,
                  'linear': linear,
                  'positionMs': incomingPos,
                  'songId': nextSong.id,
                });
                if (transitionWasPreempted()) return false;
                if (incomingRecoveryAttempts <= 2) {
                  incoming.play();
                  lastIncomingProgressAt = DateTime.now();
                } else {
                  throw StateError('DJ incoming position stalled during transition');
                }
              }
            }
          } catch (e) {
            if (e is StateError) rethrow;
            // Monitoring itself must never become a playback failure.
          }
        }

        // Club-style filter-sweep feel alongside the volume curve.
        if (_djSfxEngaged && (linear * 20).round() % 2 == 0) {
          unawaited(_tickDjClubFxSweep(linear));
        }
        if (linear >= 1.0) break;
        final spent = DateTime.now().difference(stepStarted).inMilliseconds;
        final sleep = (stepMs - spent).clamp(0, stepMs);
        if (sleep > 0) {
          await Future<void>.delayed(Duration(milliseconds: sleep));
        }
      }
      await _restoreDjTransitionSfx();
      if (transitionWasPreempted()) {
        await ResonateDiagnostics.record('crossfade_cancelled', {
          'stage': 'after_fade_sfx_restore',
          'preempted': _userTransportEpoch != transportEpoch,
          'outgoingSongId': outgoingSong?.id,
          'incomingSongId': nextSong.id,
          'intentToken': intentToken,
        });
        return false;
      }
      // Guarantee silence on outgoing before pause/stop — never cut from a
      // still-audible level (the "sudden volume loss" symptom).
      for (var s = 0; s < 3; s++) {
        if (transitionWasPreempted()) {
          await ResonateDiagnostics.record('crossfade_cancelled', {
            'stage': 'outgoing_mute',
            'preempted': _userTransportEpoch != transportEpoch,
            'outgoingSongId': outgoingSong?.id,
            'incomingSongId': nextSong.id,
            'intentToken': intentToken,
          });
          return false;
        }
        try { await outgoing.setVolume(0.0); } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 25));
        try {
          if (outgoing.volume <= 0.02) break;
        } catch (_) {
          break;
        }
      }
      if (_userTransportEpoch != transportEpoch ||
          _automaticTransitionGeneration != transitionGeneration ||
          _authority.isStale(generation) ||
          !_playbackIntentGate.isCurrent(intentToken)) {
        await ResonateDiagnostics.record('crossfade_cancelled', {'stage': 'commit', 'preempted': _userTransportEpoch != transportEpoch, 'outgoingSongId': outgoingSong?.id, 'incomingSongId': nextSong.id, 'intentToken': intentToken}); return false; }
      // Finish the outgoing history record while currentSong still refers to it.
      // Mutating currentSong first caused history to be attributed to the next track.
      await _finishHistoryEvent();
      if (transitionWasPreempted()) {
        await ResonateDiagnostics.record('crossfade_cancelled', {
          'stage': 'finish_history',
          'preempted': _userTransportEpoch != transportEpoch,
          'outgoingSongId': outgoingSong?.id,
          'incomingSongId': nextSong.id,
          'intentToken': intentToken,
        });
        return false;
      }
      // Pause only after volume is already 0 so pause cannot audibly chop the tail.
      try { await outgoing.pause(); } catch (_) {}
      if (transitionWasPreempted()) return false;
      try { await incoming.setLoopMode(LoopMode.off); } catch (_) {}
      if (transitionWasPreempted()) return false;
      try { await incoming.setVolume(_effectiveCrossfadeMaster.clamp(0.05, 1.0)); } catch (_) {}
      if (transitionWasPreempted()) return false;
      await _clearDjStretchSpeeds(outgoing: outgoing, incoming: incoming);
      if (transitionWasPreempted()) return false;
      try {
        if (incoming.volume < 0.05) await incoming.setVolume(_effectiveCrossfadeMaster.clamp(0.05, 1.0));
      } catch (_) {}
      if (transitionWasPreempted()) return false;
      // Hard guarantee: incoming must be audible before we flip active engine.
      try {
        await incoming.setSpeed(1.0);
        if (transitionWasPreempted()) return false;
        await incoming.setVolume(_effectiveCrossfadeMaster.clamp(0.05, 1.0));
        if (transitionWasPreempted()) return false;
        if (!incoming.playing) {
          try { incoming.play(); } catch (_) {}
        }
        await ResonateDiagnostics.record('crossfade_commit_volume', {
          'volume': incoming.volume,
          'playing': incoming.playing,
          'master': master,
          'songId': nextSong.id,
        });
      } catch (_) {}
      if (transitionWasPreempted()) return false;
      _activeIsA = !_activeIsA; // Phase 2: only crossfade may leave Engine B active
      _queueIndex = nextIndex;
      currentSong = nextSong;
      // Apply the incoming track's cached trim after this crossfade releases volume ownership.
      _lastCompletionSongId = null;
      currentDuration = nextSong.duration;
      currentPosition = incoming.position;
      // Never inherit a stale mid-track resume for a freshly crossfaded-in song.
      if (currentPosition.inMilliseconds < 2500) {
        _resumeStore.clearSong(nextSong.id);
        if (_resumeSongId == nextSong.id) {
          _resumeSongId = null;
          _resumePositionMs = 0;
        }
      }
      // Audible guarantee: UI must not show B playing while engine is silent.
      try {
        await incoming.setSpeed(1.0);
        if (transitionWasPreempted()) return false;
        await incoming.setVolume(_effectiveCrossfadeMaster.clamp(0.05, 1.0));
        if (transitionWasPreempted()) return false;
        if (_userWantsPlaying && !incoming.playing) {
          try {
            incoming.play();
          } catch (_) {}
          for (var i = 0; i < 10 && !incoming.playing && _userWantsPlaying; i++) {
            await Future<void>.delayed(Duration(milliseconds: 35 + i * 20));
            if (transitionWasPreempted()) return false;
            try {
              incoming.play();
            } catch (_) {}
          }
        }
      } catch (_) {}
      if (transitionWasPreempted()) return false;
      isPlaying = _userWantsPlaying && (incoming.playing || incoming.volume >= 0.05);
      if (_userWantsPlaying && !incoming.playing) {
        // Last resort: hard cut to A with the incoming song (no silent scrub).
        try {
          await _playSongInternal(
            nextSong,
            queue: _queue,
            startIndex: nextIndex,
            playbackIntentToken: intentToken,
          );
        } catch (_) {}
        return audioPlayer.playing;
      }
      await _persistQueue();
      if (transitionWasPreempted()) return false;
      _bindActivePlayerStreams();
      await _startHistoryEvent(nextSong);
      if (transitionWasPreempted()) return false;
      _publishServiceState();
      notifyListeners();
      if (transitionWasPreempted()) return false;
      try { await outgoing.stop(); } catch (_) {}
      if (transitionWasPreempted()) return false;
      // Restore volume on the now-idle engine so the next time it is used it is not stuck at 0.
      try { await outgoing.setVolume(_effectiveCrossfadeMaster.clamp(0.05, 1.0)); } catch (_) {}
      _preloadedNextSongId = null;
      await ResonateDiagnostics.record('crossfade_committed', {
        'outgoingSongId': outgoingSong?.id,
        'incomingSongId': nextSong.id,
        'queueIndex': _queueIndex,
        'intentToken': intentToken,
        'activeEngine': _activeIsA ? 'A' : 'B',
      });
      return true;
    } catch (e, stack) {
      // Cancellation can race any awaited engine operation. If a user command
      // or newer transition has taken ownership, do not run failure recovery
      // against the shared A/B players (the "incoming" engine may now be the
      // user's selected track).
      if (_userTransportEpoch != transportEpoch ||
          _automaticTransitionGeneration != transitionGeneration ||
          _authority.isStale(generation) ||
          !_playbackIntentGate.isCurrent(intentToken)) {
        await ResonateDiagnostics.record('crossfade_cancelled', {
          'stage': 'stale_failure_cleanup',
          'outgoingSongId': outgoingSong?.id,
          'incomingSongId': nextSong.id,
          'error': e.toString(),
          'intentToken': intentToken,
        });
        return false;
      }
      await _clearDjStretchSpeeds(outgoing: outgoing, incoming: incoming);
      debugPrint('True crossfade failed: $e'); debugPrint('$stack');
      try { await incoming.stop(); } catch (_) {}
      try { await outgoing.setSpeed(1.0); } catch (_) {}
      try { await incoming.setSpeed(1.0); } catch (_) {}
      try { await outgoing.setVolume(_effectiveCrossfadeMaster.clamp(0.05, 1.0)); } catch (_) {}
      try {
        if (outgoing.playing && outgoing.volume < 0.02) {
          await outgoing.setVolume(_effectiveCrossfadeMaster.clamp(0.05, 1.0));
        }
      } catch (_) {}
      await ResonateDiagnostics.record('crossfade_failed', {'outgoingSongId': outgoingSong?.id, 'incomingSongId': nextSong.id, 'error': e.toString(), 'intentToken': intentToken});
      // Hard execution failures are stronger negative learning than a later
      // manual skip. User cancellation/preemption exits before this catch.
      if (_djHandoffsLive &&
          outgoingSong != null &&
          _lastDjStrategy != null) {
        unawaited(DjTransitionMemory.recordOutcome(
          fromId: outgoingSong.id,
          toId: nextSong.id,
          strategy: _lastDjStrategy!,
          successful: false,
          weight: (_lastDjRecoveryAttempts + 1).clamp(1, 3),
          score: _lastDjTransitionScore,
          confidence: _lastDjTransitionConfidence,
          risks: _lastDjTransitionRisks,
          transitionDurationMs: _lastDjTransitionDurationMs,
          recoveryAttempts: _lastDjRecoveryAttempts,
        ));
        unawaited(ResonateDiagnostics.recordDj(
          stage: 'learn',
          outcome: 'execution_failure',
          reason: _lastDjStrategy!,
          songId: nextSong.id,
          extra: {
            'fromId': outgoingSong.id,
            'error': e.toString(),
            'recoveryAttempts': _lastDjRecoveryAttempts,
          },
        ));
      }
      try {
        await ResonateDiagnostics.recordDj(
          stage: 'crossfade',
          outcome: 'failed',
          reason: e.toString(),
          songId: nextSong.id,
        );
      } catch (_) {}
      if (_automaticTransitionGeneration != transitionGeneration ||
          _authority.isStale(generation) ||
          !_playbackIntentGate.isCurrent(intentToken)) return false;
      try { await outgoing.stop(); await _playSongInternal(nextSong, queue: _queue, startIndex: nextIndex, playbackIntentToken: intentToken); return true; } catch (fallbackError) { debugPrint('Crossfade fallback failed: $fallbackError'); await ResonateDiagnostics.record('crossfade_fallback_failed', {'incomingSongId': nextSong.id, 'error': fallbackError.toString(), 'intentToken': intentToken}); return false; }
    } finally {
      // A stale transition may finish after a newer user/automatic command.
      // Its cleanup must never touch resources currently owned by the newer
      // transition. This matters because A/B reuses the same two engine/effect
      // instances across rapid Next/Previous commands.
      final ownsTransition = _automaticTransitionGeneration == transitionGeneration;
      if (ownsTransition) {
        _crossfadeInProgress = false;
        _automaticCrossfadeInFlight = false;
        _transitionArmedAt = null;
        unawaited(_refreshTrackLevelingFor(currentSong));
        try {
          await _clearDjStretchSpeeds(outgoing: _playerA, incoming: _playerB);
        } catch (_) {}
        try {
          await _restoreDjTransitionSfx();
        } catch (_) {}
        _lastDjBassDuckNeeded = false;
        _lastDjIncomingBeatMs = const <int>[];
        _lastDjIncomingBpm = null;
        _djBeatCorrectionAttempts = 0;
        _djRuntimeCorrectionBaseSpeed = 1.0;
        _djRuntimeCorrectionUntil = null;
      } else if (!_crossfadeInProgress && bassDuckOriginal.isNotEmpty) {
        // No newer transition took ownership, so the cancelled transition
        // still needs to restore its own captured EQ state.
        try {
          await _audioEffectsController.restoreBassAfterTransition(
            equalizer: incomingEq,
            original: bassDuckOriginal,
          );
          await ResonateDiagnostics.record('dj_bass_duck', {
            'action': 'restore_stale',
            'bands': bassDuckOriginal.keys.toList(),
            'songId': nextSong.id,
          });
        } catch (_) {}
      }
      if (ownsTransition && bassDuckOriginal.isNotEmpty) {
        try {
          await _audioEffectsController.restoreBassAfterTransition(
            equalizer: incomingEq,
            original: bassDuckOriginal,
          );
          await ResonateDiagnostics.record('dj_bass_duck', {
            'action': 'restore',
            'bands': bassDuckOriginal.keys.toList(),
            'songId': nextSong.id,
          });
        } catch (_) {}
      }
      // A stale transition must never "unstick" the current active engine:
      // it may now belong to a manual track selection with intentional gain.
      if (ownsTransition) {
        try {
          final active = audioPlayer;
          final vol = _effectiveCrossfadeMaster.clamp(0.05, 1.0).toDouble();
          if ((_userWantsPlaying || active.playing) && active.volume < 0.05) {
            await active.setSpeed(1.0);
            await active.setVolume(vol);
            await ResonateDiagnostics.record('playback_volume_unstick', {
              'reason': 'crossfade_finally',
              'volume': active.volume,
              'engine': _activeIsA ? 'A' : 'B',
            });
          }
        } catch (_) {}
        // Capture the final state of both reusable engines after transition
        // cleanup. A volume value alone is insufficient: a player can report
        // volume 1.0 while stopped, or retain a DJ stretch speed after handoff.
        try {
          final active = audioPlayer;
          final inactive = inactivePlayer;
          await ResonateDiagnostics.record('crossfade_final_engine_state', {
            'activeEngine': _activeIsA ? 'A' : 'B',
            'activeSongId': currentSong?.id,
            'activeVolume': active.volume,
            'activeSpeed': active.speed,
            'activePlaying': active.playing,
            'inactiveVolume': inactive.volume,
            'inactiveSpeed': inactive.speed,
            'inactivePlaying': inactive.playing,
            'userWantsPlaying': _userWantsPlaying,
            'crossfadeInProgress': _crossfadeInProgress,
          });
        } catch (_) {}
      }
      if (!_crossfadeInProgress && _unduckPendingAfterCrossfade) {
        // The transition (or a newer transport that cancelled it) no longer owns
        // the engines, so finish the deferred focus-gain restoration safely.
        unawaited(_unduckAfterInterruption());
      }
      notifyListeners();

      // Critical fix: if the outgoing track reached completed while we were
      // crossfading, the normal completion path was suppressed. Force
      // continuation now that the hand-off is finished.
      if (_completionObservedDuringCrossfade) {
        final completedSongId = _completionObservedSongId;
        final completedStillCurrent = completedSongId != null &&
            currentSong?.id == completedSongId;
        _completionObservedDuringCrossfade = false;
        _completionObservedSongId = null;
        if (!_completionAdvanceInProgress) {
          unawaited(ResonateDiagnostics.record('completion_transition_recovered', {
            'result': completedStillCurrent
                ? 'advance_completed_track'
                : 'continue_committed_track',
            'completedSongId': completedSongId,
            'currentSongId': currentSong?.id,
            'queueIndex': _queueIndex,
            'queueLength': _queue.length,
          }));
          if (completedStillCurrent) {
            // The transition did not commit a new queue item. Completion was
            // suppressed while the fade owned the player, so explicitly hand
            // the completed song back to the single completion path.
            unawaited(onTrackEnded(completedSongId!));
          } else {
            unawaited(_ensureContinueAfterCrossfade());
          }
        }
      } else {
        _completionObservedSongId = null;
        _completionObservedDuringCrossfade = false;
      }
    }
  }
}
