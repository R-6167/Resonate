#!/usr/bin/env python3
"""Harden preamp, EQ category, SFX release gap, next/completion races."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def try_replace(path: Path, old: str, new: str, label: str) -> bool:
    t = path.read_text()
    if old not in t:
        print('skip', label)
        return False
    path.write_text(t.replace(old, new, 1))
    print('ok', label)
    return True


def main() -> None:
    eq_ui = ROOT / 'lib/screens/equalizer_screen.dart'
    try_replace(
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
    try_replace(
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

    eq = ROOT / 'lib/providers/equalizer_provider.dart'
    try_replace(
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
    // Boosts (0…+6 dB): AndroidLoudnessEnhancer in millibels.
    // Never use LoudnessEnhancer for cuts — some OEMs mute below ~−4 dB.
    final effective = isEnabled ? preamp.clamp(-6.0, 6.0) : 0.0;
    final cutDb = effective < 0 ? effective : 0.0;
    final scale =
        math.pow(10.0, cutDb / 20.0).toDouble().clamp(0.25, 1.0);
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
      final boostDb = effective.clamp(0.0, 6.0);
      await _loudnessEnhancer!.setTargetGain(boostDb * 100.0);
      await _loudnessEnhancer!.setEnabled(true);
    } catch (e) {
      debugPrint('preamp boost failed: $e');
    }
  }""",
        'preamp_apply',
    )

    music = ROOT / 'lib/providers/music_provider.dart'
    try_replace(
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
    try_replace(
        music,
        """  Future<void> _advanceAfterCompletion(String completedSongId) {
    if (_completionAdvanceInProgress) return Future<void>.value();""",
        """  Future<void> _advanceAfterCompletion(String completedSongId) {
    if (_completionAdvanceInProgress) return Future<void>.value();
    // Already moved past this track — do not double-advance.
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
    try_replace(
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
    try_replace(
        music,
        """  Future<void> nextSong({String source = 'normal_player'}) {
    final intentToken = _playbackIntentGate.issue();
    _cancelAutomaticPlaybackWork();

    return _serializePlayback(
      () async {
        if (_queue.isEmpty) return;""",
        """  int _pendingNextSteps = 0;

  Future<void> nextSong({String source = 'normal_player'}) {
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
    try_replace(
        music,
        """        _transportInFlight = true;
        try {
          if (_queueIndex >= _queue.length - 1) {
            if (_repeatMode == PlaybackRepeatMode.all) {
              await _playSongInternal(_queue.first, queue: _queue, startIndex: 0, playbackIntentToken: intentToken);
            } else if (_repeatMode == PlaybackRepeatMode.one && currentSong != null) {
              await _playSongInternal(currentSong!, queue: _queue, startIndex: _queueIndex, playbackIntentToken: intentToken);
            }
            return;
          }

          final nextIndex = _queueIndex + 1;
          // Prefer in-window gapless seek so title and audio stay aligned.
          if (await _tryGaplessSeekToQueueIndex(nextIndex)) return;
          await _playSongInternal(
            _queue[nextIndex],
            queue: _queue,
            startIndex: nextIndex,
            playbackIntentToken: intentToken,
          );
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
    print('harden done')


if __name__ == '__main__':
    main()
