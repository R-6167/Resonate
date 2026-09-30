#!/usr/bin/env python3
"""Restore full polished home_screen.dart from known-good parent if truncated."""
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "lib/screens/home_screen.dart"
t = path.read_text()

if "class _RecommendationTileState" in t and "ResonateGlassScaffold" in t:
    print("home already complete", len(t))
    raise SystemExit(0)

# Fetch full polished version from commit that had complete file
url = "https://raw.githubusercontent.com/R-6167/Resonate/0283f7d58dae89c292647f0d26be83f3984843e8/lib/screens/home_screen.dart"
with urllib.request.urlopen(url) as r:
    full = r.read().decode("utf-8")

if "class _RecommendationTileState" not in full:
    raise SystemExit("upstream restore source incomplete")
if "ResonateGlassScaffold" not in full:
    raise SystemExit("upstream missing glass")

path.write_text(full)
print("restored", len(full))
