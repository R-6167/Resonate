#!/usr/bin/env python3
"""Hard pause that cannot be undone by player streams; SFX bags by aggressiveness."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def patch_music_pause() -> None:
    path = ROOT / "lib/providers/music_provider.dart"
    t = path.read_text()

    # 1) Never promote _userWantsPlaying from native playing alone.
    old_stream = """      } else if (state.playing) {
        if (!isPlaying) {
          isPlaying = true;
          _userWantsPlaying = true;
          notifyListeners();
          _publishServiceState();
        }
"""
    new_stream = """      } else if (state.playing) {
        // Reflect native play in UI only when the user still wants playback.
        // Never re-assert _userWantsPlaying here — that made pause feel broken
        // when a second engine or late stream event flipped intent back on.
        if (_userWantsPlaying && !isPlaying) {
          isPlaying = true;
          notifyListeners();
          _publishServiceState();
        }
"""
    if old_stream in t:
        t = t.replace(old_stream, new_stream, 1)
        print("stream listener fixed")
    elif "Never re-assert _userWantsPlaying" in t:
        print("stream listener already fixed")
    else:
        print("WARNING: stream listener pattern miss")

    # 2) Harden pause: clear intent first, cancel fades/crossfade ownership, pause both.
    old_pause = """Future<void> pause({String source = 'normal_player'}) {
    final intentToken = _playbackIntentGate.issue();
    // System audio-focus pause must preserve intent so we can resume when focus returns.
    final fromSystemFocus = source == 'system';
    final fromNoisy = source == 'becoming_noisy';
    if (!fromSystemFocus) {
      _cancelAutomaticPlaybackWork();
    }
    return _serializePlayback(() async {
      try {
        if (!fromSystemFocus) {
          _userWantsPlaying = false;
        }
        // Only skip fade during a *real* volume ramp (not a stuck automatic flag).
        final midTransition =
            _crossfadeInProgress || _repeatSelfHandoffInFlight;
        if (!midTransition && audioPlayer.playing) {
          final from = audioPlayer.volume;
          final fadeMs = fromSystemFocus ? 120 : _transportFadeMs;
          await _fadePlayerVolume(audioPlayer, from, 0.0, durationMs: fadeMs);
        }
        await audioPlayer.pause();
        try {
          await inactivePlayer.pause();
        } catch (_) {}
        // Restore internal gain so the next play/resume fade-in starts clean.
        if (!midTransition) {
          try {
            await audioPlayer.setVolume(_eqPreampScale.clamp(0.0, 1.0));
          } catch (_) {}
        }
        isPlaying = false;
        _isDucked = false;
        _persistResumePosition(force: true);
        _publishServiceState();
        notifyListeners();
        await ResonateDiagnostics.record('audio_focus_pause', {
          'source': source,
          'userWantsPlaying': _userWantsPlaying,
          'preservedIntent': fromSystemFocus,
          'faded': !midTransition,
          'noisy': fromNoisy,
        });
      } catch (_) {}
    }, command: 'pause', source: source, userInitiated: !fromSystemFocus, intentToken: intentToken);
  }
"""

    new_pause = """  Future<void> pause({String source = 'normal_player'}) {
    final intentToken = _playbackIntentGate.issue();
    // System audio-focus pause must preserve intent so we can resume when focus returns.
    final fromSystemFocus = source == 'system';
    final fromNoisy = source == 'becoming_noisy';
    // Clear user intent immediately (before async lane) so stream listeners and
    // ensureAudiblePlayback cannot race a late play() back in.
    if (!fromSystemFocus) {
      _userWantsPlaying = false;
      isPlaying = false;
      _volumeFadeGen++; // cancel in-flight volume fades
      _cancelAutomaticPlaybackWork();
      // Drop stuck crossfade ownership so dual-engine audio cannot keep going.
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
        // Pause both engines first (hard stop), then optional short fade is skipped
        // when we already cleared transition flags above.
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
            await audioPlayer.setVolume(_eqPreampScale.clamp(0.0, 1.0));
          } catch (_) {}
          try {
            await inactivePlayer.setVolume(0.0);
          } catch (_) {}
        }
        isPlaying = false;
        _isDucked = false;
        _persistResumePosition(force: true);
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
"""

    if "hardStop": True and "hardStop" in t and "_playerA.pause()" in t[t.find("Future<void> pause"):t.find("Future<void> pause")+1200]:
        print("pause already hardened")
    elif old_pause in t:
        t = t.replace(old_pause, new_pause, 1)
        print("pause hardened")
    else:
        # try without leading Future indent variant
        if "Future<void> pause({String source = 'normal_player'})" in t and "hardStop" not in t:
            # replace from Future pause through closing of method
            start = t.find("Future<void> pause({String source = 'normal_player'})")
            # also try indented
            start2 = t.find("  Future<void> pause({String source = 'normal_player'})")
            start = start2 if start2 >= 0 else start
            if start < 0:
                raise SystemExit("pause method not found")
            # find next method at class level Future after pause body
            end_marker = "\n  Future<void> stop("
            end = t.find(end_marker, start)
            if end < 0:
                raise SystemExit("stop after pause not found")
            t = t[:start] + new_pause.strip() + "\n" + t[end:]
            print("pause replaced by span")
        else:
            print("WARNING: pause pattern miss")

    # 3) Fix togglePlayPause indentation / ensure it's a clean class method
    old_toggle = """    Future<void> togglePlayPause({String source = 'normal_player'}) {
    // Route through pause/resume so transport fades always apply.
    // Native playing state decides the branch (not optimistic isPlaying).
    if (audioPlayer.playing) {
      return pause(source: source);
    }
    return resumePlayback(source: source);
  }
"""
    new_toggle = """  Future<void> togglePlayPause({String source = 'normal_player'}) {
    // Prefer optimistic isPlaying when native lags; user pause must win.
    final wantPause = isPlaying || audioPlayer.playing || _userWantsPlaying;
    if (wantPause) {
      return pause(source: source);
    }
    return resumePlayback(source: source);
  }
"""
    if "Prefer optimistic isPlaying" in t:
        print("toggle already fixed")
    elif old_toggle in t:
        t = t.replace(old_toggle, new_toggle, 1)
        print("toggle fixed")
    else:
        # looser replace
        import re

        m = re.search(
            r"[ \t]*Future<void> togglePlayPause\(\{String source = 'normal_player'\}\) \{[\s\S]*?return resumePlayback\(source: source\);\n  \}",
            t,
        )
        if m:
            t = t[: m.start()] + new_toggle + t[m.end() :]
            print("toggle fixed via regex")
        else:
            print("WARNING: toggle miss")

    # 4) Pass policy into SFX engage
    if "aggressiveness:" in t and "_djPolicy.aggressiveness" in t:
        print("sfx policy already passed")
    else:
        t2 = t
        # engageDelayed call
        if "aggressiveness:" not in t:
            t = t.replace(
                "transitionKind: transitionKind,\n            );\n            if (_djSfxRack.engaged && _djSfxActive)",
                "transitionKind: transitionKind,\n"
                "              aggressiveness: _djPolicy.aggressiveness,\n"
                "            );\n            if (_djSfxRack.engaged && _djSfxActive)",
                1,
            )
            t = t.replace(
                """        await _djSfxRack.engage(
          energyScore: energyScore,
          equalizerA: _equalizerA,
          equalizerB: _equalizerB,
          outgoing: audioPlayer,
          outgoingUri: currentSong?.filePath,
          beatMs: beatMs,
          sections: sections,
          transitionKind: transitionKind,
        );
""",
                """        await _djSfxRack.engage(
          energyScore: energyScore,
          equalizerA: _equalizerA,
          equalizerB: _equalizerB,
          outgoing: audioPlayer,
          outgoingUri: currentSong?.filePath,
          beatMs: beatMs,
          sections: sections,
          transitionKind: transitionKind,
          aggressiveness: _djPolicy.aggressiveness,
        );
""",
                1,
            )
            if t == t2:
                print("WARNING: could not wire aggressiveness into engage calls")
            else:
                print("wired aggressiveness into engage")

    path.write_text(t)
    print("music done")


def patch_sfx_bags() -> None:
    path = ROOT / "lib/services/dj_sfx_rack.dart"
    t = path.read_text()
    if "DjAggressiveness" in t and "_presetsFor" in t:
        print("sfx bags already present")
        return

    if "import '../dj_engine/core/dj_policy.dart';" not in t:
        t = t.replace(
            "import '../dj_engine/core/dj_types.dart';\n",
            "import '../dj_engine/core/dj_types.dart';\n"
            "import '../dj_engine/core/dj_policy.dart';\n",
            1,
        )

    # Replace pickRandom to take aggressiveness
    old_pick = """  DjSfxPreset pickRandom({double energyScore = 0.5}) {
    final high = energyScore >= 0.75;
    // Mix character FX + samples; avoid stacking loudness.
    final weights = <DjSfxPreset, int>{
      DjSfxPreset.echo: 2,
      DjSfxPreset.vinylStop: high ? 2 : 2,
      DjSfxPreset.rewind: 2,
      DjSfxPreset.filterOpen: high ? 2 : 2,
      DjSfxPreset.filterClose: 2,
      DjSfxPreset.tightGlue: 2,
      DjSfxPreset.dryEcho: 1,
      DjSfxPreset.airHorn: high ? 3 : 2,
      DjSfxPreset.gunshot: high ? 2 : 1,
      DjSfxPreset.vinylScratch: 2,
      DjSfxPreset.repeat: 2,
      DjSfxPreset.repeatRestart: high ? 2 : 1,
      DjSfxPreset.scratch: 2,
      DjSfxPreset.stutter: high ? 2 : 1,
      DjSfxPreset.beatRepeat: high ? 2 : 1,
      DjSfxPreset.retrigger: 2,
      DjSfxPreset.brake: 2,
      DjSfxPreset.whoosh: 2,
      DjSfxPreset.impact: high ? 2 : 1,
    };
    final total = weights.values.fold<int>(0, (a, b) => a + b);
    var r = _rng.nextInt(total);
    for (final e in weights.entries) {
      r -= e.value;
      if (r < 0) return e.key;
    }
    return DjSfxPreset.echo;
  }
"""

    new_pick = """  /// Preset bags by DJ aggressiveness — Safe never fires club samples or
  /// track-destructive FX; Musical may, but still prefers glue most of the time.
  static const _safeBagets = <DjSfxPreset>[
    DjSfxPreset.tightGlue,
    DjSfxPreset.dryEcho,
    DjSfxPreset.echo,
    DjSfxPreset.filterOpen,
    DjSfxPreset.filterClose,
  ];

  static const _balancedPresets = <DjSfxPreset>[
    DjSfxPreset.tightGlue,
    DjSfxPreset.dryEcho,
    DjSfxPreset.echo,
    DjSfxPreset.filterOpen,
    DjSfxPreset.filterClose,
    DjSfxPreset.whoosh,
    DjSfxPreset.rewind,
    DjSfxPreset.vinylStop,
  ];

  static const _musicalPresets = <DjSfxPreset>[
    DjSfxPreset.tightGlue,
    DjSfxPreset.echo,
    DjSfxPreset.whoosh,
    DjSfxPreset.impact,
    DjSfxPreset.vinylScratch,
    DjSfxPreset.scratch,
    DjSfxPreset.stutter,
    DjSfxPreset.brake,
    DjSfxPreset.repeat,
    DjSfxPreset.airHorn,
    DjSfxPreset.gunshot,
    DjSfxPreset.beatRepeat,
  ];

  List<DjSfxPreset> _bagFor(DjAggressiveness aggressiveness) {
    return switch (aggressiveness) {
      DjAggressiveness.safe => _safePresets,
      DjAggressiveness.balanced => _balancedPresets,
      DjAggressiveness.musical => _musicalPresets,
    };
  }

  DjSfxPreset pickRandom({
    double energyScore = 0.5,
    DjAggressiveness aggressiveness = DjAggressiveness.balanced,
  }) {
    final bag = _bagFor(aggressiveness);
    final high = energyScore >= 0.75;
    final weights = <DjSfxPreset, int>{};
    for (final p in bag) {
      var w = 2;
      // Prefer soft glue; de-emphasize loud samples even in Musical.
      if (p == DjSfxPreset.tightGlue || p == DjSfxPreset.dryEcho) w = 4;
      if (p == DjSfxPreset.airHorn || p == DjSfxPreset.gunshot) w = high ? 1 : 0;
      if (p == DjSfxPreset.stutter || p == DjSfxPreset.beatRepeat) w = high ? 2 : 1;
      if (w > 0) weights[p] = w;
    }
    if (weights.isEmpty) return DjSfxPreset.tightGlue;
    final total = weights.values.fold<int>(0, (a, b) => a + b);
    var r = _rng.nextInt(total);
    for (final e in weights.entries) {
      r -= e.value;
      if (r < 0) return e.key;
    }
    return DjSfxPreset.tightGlue;
  }
"""

    if old_pick not in t:
        raise SystemExit("pickRandom not found")
    t = t.replace(old_pick, new_pick, 1)

    # engage signature + aggressiveness param
    old_eng = """  Future<void> engage({
    required double energyScore,
    DjSfxPreset? preset,
    AndroidEqualizer? equalizerA,
    AndroidEqualizer? equalizerB,
    AudioPlayer? outgoing,
    String? outgoingUri,
    List<int> beatMs = const <int>[],
    List<DjSection> sections = const <DjSection>[],
    DjTransitionKind? transitionKind,
  }) async {
    final score =
        energyScore.isFinite ? energyScore.clamp(0.0, 1.0).toDouble() : 0.5;
    activePreset = preset ?? _pickPhraseAwarePreset(energyScore: score, transitionKind: transitionKind, sections: sections, positionMs: outgoing?.position.inMilliseconds ?? 0);
"""
    new_eng = """  Future<void> engage({
    required double energyScore,
    DjSfxPreset? preset,
    AndroidEqualizer? equalizerA,
    AndroidEqualizer? equalizerB,
    AudioPlayer? outgoing,
    String? outgoingUri,
    List<int> beatMs = const <int>[],
    List<DjSection> sections = const <DjSection>[],
    DjTransitionKind? transitionKind,
    DjAggressiveness aggressiveness = DjAggressiveness.balanced,
  }) async {
    final score =
        energyScore.isFinite ? energyScore.clamp(0.0, 1.0).toDouble() : 0.5;
    activePreset = preset ??
        _pickPhraseAwarePreset(
          energyScore: score,
          transitionKind: transitionKind,
          sections: sections,
          positionMs: outgoing?.position.inMilliseconds ?? 0,
          aggressiveness: aggressiveness,
        );
"""
    if old_eng not in t:
        raise SystemExit("engage signature miss")
    t = t.replace(old_eng, new_eng, 1)

    # engageDelayed aggressiveness
    old_del = """  Future<void> engageDelayed({
    required Duration delay,
    required double energyScore,
    DjSfxPreset? preset,
    AndroidEqualizer? equalizerA,
    AndroidEqualizer? equalizerB,
    AudioPlayer? outgoing,
    String? outgoingUri,
    List<int> beatMs = const <int>[],
    List<DjSection> sections = const <DjSection>[],
    DjTransitionKind? transitionKind,
  }) async {
"""
    new_del = """  Future<void> engageDelayed({
    required Duration delay,
    required double energyScore,
    DjSfxPreset? preset,
    AndroidEqualizer? equalizerA,
    AndroidEqualizer? equalizerB,
    AudioPlayer? outgoing,
    String? outgoingUri,
    List<int> beatMs = const <int>[],
    List<DjSection> sections = const <DjSection>[],
    DjTransitionKind? transitionKind,
    DjAggressiveness aggressiveness = DjAggressiveness.balanced,
  }) async {
"""
    if old_del in t:
        t = t.replace(old_del, new_del, 1)
        t = t.replace(
            """      await engage(
        energyScore: energyScore,
        preset: preset,
        equalizerA: equalizerA,
        equalizerB: equalizerB,
        outgoing: outgoing,
        outgoingUri: outgoingUri,
        beatMs: beatMs,
        sections: sections,
        transitionKind: transitionKind,
      );
""",
            """      await engage(
        energyScore: energyScore,
        preset: preset,
        equalizerA: equalizerA,
        equalizerB: equalizerB,
        outgoing: outgoing,
        outgoingUri: outgoingUri,
        beatMs: beatMs,
        sections: sections,
        transitionKind: transitionKind,
        aggressiveness: aggressiveness,
      );
""",
            1,
        )
        print("engageDelayed updated")

    # _pickPhraseAwarePreset
    old_pp = """  DjSfxPreset _pickPhraseAwarePreset({
    required double energyScore,
    DjTransitionKind? transitionKind,
    List<DjSection> sections = const <DjSection>[],
    int positionMs = 0,
  }) {
"""
    # Need full method - replace switch returns for safe
    import re

    m = re.search(
        r"  DjSfxPreset _pickPhraseAwarePreset\(\{.*?\n  \}",
        t,
        re.S,
    )
    if not m:
        raise SystemExit("pickPhraseAware miss")

    new_pp = """  DjSfxPreset _pickPhraseAwarePreset({
    required double energyScore,
    DjTransitionKind? transitionKind,
    List<DjSection> sections = const <DjSection>[],
    int positionMs = 0,
    DjAggressiveness aggressiveness = DjAggressiveness.balanced,
  }) {
    // Safe: only soft glue / filter colour — never samples or track surgery.
    if (aggressiveness == DjAggressiveness.safe) {
      return switch (transitionKind) {
        DjTransitionKind.safeCrossfade => DjSfxPreset.dryEcho,
        DjTransitionKind.outroIntro => DjSfxPreset.filterClose,
        DjTransitionKind.energyBridge => DjSfxPreset.echo,
        _ => DjSfxPreset.tightGlue,
      };
    }

    DjSection? section;
    for (final s in sections) {
      if (positionMs >= s.startMs && positionMs < s.endMs) {
        section = s;
        break;
      }
    }

    DjSfxPreset chosen;
    switch (transitionKind) {
      case DjTransitionKind.breakdownDrop:
        chosen = energyScore >= 0.72 ? DjSfxPreset.impact : DjSfxPreset.whoosh;
        break;
      case DjTransitionKind.phraseBlend:
        chosen = section?.type == DjSectionType.breakdown
            ? DjSfxPreset.repeatRestart
            : DjSfxPreset.repeat;
        break;
      case DjTransitionKind.beatBlend:
        chosen = energyScore >= 0.86
            ? DjSfxPreset.stutter
            : (energyScore >= 0.78 ? DjSfxPreset.scratch : DjSfxPreset.repeat);
        break;
      case DjTransitionKind.energyBridge:
        chosen = energyScore >= 0.75 ? DjSfxPreset.whoosh : DjSfxPreset.echo;
        break;
      case DjTransitionKind.outroIntro:
        chosen = energyScore >= 0.82
            ? DjSfxPreset.brake
            : (energyScore >= 0.75 ? DjSfxPreset.filterClose : DjSfxPreset.echo);
        break;
      case DjTransitionKind.safeCrossfade:
        chosen = DjSfxPreset.dryEcho;
        break;
      case null:
        chosen = pickRandom(
          energyScore: energyScore,
          aggressiveness: aggressiveness,
        );
        break;
    }

    // Balanced: clamp destructive / club samples back to glue.
    if (aggressiveness == DjAggressiveness.balanced) {
      const banned = {
        DjSfxPreset.airHorn,
        DjSfxPreset.gunshot,
        DjSfxPreset.stutter,
        DjSfxPreset.beatRepeat,
        DjSfxPreset.scratch,
        DjSfxPreset.repeatRestart,
        DjSfxPreset.brake,
      };
      if (banned.contains(chosen)) {
        chosen = energyScore >= 0.75 ? DjSfxPreset.whoosh : DjSfxPreset.tightGlue;
      }
    }

    final bag = _bagFor(aggressiveness);
    if (!bag.contains(chosen)) {
      return pickRandom(
        energyScore: energyScore,
        aggressiveness: aggressiveness,
      );
    }
    return chosen;
  }
"""
    t = t[: m.start()] + new_pp + t[m.end() :]
    path.write_text(t)
    print("sfx bags done")


def main() -> None:
    patch_music_pause()
    patch_sfx_bags()
    print("pause + sfx bags complete")


if __name__ == "__main__":
    main()
