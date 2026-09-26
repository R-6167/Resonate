#!/usr/bin/env python3
"""Harden high-energy SFX, long DJ crossfade, gapless vs dual-engine crossfade."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MUSIC = ROOT / 'lib/providers/music_provider.dart'
SFX = ROOT / 'lib/services/dj_sfx_rack.dart'


def try_replace(path: Path, old: str, new: str, label: str) -> bool:
    t = path.read_text()
    if old not in t:
        print('skip', label)
        return False
    path.write_text(t.replace(old, new, 1))
    print('ok', label)
    return True


def main() -> None:
    # ---------- SFX rack: energy-aware pick + softer high-energy levels ----------
    try_replace(
        SFX,
        """  DjSfxPreset pickRandom() {
    const weights = <DjSfxPreset, int>{
      DjSfxPreset.clubOpen: 3,
      DjSfxPreset.filterOpen: 2,
      DjSfxPreset.filterClose: 2,
      DjSfxPreset.bassDrop: 2,
      DjSfxPreset.wideSpace: 2,
      DjSfxPreset.tightGlue: 3,
      DjSfxPreset.dryPunch: 2,
    };
    final total = weights.values.fold<int>(0, (a, b) => a + b);
    var r = _rng.nextInt(total);
    for (final e in weights.entries) {
      r -= e.value;
      if (r < 0) return e.key;
    }
    return DjSfxPreset.clubOpen;
  }""",
        """  DjSfxPreset pickRandom({double energyScore = 0.5}) {
    final high = energyScore >= 0.75;
    // At high energy avoid clubOpen / bassDrop (they stack on already loud mixes).
    final weights = <DjSfxPreset, int>{
      DjSfxPreset.clubOpen: high ? 1 : 3,
      DjSfxPreset.filterOpen: high ? 3 : 2,
      DjSfxPreset.filterClose: high ? 3 : 2,
      DjSfxPreset.bassDrop: high ? 1 : 2,
      DjSfxPreset.wideSpace: high ? 2 : 2,
      DjSfxPreset.tightGlue: high ? 4 : 3,
      DjSfxPreset.dryPunch: high ? 3 : 2,
    };
    final total = weights.values.fold<int>(0, (a, b) => a + b);
    var r = _rng.nextInt(total);
    for (final e in weights.entries) {
      r -= e.value;
      if (r < 0) return e.key;
    }
    return DjSfxPreset.tightGlue;
  }""",
        'sfx_pick_energy',
    )

    try_replace(
        SFX,
        """    activePreset = preset ?? pickRandom();
    engaged = true;""",
        """    activePreset = preset ?? pickRandom(energyScore: score);
    engaged = true;""",
        'sfx_engage_pick',
    )

    try_replace(
        SFX,
        """    bass *= env;
    width *= env;
    reverb *= env;
    await AudioEffectsBridge.setBassBoost(bass);
    await AudioEffectsBridge.setVirtualizer(width);
    await AudioEffectsBridge.setReverb(reverb);
  }""",
        """    // High-energy tracks: pull SFX way down so we do not double-thump.
    final energyScale = score >= 0.85
        ? 0.45
        : (score >= 0.7 ? 0.62 : (score >= 0.55 ? 0.82 : 1.0));
    bass = (bass * env * energyScale).clamp(0.0, 0.14);
    width = (width * env * energyScale).clamp(0.0, 0.36);
    reverb = (reverb * env * energyScale).clamp(0.0, 0.32);
    await AudioEffectsBridge.setBassBoost(bass);
    await AudioEffectsBridge.setVirtualizer(width);
    await AudioEffectsBridge.setReverb(reverb);
  }""",
        'sfx_energy_scale',
    )

    # Soften clubOpen base curves further
    try_replace(
        SFX,
        """      case DjSfxPreset.clubOpen:
        bass = (0.10 * (1.0 - x) + 0.03).clamp(0.02, 0.16);
        width = (0.08 + 0.28 * x).clamp(0.06, 0.36);
        reverb = (0.14 + 0.26 * math.sin(x * math.pi)).clamp(0.10, 0.40);
        break;""",
        """      case DjSfxPreset.clubOpen:
        // Kept gentle — high-energy path scales further in energyScale.
        bass = (0.06 * (1.0 - x) + 0.02).clamp(0.01, 0.10);
        width = (0.06 + 0.18 * x).clamp(0.04, 0.26);
        reverb = (0.10 + 0.16 * math.sin(x * math.pi)).clamp(0.06, 0.28);
        break;""",
        'sfx_club_open_soft',
    )

    try_replace(
        SFX,
        """      case DjSfxPreset.bassDrop:
        final punch = math.sin(x * math.pi);
        bass = (0.06 + 0.16 * punch).clamp(0.03, 0.22);
        width = (0.06 + 0.10 * x).clamp(0.04, 0.20);
        reverb = (0.08 + 0.12 * punch).clamp(0.05, 0.24);
        break;""",
        """      case DjSfxPreset.bassDrop:
        final punch = math.sin(x * math.pi);
        bass = (0.04 + 0.10 * punch).clamp(0.02, 0.14);
        width = (0.04 + 0.08 * x).clamp(0.03, 0.14);
        reverb = (0.06 + 0.08 * punch).clamp(0.04, 0.18);
        break;""",
        'sfx_bass_drop_soft',
    )

    # ---------- Crossfade: DJ duration cap + gapless teardown ----------
    try_replace(
        MUSIC,
        """      final plannedMs = (milliseconds + _lastDjCrossfadeBiasMs).clamp(500, 12000).toInt();
      if (_lastDjCrossfadeBiasMs != 0) {
        unawaited(ResonateDiagnostics.record('crossfade_energy_bridge', {
          'biasMs': _lastDjCrossfadeBiasMs,
          'baseMs': milliseconds,
          'plannedMs': plannedMs,
          'outgoingSongId': outgoingSong?.id,
          'incomingSongId': nextSong.id,
        }));
      }""",
        """      // DJ Mode: long fades (8–12s) + stretch/SFX feel mushy and raise static risk.
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
      }""",
        'dj_xfade_cap',
    )

    # Gapless teardown before dual-engine fade — insert near start of true crossfade after canCrossfade checks
    try_replace(
        MUSIC,
        """    _crossfadeInProgress = true; final outgoing = audioPlayer; final outgoingSong = currentSong; final incoming = inactivePlayer; final incomingEq = inactiveEqualizer; final incomingLoud = inactiveLoudnessEnhancer; final master = _eqPreampScale.clamp(0.05, 1.0);
    try {
      await _clearDjStretchSpeeds(outgoing: outgoing, incoming: incoming);
      await outgoing.setLoopMode(LoopMode.off);
      final alreadyPreloaded = _preloadedNextSongId == nextSong.id;""",
        """    _crossfadeInProgress = true; final outgoing = audioPlayer; final outgoingSong = currentSong; final incoming = inactivePlayer; final incomingEq = inactiveEqualizer; final incomingLoud = inactiveLoudnessEnhancer; final master = _eqPreampScale.clamp(0.05, 1.0);
    try {
      await _clearDjStretchSpeeds(outgoing: outgoing, incoming: incoming);
      await outgoing.setLoopMode(LoopMode.off);

      // Gapless concatenating source fights dual-engine crossfade (index jumps,
      // double-completion). Flatten outgoing to a single URI at current position.
      if (_gaplessSourceActive && outgoingSong != null) {
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
            await outgoing.setVolume(master);
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
        _gaplessSourceActive = false;
        _gaplessWindowIds = const [];
      }

      final alreadyPreloaded = _preloadedNextSongId == nextSong.id;""",
        'gapless_flatten',
    )

    # Near-end auto trigger: when DJ on, use capped duration for trigger timing too
    try_replace(
        MUSIC,
        """    final startMarginMs = (1200 + (_crossfadeDurationMs ~/ 10)).clamp(1500, 3000);
    final triggerMs = (_crossfadeDurationMs + startMarginMs).clamp(2000, 16000);
    if (remaining > Duration(milliseconds: triggerMs)) return;
    if (remaining < const Duration(milliseconds: 1200)) return;
    _automaticCrossfadeInFlight = true;
    unawaited(_runAutomaticCrossfade());
  }""",
        """    final djActive = _djBeatAlignActive || _djTempoMatchActive || _djSfxActive;
    final effectiveXfMs =
        (djActive ? _crossfadeDurationMs.clamp(500, 6500) : _crossfadeDurationMs)
            .toInt();
    final startMarginMs = (1200 + (effectiveXfMs ~/ 10)).clamp(1500, 3000);
    final triggerMs = (effectiveXfMs + startMarginMs).clamp(2000, 16000);
    if (remaining > Duration(milliseconds: triggerMs)) return;
    if (remaining < const Duration(milliseconds: 1200)) return;
    _automaticCrossfadeInFlight = true;
    unawaited(_runAutomaticCrossfade());
  }""",
        'auto_trigger_dj_cap',
    )

    # Pass capped ms into _performTrueCrossfade from automatic path if possible
    try_replace(
        MUSIC,
        """      final timeout = Duration(milliseconds: (_crossfadeDurationMs + 12000).clamp(12000, 30000));
      final ok = await _performTrueCrossfade(
        milliseconds: _crossfadeDurationMs,
        fadeType: _crossfadeFadeType,
        generation: generation,
      ).timeout(timeout, onTimeout: () {
        debugPrint('automatic crossfade timed out');
        return false;
      });""",
        """      final djActive = _djBeatAlignActive || _djTempoMatchActive || _djSfxActive;
      final xfMs = (djActive
              ? _crossfadeDurationMs.clamp(500, 6500)
              : _crossfadeDurationMs)
          .toInt();
      final timeout =
          Duration(milliseconds: (xfMs + 12000).clamp(12000, 30000));
      final ok = await _performTrueCrossfade(
        milliseconds: xfMs,
        fadeType: _crossfadeFadeType,
        generation: generation,
      ).timeout(timeout, onTimeout: () {
        debugPrint('automatic crossfade timed out');
        return false;
      });""",
        'auto_run_dj_cap',
    )

    print('sfx/xfade/gapless harden done')


if __name__ == '__main__':
    main()
