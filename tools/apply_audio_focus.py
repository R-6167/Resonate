#!/usr/bin/env python3
"""Apply audio-focus harden patch to lib/providers/music_provider.dart"""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / "lib/providers/music_provider.dart"
PATCH = ROOT / "tools/audio_focus.patch"
# Known-good tree before the PLACEHOLDER corruption commit.
GOOD_SHAS = [
    "HEAD~1",
    "8551fb84ca3c42782edc332352bb80523b3255be",
]

def restore_from_git():
    for ref in GOOD_SHAS:
        r = subprocess.run(
            ["git", "show", f"{ref}:lib/providers/music_provider.dart"],
            cwd=ROOT, capture_output=True, text=True
        )
        if r.returncode == 0 and len(r.stdout) > 1000 and "MusicProvider" in r.stdout:
            TARGET.write_text(r.stdout)
            print(f"restored music_provider.dart from {ref} ({len(r.stdout)} bytes)")
            return True
        print(f"restore from {ref} failed: {(r.stderr or '')[:200]}")
    return False

def main():
    if not TARGET.exists():
        print("missing", TARGET)
        return 1
    text = TARGET.read_text()
    if "_unduckAfterInterruption" in text and "AndroidAudioFocusGainType.gain" in text:
        print("audio focus harden already present")
        return 0
    if "PLACEHOLDER" in text or len(text) < 1000:
        print("music_provider.dart looks corrupted; restoring…")
        if not restore_from_git():
            print("FATAL: could not restore base file")
            return 2
        text = TARGET.read_text()
    r = subprocess.run(
        ["git", "apply", "--whitespace=nowarn", str(PATCH)],
        cwd=ROOT, capture_output=True, text=True
    )
    if r.returncode != 0:
        print("git apply failed:", r.stderr)
        return 3
    text = TARGET.read_text()
    if "_unduckAfterInterruption" not in text:
        print("patch applied but marker missing")
        return 4
    print("applied audio focus harden OK")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
