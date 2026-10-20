#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# 1) music_provider: profileFor -> getProfile(songId)
mp = ROOT / "lib/providers/music_provider.dart"
t = mp.read_text()
old = """      DjTrackProfile? outProfile;
      try {
        final path = outgoingSong?.filePath;
        if (path != null && _djAnalysis != null) {
          outProfile = await _djAnalysis!.profileFor(path);
        }
      } catch (_) {}
"""
new = """      DjTrackProfile? outProfile;
      try {
        final id = outgoingSong?.id;
        if (id != null && _djAnalysis != null) {
          outProfile = await _djAnalysis!.getProfile(id);
        }
      } catch (_) {}
"""
if "profileFor" in t:
    if old in t:
        t = t.replace(old, new, 1)
        print("music getProfile fixed")
    else:
        t = t.replace("profileFor(path)", "getProfile(outgoingSong!.id)")
        t = t.replace("final path = outgoingSong?.filePath;", "final id = outgoingSong?.id;")
        t = t.replace("if (path != null && _djAnalysis != null)", "if (id != null && _djAnalysis != null)")
        print("music getProfile fixed loose")
else:
    print("music already ok")
mp.write_text(t)

# 2) dj_sfx_rack: late final chosen cannot be reassigned
sfx = ROOT / "lib/services/dj_sfx_rack.dart"
s = sfx.read_text()
old_pp = """    late final DjSfxPreset chosen;
    switch (transitionKind) {
      case DjTransitionKind.breakdownDrop:
        chosen = energyScore >= 0.72 ? DjSfxPreset.impact : DjSfxPreset.whoosh;
      case DjTransitionKind.phraseBlend:
        chosen = section?.type == DjSectionType.breakdown
            ? DjSfxPreset.repeatRestart
            : DjSfxPreset.repeat;
      case DjTransitionKind.beatBlend:
        chosen = energyScore >= 0.86
            ? DjSfxPreset.stutter
            : (energyScore >= 0.78 ? DjSfxPreset.scratch : DjSfxPreset.repeat);
      case DjTransitionKind.energyBridge:
        chosen = energyScore >= 0.75 ? DjSfxPreset.whoosh : DjSfxPreset.echo;
      case DjTransitionKind.outroIntro:
        chosen = energyScore >= 0.82
            ? DjSfxPreset.brake
            : (energyScore >= 0.75 ? DjSfxPreset.filterClose : DjSfxPreset.echo);
      case DjTransitionKind.safeCrossfade:
        chosen = DjSfxPreset.dryEcho;
      case null:
        chosen = pickRandom(
          energyScore: energyScore,
          aggressiveness: aggressiveness,
        );
    }

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
"""

new_pp = """    DjSfxPreset chosen = switch (transitionKind) {
      DjTransitionKind.breakdownDrop =>
        energyScore >= 0.72 ? DjSfxPreset.impact : DjSfxPreset.whoosh,
      DjTransitionKind.phraseBlend => section?.type == DjSectionType.breakdown
          ? DjSfxPreset.repeatRestart
          : DjSfxPreset.repeat,
      DjTransitionKind.beatBlend => energyScore >= 0.86
          ? DjSfxPreset.stutter
          : (energyScore >= 0.78 ? DjSfxPreset.scratch : DjSfxPreset.repeat),
      DjTransitionKind.energyBridge =>
        energyScore >= 0.75 ? DjSfxPreset.whoosh : DjSfxPreset.echo,
      DjTransitionKind.outroIntro => energyScore >= 0.82
          ? DjSfxPreset.brake
          : (energyScore >= 0.75 ? DjSfxPreset.filterClose : DjSfxPreset.echo),
      DjTransitionKind.safeCrossfade => DjSfxPreset.dryEcho,
      null => pickRandom(
          energyScore: energyScore,
          aggressiveness: aggressiveness,
        ),
    };

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
"""

if "late final DjSfxPreset chosen" in s:
    if old_pp not in s:
        raise SystemExit("chosen block pattern miss")
    s = s.replace(old_pp, new_pp, 1)
    print("sfx chosen fixed")
elif "DjSfxPreset chosen = switch" in s:
    print("sfx already ok")
else:
    print("WARNING sfx pattern miss")
sfx.write_text(s)
print("compile fixes applied")
