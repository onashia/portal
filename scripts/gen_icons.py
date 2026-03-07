#!/usr/bin/env python3
"""
Generate Portal app icons.

Design: Material `tonality` icon (scripts/tonality_source.png — white glyph
on transparent background) centred on a rounded rectangle in the app's M3
seed colour #63A002.

Usage:
    python3 scripts/gen_icons.py

Requires Pillow:
    pip install -r scripts/requirements.txt
"""

import os
import sys
from PIL import Image, ImageDraw

# ---------------------------------------------------------------------------
# Paths (run from repo root)
# ---------------------------------------------------------------------------
SCRIPT_DIR  = os.path.dirname(os.path.abspath(__file__))
SOURCE_ICON = os.path.join(SCRIPT_DIR, "tonality_source.png")
MACOS_DIR   = "macos/Runner/Assets.xcassets/AppIcon.appiconset"
WINDOWS_DIR = "windows/runner/resources"

# ---------------------------------------------------------------------------
# Colours
# M3 TonalSpot primary P-40 approximated from seed #63A002 (vivid green).
# The app uses ColorScheme.fromSeed(seedColor: Color(0xFF63A002),
#   dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot).
# ---------------------------------------------------------------------------
BG_COLOR = (56, 106, 0)   # ~M3 primary P-40

# Fraction of the icon canvas the glyph should occupy (padding = remainder/2)
GLYPH_FILL = 0.60

# macOS requires these exact pixel sizes in the appiconset
MACOS_SIZES = [16, 32, 64, 128, 256, 512, 1024]

# Windows ICO sizes to embed
WIN_ICO_SIZES = [16, 32, 48, 256]


# ---------------------------------------------------------------------------
# Icon renderer
# ---------------------------------------------------------------------------

def _load_source(path: str) -> Image.Image:
    """
    Load the source glyph PNG and return it as RGBA.

    The source is expected to be a white glyph on a transparent background.
    The alpha channel is used as the mask when compositing.
    """
    src = Image.open(path).convert("RGBA")
    return src


def draw_icon(size: int, source: Image.Image) -> Image.Image:
    """
    Render one Portal icon frame.

    Steps:
      1. Rounded rectangle background (BG_COLOR)
      2. Glyph resized to GLYPH_FILL × size, composited centred
    """
    img  = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # --- Background ---
    corner = max(1, int(size * 0.22))
    draw.rounded_rectangle(
        [0, 0, size - 1, size - 1],
        radius=corner,
        fill=(*BG_COLOR, 255),
    )

    # --- Glyph ---
    glyph_px = max(1, round(size * GLYPH_FILL))
    # Use LANCZOS for downsizing, BICUBIC for upsizing (source is 1000 px)
    resample = Image.LANCZOS if size < source.width else Image.BICUBIC
    glyph = source.resize((glyph_px, glyph_px), resample=resample)

    # Centre the glyph on the canvas
    offset = (size - glyph_px) // 2
    # Composite via alpha channel so anti-aliased edges blend properly
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(glyph, (offset, offset))
    img = Image.alpha_composite(img, canvas)

    return img


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    repo_root = os.path.dirname(SCRIPT_DIR)
    os.chdir(repo_root)

    if not os.path.exists(SOURCE_ICON):
        print(
            f"Error: source icon not found at {SOURCE_ICON}\n"
            "Place a white-on-transparent PNG there and re-run.",
            file=sys.stderr,
        )
        sys.exit(1)

    source = _load_source(SOURCE_ICON)
    print(f"Source icon: {source.size[0]}×{source.size[1]} px")

    os.makedirs(MACOS_DIR,   exist_ok=True)
    os.makedirs(WINDOWS_DIR, exist_ok=True)

    print("\nGenerating macOS icons…")
    for px in MACOS_SIZES:
        icon = draw_icon(px, source)
        path = os.path.join(MACOS_DIR, f"app_icon_{px}.png")
        icon.save(path, "PNG")
        print(f"  {path}  ({px}×{px})")

    print("\nGenerating Windows ICO…")
    ico_path = os.path.join(WINDOWS_DIR, "app_icon.ico")
    # Pillow's ICO plugin resizes a single source image to each requested size.
    # Render at the largest ICO size so downscales are high-quality.
    ico_source = draw_icon(max(WIN_ICO_SIZES), source)
    ico_source.save(
        ico_path,
        format="ICO",
        sizes=[(px, px) for px in WIN_ICO_SIZES],
    )
    print(f"  {ico_path}  (sizes: {WIN_ICO_SIZES})")

    print("\nDone.")


if __name__ == "__main__":
    try:
        from PIL import Image, ImageDraw  # noqa: F401
    except ImportError:
        print("Error: Pillow is required.  Run:  pip install Pillow", file=sys.stderr)
        sys.exit(1)
    main()
