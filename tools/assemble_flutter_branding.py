#!/usr/bin/env python3
"""Assemble branding_chunks into Flutter asset PNGs."""
import base64
from pathlib import Path

def write(key, dest):
  d = Path('tools/branding_chunks') / key
  parts = sorted(d.glob('*.b64'))
  if not parts:
    print('MISSING', key)
    return
  raw = base64.b64decode(''.join(p.read_text().strip() for p in parts))
  out = Path(dest)
  out.parent.mkdir(parents=True, exist_ok=True)
  out.write_bytes(raw)
  print(f'wrote {dest} ({len(raw)} bytes)')

# App mark used for both until full in-app composite is committed.
write('app_icon', 'assets/branding/resonate_app_icon.png')
write('app_icon', 'assets/branding/resonate_in_app_logo.png')
