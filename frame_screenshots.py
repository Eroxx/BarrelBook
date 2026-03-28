#!/usr/bin/env python3
"""
BarrelBook App Store Screenshot Framer — Premium Edition

Creates polished, marketing-ready screenshots with a bourbon-themed
gradient background, bold headline, and gold subheading.

Run:    python3 frame_screenshots.py
Output: AppStoreScreenshots_Framed/
"""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

# ── Paths ──────────────────────────────────────────────────────────────────
SCRIPT_DIR = Path(__file__).resolve().parent
SRC_DIR    = SCRIPT_DIR / "AppStore Screenshots" / "Original"
OUT_DIR    = SCRIPT_DIR / "AppStore Screenshots" / "Framed"

# ── Canvas ─────────────────────────────────────────────────────────────────
OUT_W, OUT_H = 1284, 2778   # iPhone 13/14 Pro Max 6.7" — required by App Store Connect

# ── Palette ────────────────────────────────────────────────────────────────
BG_TOP        = (10,  4,  1)       # near-black
BG_BOTTOM     = (78, 32,  8)       # deep amber-brown
HEADLINE_CLR  = (255, 255, 255)    # white
SUBHEAD_CLR   = (215, 160,  48)    # warm gold
FRAME_CLR     = (255, 255, 255)    # white phone bezel

# ── Layout (pixels) ────────────────────────────────────────────────────────
TEXT_TOP       = 100    # top margin for first text line
HEADLINE_SIZE  =  88    # font size for headline
SUBHEAD_SIZE   =  42    # font size for subheading
HEADLINE_LEAD  =  18    # extra gap between headline lines
SUBHEAD_LEAD   =  12    # extra gap between subhead lines
TEXT_PHONE_GAP =  56    # gap from bottom of text block to top of phone frame
PHONE_SIDE     =  44    # horizontal padding — tighter so screenshot fills more canvas
PHONE_BOT      =  56    # padding below phone frame
BEZEL          =  16    # white frame thickness around screenshot
CORNER_R       =  72    # corner radius for screenshot clipping mask
FRAME_CORNER_R =  90    # corner radius for white phone frame
SHADOW_OFFSET  = (0, 24)
SHADOW_BLUR    = 40
SHADOW_ALPHA   = 140

# ── Font paths (tried in order, first success wins) ────────────────────────
BOLD_FONTS = [
    ("/System/Library/Fonts/HelveticaNeue.ttc", 1),  # HelveticaNeue-Bold
    ("/System/Library/Fonts/Helvetica.ttc",     1),  # Helvetica Bold
    ("/Library/Fonts/Arial Bold.ttf",           0),
    ("/System/Library/Fonts/Helvetica.ttc",     0),  # fallback: regular
]
REGULAR_FONTS = [
    ("/System/Library/Fonts/HelveticaNeue.ttc", 0),  # HelveticaNeue
    ("/System/Library/Fonts/Helvetica.ttc",     0),
]

# ── Screenshot manifest — ordered as they should appear in the App Store ───
SCREENSHOTS = [
    {
        "file":     "Paywall.png",
        "headline": "Everything You\nNeed",
        "subhead":  "Unlimited bottles, tasting notes,\nstatistics and more",
    },
    {
        "file":     "1 Collection.png",
        "headline": "Catalog Your\nEntire Shelf",
        "subhead":  "Track proof, price, distillery &\nspecial designations for every bottle",
    },
    {
        "file":     "2 Tasting.png",
        "headline": "Never Forget\na Dram",
        "subhead":  "Log ratings and tasting notes so\nevery pour is remembered",
    },
    {
        "file":     "3 flavor wheel.png",
        "headline": "Detail Every\nFlavor",
        "subhead":  "8 flavor categories, each with subflavors,\nto map nose, palate and finish precisely",
    },
    {
        "file":     "Tasting Distribution - NEW.png",
        "headline": "See What\nYou've Tasted",
        "subhead":  "Track your tasting progress across\nevery type in your collection",
    },
    {
        "file":     "5 Overall Statistics.png",
        "headline": "Understand Your\nCollection",
        "subhead":  "Know how many BiB, Single Barrel\n& Store Pick bottles you own",
    },
    {
        "file":     "Graphs.png",
        "headline": "Analyze Your\nWhiskeys",
        "subhead":  "See how your collection breaks down\nby proof range and price",
    },
    {
        "file":     "6 wishlist view.png",
        "headline": "Build Your\nHunt List",
        "subhead":  "Save bottles you want with target\nprices and which stores carry them",
    },
]


# ── Helpers ────────────────────────────────────────────────────────────────

def make_gradient(w: int, h: int, top: tuple, bottom: tuple) -> Image.Image:
    """Vertical linear gradient."""
    img  = Image.new("RGB", (w, h))
    draw = ImageDraw.Draw(img)
    for y in range(h):
        t = y / max(h - 1, 1)
        r = int(top[0] + t * (bottom[0] - top[0]))
        g = int(top[1] + t * (bottom[1] - top[1]))
        b = int(top[2] + t * (bottom[2] - top[2]))
        draw.line([(0, y), (w - 1, y)], fill=(r, g, b))
    return img


