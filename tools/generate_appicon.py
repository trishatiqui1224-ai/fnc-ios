#!/usr/bin/env python3
"""
tools/generate_appicon.py
Generates official Apple iOS/iPadOS AppIcon.appiconset assets for
Fight Night Champion (Xbox 360 Title ID: 45410915).

Design:
  Dramatic dark ringside spotlight background (#0B0B0E charcoal-black with subtle
  arena haze and championship gold #D4AF37 rim light), featuring an iconic laced leather
  championship boxing glove / gold belt crest with bold gritty "FNC" / championship styling.
  Guarantees strict 24-bit zero-alpha RGB formatting for Apple App Store / actool compliance.
"""

import json
import math
import pathlib
import sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parent.parent
APPICONSET_DIR = ROOT / "ios" / "resources" / "Assets.xcassets" / "AppIcon.appiconset"

ICON_SPECS = [
    # Universal / App Store
    {"idiom": "universal", "size": "1024x1024", "scale": "1x", "pixels": 1024, "filename": "AppIcon-1024.png", "platform": "ios"},
    # iPhone
    {"idiom": "iphone", "size": "20x20", "scale": "2x", "pixels": 40, "filename": "AppIcon-20@2x.png"},
    {"idiom": "iphone", "size": "20x20", "scale": "3x", "pixels": 60, "filename": "AppIcon-20@3x.png"},
    {"idiom": "iphone", "size": "29x29", "scale": "2x", "pixels": 58, "filename": "AppIcon-29@2x.png"},
    {"idiom": "iphone", "size": "29x29", "scale": "3x", "pixels": 87, "filename": "AppIcon-29@3x.png"},
    {"idiom": "iphone", "size": "40x40", "scale": "2x", "pixels": 80, "filename": "AppIcon-40@2x.png"},
    {"idiom": "iphone", "size": "40x40", "scale": "3x", "pixels": 120, "filename": "AppIcon-40@3x.png"},
    {"idiom": "iphone", "size": "60x60", "scale": "2x", "pixels": 120, "filename": "AppIcon-60@2x.png"},
    {"idiom": "iphone", "size": "60x60", "scale": "3x", "pixels": 180, "filename": "AppIcon-60@3x.png"},
    # iPad
    {"idiom": "ipad", "size": "20x20", "scale": "1x", "pixels": 20, "filename": "AppIcon-20@1x.png"},
    {"idiom": "ipad", "size": "20x20", "scale": "2x", "pixels": 40, "filename": "AppIcon-20@2x-ipad.png"},
    {"idiom": "ipad", "size": "29x29", "scale": "1x", "pixels": 29, "filename": "AppIcon-29@1x.png"},
    {"idiom": "ipad", "size": "29x29", "scale": "2x", "pixels": 58, "filename": "AppIcon-29@2x-ipad.png"},
    {"idiom": "ipad", "size": "40x40", "scale": "1x", "pixels": 40, "filename": "AppIcon-40@1x.png"},
    {"idiom": "ipad", "size": "40x40", "scale": "2x", "pixels": 80, "filename": "AppIcon-40@2x-ipad.png"},
    {"idiom": "ipad", "size": "76x76", "scale": "1x", "pixels": 76, "filename": "AppIcon-76@1x.png"},
    {"idiom": "ipad", "size": "76x76", "scale": "2x", "pixels": 152, "filename": "AppIcon-76@2x.png"},
    {"idiom": "ipad", "size": "83.5x83.5", "scale": "2x", "pixels": 167, "filename": "AppIcon-83.5@2x.png"},
]


