#!/usr/bin/env python3
"""Repair stale aliasing code in the checked-in FNC codegen cache.

The ReXGlue SDK patch fixes vpkuwus code generation by loading both source
vectors before storing the packed destination. The build also restores
generated/default from gen.tar.gz, which can predate that SDK fix. Repair only
the old generated blocks where the destination aliases either source; already
fixed output and non-aliasing blocks are left alone.
"""

import pathlib
import re


INSTRUCTION = re.compile(r"^\s*//\s+vpkuwus128\s+(v\d+),(v\d+),(v\d+)\s*$")


def _old_block(dst: str, src_a: str, src_b: str) -> list[str]:
    lines = []
    for i in range(4):
        src_index = 3 - i
        lines.append(
            f"\tctx.{dst}.u16[{7 - i}] = ctx.{src_a}.u32[{src_index}] > 0xFFFF ? "
            f"0xFFFF : (uint16_t)ctx.{src_a}.u32[{src_index}];"
        )
        lines.append(
            f"\tctx.{dst}.u16[{3 - i}] = ctx.{src_b}.u32[{src_index}] > 0xFFFF ? "
            f"0xFFFF : (uint16_t)ctx.{src_b}.u32[{src_index}];"
        )
    return lines


def _fixed_store(dst: str, src_a: str, src_b: str) -> str:
    # Xenos lane order is reversed in the host vector representation, so vB
    # is the first pack argument and vA is the second. Load both before store.
    return (
        f"\tsimde_mm_store_si128((simde__m128i*)ctx.{dst}.u16, "
        f"simde_mm_packus_epi32("
        f"simde_mm_min_epu32(simde_mm_load_si128((simde__m128i*)ctx.{src_b}.u32), "
        f"simde_mm_set1_epi32(0xFFFF)), "
        f"simde_mm_min_epu32(simde_mm_load_si128((simde__m128i*)ctx.{src_a}.u32), "
        f"simde_mm_set1_epi32(0xFFFF))));"
    )


def patch_generated_dir(generated_dir: pathlib.Path) -> int:
    """Patch stale generated vpkuwus alias blocks; return the count changed."""
    if not generated_dir.is_dir():
        return 0

    patched = 0
    for path in sorted(generated_dir.glob("fnc_recomp.*.cpp")):
        text = path.read_text(encoding="utf-8")
        newline = "\r\n" if "\r\n" in text else "\n"
        lines = text.splitlines()
        changed = False
        i = 0
        while i < len(lines):
            match = INSTRUCTION.match(lines[i])
            if not match:
                i += 1
                continue
            dst, src_a, src_b = match.groups()
            if dst not in (src_a, src_b):
                i += 1
                continue

            old = _old_block(dst, src_a, src_b)
            current = lines[i + 1 : i + 9]
            if current == old:
                lines[i + 1 : i + 9] = [_fixed_store(dst, src_a, src_b)]
                patched += 1
                changed = True
                i += 2
                continue

            # The SDK's corrected translator already emitted this alias-safe
            # form when codegen ran after its patch.
            if (
                len(current) >= 1
                and "simde_mm_packus_epi32(" in current[0]
                and f"ctx.{dst}.u16" in current[0]
            ):
                i += 2
                continue

            raise RuntimeError(
                f"Unrecognized generated vpkuwus alias block at {path}:{i + 1}: "
                f"{lines[i].strip()}"
            )

        if changed:
            path.write_text(newline.join(lines) + newline, encoding="utf-8", newline="")

    return patched


if __name__ == "__main__":
    root = pathlib.Path(__file__).resolve().parents[1]
    count = patch_generated_dir(root / "generated" / "default")
    print(f"[Codegen] Fixed {count} stale vpkuwus destination/source alias blocks")