def load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    """Load the best available font at the given size."""
    for path, idx in (BOLD_FONTS if bold else REGULAR_FONTS):
        try:
            return ImageFont.truetype(path, size, index=idx)
        except Exception:
            pass
    return ImageFont.load_default()


def draw_text_block(
    draw: ImageDraw.Draw,
    lines: list,
    y: int,
    font: ImageFont.FreeTypeFont,
    color: tuple,
    canvas_w: int,
    lead: int,
) -> int:
    """Draw centered multi-line text. Returns y coordinate below last line."""
    for i, line in enumerate(lines):
        bb = draw.textbbox((0, 0), line, font=font)
        tw = bb[2] - bb[0]
        th = bb[3] - bb[1]
        x  = (canvas_w - tw) // 2
        draw.text((x, y), line, fill=color, font=font)
        y += th
        if i < len(lines) - 1:
            y += lead
    return y


# ── Core framing function ──────────────────────────────────────────────────

def frame_one(src_path: Path, out_path: Path, headline: str, subhead: str) -> None:

    # 1. Gradient background
    canvas = make_gradient(OUT_W, OUT_H, BG_TOP, BG_BOTTOM)
    draw   = ImageDraw.Draw(canvas)

    # 2. Fonts
    font_h = load_font(HEADLINE_SIZE, bold=True)
    font_s = load_font(SUBHEAD_SIZE,  bold=False)

    # 3. Headline
    h_lines = headline.split("\n")
    y = TEXT_TOP
    y = draw_text_block(draw, h_lines, y, font_h, HEADLINE_CLR, OUT_W, HEADLINE_LEAD)

    # 4. Subheading
    y += 30
    s_lines = subhead.split("\n")
    y = draw_text_block(draw, s_lines, y, font_s, SUBHEAD_CLR, OUT_W, SUBHEAD_LEAD)

    # 5. Compute phone / frame dimensions
    phone_top       = y + TEXT_PHONE_GAP
    phone_avail_h   = OUT_H - phone_top - PHONE_BOT
    phone_avail_w   = OUT_W - 2 * PHONE_SIDE

    src    = Image.open(src_path).convert("RGB")
    sw, sh = src.size

    # Scale screenshot to fit inside the bezel area
    scr_avail_w = phone_avail_w - 2 * BEZEL
    scr_avail_h = phone_avail_h - 2 * BEZEL
    scale  = min(scr_avail_w / sw, scr_avail_h / sh)
    scr_w  = int(sw * scale)
    scr_h  = int(sh * scale)
    src_sc = src.resize((scr_w, scr_h), Image.Resampling.LANCZOS)

    frame_w = scr_w + 2 * BEZEL
    frame_h = scr_h + 2 * BEZEL
    frame_x0 = (OUT_W - frame_w) // 2
    frame_y0 = phone_top
    frame_x1 = frame_x0 + frame_w
    frame_y1 = frame_y0 + frame_h

    # 6. Drop shadow
    shadow = Image.new("RGBA", (OUT_W, OUT_H), (0, 0, 0, 0))
    sx, sy = SHADOW_OFFSET
    ImageDraw.Draw(shadow).rounded_rectangle(
        [frame_x0 + sx, frame_y0 + sy, frame_x1 + sx, frame_y1 + sy],
        radius=FRAME_CORNER_R,
        fill=(0, 0, 0, SHADOW_ALPHA),
    )
    shadow  = shadow.filter(ImageFilter.GaussianBlur(SHADOW_BLUR))
    canvas  = Image.alpha_composite(canvas.convert("RGBA"), shadow).convert("RGB")
    draw    = ImageDraw.Draw(canvas)

    # 7. White phone frame
    draw.rounded_rectangle(
        [frame_x0, frame_y0, frame_x1, frame_y1],
        radius=FRAME_CORNER_R,
        fill=FRAME_CLR,
    )

    # 8. Screenshot with rounded corners
    scr_x = frame_x0 + BEZEL
    scr_y = frame_y0 + BEZEL
    mask  = Image.new("L", (scr_w, scr_h), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, scr_w - 1, scr_h - 1], radius=CORNER_R, fill=255
    )
    canvas.paste(src_sc, (scr_x, scr_y), mask)

    # 9. Save
    canvas.save(out_path, "PNG", optimize=True)


# ── Entry point ────────────────────────────────────────────────────────────

def main():
    OUT_DIR.mkdir(exist_ok=True)
    print(f"Output: {OUT_DIR}\n")

    for i, meta in enumerate(SCREENSHOTS, 1):
        src_path = SRC_DIR / meta["file"]
        if not src_path.exists():
            print(f"  [{i:02d}] SKIP — not found: {meta['file']}")
            continue
        stem     = src_path.stem.replace(" ", "_")
        out_name = f"{i:02d}_{stem}.png"
        out_path = OUT_DIR / out_name
        print(f"  [{i:02d}] {meta['file']}")
        frame_one(src_path, out_path, meta["headline"], meta["subhead"])
        print(f"       -> {out_name}")

    print(f"\nAll done. {OUT_DIR}")


if __name__ == "__main__":
    main()