def render_master_icon() -> Image.Image:
    """Renders the master 1024x1024 Fight Night Champion App Icon (RGB, no alpha)."""
    W, H = 1024, 1024
    img = Image.new("RGB", (W, H), (11, 11, 14)) # #0B0B0E charcoal-black
    draw = ImageDraw.Draw(img)

    # 1. Ringside arena spotlight radial gradient
    # Center slightly above midpoint (512, 450)
    cx, cy = 512, 440
    spotlight = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sdraw = ImageDraw.Draw(spotlight)
    max_r = 650
    for r in range(max_r, 0, -8):
        alpha = int(45 * (1.0 - (r / max_r) ** 1.5))
        # Warm golden arena haze
        sdraw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(212, 175, 55, alpha))

    # Inner high-intensity ringside spot
    for r in range(260, 0, -6):
        alpha = int(70 * (1.0 - (r / 260) ** 2))
        sdraw.ellipse([cx - r, cy - r - 40, cx + r, cy + r - 40], fill=(255, 230, 160, alpha))

    img.paste(Image.alpha_composite(Image.new("RGBA", (W, H), (11, 11, 14, 255)), spotlight).convert("RGB"))
    draw = ImageDraw.Draw(img)

    # 2. Championship Shield / Crest outline in gold (#D4AF37)
    crest_pts = [
        (512, 140),   # Top center peak
        (780, 210),   # Top right shoulder
        (820, 500),   # Mid right curve
        (720, 720),   # Lower right taper
        (512, 880),   # Bottom shield point
        (304, 720),   # Lower left taper
        (204, 500),   # Mid left curve
        (244, 210),   # Top left shoulder
    ]

    # Draw gold crest shadow / outer glow
    glow_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(glow_layer)
    for w_off in range(16, 0, -2):
        alpha = int(40 * (1.0 - w_off / 16.0))
        gdraw.polygon(crest_pts, outline=(212, 175, 55, alpha), width=w_off)
    gdraw.polygon(crest_pts, fill=(22, 22, 28, 220), outline=(212, 175, 55, 255), width=8)

    # Inner gold border
    inner_crest = [
        (512, 165),
        (760, 230),
        (795, 495),
        (700, 705),
        (512, 855),
        (324, 705),
        (229, 495),
        (264, 230),
    ]
    gdraw.polygon(inner_crest, outline=(245, 215, 110, 160), width=3)

    img.paste(Image.alpha_composite(img.convert("RGBA"), glow_layer).convert("RGB"))
    draw = ImageDraw.Draw(img)

    # 3. Championship Boxing Glove (Silhouette with leather highlights and lacing)
    # Right-facing stylized laced glove centered in shield
    glove_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gldraw = ImageDraw.Draw(glove_layer)

    # Main glove fist body
    fist_box = [370, 310, 670, 610]
    gldraw.ellipse(fist_box, fill=(180, 25, 25, 255), outline=(212, 175, 55, 255), width=5)

    # Thumb segment
    thumb_box = [320, 390, 440, 520]
    gldraw.ellipse(thumb_box, fill=(160, 20, 20, 255), outline=(212, 175, 55, 230), width=4)

    # Glove wrist cuff
    cuff_pts = [
        (430, 570),
        (610, 570),
        (630, 700),
        (410, 700),
    ]
    gldraw.polygon(cuff_pts, fill=(35, 35, 42, 255), outline=(212, 175, 55, 255), width=5)

    # White wrist tape / laces across cuff
    for y_lace in range(595, 685, 18):
        gldraw.line([(440, y_lace), (600, y_lace)], fill=(240, 240, 245, 240), width=4)
        # Cross lacing effect
        gldraw.line([(500, y_lace - 6), (540, y_lace + 12)], fill=(255, 255, 255, 220), width=3)
        gldraw.line([(540, y_lace - 6), (500, y_lace + 12)], fill=(255, 255, 255, 220), width=3)

    # Leather sheen / specular highlight curve
    sheen_box = [430, 340, 630, 460]
    gldraw.arc(sheen_box, start=190, end=330, fill=(255, 140, 140, 200), width=8)

    img.paste(Image.alpha_composite(img.convert("RGBA"), glove_layer).convert("RGB"))
    draw = ImageDraw.Draw(img)

    # 4. Bold Gritty Typography: "FNC" Banner
    # Banner plate
    banner_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    bdraw = ImageDraw.Draw(banner_layer)
    b_pts = [
        (190, 700),
        (834, 700),
        (804, 820),
        (220, 820),
    ]
    bdraw.polygon(b_pts, fill=(15, 15, 20, 245), outline=(212, 175, 55, 255), width=6)
    bdraw.polygon([(205, 712), (819, 712), (794, 808), (230, 808)], outline=(245, 215, 110, 180), width=2)

    # FNC Text using clean geometric sans fallback
    # Draw "F N C" in prominent bold gold with dark drop shadow
    font = None
    font_paths = [
        "C:/Windows/Fonts/impact.ttf",
        "C:/Windows/Fonts/arialbd.ttf",
        "C:/Windows/Fonts/seguihb.ttf",
        "/System/Library/Fonts/HelveticaNeue.ttc",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    ]
    for fp in font_paths:
        if pathlib.Path(fp).exists():
            try:
                font = ImageFont.truetype(fp, 95)
                break
            except Exception:
                pass
    if font is None:
        font = ImageFont.load_default()

    text = "FNC"
    # Measure text bbox
    bbox = bdraw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    tx = (W - tw) / 2
    ty = 760 - th / 2

    # Drop shadow
    bdraw.text((tx + 4, ty + 5), text, fill=(0, 0, 0, 230), font=font)
    # Gold gradient / fill
    bdraw.text((tx, ty), text, fill=(245, 215, 110, 255), font=font)

    # Small subtitle: "CHAMPION"
    sub_font = None
    for fp in font_paths:
        if pathlib.Path(fp).exists():
            try:
                sub_font = ImageFont.truetype(fp, 26)
                break
            except Exception:
                pass
    if sub_font:
        sub_text = "C H A M P I O N"
        sbox = bdraw.textbbox((0, 0), sub_text, font=sub_font)
        stw = sbox[2] - sbox[0]
        bdraw.text(((W - stw) / 2, 836), sub_text, fill=(212, 175, 55, 220), font=sub_font)

    img.paste(Image.alpha_composite(img.convert("RGBA"), banner_layer).convert("RGB"))

    # Final guarantee: ensure exact RGB 24-bit with no alpha channel
    return img.convert("RGB")


