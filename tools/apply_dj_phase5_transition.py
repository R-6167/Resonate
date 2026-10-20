#!/usr/bin/env python3
"""Phase 5 lite: strategy-based DJ handoff using DjTransitionPlanner."""
from pathlib import Path

MP = Path("lib/providers/music_provider.dart")
t = MP.read_text()
n = 0

if "planDjTransition" in t and "dj_transition_planner.dart" in t:
    print("already phase5")
    raise SystemExit(0)

old_imp = "import '../services/dj_bpm_estimator.dart';\n"
new_imp = (
    "import '../services/dj_bpm_estimator.dart';\n"
    "import '../services/dj_transition_planner.dart';\n"
)
if "dj_transition_planner.dart" not in t and old_imp in t:
    t = t.replace(old_imp, new_imp, 1)
    n += 1
    print("import")

old_block = '''      if (!analysisA.hasUsableBpm || !analysisB.hasUsableBpm) {
        await ResonateDiagnostics.record('dj_handoff_safe_fallback', {
          'reason': 'missing_bpm',
          'strategy': 'safe_fallback',
          'outgoingSongId': outgoingSong.id,
          'incomingSongId': incomingSong.id,
          'hasBpmA': analysisA.hasUsableBpm,
          'hasBpmB': analysisB.hasUsableBpm,
        });
        await ResonateDiagnostics.recordDj(
          stage: 'handoff',
          outcome: 'applied',
          reason: 'safe_fallback',
          songId: incomingSong.id,
          extra: {
            'strategy': 'safe_fallback',
            'hasBpmA': analysisA.hasUsableBpm,
            'hasBpmB': analysisB.hasUsableBpm,
          },
        );
        return;
      }

      final bpmA = analysisA.bpm!;
      final bpmB = analysisB.bpm!;
      DjTempoStretchPlan? stretch;
      if (_djTempoMatchActive) {
        stretch = computeTempoStretch(
          bpmA: bpmA,
          bpmB: bpmB,
          maxStretchPercent: _djMaxStretchPercent,
        );
        if (stretch == null) {
          await ResonateDiagnostics.record('dj_tempo_match_skipped', {
            'reason': 'stretch_budget',
            'bpmA': bpmA,
            'bpmB': bpmB,
            'maxPercent': _djMaxStretchPercent,
          });
          await ResonateDiagnostics.recordDj(
            stage: 'tempo_match',
            outcome: 'skipped',
            reason: 'stretch_budget',
            bpmA: bpmA,
            bpmB: bpmB,
            songId: incomingSong.id,
          );
        }
      }

      final effectiveBpmB = stretch?.effectiveBpm ?? bpmB;
      final beatOffsetB = analysisB.beatOffsetMs ?? 0;
      final beatOffsetA = analysisA.beatOffsetMs ?? 0;

      if (_djBeatAlignActive) {
        final posMs = outgoing.position.inMilliseconds;
        final seek = computeBeatAlignedSeekMs(
          bpmA: stretch != null ? stretch.effectiveBpm : bpmA,
          beatOffsetMsA: beatOffsetA,
          bpmB: effectiveBpmB,
          beatOffsetMsB: beatOffsetB,
          outgoingPositionMs: posMs,
          maxRelativeDelta: stretch != null ? 0.25 : 0.08,
        );
        if (seek == null) {
          await ResonateDiagnostics.record('dj_beat_align_skipped', {
            'reason': 'bpm_delta',
            'bpmA': bpmA,
            'bpmB': bpmB,
            'stretched': stretch != null,
          });
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
          await ResonateDiagnostics.record('dj_beat_align_applied', {
            'outgoingSongId': outgoingSong.id,
            'incomingSongId': incomingSong.id,
            'bpmA': bpmA,
            'bpmB': bpmB,
            'seekMs': target.inMilliseconds,
            'outgoingPosMs': posMs,
            'stretched': stretch != null,
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
          await ResonateDiagnostics.record('dj_tempo_match_applied', {
            'outgoingSongId': outgoingSong.id,
            'incomingSongId': incomingSong.id,
            'bpmA': bpmA,
            'bpmB': bpmB,
            'speedOut': stretch.speedOutgoing,
            'speedIn': stretch.speedIncoming,
            'mode': stretch.mode,
            'effectiveBpm': stretch.effectiveBpm,
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
      }'''

new_block = '''      final plan = planDjTransition(
        analysisA: analysisA,
        analysisB: analysisB,
        tempoMatchActive: _djTempoMatchActive,
        beatAlignActive: _djBeatAlignActive,
        maxStretchPercent: _djMaxStretchPercent,
      );

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

      final bpmA = plan.bpmA!;
      final bpmB = plan.bpmB!;
      final stretch = plan.stretch;
      final effectiveBpmB = stretch?.effectiveBpm ?? bpmB;
      final beatOffsetB = analysisB.beatOffsetMs ?? 0;
      final beatOffsetA = analysisA.beatOffsetMs ?? 0;
      var beatApplied = false;
      var tempoApplied = false;

      if (plan.attemptBeatAlign) {
        final posMs = outgoing.position.inMilliseconds;
        final seek = computeBeatAlignedSeekMs(
          bpmA: stretch != null ? stretch.effectiveBpm : bpmA,
          beatOffsetMsA: beatOffsetA,
          bpmB: effectiveBpmB,
          beatOffsetMsB: beatOffsetB,
          outgoingPositionMs: posMs,
          maxRelativeDelta: stretch != null ? 0.25 : 0.08,
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
      )'''

if old_block in t:
    t = t.replace(old_block, new_block, 1)
    n += 1
    print("handoff block")
else:
    print("MISS handoff block")
    if "if (!analysisA.hasUsableBpm || !analysisB.hasUsableBpm)" in t:
        print("  found missing_bpm guard")

MP.write_text(t)
print("patches", n)
