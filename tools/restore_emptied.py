#!/usr/bin/env python3
"""Restore emptied critical files from tools/*.b64 chunks."""
from pathlib import Path
import base64

ROOT = Path(__file__).resolve().parents[1]
TOOLS = Path(__file__).resolve().parent

def restore(dest_rel, prefix, count):
    parts = []
    for i in range(count):
        p = TOOLS / f"{prefix}_{i}.b64"
        if not p.exists():
            print(f"missing {p.name}")
            return False
        parts.append(p.read_text().strip())
    data = base64.b64decode("".join(parts).encode())
    dest = ROOT / dest_rel
    dest.write_bytes(data)
    print(f"restored {dest_rel} ({len(data)} bytes)")
    return True

ok = True
ok &= restore("lib/screens/settings_screen.dart", "settings", 3)
ok &= restore("lib/screens/equalizer_screen.dart", "eq", 8)
ok &= restore("lib/providers/music_provider.dart", "music", 18)
print("done", ok)
