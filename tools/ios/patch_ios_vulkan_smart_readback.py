#!/usr/bin/env python3
"""Apply frequency-aware readback to the Vulkan backend on iOS.

Fight Night resolves textures both for recurring GPU-only render passes and for
CPU-built boxer/ring textures. Synchronously reading every resolve is too slow;
delaying every resolve can expose stale data. This mirrors the SDK's smart
readback policy for D3D12: only addresses with a stable per-frame resolve count
become one-frame delayed. New and irregular resolve sequences stay synchronous.
"""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from patch_engine import run  # noqa: E402

H = "include/rex/graphics/vulkan/command_processor.h"
CPP = "src/graphics/vulkan/command_processor.cpp"

TRACKER_ANCHOR = '''  std::unordered_map<uint64_t, ReadbackBuffer> readback_buffers_;
'''
TRACKER_NEW = '''  std::unordered_map<uint64_t, ReadbackBuffer> readback_buffers_;
#if REX_PLATFORM_IOS
  // LOCAL PATCH - iOS: make recurring Vulkan resolves asynchronous while keeping
  // one-shot and changing CPU-generated textures on the accurate sync path.
  struct IosReadbackResolveTracker {
    uint64_t frame = 0;
    uint32_t count = 0;
    uint32_t count_prev = 0;
    uint32_t steady_frames = 0;
  };
  std::unordered_map<uint64_t, IosReadbackResolveTracker> ios_readback_resolve_trackers_;
#endif
'''

KEY_ANCHOR = '''  bool is_scaled = texture_cache_->IsDrawResolutionScaled();
  uint64_t resolve_key = MakeReadbackResolveKey(written_address, written_length);
  ReadbackBuffer& readback = readback_buffers_[resolve_key];
'''
KEY_NEW = '''  bool is_scaled = texture_cache_->IsDrawResolutionScaled();
  uint64_t resolve_key = MakeReadbackResolveKey(written_address, written_length);
  bool ios_smart_delayed = false;
#if REX_PLATFORM_IOS
  if (readback_mode == ReadbackResolveMode::kSmart) {
    IosReadbackResolveTracker& tracker = ios_readback_resolve_trackers_[resolve_key];
    if (tracker.frame != frame_current_) {
      const bool adjacent_frame = tracker.frame + 1 == frame_current_;
      if (adjacent_frame && tracker.count && tracker.count == tracker.count_prev) {
        ++tracker.steady_frames;
      } else {
        tracker.steady_frames = 0;
      }
      tracker.count_prev = adjacent_frame ? tracker.count : 0;
      tracker.count = 0;
      tracker.frame = frame_current_;
    }
    const uint32_t occurrence = tracker.count++;
    const int32_t smart_frames = REXCVAR_GET(readback_resolve_smart_frames);
    ios_smart_delayed = smart_frames >= 0 && occurrence < 8 &&
                        occurrence < tracker.count_prev &&
                        tracker.steady_frames >= uint32_t(smart_frames);
    if (ios_smart_delayed && REXCVAR_GET(readback_resolve_smart_skip_steady)) {
      return true;
    }
    // Physical Xenos addresses use fewer than 29 bits, leaving bits 61..63 free
    // for independent readback pairs for repeated resolves to the same range.
    resolve_key ^= uint64_t(occurrence < 7 ? occurrence : 7) << 61;
  }
#endif
  ReadbackBuffer& readback = readback_buffers_[resolve_key];
'''

DELAY_ANCHOR = '''  bool use_delayed_sync =
      readback_mode == ReadbackResolveMode::kFast || readback_mode == ReadbackResolveMode::kSome;
'''
DELAY_NEW = '''  bool use_delayed_sync =
      readback_mode == ReadbackResolveMode::kFast || readback_mode == ReadbackResolveMode::kSome;
#if REX_PLATFORM_IOS
  use_delayed_sync |= readback_mode == ReadbackResolveMode::kSmart && ios_smart_delayed;
#endif
'''

EVICT_ANCHOR = '''    EvictOldReadbackBuffers(readback_buffers_);
    EvictOldReadbackBuffers(memexport_readback_buffers_);
'''
EVICT_NEW = '''    EvictOldReadbackBuffers(readback_buffers_);
    EvictOldReadbackBuffers(memexport_readback_buffers_);
#if REX_PLATFORM_IOS
    if (!ios_readback_resolve_trackers_.empty() &&
        frame_current_ > kReadbackBufferEvictionAgeFrames) {
      const uint64_t tracker_floor = frame_current_ - kReadbackBufferEvictionAgeFrames;
      for (auto it = ios_readback_resolve_trackers_.begin();
           it != ios_readback_resolve_trackers_.end();) {
        it = it->second.frame < tracker_floor ? ios_readback_resolve_trackers_.erase(it)
                                              : std::next(it);
      }
    }
#endif
'''

BLOCKS = [
    (H, "per-resolve cadence tracking", TRACKER_ANCHOR, TRACKER_NEW),
    (CPP, "classify stable recurring Vulkan resolves", KEY_ANCHOR, KEY_NEW),
    (CPP, "delay only stable Vulkan resolves", DELAY_ANCHOR, DELAY_NEW),
    (CPP, "evict old Vulkan resolve cadence records", EVICT_ANCHOR, EVICT_NEW),
]

if __name__ == "__main__":
    sys.exit(run("ios_vulkan_smart_readback", BLOCKS))
