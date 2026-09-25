#!/usr/bin/env python3
"""Generate Android launcher, splash, and notification icons from assets/branding."""
from pathlib import Path

try:
    from PIL import Image
except ImportError as e:
    raise SystemExit('Pillow required: pip install pillow') from e

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'assets' / 'branding' / 'resonate_app_icon.png'
RES = ROOT / 'android' / 'app' / 'src' / 'main' / 'res'


def _load() -> Image.Image:
    if not SRC.exists():
        raise SystemExit(f'Missing {SRC}')
    return Image.open(SRC).convert('RGBA')


def _save(im: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    im.save(path, 'PNG', optimize=True)
    print(f'wrote {path.relative_to(ROOT)} ({path.stat().st_size} bytes)')


def _white_stat(im: Image.Image, size: int) -> Image.Image:
    im = im.resize((size, size), Image.Resampling.LANCZOS)
    gray = im.convert('L')
    alpha = gray.point(lambda p: 0 if p < 18 else min(255, int((p - 18) * 1.25)))
    white = Image.new('RGBA', (size, size), (255, 255, 255, 255))
    empty = Image.new('RGBA', (size, size), (255, 255, 255, 0))
    return Image.composite(white, empty, alpha)


def main() -> None:
    app = _load()

    # Adaptive / splash foregrounds
    _save(app.resize((432, 432), Image.Resampling.LANCZOS),
          RES / 'drawable' / 'ic_launcher_foreground.png')
    _save(app.resize((320, 320), Image.Resampling.LANCZOS),
          RES / 'drawable' / 'splash_logo.png')

    # Legacy mipmaps
    for folder, size in [
        ('mipmap-mdpi', 48),
        ('mipmap-hdpi', 72),
        ('mipmap-xhdpi', 96),
        ('mipmap-xxhdpi', 144),
        ('mipmap-xxxhdpi', 192),
    ]:
        _save(app.resize((size, size), Image.Resampling.LANCZOS),
              RES / folder / 'ic_launcher.png')

    # Notification small icons (white silhouette)
    for folder, size in [
        ('drawable-mdpi', 24),
        ('drawable-hdpi', 36),
        ('drawable-xhdpi', 48),
        ('drawable-xxhdpi', 72),
        ('drawable-xxxhdpi', 96),
    ]:
        _save(_white_stat(app, size), RES / folder / 'ic_stat_resonate.png')
    _save(_white_stat(app, 96), RES / 'drawable' / 'ic_stat_resonate.png')

    print('android branding generated')


if __name__ == '__main__':
    main()
