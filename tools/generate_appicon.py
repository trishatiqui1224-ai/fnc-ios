#!/usr/bin/env python3
"""
tools/generate_appicon.py
Generates official Apple iOS/iPadOS AppIcon assets for
Fight Night Champion (Xbox 360 Title ID: 45410915).

Design:
  Authentic Xbox 360 Fight Night Champion title iconography (title_icon_64x64.png):
  - EA SPORTS round emblem atop the iconic FIGHT ★ NIGHT logo in metallic white
  - Bold red CHAMPION lettering
  - Atmospheric ringside arena spotlight and dust particles full bleed
  - Strict 24-bit zero-alpha RGB formatting for Apple App Store / actool compliance
  - Modern single-size Contents.json for Xcode asset catalog
  - Bundled standalone legacy PNG icon sizes for iOS sideloaders
"""

import json
import os
import pathlib
import shutil
import sys
from PIL import Image, ImageFilter, ImageEnhance

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
]


def render_master_from_title_icon(src_icon_path: pathlib.Path) -> Image.Image:
    """Progressive upscaling of authentic 64x64 title icon to 1024x1024 with edge sharpening."""
    base = Image.open(src_icon_path).convert("RGB")
    master = base
    for sz in [128, 256, 512, 1024]:
        master = master.resize((sz, sz), Image.Resampling.LANCZOS)
        master = master.filter(ImageFilter.UnsharpMask(radius=1.2, percent=110, threshold=2))
    enh = ImageEnhance.Contrast(master)
    master = enh.enhance(1.1)
    return master


def main():
    RES_DIR.mkdir(parents=True, exist_ok=True)
    APPICONSET_DIR.mkdir(parents=True, exist_ok=True)

    # 1. Preserve or copy authentic title_icon_64x64.png
    src_title_candidates = [
        ROOT / "tools" / "title_icon_64x64.png",
        ROOT.parent / "title_icon_64x64.png",
        RES_DIR / "title_icon_64x64.png",
    ]
    src_title = None
    for cand in src_title_candidates:
        if cand.exists() and cand.stat().st_size >= 10000:
            src_title = cand
            break

    if src_title and src_title != RES_DIR / "title_icon_64x64.png":
        shutil.copyfile(src_title, RES_DIR / "title_icon_64x64.png")
        print(f"[appicon] Preserved authentic title_icon_64x64.png from {src_title}")

    # 2. Acquire 1024x1024 master icon
    master_path = RES_DIR / "AppIcon-1024.png"
    master = None
    if master_path.exists():
        try:
            im = Image.open(master_path).convert("RGB")
            if im.size == (1024, 1024):
                master = im
                print(f"[appicon] Loaded existing 1024x1024 master icon from {master_path}")
        except Exception as e:
            print(f"[appicon] Notice: Could not read existing master icon: {e}")

    if master is None:
        title_for_master = RES_DIR / "title_icon_64x64.png"
        if title_for_master.exists():
            master = render_master_from_title_icon(title_for_master)
            print(f"[appicon] Rendered 1024x1024 master icon from {title_for_master}")
        else:
            raise RuntimeError("Cannot find title_icon_64x64.png to generate AppIcon!")

    master = master.convert("RGB")

    # 3. Write modern single-size Contents.json
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

    # 4. Save master to asset catalog & resources
    master.save(APPICONSET_DIR / "AppIcon-1024.png", "PNG", optimize=True)
    master.save(RES_DIR / "AppIcon-1024.png", "PNG", optimize=True)
    master.save(RES_DIR / "AppIcon1024x1024.png", "PNG", optimize=True)

    # 5. Generate all downscaled variants
    for name, w, h in SIZES:
        if (w, h) == (1024, 1024):
            continue
        resized = master.resize((w, h), Image.Resampling.LANCZOS)
        dest_res = RES_DIR / name
        resized.save(dest_res, "PNG", optimize=True)
        print(f"[appicon] Generated {name} ({w}x{h})")

    print("[appicon] All Fight Night Champion AppIcon assets generated successfully!")


if __name__ == "__main__":
    main()