def main():
    APPICONSET_DIR.mkdir(parents=True, exist_ok=True)
    print(f"[AppIcon] Rendering 1024x1024 Fight Night Champion master icon...")
    master = render_master_icon()

    # Save 1024x1024 master
    master_path = APPICONSET_DIR / "AppIcon-1024.png"
    master.save(str(master_path), "PNG")
    print(f"  [ok] {master_path.name} ({master.size[0]}x{master.size[1]} RGB)")

    # Downsample all icon sizes
    images_meta = []
    for spec in ICON_SPECS:
        px = spec["pixels"]
        fn = spec["filename"]
        out_p = APPICONSET_DIR / fn
        if px == 1024:
            resized = master
        else:
            resized = master.resize((px, px), Image.Resampling.LANCZOS)
        resized.save(str(out_p), "PNG")
        print(f"  [ok] {fn:24s} ({px}x{px})")

        meta = {
            "idiom": spec["idiom"],
            "size": spec["size"],
            "scale": spec["scale"],
            "filename": fn,
        }
        if "platform" in spec:
            meta["platform"] = spec["platform"]
        images_meta.append(meta)

    # Also save standard AppIcon.png alias
    master.save(str(APPICONSET_DIR / "AppIcon.png"), "PNG")

    # Write Contents.json for Xcode actool
    contents = {
        "images": images_meta,
        "info": {
            "author": "xcode",
            "version": 1
        }
    }
    contents_path = APPICONSET_DIR / "Contents.json"
    with open(contents_path, "w", encoding="utf-8") as f:
        json.dump(contents, f, indent=2)
    print(f"[ok] Wrote {contents_path}")
    print("[AppIcon] All AppIcon assets successfully generated!")


if __name__ == "__main__":
    main()
