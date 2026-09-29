#!/usr/bin/env python3
"""Surgical harden: soft-outgoing crossfade, EQ effects card, settings cleanup, live badge."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
changed = []

def patch(path: str, old: str, new: str, label: str) -> None:
    p = ROOT / path
    if not p.exists():
        print(f"MISSING {path}")
        sys.exit(1)
    text = p.read_text()
    if new.strip() and new in text and old not in text:
        print(f"already applied: {label}")
        return
    if old not in text:
        print(f"pattern not found: {label}")
        return
    p.write_text(text.replace(old, new, 1))
    changed.append(label)
    print(f"patched: {label}")

# --- music_provider: soft-outgoing equal-power ---
patch(
    "lib/providers/music_provider.dart",
    """        // Equal-power: cos out / sin in — smooth energy, no mid-fade dip.\n        final angle = t * (math.pi / 2.0);\n        final outGain = math.cos(angle);\n        final inGain = math.sin(angle);\n        final outVol = (base * outGain).clamp(0.0, 1.0);\n        final inVol = (master * inGain).clamp(0.0, 1.0);""",
    """        // Soft-outgoing equal-power: keep the outgoing track a little louder\n        // for longer so the cut does not feel hard, while incoming still\n        // rises smoothly (classic DJ energy-preserving curve with bias).\n        final outT = math.pow(t, 1.28).toDouble().clamp(0.0, 1.0);\n        final inT = math.pow(t, 0.92).toDouble().clamp(0.0, 1.0);\n        final outGain = math.cos(outT * (math.pi / 2.0));\n        final inGain = math.sin(inT * (math.pi / 2.0));\n        final outVol = (base * outGain).clamp(0.0, 1.0);\n        final inVol = (master * inGain).clamp(0.0, 1.0);""",
    "crossfade main soft-outgoing",
)

patch(
    "lib/providers/music_provider.dart",
    """        switch (fadeType) {\n          case 'ease_in':\n            outV = master * (1.0 - t * t);\n            inV = master * (t * t);\n            break;\n          case 'ease_out':\n            final u = 1.0 - t;\n            outV = master * (u * u);\n            inV = master * (1.0 - u * u);\n            break;\n          case 'ease_in_out':\n            final s = t * t * (3.0 - 2.0 * t);\n            outV = master * (1.0 - s);\n            inV = master * s;\n            break;\n          default:\n            outV = master * (1.0 - t);\n            inV = master * t;\n        }""",
    """        // Soft-outgoing: delay the drop on the leaving track.\n        final outT = math.pow(t, 1.28).toDouble().clamp(0.0, 1.0);\n        final inT = math.pow(t, 0.92).toDouble().clamp(0.0, 1.0);\n        switch (fadeType) {\n          case 'ease_in':\n            outV = master * (1.0 - outT * outT);\n            inV = master * (inT * inT);\n            break;\n          case 'ease_out':\n            final u = 1.0 - outT;\n            outV = master * (u * u);\n            inV = master * (1.0 - math.pow(1.0 - inT, 2).toDouble());\n            break;\n          case 'ease_in_out':\n            final sOut = outT * outT * (3.0 - 2.0 * outT);\n            final sIn = inT * inT * (3.0 - 2.0 * inT);\n            outV = master * (1.0 - sOut);\n            inV = master * sIn;\n            break;\n          default:\n            // Equal-power soft-outgoing for the default path.\n            outV = master * math.cos(outT * (math.pi / 2.0));\n            inV = master * math.sin(inT * (math.pi / 2.0));\n        }""",
    "crossfade switch soft-outgoing",
)

patch(
    "lib/providers/music_provider.dart",
    """        try {\n          await outgoing.setVolume((startOut * (1.0 - t)).clamp(0.0, 1.0));\n        } catch (_) {}\n        try {\n          await incoming.setVolume((master * t).clamp(0.0, 1.0));\n        } catch (_) {}""",
    """        final outT = math.pow(t, 1.28).toDouble().clamp(0.0, 1.0);\n        final inT = math.pow(t, 0.92).toDouble().clamp(0.0, 1.0);\n        try {\n          await outgoing.setVolume((startOut * math.cos(outT * (math.pi / 2.0))).clamp(0.0, 1.0));\n        } catch (_) {}\n        try {\n          await incoming.setVolume((master * math.sin(inT * (math.pi / 2.0))).clamp(0.0, 1.0));\n        } catch (_) {}""",
    "repeat-self soft-outgoing",
)

# --- settings: remove Effects entry ---
patch(
    "lib/screens/settings_screen.dart",
    """              _item(context, 'Effects', 'Loudness and audio processing', Icons.tune_rounded, const AudioEffectsScreen()),\n""",
    """              // Effects moved into Equalizer (Bass / Width / Reverb). Loudness retired.\n""",
    "settings remove Effects nav",
)

patch(
    "lib/screens/settings_screen.dart",
    """'Equalizer, Crossfade, DJ Mode, and Effects work from Settings even before you play a song. Open Playback to find DJ Mode.'""",
    """'Equalizer (includes Bass / Width / Reverb), Crossfade, and DJ Mode work from Settings even before you play a song.'""",
    "settings tip text",
)

patch(
    "lib/screens/settings_screen.dart",
    """_item(context, 'Equalizer', 'Main sound profile', Icons.equalizer_rounded, const EqualizerScreen()),""",
    """_item(context, 'Equalizer', 'Tone, preamp, bass, width & reverb', Icons.equalizer_rounded, const EqualizerScreen()),""",
    "settings equalizer subtitle",
)

# Copy glass equalizer with colour effects if shipped beside this script
src = Path(__file__).resolve().parent / "equalizer_screen_glass.dart"
dst = ROOT / "lib/screens/equalizer_screen.dart"
if src.exists():
    dst.write_text(src.read_text())
    changed.append("equalizer glass + colour effects")
    print("wrote equalizer_screen.dart from tools/equalizer_screen_glass.dart")
else:
    print("no equalizer_screen_glass.dart beside script — skip UI copy")

print("TOTAL changed:", len(changed), changed)
