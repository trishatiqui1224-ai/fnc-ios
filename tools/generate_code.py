#!/usr/bin/env python3
"""
tools/generate_code.py
Ahead-Of-Time (AOT) PowerPC-to-C++ Code Generator for Fight Night Champion (Europe / Region-Free 2DC50868, Title ID: 45410915).
"""

import argparse
import os
import pathlib
import platform
import shutil
import subprocess
import sys
import tarfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
XEX_CANDIDATES = [
    ROOT / "xex" / "default.xex",
    ROOT / "game" / "default.xex",
    ROOT.parent / "Fight Night Champion (Europe)" / "default.xex",
]
GENERATED_DIR = ROOT / "generated" / "default"
MANIFEST_FILE = ROOT / "fnc_manifest.toml"
if not MANIFEST_FILE.is_file():
    MANIFEST_FILE = ROOT / "config" / "fnc_manifest.toml"


def fail(msg):
    sys.exit(f"[ERROR] {msg}")


def check_and_extract_cache():
    """Checks for gen.tar.gz in current or parent directory and unpacks if available."""
    cache_candidates = [
        ROOT / "gen.tar.gz",
        ROOT.parent / "gen.tar.gz",
        ROOT.parent.parent / "gen.tar.gz",
    ]
    for c in cache_candidates:
        if c.is_file():
            print(f"[Codegen] Found pre-generated C++ code archive at: {c}")
            print(f"          Unpacking into {ROOT}...")
            GENERATED_DIR.mkdir(parents=True, exist_ok=True)
            with tarfile.open(c, "r:gz") as tar:
                if hasattr(tarfile, 'data_filter'):
                    tar.extractall(path=ROOT, filter='data')
                else:
                    tar.extractall(path=ROOT)
            sources_cmake = GENERATED_DIR / "sources.cmake"
            if sources_cmake.exists():
                print(f"[Codegen] Successfully restored generated sources from {c.name}!")
                return True
    return False


def build_rexglue_cli(sdk_dir):
    """Compiles the host rexglue CLI tool from the prepared ReXGlue SDK."""
    if not sdk_dir.exists():
        fail(f"SDK directory does not exist: {sdk_dir}")

    is_mac = platform.system() == "Darwin"
    preset = "mac-arm64" if (is_mac and platform.machine() == "arm64") else ("mac-amd64" if is_mac else "linux-x64")
    print(f"[Codegen] Building rexglue host CLI using preset: {preset}...")

    # Configure
    if subprocess.run(["cmake", "--preset", preset], cwd=sdk_dir).returncode != 0:
        fail("Failed to configure ReXGlue SDK host tools via CMake.")

    # Build
    if subprocess.run(["cmake", "--build", f"out/build/{preset}", "--config", "Release", "--target", "rexglue"],
                      cwd=sdk_dir).returncode != 0:
        fail("Failed to build rexglue host CLI binary.")

    # Locate executable
    candidates = list((sdk_dir / "out").rglob("rexglue")) + list((sdk_dir / "out").rglob("rexglue.exe"))
    candidates = [c for c in candidates if c.is_file() and os.access(c, os.X_OK)]
    if not candidates:
        fail(f"Could not locate built rexglue executable under {sdk_dir / 'out'}")
    return candidates[0]


def generate_code(xex_path=None, sdk_path=None, rexglue_bin=None, force_codegen=False):
    target_xex = None
    if xex_path:
        p = pathlib.Path(xex_path).resolve()
        if p.is_file():
            target_xex = p
    if not target_xex:
        for c in XEX_CANDIDATES:
            if c.is_file():
                target_xex = c.resolve()
                break

    # If not forcing codegen, prefer unpacking pre-generated cache
    if not force_codegen and not target_xex:
        if check_and_extract_cache():
            return

    if not target_xex or not target_xex.is_file():
        # Try unpack cache before failing
        if check_and_extract_cache():
            return
        fail(
            f"No Fight Night Champion default.xex found and no gen.tar.gz cache available.\n"
            f"Provide default.xex in 'xex/default.xex' or specify with --xex."
        )

    print("============================================================")
    print("  Fight Night Champion (45410915) AOT Codegen Pipeline      ")
    print(f"  Input:  {target_xex}")
    print(f"  Output: {GENERATED_DIR}")
    print("============================================================")

    sdk_dir = pathlib.Path(sdk_path).resolve() if sdk_path else (ROOT.parent / "rexglue-sdk-ios")
    if not rexglue_bin:
        rexglue_exe = build_rexglue_cli(sdk_dir)
    else:
        rexglue_exe = pathlib.Path(rexglue_bin).resolve()

    if not rexglue_exe.is_file():
        fail(f"Invalid rexglue executable: {rexglue_exe}")

    print(f"[Codegen] Using rexglue tool: {rexglue_exe}")
    print(f"[Codegen] Running static analysis and PowerPC AOT translation...")

    cmd = [
        str(rexglue_exe),
        "codegen",
        str(MANIFEST_FILE)
    ]
    res = subprocess.run(cmd, cwd=ROOT)
    if res.returncode != 0:
        fail(f"Codegen failed with exit code {res.returncode}")

    sources_cmake = GENERATED_DIR / "sources.cmake"
    if not sources_cmake.is_file():
        fail(f"Codegen did not produce expected sources file: {sources_cmake}")

    print(f"\n[Codegen Complete] Recompiled C++ sources generated at: {GENERATED_DIR}")


def main():
    parser = argparse.ArgumentParser(description="Ahead-of-Time Code Generator for Fight Night Champion iOS")
    parser.add_argument("--xex", default=None, help="Path to default.xex")
    parser.add_argument("--sdk", default=None, help="Path to ReXGlue iOS SDK")
    parser.add_argument("--rexglue", default=None, help="Path to pre-built rexglue CLI")
    parser.add_argument("--unpack-cache", action="store_true", help="Extract gen.tar.gz cache without invoking compiler")
    parser.add_argument("--force-codegen", action="store_true", help="Force recompilation even if cache is present")
    args = parser.parse_args()

    if args.unpack_cache:
        if check_and_extract_cache():
            sys.exit(0)
        else:
            fail("No gen.tar.gz cache found.")

    generate_code(args.xex, args.sdk, args.rexglue, force_codegen=args.force_codegen)


if __name__ == "__main__":
    main()
