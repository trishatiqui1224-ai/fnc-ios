// Game-specific function overrides for Fight Night Champion (default.xex v0.0.0.3,
// media 2DC50868). Addresses are only valid for that executable.
//
// Recompiled functions are weak symbols; defining one here replaces it, and
// __imp__<name> is always the original.

#include <rex/cvar.h>
#include <rex/logging.h>
#include <rex/ppc.h>

#include <atomic>

REXCVAR_DEFINE_DOUBLE(fnc_frame_rate, 60.0, "Game",
                      "Frame rate cap. The retail game runs at 30. Set 30 to restore it.");

// ---------------------------------------------------------------------------
// 60 FPS.
// sub_827C6380 builds one of the game's fixed-rate frame timers; f1 = rate in Hz,
// which sub_827C5E60 turns into a tick period (timebase / rate). The game makes
// exactly two, each once:
//   sub_822A9570 -> 30 Hz (constant 0x82008430), returns to 0x822A9594  <- changed
//   sub_822AA558 -> 60 Hz (constant 0x82008454), returns to 0x822AA580  <- untouched
// The community "Unlock FPS" patch for TU2 (illusion, xenia-canary/game-patches)
// raises the same 30.0 constant (it sits at 0x82008574 in TU2).
// ---------------------------------------------------------------------------
extern "C" void __imp__sub_827C6380(PPCContext& __restrict ctx, uint8_t* base);
extern "C" void sub_827C6380(PPCContext& __restrict ctx, uint8_t* base) {
  if (ctx.lr == 0x822A9594 && ctx.f1.f64 == 30.0) {
    double rate = REXCVAR_GET(fnc_frame_rate);
    if (rate >= 10.0 && rate <= 240.0 && rate != 30.0) {
      REXLOG_INFO("[FNC-60FPS] frame timer 30 Hz -> {:.0f} Hz (fnc_frame_rate)", rate);
      ctx.f1.f64 = rate;
    } else {
      REXLOG_INFO("[FNC-60FPS] frame timer left at 30 Hz (fnc_frame_rate = {})", rate);
    }
  }
  __imp__sub_827C6380(ctx, base);
}

// ---------------------------------------------------------------------------
// Failed asynchronous operation cleanup.
// sub_82E3E5A0 checks the nested operation at request + 0x14, then immediately
// dereferences its vtable. The Nov 10 iOS trace reached it with request
// 0xBD4A0C00 and a null nested operation while handling status 0xDEA12002,
// causing an unhandled guest read from address zero on a game-created worker.
// The function's non-pending path sets request + 0x18 to 1; use that same
// completion state when the operation object was never created, then let the
// caller continue its normal failure/completion handling.
// ---------------------------------------------------------------------------
extern "C" void __imp__sub_82E3E5A0(PPCContext& __restrict ctx, uint8_t* base);
extern "C" void sub_82E3E5A0(PPCContext& __restrict ctx, uint8_t* base) {
  const uint32_t request = ctx.r3.u32;
  if (request != 0) {
    const uint32_t operation = REX_LOAD_U32(request + 20);
    if (operation == 0) {
      static std::atomic<bool> logged{false};
      if (!logged.exchange(true, std::memory_order_relaxed)) {
        REXLOG_WARNING(
            "[FNC-async] request 0x{:08X} has no operation object (caller LR 0x{:08X}, r11 0x{:08X}); "
            "marking it complete",
            request, static_cast<uint32_t>(ctx.lr), ctx.r11.u32);
      }
      REX_STORE_U8(request + 24, 1);
      ctx.r3.u64 = 0;
      return;
    }
  } else {
    REXLOG_WARNING("[FNC-async] null request passed to sub_82E3E5A0; skipping cleanup");
    ctx.r3.u64 = 0;
    return;
  }

  __imp__sub_82E3E5A0(ctx, base);
}
