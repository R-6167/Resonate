#!/usr/bin/env python3
"""Fix delayed DJ SFX so envelope ticks run during the rest of the crossfade."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def patch_music() -> None:
    path = ROOT / "lib/providers/music_provider.dart"
    t = path.read_text()
    if "engage_after_delay" in t:
        print("music already patched")
        return

    old = """  Future<void> _engageDjTransitionSfx({
    double energyScore = 0.5,
    DjTransitionKind? transitionKind,
    Duration delay = Duration.zero,
    DjTrackProfile? outgoingProfile,
  }) async {
    if (!_djSfxActive) return;
    try {
      final profile = outgoingProfile;
      if (delay > Duration.zero) {
        unawaited(_djSfxRack.engageDelayed(
          delay: delay,
          energyScore: energyScore,
          equalizerA: _equalizerA,
          equalizerB: _equalizerB,
          outgoing: audioPlayer,
          outgoingUri: currentSong?.filePath,
          beatMs: profile?.beatGrid.beatMs ?? const <int>[],
          sections: profile?.sections ?? const <DjSection>[],
          transitionKind: transitionKind,
        ));
      } else {
        await _djSfxRack.engage(
          energyScore: energyScore,
          equalizerA: _equalizerA,
          equalizerB: _equalizerB,
          outgoing: audioPlayer,
          outgoingUri: currentSong?.filePath,
          beatMs: profile?.beatGrid.beatMs ?? const <int>[],
          sections: profile?.sections ?? const <DjSection>[],
          transitionKind: transitionKind,
        );
        _djSfxEngaged = true;
      }
      await ResonateDiagnostics.record('dj_transition_sfx', {
        'action': delay > Duration.zero ? 'scheduled' : 'engage',
        'delayMs': delay.inMilliseconds,
        'energyScore': energyScore,
      });
    } catch (e) {
      debugPrint('DJ transition SFX engage: $e');
    }
  }
"""

    new = """  Future<void> _engageDjTransitionSfx({
    double energyScore = 0.5,
    DjTransitionKind? transitionKind,
    Duration delay = Duration.zero,
    DjTrackProfile? outgoingProfile,
  }) async {
    if (!_djSfxActive) return;
    try {
      final profile = outgoingProfile;
      final beatMs = profile?.beatGrid.beatMs ?? const <int>[];
      final sections = profile?.sections ?? const <DjSection>[];
      if (delay > Duration.zero) {
        // Schedule without blocking crossfade start. Set _djSfxEngaged only
        // after the rack actually applies FX so _tickDjClubFxSweep runs for
        // the remainder of the fade. restore() bumps delayed generation so a
        // cancelled schedule cannot engage late.
        unawaited(() async {
          try {
            await _djSfxRack.engageDelayed(
              delay: delay,
              energyScore: energyScore,
              equalizerA: _equalizerA,
              equalizerB: _equalizerB,
              outgoing: audioPlayer,
              outgoingUri: currentSong?.filePath,
              beatMs: beatMs,
              sections: sections,
              transitionKind: transitionKind,
            );
            if (_djSfxRack.engaged && _djSfxActive) {
              _djSfxEngaged = true;
              await ResonateDiagnostics.record('dj_transition_sfx', {
                'action': 'engage_after_delay',
                'delayMs': delay.inMilliseconds,
                'energyScore': energyScore,
                'preset': _djSfxRack.presetName,
              });
            }
          } catch (e) {
            debugPrint('DJ transition SFX delayed engage: $e');
          }
        }());
        await ResonateDiagnostics.record('dj_transition_sfx', {
          'action': 'scheduled',
          'delayMs': delay.inMilliseconds,
          'energyScore': energyScore,
        });
      } else {
        await _djSfxRack.engage(
          energyScore: energyScore,
          equalizerA: _equalizerA,
          equalizerB: _equalizerB,
          outgoing: audioPlayer,
          outgoingUri: currentSong?.filePath,
          beatMs: beatMs,
          sections: sections,
          transitionKind: transitionKind,
        );
        _djSfxEngaged = true;
        await ResonateDiagnostics.record('dj_transition_sfx', {
          'action': 'engage',
          'delayMs': 0,
          'energyScore': energyScore,
          'preset': _djSfxRack.presetName,
        });
      }
    } catch (e) {
      debugPrint('DJ transition SFX engage: $e');
    }
  }
"""

    if old not in t:
        raise SystemExit("engage method not found")
    path.write_text(t.replace(old, new, 1))
    print("music_provider engage flag fixed")


def patch_rack() -> None:
    path = ROOT / "lib/services/dj_sfx_rack.dart"
    r = path.read_text()
    if "Cancelled by restore" in r:
        print("engageDelayed already hardened")
        return

    old_d = """    final gen = ++_delayedSfxGen;
    engaged = true;
    try {
      await Future<void>.delayed(delay);
      if (gen != _delayedSfxGen || !engaged) return;
      await engage(
"""
    new_d = """    final gen = ++_delayedSfxGen;
    try {
      await Future<void>.delayed(delay);
      // Cancelled by restore() (gen bump) or a newer schedule — do not engage.
      if (gen != _delayedSfxGen) return;
      await engage(
"""
    if old_d not in r:
        raise SystemExit("engageDelayed pattern miss")
    path.write_text(r.replace(old_d, new_d, 1))
    print("engageDelayed hardened")


def main() -> None:
    patch_music()
    patch_rack()
    print("sfx engaged flag fix complete")


if __name__ == "__main__":
    main()
