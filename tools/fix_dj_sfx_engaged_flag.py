#!/usr/bin/env python3
"""Fix delayed DJ SFX so envelope ticks run during the rest of the crossfade."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "lib/providers/music_provider.dart"
t = path.read_text()

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
        // Schedule without blocking the crossfade start. Mark engaged only
        // after the rack actually applies FX so envelope ticks (_tickDjClubFxSweep)
        // run for the remainder of the fade. Cancel via restore still bumps the
        // delayed generation and prevents a late engage from sticking.
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
    if "engage_after_delay" in t:
        print("already patched")
    else:
        raise SystemExit("engage method not found")
else:
    path.write_text(t.replace(old, new, 1))
    print("music_provider engage flag fixed")

# Harden engageDelayed: do not claim engaged until FX is applied (after delay).
rack = ROOT / "lib/services/dj_sfx_rack.dart"
r = rack.read_text()
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
if old_d in r:
    rack.write_text(r.replace(old_d, new_d, 1))
    print("engageDelayed hardened")
elif "Cancelled by restore" in r:
    print("engageDelayed already hardened")
else:
    print("WARNING: engageDelayed pattern miss")
"""
