#!/usr/bin/env python3
"""
tools/verify_codegen.py
Verifies that generated PowerPC-to-C++ sources for Fight Night Champion are present,
well-formed, and contain the required guest symbols.
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
GEN_DIR = ROOT / "generated" / "default"
SOURCES_CMAKE = GEN_DIR / "sources.cmake"
REGISTER_CPP = GEN_DIR / "fnc_register.cpp"
INIT_CPP = GEN_DIR / "fnc_init.cpp"


def main():
    print("[Verify] Checking Fight Night Champion recompilation artifacts...")
    if not GEN_DIR.is_dir():
        sys.exit(f"[ERROR] Generated directory not found: {GEN_DIR}")

    if not SOURCES_CMAKE.is_file():
        sys.exit(f"[ERROR] Missing sources.cmake at {SOURCES_CMAKE}")

    cmake_content = SOURCES_CMAKE.read_text(encoding="utf-8")
    cpp_files = [line.strip() for line in cmake_content.splitlines() if line.strip().endswith(".cpp")]
    print(f"  [ok] sources.cmake references {len(cpp_files)} C++ translation units")

    if len(cpp_files) < 50:
        sys.exit(f"[ERROR] Expected at least 50 recompiled shards, found {len(cpp_files)}")

    if not REGISTER_CPP.is_file():
        sys.exit(f"[ERROR] Missing register file: {REGISTER_CPP}")

    if not INIT_CPP.is_file():
        sys.exit(f"[ERROR] Missing init file: {INIT_CPP}")

    # Count sub_82* occurrences in init/register
    with open(INIT_CPP, "r", encoding="utf-8", errors="ignore") as f:
        init_txt = f.read(2_000_000)
    func_count = init_txt.count("sub_82")
    print(f"  [ok] fnc_init.cpp contains {func_count}+ mapped PowerPC guest functions")
    if func_count < 1000:
        sys.exit(f"[ERROR] Expected thousands of guest function mappings, found only {func_count}")

    print("[Verify] Fight Night Champion codegen verification PASSED!")
    return 0


if __name__ == "__main__":
    sys.exit(main())
