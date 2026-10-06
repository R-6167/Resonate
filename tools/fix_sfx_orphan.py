#!/usr/bin/env python3
from pathlib import Path

path = Path(__file__).resolve().parents[1] / "lib/services/dj_sfx_rack.dart"
t = path.read_text()

orphan = """  }
) {
    DjSection? section;
    for (final s in sections) {
      if (positionMs >= s.startMs && positionMs < s.endMs) {
        section = s;
        break;
      }
    }
    switch (transitionKind) {
      case DjTransitionKind.breakdownDrop:
        return energyScore >= 0.72 ? DjSfxPreset.impact : DjSfxPreset.whoosh;
      case DjTransitionKind.phraseBlend:
        return section?.type == DjSectionType.breakdown
            ? DjSfxPreset.repeatRestart
            : DjSfxPreset.repeat;
      case DjTransitionKind.beatBlend:
        return energyScore >= 0.86 ? DjSfxPreset.stutter : (energyScore >= 0.78 ? DjSfxPreset.scratch : DjSfxPreset.repeat);
      case DjTransitionKind.energyBridge:
        return energyScore >= 0.75 ? DjSfxPreset.whoosh : DjSfxPreset.echo;
      case DjTransitionKind.outroIntro:
        return energyScore >= 0.82 ? DjSfxPreset.brake : (energyScore >= 0.75 ? DjSfxPreset.filterClose : DjSfxPreset.echo);
      case DjTransitionKind.safeCrossfade:
        return DjSfxPreset.dryEcho;
      case null:
        break;
    }
    if (section?.type == DjSectionType.build ||
        section?.type == DjSectionType.chorus ||
        section?.type == DjSectionType.drop) {
      return energyScore >= 0.86 ? DjSfxPreset.stutter : (energyScore >= 0.8 ? DjSfxPreset.scratch : DjSfxPreset.echo);
    }
    return pickRandom(energyScore: energyScore);
  }

  List<int> _buildPhraseAnchors
"""

fixed = """  }

  List<int> _buildPhraseAnchors
"""

if orphan not in t:
    if ") {\n    DjSection? section;" not in t:
        print("orphan already gone")
    else:
        raise SystemExit("orphan pattern miss")
else:
    t = t.replace(orphan, fixed, 1)
    path.write_text(t)
    print("orphan removed")
