#!/usr/bin/env python3
"""
tools/generate_appicon.py
Generates official Apple iOS/iPadOS AppIcon assets for
Fight Night Champion (Xbox 360 Title ID: 45410915).

Design:
  Authentic upstream FNC REBORN iconography:
  - Top plate: Crimson Red #B21820 (178, 24, 32) with bold white "FNC"
  - Middle: Gold #F1C13C (241, 193, 60) horizontal accent bar
  - Bottom plate: Dark Charcoal #141418 (20, 20, 24) with bold gold "REBORN"
  - Full-bleed 1024x1024 without pre-clipped corners (allowing iOS SpringBoard
    squircle masking to shape it natively without dark bezel artifacts).
  - Modern single-size Contents.json for Xcode asset catalog.
  - Bundled standalone legacy PNG icon sizes for iOS sideloaders (AltStore, LiveContainer, Sideloadly).
  - Strict 24-bit zero-alpha RGB formatting for Apple App Store / actool compliance.
"""

import json
import os
import pathlib
import sys
from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
RES_DIR = ROOT / "ios" / "resources"
APPICONSET_DIR = RES_DIR / "Assets.xcassets" / "AppIcon.appiconset"

SIZES = [
    ("AppIcon-1024.png", 1024, 1024),
    ("AppIcon1024x1024.png", 1024, 1024),
    ("AppIcon60x60@2x.png", 120, 120),
    ("AppIcon60x60@3x.png", 180, 180),
    ("AppIcon76x76@2x~ipad.png", 152, 152),
    ("AppIcon83.5x83.5@2x~ipad.png", 167, 167),
    ("AppIcon.png", 120, 120),
    ("title_icon_64x64.png", 64, 64),
]


def render_master_icon() -> Image.Image:
    """Renders or loads the master 1024x1024 FNC REBORN App Icon (RGB, no alpha)."""
    master_path = RES_DIR / "AppIcon-1024.png"
    if master_path.exists():
        try:
            existing = Image.open(master_path).convert("RGB")
            if existing.size == (1024, 1024):
                print(f"[appicon] Using pre-rendered master icon from {master_path}")
                return existing
        except Exception as e:
            print(f"[appicon] Notice: Could not read existing master icon: {e}")

    # Render fresh full-bleed master icon
    W, H = 1024, 1024
    img = Image.new("RGB", (W, H), (178, 24, 32))  # #B21820 Crimson Red
    draw = ImageDraw.Draw(img)

    split_y = 608
    gold_bar_h = 18

    # Bottom plate: #141418 Dark Charcoal
    draw.rectangle([(0, split_y), (W, H)], fill=(20, 20, 24))

    # Horizontal gold accent bar: #F1C13C Gold
    draw.rectangle([(0, split_y), (W, split_y + gold_bar_h)], fill=(241, 193, 60))

    # Font search
    font_candidates_fnc = [
        "C:/Windows/Fonts/ariblk.ttf",
        "/System/Library/Fonts/Supplemental/Arial Black.ttf",
        "/Library/Fonts/Arial Black.ttf",
        "/usr/share/fonts/truetype/msttcorefonts/ariblk.ttf",
        "C:/Windows/Fonts/impact.ttf",
        "/System/Library/Fonts/Supplemental/Impact.ttf",
    ]
    font_fnc = None
    font_reb = None
    for fc in font_candidates_fnc:
        if os.path.exists(fc):
            try:
                font_fnc = ImageFont.truetype(fc, 340)
                font_reb = ImageFont.truetype(fc, 140)
                print(f"[appicon] Loaded font: {fc}")
                break
            except Exception:
                continue

    if font_fnc is None:
        try:
            font_fnc = ImageFont.load_default(size=280)
            font_reb = ImageFont.load_default(size=120)
        except Exception:
            font_fnc = ImageFont.load_default()
            font_reb = ImageFont.load_default()

    # Draw FNC
    bbox_f = draw.textbbox((0, 0), "FNC", font=font_fnc)
    tw, th = bbox_f[2] - bbox_f[0], bbox_f[3] - bbox_f[1]
    tx = (W - tw) / 2
    ty = (split_y - th) / 2 - 20
    draw.text((tx, ty), "FNC", fill=(255, 255, 255), font=font_fnc)

    # Draw REBORN
    bbox_r = draw.textbbox((0, 0), "REBORN", font=font_reb)
    rw, rh = bbox_r[2] - bbox_r[0], bbox_r[3] - bbox_r[1]
    rx = (W - rw) / 2
    bot_h = H - (split_y + gold_bar_h)
    ry = (split_y + gold_bar_h) + (bot_h - rh) / 2 - 16
    draw.text((rx, ry), "REBORN", fill=(241, 193, 60), font=font_reb)

    return img


def main():
    RES_DIR.mkdir(parents=True, exist_ok=True)
    APPICONSET_DIR.mkdir(parents=True, exist_ok=True)

    # If test_master_icon.png exists in parent, use it as baseline
    parent_master = ROOT.parent / "test_master_icon.png"
    if parent_master.exists():
        try:
            master = Image.open(parent_master).convert("RGB")
            master.save(RES_DIR / "AppIcon-1024.png", "PNG", optimize=True)
            print(f"[appicon] Copied test_master_icon.png to {RES_DIR / 'AppIcon-1024.png'}")
        except Exception as e:
            print(f"[appicon] Warning: Could not copy test_master_icon.png: {e}")
            master = render_master_icon()
    else:
        master = render_master_icon()

    # Verify master icon
    assert master.size == (1024, 1024), f"Master icon must be 1024x1024, got {master.size}"
    master = master.convert("RGB")

    # 1. Write modern single-size Contents.json
    contents = {
        "images": [
            {
                "filename": "AppIcon-1024.png",
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024",
            }
        ],
        "info": {
            "author": "xcode",
            "version": 1,
        },
    }
    with open(APPICONSET_DIR / "Contents.json", "w", encoding="utf-8") as f:
        json.dump(contents, f, indent=2)
    print(f"[appicon] Wrote modern single-size {APPICONSET_DIR / 'Contents.json'}")

    # 2. Copy 1024 master to asset catalog
    master.save(APPICONSET_DIR / "AppIcon-1024.png", "PNG", optimize=True)
    master.save(RES_DIR / "AppIcon-1024.png", "PNG", optimize=True)
    master.save(RES_DIR / "AppIcon1024x1024.png", "PNG", optimize=True)

    # 3. Generate all downscaled sizes with Lanczos in ios/resources
    for name, w, h in SIZES:
        if (w, h) == (1024, 1024):
            resized = master
        else:
            resized = master.resize((w, h), Image.Resampling.LANCZOS)

        # Save to ios/resources for direct bundle bundling
        dest_res = RES_DIR / name
        resized.save(dest_res, "PNG", optimize=True)
        print(f"[appicon] Generated {name} ({w}x{h})")

    print("[appicon] All FNC REBORN AppIcon assets generated successfully!")


if __name__ == "__main__":
    main()
