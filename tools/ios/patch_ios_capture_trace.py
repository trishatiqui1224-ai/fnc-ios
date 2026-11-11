#!/usr/bin/env python3
import sys

from patch_engine import run

CP = "src/graphics/vulkan/command_processor.cpp"
CACHE = "src/graphics/pipeline/texture/cache.cpp"

CP_INCLUDE = "#include <rex/graphics/vulkan/command_processor.h>\n"
STATE = r'''#if REX_PLATFORM_IOS
#include <atomic>
#include <mutex>

namespace {
std::atomic<bool> fnc_capture_active{false};
std::mutex fnc_capture_mutex;
unsigned fnc_capture_draws = 0;
unsigned fnc_capture_resolves = 0;
unsigned fnc_capture_uploads = 0;
}

extern "C" __attribute__((visibility("default")))
void FncSetVulkanTraceEnabled(bool enabled) {
  std::lock_guard lock(fnc_capture_mutex);
  if (enabled) {
    fnc_capture_draws = fnc_capture_resolves = fnc_capture_uploads = 0;
  }
  fnc_capture_active.store(enabled, std::memory_order_release);
}

bool FncReserveVulkanTraceEvent(unsigned kind, unsigned& event) {
  if (!fnc_capture_active.load(std::memory_order_acquire)) {
    return false;
  }
  std::lock_guard lock(fnc_capture_mutex);
  if (!fnc_capture_active.load(std::memory_order_relaxed)) {
    return false;
  }
  unsigned& counter = kind == 0 ? fnc_capture_draws :
                      kind == 1 ? fnc_capture_resolves : fnc_capture_uploads;
  if (counter >= 512) {
    return false;
  }
  event = ++counter;
  return true;
}
#endif

'''

DRAW = '''  if (!UpdateBindings(vertex_shader, pixel_shader)) {
    return draw_fail("update_bindings");
  }
'''
DRAW_TRACE = r'''#if REX_PLATFORM_IOS
  unsigned trace_draw;
  if (FncReserveVulkanTraceEvent(0, trace_draw)) {
    REXGPU_INFO("[fnc-gpu-trace] draw={} frame={} submission={} pipeline={:X} prim={} count={}",
                trace_draw, frame_current_, GetCurrentSubmission(),
                reinterpret_cast<uintptr_t>(pipeline), uint32_t(prim_type), index_count);
    auto trace_bindings = [&](const char* stage, const VulkanShader* shader) {
      if (!shader) {
        return;
      }
      for (const auto& binding : shader->GetTextureBindingsAfterTranslation()) {
        const uint32_t reg = XE_GPU_REG_SHADER_CONSTANT_FETCH_00_0 +
                             uint32_t(binding.fetch_constant) * 6;
        const auto view = texture_cache_->GetActiveBindingOrNullImageView(
            binding.fetch_constant, binding.dimension, bool(binding.is_signed));
        REXGPU_INFO("[fnc-gpu-trace] draw={} stage={} slot={} dim={} signed={} view={:X} "
                    "fetch={:08X},{:08X},{:08X},{:08X},{:08X},{:08X}",
                    trace_draw, stage, uint32_t(binding.fetch_constant),
                    uint32_t(binding.dimension), bool(binding.is_signed),
                    reinterpret_cast<uintptr_t>(view),
                    register_file_->values[reg], register_file_->values[reg + 1],
                    register_file_->values[reg + 2], register_file_->values[reg + 3],
                    register_file_->values[reg + 4], register_file_->values[reg + 5]);
      }
    };
    trace_bindings("vs", vertex_shader);
    trace_bindings("ps", pixel_shader);
  }
#endif
'''
RESOLVE = '''  if (!written_length) {
    return true;
  }

  if (!memory_->TranslatePhysical(written_address)) {
'''
RESOLVE_TRACE = r'''#if REX_PLATFORM_IOS
  unsigned trace_resolve;
  if (written_length && FncReserveVulkanTraceEvent(1, trace_resolve)) {
    REXGPU_INFO("[fnc-gpu-trace] resolve={} frame={} submission={} addr={:08X} bytes={}",
                trace_resolve, frame_current_, GetCurrentSubmission(),
                written_address, written_length);
  }
#endif
'''
UPLOAD = '  texture.LogAction("Loaded");\n'
UPLOAD_TRACE = r'''#if REX_PLATFORM_IOS
  unsigned trace_upload;
  if (::FncReserveVulkanTraceEvent(2, trace_upload)) {
    REXGPU_INFO("[fnc-gpu-trace] upload={} addr={:08X} size={}x{} fmt={} base={} mips={}",
                trace_upload, uint32_t(texture_key.base_page) << 12, texture_key.GetWidth(),
                texture_key.GetHeight(), uint32_t(texture_key.format),
                pending_load.load_base, pending_load.load_mips);
  }
#endif
'''

# Declare the shared gate at file scope, outside the cache namespace.
CACHE_INCLUDE = "#include <rex/graphics/pipeline/texture/info.h>\n"
DECLARATION = ("#if REX_PLATFORM_IOS\n"
               "bool FncReserveVulkanTraceEvent(unsigned kind, unsigned& event);\n"
               "#endif\n\n")

if __name__ == "__main__":
    sys.exit(run("ios_capture_trace", [
        (CP, "capture gate", CP_INCLUDE, CP_INCLUDE + "\n" + STATE),
        (CP, "draw bindings", DRAW, DRAW + DRAW_TRACE),
        (CP, "resolve ranges", RESOLVE, RESOLVE_TRACE + RESOLVE),
        (CACHE, "upload gate declaration", CACHE_INCLUDE, CACHE_INCLUDE + "\n" + DECLARATION),
        (CACHE, "texture uploads", UPLOAD, UPLOAD + UPLOAD_TRACE),
    ]))
