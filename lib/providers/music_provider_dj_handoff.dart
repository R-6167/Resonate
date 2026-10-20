part of 'music_provider.dart';

  /// Step 2–3: optional beat seek + tempo stretch for the incoming handoff.
  Future<void> _prepareDjHandoff({
    required AudioPlayer outgoing,
    required AudioPlayer incoming,
    required Song? outgoingSong,
    required Song incomingSong,
  }) async {
    _lastDjCrossfadeBiasMs = 0;
    _activeDjExecutionPlan = null;
    if ((!_djHandoffsLive) || _djAnalysis == null) {
      return;
    }
    if (outgoingSong == null) return;
    try {
      final profileA = await _djAnalysis!.getProfile(outgoingSong.id);
      final profileB = await _djAnalysis!.getProfile(incomingSong.id);
      if (profileA != null && profileB != null) {
        // Autonomous layer: the musical brain proposes valid candidates;
        // local learning softly reranks them without ever removing fallback.
        final learnedCandidate = await _djAutopilotPlanner.choose(
          outgoing: profileA,
          incoming: profileB,
          outgoingPositionMs: outgoing.position.inMilliseconds,
          preferredDurationMs: _crossfadeDurationMs,
          maxDurationMs: 6500,
          policy: _djPolicy,
        );
        final v2 = _djEngine.execution.plan(
          outgoing: profileA,
          incoming: profileB,
          candidate: learnedCandidate,
          policy: _djPolicy,
        );
        if (!v2.fallback) {
          await _applyV2DjHandoff(
            outgoing: outgoing,
            incoming: incoming,
            outgoingSong: outgoingSong,
            incomingSong: incomingSong,
            profileA: profileA,
            profileB: profileB,
            plan: v2,
          );
          _activeDjExecutionPlan = v2;
          return;
        }
        await ResonateDiagnostics.recordDj(stage: 'v2_brain', outcome: 'fallback', reason: v2.reason, songId: incomingSong.id, extra: {'kind': v2.candidate.kind.name, 'score': v2.candidate.score});
      }

      List<DjAnalysis> results;
      try {
        final aFuture = _djAnalysis!.analyzeSongCachedFirst(outgoingSong);
        final bFuture = _djAnalysis!.analyzeSongCachedFirst(incomingSong);
        results = await Future.wait<DjAnalysis>([aFuture, bFuture]).timeout(
          const Duration(milliseconds: 2200),
          onTimeout: () => const <DjAnalysis>[],
        );
      } catch (e) {
        await ResonateDiagnostics.recordDj(
          stage: 'handoff_prepare',
          outcome: 'failed',
          reason: 'analysis_wait: $e',
        );
        return;
      }
      if (results.length < 2) return;
      final analysisA = results[0];
      final analysisB = results[1];
      final outPos = outgoing.position.inMilliseconds;
      final outDur = outgoingSong.duration.inMilliseconds > 0
          ? outgoingSong.duration.inMilliseconds
          : analysisA.durationMs;
      final plan = await planDjTransitionLearned(
        analysisA: analysisA,
        analysisB: analysisB,
        tempoMatchActive: _djTempoMatchActive,
        beatAlignActive: _djBeatAlignActive,
        maxStretchPercent: _djMaxStretchPercent,
        fromSongId: outgoingSong.id,
        toSongId: incomingSong.id,
        outgoingPositionMs: outPos,
        outgoingDurationMs: outDur,
      );
      _lastDjCrossfadeBiasMs = plan.crossfadeBiasMs;
      _lastDjEnergyScore = plan.energyScore.isFinite
          ? plan.energyScore.clamp(0.0, 1.0).toDouble()
          : 0.5;

      if (plan.strategy == 'safe_fallback') {
        await ResonateDiagnostics.record('dj_handoff_safe_fallback', {
          'reason': plan.reason,
          'strategy': plan.strategy,
          'outgoingSongId': outgoingSong.id,
          'incomingSongId': incomingSong.id,
          ...plan.toDiagExtra(),
        });
        await ResonateDiagnostics.recordDj(
          stage: 'handoff',
          outcome: 'applied',
          reason: plan.reason,
          songId: incomingSong.id,
          extra: plan.toDiagExtra(),
        );
        return;
      }

      final bpmA = plan.bpmA;
      final bpmB = plan.bpmB;
      if (bpmA == null || bpmB == null || bpmA < 40 || bpmB < 40) {
        await ResonateDiagnostics.recordDj(
          stage: 'handoff',
          outcome: 'applied',
          reason: 'missing_bpm_after_plan',
          songId: incomingSong.id,
          extra: plan.toDiagExtra(),
        );
        return;
      }
      final stretch = plan.stretch;
      final effectiveBpmB = stretch?.effectiveBpm ?? bpmB;
      final beatOffsetB = analysisB.beatOffsetMs ?? 0;
      final beatOffsetA = analysisA.beatOffsetMs ?? 0;
      var beatApplied = false;
      var tempoApplied = false;

      if (plan.attemptBeatAlign) {
        final posMs = outgoing.position.inMilliseconds;
        final seek = plan.usePhraseGrid
            ? computePhraseAlignedSeekMs(
                bpmA: stretch != null ? stretch.effectiveBpm : bpmA,
                beatOffsetMsA: beatOffsetA,
                bpmB: effectiveBpmB,
                beatOffsetMsB: beatOffsetB,
                outgoingPositionMs: posMs,
                beatsPerPhrase: plan.phraseBeats,
                maxRelativeDelta: stretch != null ? 0.22 : 0.09,
              )
            : computeBeatAlignedSeekMs(
                bpmA: stretch != null ? stretch.effectiveBpm : bpmA,
                beatOffsetMsA: beatOffsetA,
                bpmB: effectiveBpmB,
                beatOffsetMsB: beatOffsetB,
                outgoingPositionMs: posMs,
                maxRelativeDelta: stretch != null ? 0.22 : 0.09,
              );
        if (seek == null) {
          await ResonateDiagnostics.recordDj(
            stage: 'beat_align',
            outcome: 'skipped',
            reason: 'bpm_delta',
            bpmA: bpmA,
            bpmB: bpmB,
            songId: incomingSong.id,
          );
        } else {
          final dur = incoming.duration ?? incomingSong.duration;
          var target = seek;
          if (dur > Duration.zero && target >= dur) {
            final periodMs = (60000.0 / effectiveBpmB).round();
            if (periodMs > 0) {
              target = Duration(milliseconds: target.inMilliseconds % periodMs);
            } else {
              target = Duration.zero;
            }
          }
          await incoming.seek(target);
          beatApplied = true;
          await ResonateDiagnostics.record('dj_beat_align_applied', {
            'outgoingSongId': outgoingSong.id,
            'incomingSongId': incomingSong.id,
            'bpmA': bpmA,
            'bpmB': bpmB,
            'seekMs': target.inMilliseconds,
            'outgoingPosMs': posMs,
            'stretched': stretch != null,
            'harmonicScore': plan.harmonicScore,
          });
        }
      }

      if (stretch != null) {
        try {
          if ((stretch.speedOutgoing - 1.0).abs() > 0.001) {
            await outgoing.setSpeed(stretch.speedOutgoing);
          }
          await incoming.setSpeed(stretch.speedIncoming);
          _djStretchSpeedOut = stretch.speedOutgoing;
          _djStretchSpeedIn = stretch.speedIncoming;
          tempoApplied = true;
          await ResonateDiagnostics.record('dj_tempo_match_applied', {
            'outgoingSongId': outgoingSong.id,
            'incomingSongId': incomingSong.id,
            'bpmA': bpmA,
            'bpmB': bpmB,
            'speedOut': stretch.speedOutgoing,
            'speedIn': stretch.speedIncoming,
            'mode': stretch.mode,
            'effectiveBpm': stretch.effectiveBpm,
            'harmonicScore': plan.harmonicScore,
          });
        } catch (e) {
          await _clearDjStretchSpeeds(outgoing: outgoing, incoming: incoming);
          await ResonateDiagnostics.recordDj(
            stage: 'tempo_match',
            outcome: 'failed',
            reason: e.toString(),
            songId: incomingSong.id,
          );
        }
      }

      final appliedStrategy = tempoApplied && beatApplied
          ? 'beat_tempo'
          : (tempoApplied
              ? 'tempo_match'
              : (beatApplied ? 'beat_align' : 'safe_fallback'));
      await ResonateDiagnostics.recordDj(
        stage: 'handoff',
        outcome: 'applied',
        reason: appliedStrategy,
        songId: incomingSong.id,
        bpmA: bpmA,
        bpmB: bpmB,
        extra: {
          ...plan.toDiagExtra(),
          'strategyApplied': appliedStrategy,
          'beatApplied': beatApplied,
          'tempoApplied': tempoApplied,
        },
      );
      _lastDjHandoffAt = DateTime.now();
      _lastDjFromId = outgoingSong.id;
      _lastDjToId = incomingSong.id;
      _lastDjStrategy = appliedStrategy;
      _lastDjTransitionScore = null;
      _lastDjTransitionConfidence = math.min(plan.confidenceA, plan.confidenceB);
      _lastDjTransitionRisks = const <String>[];
      _lastDjTransitionDurationMs = null;
      _lastDjRecoveryAttempts = 0;
      notifyListeners(); // dj transition chip
    } catch (e) {
      debugPrint('DJ handoff prepare skipped: $e');
      try {
        await ResonateDiagnostics.recordDj(
          stage: 'handoff_prepare',
          outcome: 'failed',
          reason: e.toString(),
        );
      } catch (_) {}
    }
  }

  Future<void> _applyV2DjHandoff({
    required AudioPlayer outgoing,
    required AudioPlayer incoming,
    required Song outgoingSong,
    required Song incomingSong,
    required DjTrackProfile profileA,
    required DjTrackProfile profileB,
    required DjExecutionPlan plan,
  }) async {
    final candidate = plan.candidate;
    _lastDjCrossfadeBiasMs = 0;
    _lastDjEnergyScore = candidate.scores['energy'] ?? 0.5;
    _lastDjBassDuckNeeded = candidate.risks.contains(DjRiskType.bassCollision);

    // The V2 execution planner is now the source of truth for transition
    // timing. The existing A/B crossfade loop remains the actual audio executor.
    // This deliberately keeps execution engine-neutral: if a step is unknown,
    // ordinary crossfade behavior remains the safe fallback.
    for (final step in plan.steps) {
      if (step.action == 'extend_crossfade') {
        final requested = (step.parameters['durationMs'] as num?)?.toInt();
        if (requested != null) {
          _lastDjCrossfadeBiasMs =
              (requested - candidate.durationMs).clamp(-4000, 8000).toInt();
        }
      }
    }

    final incomingDuration = incoming.duration ?? incomingSong.duration;
    final seekMs = candidate.incomingStartMs
        .clamp(0, incomingDuration.inMilliseconds)
        .toInt();
    await incoming.seek(Duration(milliseconds: seekMs));

    await ResonateDiagnostics.recordDj(
      stage: 'v2_execution',
      outcome: 'prepared',
      reason: 'timeline_mapped_to_ab',
      songId: incomingSong.id,
      extra: {
        'kind': candidate.kind.name,
        'incomingStartMs': seekMs,
        'durationMs': candidate.durationMs,
        'crossfadeBiasMs': _lastDjCrossfadeBiasMs,
        'steps': plan.steps.map((step) => {
          'action': step.action,
          'atMs': step.atMs,
          'parameters': step.parameters,
        }).toList(),
      },
    );

    var tempoApplied = false;
    _lastDjIncomingBeatMs = profileB.beatGrid.beatMs;
    _lastDjIncomingBpm = profileB.beatGrid.bpm;
    _djBeatCorrectionAttempts = 0;
    if (_djTempoMatchActive &&
        profileA.beatGrid.bpm != null &&
        profileB.beatGrid.bpm != null) {
      final stretch = computeTempoStretch(
        bpmA: profileA.beatGrid.bpm!,
        bpmB: profileB.beatGrid.bpm!,
        maxStretchPercent: _djMaxStretchPercent,
      );
      if (stretch != null) {
        await outgoing.setSpeed(stretch.speedOutgoing);
        await incoming.setSpeed(stretch.speedIncoming);
        _djStretchSpeedOut = stretch.speedOutgoing;
        _djStretchSpeedIn = stretch.speedIncoming;
        tempoApplied = true;
      }
    }

    _lastDjHandoffAt = DateTime.now();
    _lastDjFromId = outgoingSong.id;
    _lastDjToId = incomingSong.id;
    _lastDjStrategy = candidate.kind.name;
    _lastDjTransitionScore = candidate.score;
    _lastDjTransitionConfidence = candidate.confidence;
    _lastDjTransitionRisks = candidate.risks.map((r) => r.name).toList();
    _lastDjTransitionDurationMs = candidate.durationMs;
    _lastDjRecoveryAttempts = 0;
    notifyListeners(); // dj transition chip
    await ResonateDiagnostics.recordDj(
      stage: 'v2_handoff',
      outcome: 'applied',
      reason: plan.reason,
      songId: incomingSong.id,
      extra: {
        'kind': candidate.kind.name,
        'score': candidate.score,
        'confidence': candidate.confidence,
        'seekMs': seekMs,
        'tempoApplied': tempoApplied,
        'risks': candidate.risks.map((r) => r.name).toList(),
        'scores': candidate.scores,
      },
    );
  }
