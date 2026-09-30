#!/usr/bin/env python3
"""Re-encode launcher/notification PNGs as clean RGBA8 (no exotic chunks)."""
from pathlib import Path
import io

try:
    from PIL import Image
except ImportError:
    import subprocess, sys
    subprocess.check_call([sys.executable, "-m", "pip", "install", "pillow", "-q"])
    from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "android/app/src/main/res"

TARGETS = []
for dens in ("mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi"):
    TARGETS.append(RES / f"mipmap-{dens}" / "ic_launcher.png")
    TARGETS.append(RES / f"mipmap-{dens}" / "ic_launcher_round.png")
# notification / other common names
for pattern in ("**/ic_notification.png", "**/ic_launcher_foreground.png", "**/splash.png"):
    TARGETS.extend(RES.glob(pattern))

changed = 0
for path in TARGETS:
    if not path.exists():
        continue
    img = Image.open(path).convert("RGBA")
    buf = io.BytesIO()
    img.save(buf, format="PNG", optimize=True)
    data = buf.getvalue()
    old = path.read_bytes()
    if data != old:
        path.write_bytes(data)
        changed += 1
        print(f"re-encoded {path.relative_to(ROOT)} ({len(old)} -> {len(data)})")
    else:
        print(f"unchanged {path.relative_to(ROOT)}")
print(f"done, changed={changed}")
