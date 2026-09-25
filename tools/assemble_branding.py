#!/usr/bin/env python3
"""Assemble tools/branding_chunks/* into assets and Android res."""
import base64
from pathlib import Path

ROOT = Path('tools/branding_chunks')

TARGETS = {
  'in_app': 'assets/branding/resonate_in_app_logo.png',
  'app_icon': 'assets/branding/resonate_app_icon.png',
  'fg': 'android/app/src/main/res/drawable/ic_launcher_foreground.png',
  'mipmap-mdpi': 'android/app/src/main/res/mipmap-mdpi/ic_launcher.png',
  'mipmap-hdpi': 'android/app/src/main/res/mipmap-hdpi/ic_launcher.png',
  'mipmap-xhdpi': 'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png',
  'mipmap-xxhdpi': 'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png',
  'mipmap-xxxhdpi': 'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
  'stat-mdpi': 'android/app/src/main/res/drawable-mdpi/ic_stat_resonate.png',
  'stat-hdpi': 'android/app/src/main/res/drawable-hdpi/ic_stat_resonate.png',
  'stat-xhdpi': 'android/app/src/main/res/drawable-xhdpi/ic_stat_resonate.png',
  'stat-xxhdpi': 'android/app/src/main/res/drawable-xxhdpi/ic_stat_resonate.png',
  'stat-xxxhdpi': 'android/app/src/main/res/drawable-xxxhdpi/ic_stat_resonate.png',
}

def main():
  for key, dest in TARGETS.items():
    d = ROOT / key
    parts = sorted(d.glob('*.b64'))
    if not parts:
      print('MISSING', key)
      continue
    b64 = ''.join(p.read_text().strip() for p in parts)
    raw = base64.b64decode(b64)
    out = Path(dest)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(raw)
    print(f'wrote {dest} ({len(raw)} bytes)')

if __name__ == '__main__':
  main()
