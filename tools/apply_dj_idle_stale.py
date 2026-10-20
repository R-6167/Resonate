#!/usr/bin/env python3
from pathlib import Path
p = Path("lib/services/dj_idle_analysis_service.dart")
t = p.read_text()
if "isStale" in t:
    print("already")
    raise SystemExit(0)
old = """          if (existing != null &&
              (existing.hasUsableBpm || existing.hasUsableKey)) {
            continue;
          }"""
new = """          if (existing != null &&
              !existing.isStale &&
              (existing.hasUsableBpm || existing.hasUsableKey)) {
            continue;
          }"""
if old in t:
    p.write_text(t.replace(old, new, 1))
    print("idle stale")
else:
    print("MISS idle")
