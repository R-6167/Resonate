#!/usr/bin/env python3
"""Re-encode or regenerate launcher PNGs so AAPT2 can compile them."""
from pathlib import Path
import io
import sys

try:
    from PIL import Image, ImageDraw
except ImportError:
    import subprocess

    subprocess.check_call([sys.executable, "-m", "pip", "install", "pillow", "-q"])
    from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "android/app/src/main/res"

SIZES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}


def make_mark(size: int) -> Image.Image:
    """Simple brand-like mark if source is unreadable."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    pad = max(2, size // 12)
    # soft purple circle (matches Resonate glass accents)
    d.ellipse((pad, pad, size - pad - 1, size - pad - 1), fill=(91, 140, 255, 255))
    inner = pad + size // 6
    d.ellipse((inner, inner, size - inner - 1, size - inner - 1), fill=(124, 92, 255, 255))
    return img


def load_or_make(path: Path, size: int) -> Image.Image:
    if path.exists():
        try:
            img = Image.open(path)
            img.load()
            return img.convert("RGBA").resize((size, size), Image.Resampling.LANCZOS)
        except Exception as e:
            print(f"  BROKEN {path.name}: {e} — regenerating")
    return make_mark(size)


def write_png(path: Path, img: Image.Image) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    buf = io.BytesIO()
    img.save(buf, format="PNG", optimize=True)
    path.write_bytes(buf.getvalue())


changed = 0
# Prefer a working density as master if any loads
master = None
for dens, size in SIZES.items():
    p = RES / f"mipmap-{dens}" / "ic_launcher.png"
    if not p.exists():
        continue
    try:
        img = Image.open(p)
        img.load()
        master = img.convert("RGBA")
        print(f"master from {dens}")
        break
    except Exception as e:
        print(f"skip master {dens}: {e}")

for dens, size in SIZES.items():
    for name in ("ic_launcher.png", "ic_launcher_round.png"):
        path = RES / f"mipmap-{dens}" / name
        if master is not None:
            try:
                if path.exists():
                    old = Image.open(path)
                    old.load()
                    img = old.convert("RGBA").resize((size, size), Image.Resampling.LANCZOS)
                else:
                    img = master.resize((size, size), Image.Resampling.LANCZOS)
            except Exception:
                img = master.resize((size, size), Image.Resampling.LANCZOS)
                print(f"  regenerated {path.relative_to(ROOT)} from master")
        else:
            img = load_or_make(path, size)
        buf = io.BytesIO()
        img.save(buf, format="PNG", optimize=True)
        data = buf.getvalue()
        old_data = path.read_bytes() if path.exists() else b""
        if data != old_data:
            write_png(path, img)
            changed += 1
            print(f"wrote {path.relative_to(ROOT)} ({len(data)} bytes)")

# Any other broken PNGs under res
for path in sorted(RES.rglob("*.png")):
    try:
        Image.open(path).load()
    except Exception as e:
        print(f"extra broken {path.relative_to(ROOT)}: {e}")
        # replace with tiny valid transparent PNG
        img = Image.new("RGBA", (1, 1), (0, 0, 0, 0))
        write_png(path, img)
        changed += 1

print(f"done, changed={changed}")
