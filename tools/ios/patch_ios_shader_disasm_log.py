#!/usr/bin/env python3
"""
The microcode disassembly of every shader, or only the known XMV movie
shaders, in the log on request.

    python3 tools/ios/patch_ios_shader_disasm_log.py            apply
    python3 tools/ios/patch_ios_shader_disasm_log.py --status
    python3 tools/ios/patch_ios_shader_disasm_log.py --revert

Touches src/graphics/pipeline/shader/translator.cpp.


WHY
===

The movies' shaders (the XMV player's, vs acc15ef6157ec934 / ps
2d2462de73d283de in the native renderer's keys) are built into the
executable, not the game's shader files, so the native renderer has no
Metal version and hands movie frames to the emulated renderer. To write
them by hand (as the D3D internal vertex shaders were), their microcode is
needed: with --ios_log_movie_shader_disasm=true the two known XMV shaders'
disassembly goes to the log once ("[shader-disasm]"), with their microcode in
hex. --ios_log_shader_disasm=true retains the all-shaders diagnostic.
"""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from patch_engine import run  # noqa: E402

FILE = "src/graphics/pipeline/shader/translator.cpp"

ANCHOR = '''  ucode_disassembly_ = ucode_disasm_buffer.to_string();
'''
NEW = '''  ucode_disassembly_ = ucode_disasm_buffer.to_string();
  // LOCAL PATCH - iOS (tools/ios/patch_ios_shader_disasm_log.py).
  const bool ios_movie_shader =
      (shader_type_ == xenos::ShaderType::kVertex && ucode_data_hash_ == 0xACC15EF6157EC934ull) ||
      (shader_type_ == xenos::ShaderType::kPixel && ucode_data_hash_ == 0x2D2462DE73D283DEull);
  if (REXCVAR_GET(ios_log_shader_disasm) ||
      (REXCVAR_GET(ios_log_movie_shader_disasm) && ios_movie_shader)) {
    std::string hex;
    for (size_t i = 0; i < ucode_data_.size(); ++i) hex += fmt::format("{:08x} ", ucode_data_[i]);
    REXLOG_INFO("[shader-disasm] {} shader {:016x}, {} dwords: {}\\n{}",
                shader_type_ == xenos::ShaderType::kVertex ? "vertex" : "pixel", ucode_data_hash_,
                ucode_data_.size(), hex, ucode_disassembly_);
  }
'''

CVAR_ANCHOR = '''#include <rex/logging.h>
'''
CVAR_NEW = '''#include <rex/logging.h>
#include <rex/cvar.h>  // LOCAL PATCH - iOS (tools/ios/patch_ios_shader_disasm_log.py)

REXCVAR_DEFINE_BOOL(ios_log_shader_disasm, false, "GPU",
                    "iOS: log every shader's microcode and disassembly once");
REXCVAR_DEFINE_BOOL(ios_log_movie_shader_disasm, false, "GPU",
                    "iOS: log only the XMV movie vertex and pixel shaders once");
'''

BLOCKS = [
    (FILE, "the ios_log_shader_disasm cvar", CVAR_ANCHOR, CVAR_NEW),
    (FILE, "disassembly logged", ANCHOR, NEW),
]

if __name__ == "__main__":
    sys.exit(run("ios_shader_disasm_log", BLOCKS))
