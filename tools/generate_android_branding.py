#!/usr/bin/env python3
"""Generate Android launcher, splash, and notification icons from assets/branding.

Adaptive icons crop toward the center safe zone. We pad the mark so the side
waves of the R stay visible on the home-screen icon and the splash.
"""
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
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


def _pad_logo(im: Image.Image, canvas: int, logo_frac: float = 0.56) -> Image.Image:
    """Center the mark on a transparent canvas so adaptive crop keeps the waves."""
    out = Image.new('RGBA', (canvas, canvas), (0, 0, 0, 0))
    side = max(1, int(canvas * logo_frac))
    logo = im.resize((side, side), Image.Resampling.LANCZOS)
    off = (canvas - side) // 2
    out.paste(logo, (off, off), logo)
    return out


def _white_stat(im: Image.Image, size: int) -> Image.Image:
    im = im.resize((size, size), Image.Resampling.LANCZOS)
    gray = im.convert('L')
    alpha = gray.point(lambda p: 0 if p < 18 else min(255, int((p - 18) * 1.25)))
    white = Image.new('RGBA', (size, size), (255, 255, 255, 255))
    empty = Image.new('RGBA', (size, size), (255, 255, 255, 0))
    return Image.composite(white, empty, alpha)


def _font(size: int):
    for name in (
        '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
        '/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf',
        '/System/Library/Fonts/Supplemental/Arial Bold.ttf',
    ):
        p = Path(name)
        if p.exists():
            return ImageFont.truetype(str(p), size)
    return ImageFont.load_default()


def _make_splash(im: Image.Image) -> Image.Image:
    """Full-bleed splash: night void, padded mark, app name, one-line teaser."""
    w, h = 1080, 1920
    bg = Image.new('RGBA', (w, h), (5, 5, 16, 255))
    draw = ImageDraw.Draw(bg)

    logo_side = 420
    padded = _pad_logo(im, logo_side + 120, logo_frac=0.72)
    padded = padded.resize((logo_side, logo_side), Image.Resampling.LANCZOS)
    lx = (w - logo_side) // 2
    ly = int(h * 0.28)
    bg.paste(padded, (lx, ly), padded)

    title_font = _font(72)
    teaser_font = _font(34)
    title = 'Resonate'
    teaser = 'Your music. Your rules. Fully offline.'

    tb = draw.textbbox((0, 0), title, font=title_font)
    tw = tb[2] - tb[0]
    tx = (w - tw) // 2
    ty = ly + logo_side + 48
    draw.text((tx, ty), title, font=title_font, fill=(230, 220, 255, 255))

    sb = draw.textbbox((0, 0), teaser, font=teaser_font)
    sw = sb[2] - sb[0]
    sx = (w - sw) // 2
    sy = ty + 96
    draw.text((sx, sy), teaser, font=teaser_font, fill=(160, 150, 190, 255))

    return bg


def main() -> None:
    app = _load()

    # Adaptive foreground — padded so side waves survive OEM masks
    _save(_pad_logo(app, 432, logo_frac=0.56),
          RES / 'drawable' / 'ic_launcher_foreground.png')

    # Full splash art with name + teaser
    _save(_make_splash(app), RES / 'drawable' / 'splash_logo.png')

    # Legacy mipmaps (slight pad so waves aren't clipped by round masks)
    for folder, size in [
        ('mipmap-mdpi', 48),
        ('mipmap-hdpi', 72),
        ('mipmap-xhdpi', 96),
        ('mipmap-xxhdpi', 144),
        ('mipmap-xxxhdpi', 192),
    ]:
        _save(_pad_logo(app, size, logo_frac=0.72),
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
