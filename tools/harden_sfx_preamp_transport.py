#!/usr/bin/env python3
"""Harden DJ SFX, EQ preamp, category persistence, and next/completion races."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def must_replace(path: Path, old: str, new: str, label: str) -> None:
    t = path.read_text()
    if old not in t:
        raise SystemExit(f'FAIL {label}: pattern miss in {path}')
    path.write_text(t.replace(old, new, 1))
    print('ok', label)


def main() -> None:
    # ------------------------------------------------------------------ SFX
    sfx = ROOT / 'lib/services/dj_sfx_rack.dart'
    must_replace(
        sfx,
        """  Future<void> _applyNativeAt(double t, double score, double mismatch) async {
    final p = activePreset ?? DjSfxPreset.clubOpen;
    double bass = 0.0, width = 0.0, reverb = 0.0;
    switch (p) {
      case DjSfxPreset.clubOpen:
        bass = (0.38 * (1.0 - t) + 0.06).clamp(0.05, 0.42);
        width = (0.08 + 0.40 * t).clamp(0.08, 0.48);
        reverb = (0.16 + 0.34 * math.sin(t * math.pi)).clamp(0.12, 0.52);
        break;
      case DjSfxPreset.filterOpen:
        bass = (0.28 * (1.0 - t) + 0.05).clamp(0.04, 0.35);
        width = (0.06 + 0.25 * t).clamp(0.05, 0.35);
        reverb = (0.12 + 0.22 * math.sin(t * math.pi)).clamp(0.08, 0.40);
        break;
      case DjSfxPreset.filterClose:
        bass = (0.12 + 0.28 * t).clamp(0.05, 0.40);
        width = (0.22 * (1.0 - t) + 0.08).clamp(0.06, 0.32);
        reverb = (0.10 + 0.18 * (1.0 - t)).clamp(0.06, 0.32);
        break;
      case DjSfxPreset.bassDrop:
        final punch = math.sin(t * math.pi);
        bass = (0.15 + 0.45 * punch).clamp(0.08, 0.55);
        width = (0.08 + 0.12 * t).clamp(0.06, 0.28);
        reverb = (0.10 + 0.15 * punch).clamp(0.06, 0.30);
        break;
      case DjSfxPreset.wideSpace:
        bass = (0.10 + 0.08 * mismatch).clamp(0.05, 0.25);
        width = (0.22 + 0.40 * t + mismatch * 0.1).clamp(0.15, 0.62);
        reverb = (0.14 + 0.28 * math.sin(t * math.pi)).clamp(0.10, 0.48);
        break;
      case DjSfxPreset.tightGlue:
        bass = (0.12 + mismatch * 0.1).clamp(0.06, 0.28);
        width = (0.06 + 0.08 * t).clamp(0.04, 0.20);
        reverb = (0.22 + mismatch * 0.25 + 0.12 * math.sin(t * math.pi))
            .clamp(0.18, 0.55);
        break;
      case DjSfxPreset.dryPunch:
        bass = (0.18 * math.sin(t * math.pi)).clamp(0.0, 0.28);
        width = (0.05 + 0.06 * t).clamp(0.0, 0.15);
        reverb = (0.08 + 0.20 * math.sin(t * math.pi * 2).abs())
            .clamp(0.0, 0.28);
        break;
    }
    await AudioEffectsBridge.setBassBoost(bass);
    await AudioEffectsBridge.setVirtualizer(width);
    await AudioEffectsBridge.setReverb(reverb);
  }""",
        """  /// Soft attack / release so SFX never hard-cuts on the outgoing fade.
  /// [t] is 0→1 over the crossfade; values above 1 are post-gap release.
  double _envelope(double t) {
    if (t <= 0) return 0.0;
    if (t < 0.18) return (t / 0.18).clamp(0.0, 1.0); // fade in
    if (t <= 1.0) return 1.0;
    // Post-crossfade gap (caller ticks 1.0→1.6): fade out over ~0.6
    final release = ((1.6 - t) / 0.6).clamp(0.0, 1.0);
    return release;
  }

  Future<void> _applyNativeAt(double t, double score, double mismatch) async {
    final p = activePreset ?? DjSfxPreset.clubOpen;
    final env = _envelope(t);
    final x = t.clamp(0.0, 1.0);
    double bass = 0.0, width = 0.0, reverb = 0.0;
    switch (p) {
      case DjSfxPreset.clubOpen:
        // Soft glue — no heavy bass on a dying outgoing track.
        bass = (0.10 * (1.0 - x) + 0.03).clamp(0.02, 0.16);
        width = (0.08 + 0.28 * x).clamp(0.06, 0.36);
        reverb = (0.14 + 0.26 * math.sin(x * math.pi)).clamp(0.10, 0.40);
        break;
      case DjSfxPreset.filterOpen:
        bass = (0.08 * (1.0 - x) + 0.02).clamp(0.02, 0.12);
        width = (0.06 + 0.20 * x).clamp(0.04, 0.28);
        reverb = (0.10 + 0.18 * math.sin(x * math.pi)).clamp(0.08, 0.32);
        break;
      case DjSfxPreset.filterClose:
        bass = (0.04 + 0.10 * x).clamp(0.02, 0.14);
        width = (0.16 * (1.0 - x) + 0.06).clamp(0.04, 0.22);
        reverb = (0.10 + 0.14 * (1.0 - x)).clamp(0.06, 0.26);
        break;
      case DjSfxPreset.bassDrop:
        // Gentle mid-fade bump only — never dominate the blend.
        final punch = math.sin(x * math.pi);
        bass = (0.06 + 0.16 * punch).clamp(0.03, 0.22);
        width = (0.06 + 0.10 * x).clamp(0.04, 0.20);
        reverb = (0.08 + 0.12 * punch).clamp(0.05, 0.24);
        break;
      case DjSfxPreset.wideSpace:
        bass = (0.04 + 0.04 * mismatch).clamp(0.02, 0.10);
        width = (0.18 + 0.30 * x + mismatch * 0.08).clamp(0.12, 0.48);
        reverb = (0.12 + 0.22 * math.sin(x * math.pi)).clamp(0.08, 0.36);
        break;
      case DjSfxPreset.tightGlue:
        bass = (0.05 + mismatch * 0.05).clamp(0.02, 0.12);
        width = (0.05 + 0.06 * x).clamp(0.03, 0.16);
        reverb = (0.18 + mismatch * 0.18 + 0.10 * math.sin(x * math.pi))
            .clamp(0.12, 0.42);
        break;
      case DjSfxPreset.dryPunch:
        bass = (0.08 * math.sin(x * math.pi)).clamp(0.0, 0.14);
        width = (0.04 + 0.05 * x).clamp(0.0, 0.12);
        reverb = (0.06 + 0.14 * math.sin(x * math.pi * 2).abs())
            .clamp(0.0, 0.22);
        break;
    }
    // Apply envelope so engage/release are smooth, not hard cuts.
    bass *= env;
    width *= env;
    reverb *= env;
    await AudioEffectsBridge.setBassBoost(bass);
    await AudioEffectsBridge.setVirtualizer(width);
    await AudioEffectsBridge.setReverb(reverb);
  }""",
        'sfx_envelope',
    )
    # Softer EQ bassDrop gains
    must_replace(
        sfx,
        """          case DjSfxPreset.bassDrop:
            // Low bands dip then boom.
            final low = frac < 0.35;
            final punch = math.sin(t * math.pi);
            gain = low ? (-4.0 + 10.0 * punch) : (-2.0 * (1.0 - t) * frac);
            break;""",
        """          case DjSfxPreset.bassDrop:
            // Soft low bump — never a hard boom on the outgoing tail.
            final low = frac < 0.35;
            final punch = math.sin(t.clamp(0.0, 1.0) * math.pi);
            final env = t <= 1.0
                ? 1.0
                : ((1.6 - t) / 0.6).clamp(0.0, 1.0);
            gain = (low ? (-1.5 + 4.0 * punch) : (-1.0 * (1.0 - t.clamp(0.0, 1.0)) * frac)) *
                env;
            break;""",
        'sfx_eq_bassdrop',
    )

    # -------------------------------------------------------- equalizer screen category
    eq_ui = ROOT / 'lib/screens/equalizer_screen.dart'
    must_replace(
        eq_ui,
        """class _EqualizerScreenState extends State<EqualizerScreen> {
  String _category = 'Genre';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Equalizer'),
        actions: [
          IconButton(
            tooltip: 'Save preset',
            icon: const Icon(Icons.bookmark_add_outlined),
            onPressed: () => _saveCustom(context),
          ),
          IconButton(
            tooltip: 'Reset flat',
            icon: const Icon(Icons.restart_alt_rounded),
            onPressed: () => context.read<EqualizerProvider>().resetToFlat(),
          ),
        ],
      ),
      body: Consumer<EqualizerProvider>(
        builder: (context, eq, _) {
          final categories = eq.categories;
          if (categories.isNotEmpty && !categories.contains(_category)) {
            _category = categories.first;
          }
          final presets = eq.presetsInCategory(_category);""",
        """class _EqualizerScreenState extends State<EqualizerScreen> {
  String _category = 'Genre';
  bool _categorySynced = false;

  void _syncCategoryFromPreset(EqualizerProvider eq) {
    if (_categorySynced) return;
    for (final p in eq.allPresets) {
      if (p.name == eq.preset) {
        _category = p.category;
        _categorySynced = true;
        return;
      }
    }
    _categorySynced = true;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Equalizer'),
        actions: [
          IconButton(
            tooltip: 'Save preset',
            icon: const Icon(Icons.bookmark_add_outlined),
            onPressed: () => _saveCustom(context),
          ),
          IconButton(
            tooltip: 'Reset flat',
            icon: const Icon(Icons.restart_alt_rounded),
            onPressed: () => context.read<EqualizerProvider>().resetToFlat(),
          ),
        ],
      ),
      body: Consumer<EqualizerProvider>(
        builder: (context, eq, _) {
          _syncCategoryFromPreset(eq);
          final categories = eq.categories;
          if (categories.isNotEmpty && !categories.contains(_category)) {
            _category = categories.first;
          }
          final presets = eq.presetsInCategory(_category);""",
        'eq_category_sync',
    )

    # Also persist category chip choice when user picks
    must_replace(
        eq_ui,
        """                        child: ChoiceChip(
                          label: Text(c),
                          selected: _category == c,
                          onSelected: (_) => setState(() => _category = c),
                        ),""",
        """                        child: ChoiceChip(
                          label: Text(c),
                          selected: _category == c,
                          onSelected: (_) => setState(() {
                            _category = c;
                            _categorySynced = true;
                          }),
                        ),""",
        'eq_category_chip',
    )

    # -------------------------------------------------------- preamp boost + scale
    eq = ROOT / 'lib/providers/equalizer_provider.dart'
    must_replace(
        eq,
        """  Future<void> _applyPreamp() async {
    // Negative / zero preamp: digital attenuation via MusicProvider player gain.
    // LoudnessEnhancer is NOT used for cuts — OEMs often mute before -4 dB.
    final effective = isEnabled ? preamp : 0.0;
    final scale = math.pow(10.0, effective.clamp(-12.0, 0.0) / 20.0).toDouble().clamp(0.25, 1.0);
    try {
      if (_music != null) {
        await _music!.setEqPreampScale(scale);
      }
    } catch (e) {
      debugPrint('preamp digital scale failed: $e');
    }
    // Positive preamp only: soft LoudnessEnhancer boost (optional, capped).
    if (!_hardwareBound) return;
    if (_loudnessEnhancer == null) return;
    try {
      if (!isEnabled || effective <= 0.15) {
        await _loudnessEnhancer!.setTargetGain(0);
        await _loudnessEnhancer!.setEnabled(false);
        return;
      }
      final softDb = (effective * 0.4).clamp(0.0, 2.5);
      await _loudnessEnhancer!.setTargetGain(softDb * 100.0);
      await _loudnessEnhancer!.setEnabled(true);
    } catch (e) {
      debugPrint('preamp boost failed: $e');
    }
  }""",
        """  Future<void> _applyPreamp() async {
    // Cuts (−6…0 dB): digital attenuation via MusicProvider player volume scale.
    // Boosts (0…+6 dB): AndroidLoudnessEnhancer in millibels (soft curve, no mute).
    // Never use LoudnessEnhancer for cuts — some OEMs mute below ~−4 dB.
    final effective = isEnabled ? preamp.clamp(-6.0, 6.0) : 0.0;
    final cutDb = effective < 0 ? effective : 0.0;
    final scale =
        math.pow(10.0, cutDb / 20.0).toDouble().clamp(0.25, 1.0); // −12 dB floor
    try {
      if (_music != null) {
        await _music!.setEqPreampScale(scale);
      }
    } catch (e) {
      debugPrint('preamp digital scale failed: $e');
    }
    if (!_hardwareBound) return;
    if (_loudnessEnhancer == null) return;
    try {
      if (!isEnabled || effective <= 0.05) {
        await _loudnessEnhancer!.setTargetGain(0);
        await _loudnessEnhancer!.setEnabled(false);
        return;
      }
      // Map +6 dB UI → up to +6 dB target (millibels). Gentle enough to avoid
      // hard clip on most devices while still audible at the top of the slider.
      final boostDb = effective.clamp(0.0, 6.0);
      await _loudnessEnhancer!.setTargetGain(boostDb * 100.0);
      await _loudnessEnhancer!.setEnabled(true);
    } catch (e) {
      debugPrint('preamp boost failed: $e');
    }
  }""",
        'preamp_apply',
    )

    # -------------------------------------------------------- music: SFX release + transport
    music = ROOT / 'lib/providers/music_provider.dart'

    # 1) After crossfade SFX restore → delayed soft release ticks first
    must_replace(
        music,
        """  Future<void> _restoreDjTransitionSfx() async {
    if (!_djSfxEngaged && !_djSfxActive && !_djSfxRack.engaged) return;
    try {
      final preset = _djSfxRack.presetName;
      await _djSfxRack.restore(
        equalizerA: _equalizer""",
        """  Future<void> _restoreDjTransitionSfx() async {
    if (!_djSfxEngaged && !_djSfxActive && !_djSfxRack.engaged) return;
    try {
      // Soft release gap so SFX bridges the two songs instead of cutting at t=1.
      for (final t in <double>[1.15, 1.30, 1.45, 1.60]) {
        try {
          await _djSfxRack.tick(
            t,
            equalizerA: _equalizerA,
            equalizerB: _equalizerB,
            energyScore: _lastDjEnergyScore,
          );
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 70));
      }
      final preset = _djSfxRack.presetName;
      await _djSfxRack.restore(
        equalizerA: _equalizer""",
        'sfx_soft_release',
    )

    # 2) Completion guard — ignore completions for songs we already left
    must_replace(
        music,
        """  Future<void> _advanceAfterCompletion(String completedSongId) {
    if (_completionAdvanceInProgress) return Future<void>.value();""",
        """  Future<void> _advanceAfterCompletion(String completedSongId) {
    if (_completionAdvanceInProgress) return Future<void>.value();
    // Already moved past this track (crossfade commit or user next) — do not
    // double-advance (the "play 2s then jump" bug).
    if (currentSong != null &&
        currentSong!.id != completedSongId &&
        !_crossfadeInProgress &&
        !_automaticCrossfadeInFlight) {
      unawaited(ResonateDiagnostics.record('completion_advance_result', {
        'result': 'ignored_stale',
        'fromSongId': completedSongId,
        'currentSongId': currentSong?.id,
      }));
      return Future<void>.value();
    }""",
        'completion_stale_guard',
    )

    # 3) After crossfade: do not force-advance if we already landed on next
    must_replace(
        music,
        """      if (_completionObservedDuringCrossfade) {
        _completionObservedDuringCrossfade = false;
        if (!_completionAdvanceInProgress) {
          unawaited(_ensureContinueAfterCrossfade());
        }
      } else {
        _completionObservedDuringCrossfade = false;
      }""",
        """      if (_completionObservedDuringCrossfade) {
        _completionObservedDuringCrossfade = false;
        // Crossfade already handed off to the next track. Only unstick audio —
        // never advance the queue again (prevents 2s-then-skip).
        if (!_completionAdvanceInProgress) {
          unawaited(_ensureContinueAfterCrossfade());
        }
      } else {
        _completionObservedDuringCrossfade = false;
      }""",
        'post_xfade_comment',
    )

    # 4) ensureContinue: never skip forward in the catch path without checking
    must_replace(
        music,
        """    } catch (e) {
      debugPrint('Post-crossfade continue failed: $e');
      if (_queueIndex < _queue.length - 1) {
        final next = _queue[_queueIndex + 1];
        final token = _playbackIntentGate.issue();
        await _playSongInternal(next, queue: _queue, startIndex: _queueIndex + 1, playbackIntentToken: token);
      }
    }
  }""",
        """    } catch (e) {
      debugPrint('Post-crossfade continue failed: $e');
      // Retry the *current* queue song only — never skip ahead on failure.
      final song = currentSong;
      if (song != null && _userWantsPlaying) {
        final token = _playbackIntentGate.issue();
        try {
          await _playSongInternal(
            song,
            queue: _queue,
            startIndex: _queueIndex,
            playbackIntentToken: token,
          );
        } catch (_) {}
      }
    }
  }""",
        'ensure_continue_no_skip',
    )

    # 5) nextSong: if transport already in flight, queue one more step only after
    #    current finishes — count taps without racing parallel plays.
    must_replace(
        music,
        """  Future<void> nextSong({String source = 'normal_player'}) {
    final intentToken = _playbackIntentGate.issue();
    _cancelAutomaticPlaybackWork();

    return _serializePlayback(
      () async {
        if (_queue.isEmpty) return;""",
        """  int _pendingNextSteps = 0;

  Future<void> nextSong({String source = 'normal_player'}) {
    // Coalesce rapid taps into N sequential advances after the active play
    // settles — prevents fast-jump past more songs than taps.
    if (_transportInFlight || _loadingSource || _crossfadeInProgress) {
      _pendingNextSteps = (_pendingNextSteps + 1).clamp(0, 12);
      return Future<void>.value();
    }
    final intentToken = _playbackIntentGate.issue();
    _cancelAutomaticPlaybackWork();

    return _serializePlayback(
      () async {
        if (_queue.isEmpty) return;
        final extra = _pendingNextSteps;
        _pendingNextSteps = 0;
        final steps = 1 + extra;""",
        'next_coalesce_begin',
    )

    # Find the advance body and wrap with a loop for steps
    # The nextSong body ends with playing next index once — inject multi-step
    must_replace(
        music,
        """        _transportInFlight = true;
        try {
          if (_queueIndex >= _queue.length - 1) {
            if (_repeatMode == PlaybackRepeatMode.all) {
              await _playSongInternal(_queue.first, queue: _queue, startIndex: 0, playbackIntentToken: intentToken);
            } else if (_repeatMode == PlaybackRepeatMode.one && currentSong != null) {
              await _playSongInternal(currentSong!, queue: _queue, startIndex: _queueIndex, playbackIntentToken: intentToken);
            }
          } else {
            final nextIndex = _queueIndex + 1;
            await _playSongInternal(_queue[nextIndex], queue: _queue, startIndex: nextIndex, playbackIntentToken: intentToken);
          }
        } finally {
          _transportInFlight = false;
        }""",
        """        _transportInFlight = true;
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
            } else {
              final nextIndex = _queueIndex + 1;
              await _playSongInternal(_queue[nextIndex], queue: _queue, startIndex: nextIndex, playbackIntentToken: intentToken);
            }
            // Drain any taps that arrived mid-advance.
            if (_pendingNextSteps > 0 && stepsLeft == 0) {
              stepsLeft = _pendingNextSteps.clamp(0, 12);
              _pendingNextSteps = 0;
            }
          }
        } finally {
          _transportInFlight = false;
          // Late taps after unlock.
          if (_pendingNextSteps > 0) {
            final again = _pendingNextSteps;
            _pendingNextSteps = 0;
            unawaited(Future<void>.delayed(const Duration(milliseconds: 40), () {
              for (var i = 0; i < again; i++) {
                unawaited(nextSong(source: source));
              }
            }));
          }
        }""",
        'next_multi_step',
    )

    print('harden script done')


if __name__ == '__main__':
    main()
