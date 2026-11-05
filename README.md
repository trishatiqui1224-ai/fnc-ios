# FNC Reborn iOS

Native ARM64 iOS static recompilation port of **Fight Night Champion (Europe / Region-Free)** (`Title ID: 45410915`, `Media ID: 2DC50868`) for iPhone and iPad using **ReXGlue**.

The Xbox 360's PowerPC code is statically recompiled to ARM64 C++ ahead of time, running natively on bare metal with Apple Metal / MoltenVK rather than through dynamic emulation.

> **Zero Copyrighted Assets in Repository**: This repository contains recompiled C++ translation units, translation runtime host code, shaders, and metadata. You must supply your own legally dumped Fight Night Champion `.iso` or extracted game folder (`default.xex` + `databigs/`).

---

## Features

- **True Native Execution**: 60 FPS default frame rate cap with full ProMotion 120 FPS support on compatible iPhone/iPad displays.
- **Native iOS Dark-Mode Launcher**:
  - `UITableViewStyleInsetGrouped` UI cards (#000000 background, #1C1C1E cards).
  - 6-Tab segmented navigation bar: `Game | Extras | Graphics | Controls | Audio | Advanced`.
  - Top navigation bar: Reset top-left, title center, Play top-right.
- **Dual Disc & Folder Support**:
  - Direct 64-bit chunked `pread` ISO streaming from `Documents/` (zero memory mapping of entire 7.5 GB ISO).
  - Extracted game folder loading (`Documents/FightNightChampion/` or custom folder) with case-insensitive APFS path normalization.
- **In-Fight Player Camera Modes (whompay/FNCReborn)**:
  - `TV Broadcast (Default)`
  - `Behind Boxer (Third-Person)` with customizable distance, height, side offset, FOV, and smoothing.
  - `First-Person POV` anchored to your boxer's head looking at the opponent.
  - Live in-fight camera toggle via `Select/Back` on controller or touch button.
- **Boxing Touch Controls & Straight/Jab Calibration**:
  - **Full Spectrum Punch Control (Flick Pad)**: 360° right-side flick pad with cardinal Straight/Jab deadzone calibration corridor preventing forward punches from misfiring as hooks.
  - **Classic Xbox 360 Pad**: Dual virtual thumbsticks + A/B/X/Y face-button punches (X=Jab, Y=Straight, A=Left Hook, B=Right Hook).
  - Ergonomic ringside action buttons: Block (RT), Lean/Weave (LT), Body Modifier (LB), Power Modifier (RB), Clinch (LS), Push (RS), and Camera (Back).
  - Auto-hides on hardware Xbox/PlayStation/Backbone/MFi controller connection.
  - CoreHaptics punch rumble feedback on landed hits and knockdowns.
- **Ahead-of-Time Shaders & Prewarmed Pipeline Cache**:
  - Bundled seed Vulkan pipeline cache (`45410915.fbo.vkcache`) installed to `Caches/` on first launch.
  - Native Metal shader library (`FNCShaders.metallib`) compiled for Apple Metal.
  - Background asynchronous shader compilation (`--ios_async_submits=true`).
- **45410915 Engine & Graphics Fixes**:
  - Automatic `content/45410915/00000002/` directory provisioning to eliminate EA Sports logo freeze.
  - Mounted writable `cache:\` / `scratch:\` partition to ensure Instant KO Replays never hang.
  - `--clear_memory_page_state=true` enabled by default to prevent warped trunks and detached vertices.
  - Memory-safe texture limits (`1024 MB soft / 2048 MB hard`) to stay within iOS jetsam thresholds.

---

## Repository Structure

```
fnc-ios/
├── .github/workflows/       # GitHub Actions automated iOS IPA builder
│   └── build-ipa.yml
├── config/                  # Manifest and ReXGlue configs
│   ├── fnc_manifest.toml
│   └── FNCReborn.toml
├── generated/               # Statically recompiled ARM64 C++ translation units
│   └── default/
│       ├── sources.cmake
│       ├── rexglue.cmake
│       ├── fnc_init.cpp
│       ├── fnc_register.cpp
│       └── fnc_recomp.*.cpp
├── gen.tar.gz               # Compressed archive of generated C++ sources
├── ios/
│   ├── CMakeLists.txt       # Native iOS application and IPA packaging targets
│   ├── CMakePresets.json    # CMake presets for Xcode 16 / iOS SDK
│   ├── Info.plist.in        # Application metadata & entitlements
│   ├── fncreborn.entitlements
│   ├── resources/
│   │   ├── Assets.xcassets/ # 1024x1024 AppIcon suite
│   │   ├── shaders/         # Prewarmed .vkcache and Metal shader source
│   │   └── title_icon_64x64.png
│   └── src/                 # Native iOS host, UIKit launcher, touch controls, audio
├── patches/
│   └── rexglue-sdk.patch    # Fight Night Champion kernel, GPU, and audio fixes
├── src/                     # Game overrides (30/60/120 FPS timer, player camera, display tab)
└── tools/                   # Setup, codegen verification, app icon generator, SDK patches
```

---

## Building

### Automated GitHub Actions CI (Recommended)
1. Push to `main` or trigger `workflow_dispatch` on the GitHub Actions tab.
2. The `Build iOS IPA` workflow compiles all ~212 recompiled translation units, builds `FNCShaders.metallib`, links the Mach-O binary, and produces `FNCReborn-iOS-unsigned.ipa`.
3. Download the signed or unsigned IPA from Workflow Artifacts or Releases.

### Sideloading
Install the unsigned IPA using:
- **TrollStore** (JIT / unsandboxed root helper, iOS 14.0–17.0)
- **AltStore / SideStore**
- **LiveContainer**
- **Sideloadly**
