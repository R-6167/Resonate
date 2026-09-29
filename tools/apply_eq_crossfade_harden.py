#!/usr/bin/env python3
"""Surgical harden: soft-outgoing crossfade, settings cleanup, equalizer glass copy."""
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

patch(
    "lib/providers/music_provider.dart",
    """        // Equal-power: cos out / sin in — smooth energy, no mid-fade dip.\n        final angle = t * (math.pi / 2.0);\n        final outGain = math.cos(angle);\n        final inGain = math.sin(angle);\n        final outVol = (base * outGain).clamp(0.0, 1.0);\n        final inVol = (master * inGain).clamp(0.0, 1.0);""",
    """        // Soft-outgoing equal-power: keep the outgoing track a little louder\n        // for longer so the cut does not feel hard, while incoming still\n        // rises smoothly (classic DJ energy-preserving curve with bias).\n        final outT = math.pow(t, 1.28).toDouble().clamp(0.0, 1.0);\n        final inT = math.pow(t, 0.92).toDouble().clamp(0.0, 1.0);\n        final outGain = math.cos(outT * (math.pi / 2.0));\n        final inGain = math.sin(inT * (math.pi / 2.0));\n        final outVol = (base * outGain).clamp(0.0, 1.0);\n        final inVol = (master * inGain).clamp(0.0, 1.0);""",
    "crossfade main soft-outgoing",
)

print('placeholder - will be replaced')
