#!/usr/bin/env python3
import base64
from pathlib import Path

def write(key, dest):
  parts = sorted(Path(f'tools/branding_chunks/{key}').glob('*.b64'))
  if not parts:
    raise SystemExit(f'missing chunks for {key}')
  raw = base64.b64decode(''.join(p.read_text().strip() for p in parts))
  out = Path(dest)
  out.parent.mkdir(parents=True, exist_ok=True)
  out.write_bytes(raw)
  print(f'wrote {dest} ({len(raw)} bytes)')

write('in_app', 'assets/branding/resonate_in_app_logo.png')
write('app_icon', 'assets/branding/resonate_app_icon.png')
