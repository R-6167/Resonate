#!/usr/bin/env python3
"""Club-style FX sweep during DJ crossfade + restore bass; bump analysis v5."""
from pathlib import Path

MP = Path('lib/providers/music_provider.dart')
mp = MP.read_text()

# --- Stronger engage: bass + virt + reverb (dark open) ---
old_eng = '''  Future<void> _engageDjTransitionSfx({double energyScore = 0.5}) async {
    if (!_djSfxActive) return;
    try {
      final score = energyScore.isFinite ? energyScore.clamp(0.0, 1.0).toDouble() : 0.5;
      final mismatch = (1.0 - score).clamp(0.0, 1.0).toDouble();
      final reverb = (0.18 + mismatch * 0.28).clamp(0.18, 0.48).toDouble();
      final width = (0.12 + mismatch * 0.22).clamp(0.10, 0.36).toDouble();
      await AudioEffectsBridge.setReverb(reverb);
      await AudioEffectsBridge.setVirtualizer(width);
      _djSfxEngaged = true;
      await ResonateDiagnostics.record('dj_transition_sfx', {
        'action': 'engage',
        'reverb': reverb,
        'virtualizer': width,
        'energyScore': score,
      });
    } catch (e) {
      debugPrint('DJ transition SFX engage: $e');
    }
  }'''

new_eng = '''  Future<void> _engageDjTransitionSfx({double energyScore = 0.5}) async {
    if (!_djSfxActive) return;
    try {
      final score = energyScore.isFinite ? energyScore.clamp(0.0, 1.0).toDouble() : 0.5;
      final mismatch = (1.0 - score).clamp(0.0, 1.0).toDouble();
      // Club-style open: start slightly dark (bass up, width modest), glue with reverb.
      final reverb = (0.20 + mismatch * 0.30).clamp(0.18, 0.52).toDouble();
      final width = (0.10 + mismatch * 0.18).clamp(0.08, 0.32).toDouble();
      final bass = (0.22 + mismatch * 0.20).clamp(0.12, 0.42).toDouble();
      await AudioEffectsBridge.setBassBoost(bass);
      await AudioEffectsBridge.setReverb(reverb);
      await AudioEffectsBridge.setVirtualizer(width);
      _djSfxEngaged = true;
      await ResonateDiagnostics.record('dj_transition_sfx', {
        'action': 'engage',
        'reverb': reverb,
        'virtualizer': width,
        'bassBoost': bass,
        'energyScore': score,
        'style': 'club_open',
      });
    } catch (e) {
      debugPrint('DJ transition SFX engage: $e');
    }
  }

  /// Progress-based club filter-sweep feel (bass/virt/reverb) during the fade.
  /// [t] is 0..1 through the crossfade. Safe no-op if SFX not engaged.
  Future<void> _tickDjClubFxSweep(double t) async {
    if (!_djSfxEngaged) return;
    try {
      final x = t.clamp(0.0, 1.0).toDouble();
      // Dark → open: bass falls, width rises, reverb peaks mid-fade.
      final bass = (0.38 * (1.0 - x) + 0.06).clamp(0.05, 0.42).toDouble();
      final width = (0.08 + 0.40 * x).clamp(0.08, 0.48).toDouble();
      final reverb = (0.16 + 0.34 * math.sin(x * math.pi)).clamp(0.12, 0.52).toDouble();
      await AudioEffectsBridge.setBassBoost(bass);
      await AudioEffectsBridge.setVirtualizer(width);
      await AudioEffectsBridge.setReverb(reverb);
    } catch (_) {}
  }'''

if "style': 'club_open'" not in mp and 'style: \'club_open\'' not in mp:
    if old_eng not in mp:
        raise SystemExit('engage block miss')
    mp = mp.replace(old_eng, new_eng, 1)
    print('engage + tick')
else:
    print('engage already')

# Restore bass too
if "setBassBoost(effectsEnabled" not in mp:
    old_res = '''      final reverb = prefs.getDouble('reverb') ?? 0.0;
      final virt = prefs.getDouble('virtualizer') ?? 0.0;
      await AudioEffectsBridge.setReverb(effectsEnabled ? reverb : 0.0);
      await AudioEffectsBridge.setVirtualizer(effectsEnabled ? virt : 0.0);'''
    new_res = '''      final reverb = prefs.getDouble('reverb') ?? 0.0;
      final virt = prefs.getDouble('virtualizer') ?? 0.0;
      final bass = prefs.getDouble('bassBoost') ?? 0.0;
      await AudioEffectsBridge.setBassBoost(effectsEnabled ? bass : 0.0);
      await AudioEffectsBridge.setReverb(effectsEnabled ? reverb : 0.0);
      await AudioEffectsBridge.setVirtualizer(effectsEnabled ? virt : 0.0);'''
    if old_res not in mp:
        raise SystemExit('restore block miss')
    mp = mp.replace(old_res, new_res, 1)
    print('restore bass')

# Tick sweep inside volume loop (every step is fine; cheap native calls)
if '_tickDjClubFxSweep' in mp and mp.count('_tickDjClubFxSweep(') < 2:
    needle = '''        try {
          // Parallel volume writes so outgoing does not stall waiting on incoming.
          await Future.wait([
            outgoing.setVolume(outVol),
            incoming.setVolume(inVol),
          ]);
        } catch (_) {}'''
    insert = '''        try {
          // Parallel volume writes so outgoing does not stall waiting on incoming.
          await Future.wait([
            outgoing.setVolume(outVol),
            incoming.setVolume(inVol),
          ]);
        } catch (_) {}
        // Club-style filter-sweep feel alongside the volume curve.
        if (_djSfxEngaged && (linear * 20).round() % 2 == 0) {
          unawaited(_tickDjClubFxSweep(linear));
        }'''
    if needle not in mp:
        raise SystemExit('volume loop miss')
    mp = mp.replace(needle, insert, 1)
    print('sweep in loop')

MP.write_text(mp)

# Bump analysis version so idle scan refreshes structure/key
MOD = Path('lib/models/dj_analysis.dart')
mod = MOD.read_text()
if 'currentVersion = 4' in mod:
    mod = mod.replace('currentVersion = 4', 'currentVersion = 5', 1)
    MOD.write_text(mod)
    print('analysis v5')
elif 'currentVersion = 5' in mod:
    print('already v5')
else:
    print('WARN version')

print('CLUB FX DONE')
