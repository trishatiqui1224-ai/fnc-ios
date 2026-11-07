// Fight Night Champion iOS - Main Entrypoint & App Lifecycle (ios_main.mm)
// ReXGlue Static Recompilation Host for Xbox 360 Title ID: 45410915 / Media ID: 2DC50868

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#include <csignal>
#include <dlfcn.h>
#include <execinfo.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <memory>
#include <sstream>
#include <string>
#include <vector>

#include <SDL3/SDL.h>
#include <SDL3/SDL_main.h>
#include <spdlog/spdlog.h>

#include <rex/cvar.h>
#include <rex/logging.h>
#include <rex/rex_app.h>
#include <rex/ui/windowed_app.h>
#include <rex/ui/windowed_app_context_sdl.h>

#include "audio/coreaudio_driver.h"
#include "battery.h"
#include "boot_trace.h"
#include "fnc_init.h"
#include "fnc_app.h"
#include "ios_haptics.h"
#include "launcher.h"
#include "lifecycle.h"
#include "memory_report.h"
#include "touch_controls.h"

namespace fs = std::filesystem;

extern const rex::PPCImageInfo PPCImageConfig;

static void CrashSignalHandler(int sig) {
  const char* sig_name = "UNKNOWN";
  switch (sig) {
    case SIGSEGV: sig_name = "SIGSEGV"; break;
    case SIGBUS: sig_name = "SIGBUS"; break;
    case SIGABRT: sig_name = "SIGABRT"; break;
    case SIGILL: sig_name = "SIGILL"; break;
    case SIGFPE: sig_name = "SIGFPE"; break;
  }
  std::fprintf(stderr, "\n[FATAL CRASH] Caught signal %d (%s)!\n", sig, sig_name);
  fnc::boot::Trace(std::string("[FATAL CRASH] Caught signal ") + std::to_string(sig) + " (" + sig_name + ")");

  void* callstack[32];
  int frames = backtrace(callstack, 32);
  std::fprintf(stderr, "Host Callstack (%d frames):\n", frames);
  for (int i = 0; i < frames; ++i) {
    Dl_info info{};
    const char* sym = "?";
    const char* fname = "?";
    uintptr_t saddr = 0;
    uintptr_t fbase = 0;
    if (dladdr(callstack[i], &info)) {
      if (info.dli_sname) sym = info.dli_sname;
      if (info.dli_fname) fname = info.dli_fname;
      saddr = reinterpret_cast<uintptr_t>(info.dli_saddr);
      fbase = reinterpret_cast<uintptr_t>(info.dli_fbase);
    }
    uintptr_t addr = reinterpret_cast<uintptr_t>(callstack[i]);
    char frame_buf[512];
    snprintf(frame_buf, sizeof(frame_buf),
             "  [%02d] %p (%s + 0x%llX [%s + 0x%llX])",
             i, callstack[i], fname,
             static_cast<unsigned long long>(fbase ? (addr - fbase) : 0),
             sym, static_cast<unsigned long long>(saddr ? (addr - saddr) : 0));
    std::fprintf(stderr, "%s\n", frame_buf);
    fnc::boot::Trace(frame_buf);
  }

  rex::FlushLogging();
  if (auto logger = spdlog::default_logger()) {
    logger->flush();
  }
  std::fflush(nullptr);
  std::signal(sig, SIG_DFL);
  std::raise(sig);
}

namespace {

fs::path DocumentsFolder() {
  NSArray<NSString*>* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
  return fs::path(paths.firstObject.UTF8String);
}

fs::path CachesFolder() {
  NSArray<NSString*>* paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
  return fs::path(paths.firstObject.UTF8String);
}

fs::path ApplicationSupportFolder() {
  NSArray<NSString*>* paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
  return fs::path(paths.firstObject.UTF8String);
}

fs::path TemporaryFolder() {
  NSString* tmp = NSTemporaryDirectory();
  return fs::path(tmp.UTF8String);
}

void PrewarmShaderCache(const fs::path& caches) {
  fs::path cacheDir = caches / "rexglue";
  std::error_code ec;
  fs::create_directories(cacheDir, ec);

  fs::path destVkCache = cacheDir / "45410915.fbo.vkcache";
  if (!fs::exists(destVkCache, ec)) {
    NSString* seed = [[NSBundle mainBundle] pathForResource:@"45410915.fbo" ofType:@"vkcache"];
    if (seed && [[NSFileManager defaultManager] fileExistsAtPath:seed]) {
      fs::copy_file(fs::path(seed.UTF8String), destVkCache, fs::copy_options::overwrite_existing, ec);
      fnc::boot::Trace("Prewarmed Vulkan pipeline cache installed to Caches/rexglue/45410915.fbo.vkcache");
    }
  }
}

void SetupFightNightRuntimeDirectories(const fs::path& docs, const fs::path& caches, const fs::path& app_support, const fs::path& tmp) {
  std::error_code ec;
  // 1. Sandbox roots
  fs::create_directories(docs, ec);
  fs::create_directories(docs / "logs", ec);
  fs::create_directories(docs / "data", ec);
  fs::create_directories(docs / "config", ec);
  fs::create_directories(docs / "rex_data", ec);
  fs::create_directories(caches, ec);
  fs::create_directories(caches / "rexglue", ec);
  fs::create_directories(caches / "rexglue" / "shaders", ec);
  fs::create_directories(caches / "rex_scratch", ec);
  fs::create_directories(app_support, ec);
  fs::create_directories(tmp, ec);

  // 2. Prevent EA Sports Logo multi-core freeze: content/45410915/00000002/
  fs::create_directories(docs / "rex_data" / "content" / "45410915" / "00000002", ec);
  fs::create_directories(docs / "data" / "content" / "45410915" / "00000002", ec);

  // 3. Instant KO Replays mount scratch:/ cache:/
  fs::create_directories(docs / "data" / "cache", ec);

  // 3b. Seed FNCReborn.toml into Documents/config and Documents/rex_data
  fs::path destToml = docs / "config" / "FNCReborn.toml";
  if (!fs::exists(destToml, ec)) {
    NSString* bundledToml = [[NSBundle mainBundle] pathForResource:@"FNCReborn" ofType:@"toml"];
    if (bundledToml && [[NSFileManager defaultManager] fileExistsAtPath:bundledToml]) {
      fs::copy_file(fs::path(bundledToml.UTF8String), destToml, fs::copy_options::overwrite_existing, ec);
      fs::copy_file(fs::path(bundledToml.UTF8String), docs / "rex_data" / "config.toml", fs::copy_options::overwrite_existing, ec);
    }
  }

  // 4. Redirect XDG & Temp env vars so POSIX/XDG libraries never touch ~/.local, ~/.cache, ~/.config
  setenv("XDG_DATA_HOME", (docs / "rex_data").c_str(), 1);
  setenv("XDG_CACHE_HOME", (caches).c_str(), 1);
  setenv("XDG_CONFIG_HOME", (docs / "config").c_str(), 1);
  setenv("TMPDIR", tmp.c_str(), 1);
  if (!docs.empty()) {
    setenv("HOME", docs.parent_path().c_str(), 1);
  }

  // 5. MoltenVK queue submission & command buffer defaults for iOS
  setenv("MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS", "0", 1);
  setenv("MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS", "1", 1);
  setenv("MVK_CONFIG_RESUME_LOST_DEVICE", "0", 1);

  // 6. SDL iOS orientation & touch hint setup
  setenv("SDL_IOS_ORIENTATIONS", "LandscapeLeft LandscapeRight", 1);
  SDL_SetHint(SDL_HINT_ORIENTATIONS, "LandscapeLeft LandscapeRight");
  SDL_SetHint(SDL_HINT_TOUCH_MOUSE_EVENTS, "0");
  SDL_SetHint(SDL_HINT_MOUSE_TOUCH_EVENTS, "0");

  fnc::boot::Trace("Runtime directories & environment prepared: 45410915 content, scratch cache, and XDG ready.");
}

std::string OptionName(const std::string& arg) {
  return arg.substr(0, arg.find('='));
}

void SetArgument(std::vector<std::string>& args, const std::string& arg) {
  if (args.empty()) {
    args.push_back(arg);
    return;
  }
  const std::string name = OptionName(arg);
  if (name.rfind("--", 0) == 0) {
    for (size_t i = 1; i < args.size(); ++i) {
      if (OptionName(args[i]) == name) {
        args[i] = arg;
        return;
      }
    }
  }
  args.push_back(arg);
}

std::vector<std::string> BuildGameArguments(const fs::path& docs, const fs::path& caches, const fs::path& gameSource) {
  std::vector<std::string> args = {
      "FNCReborn",
      "--game_data_root=" + gameSource.string(),
      "--user_data_root=" + (docs / "rex_data").string(),
      "--cache_root=" + (caches / "rexglue").string(),
      "--log_file=" + (docs / "logs" / "fnc.log").string(),
      "--log_level=info",
      "--log_flush_interval=1",
      "--ios_iso_stream=true",
      "--gpu_plugin=xenos",
      "--gpu_backend=vulkan",
      "--render_target_path_vulkan=fbo",
      "--clear_memory_page_state=true",
      "--vulkan_readback_resolve=true",
      "--readback_resolve=fast",
      "--ios_readback_max_kb=0",
      "--gpu_sin_msaa=true",
      "--ios_async_submits=true",
      "--ios_xma_starve_reset=false",
      "--ios_utility_qos_guest=false",
      "--ios_utility_qos=false",
      "--mnk_mode=false",
      "--fullscreen=true",
      "--resolution_scale=1",
      "--async_shader_compilation=false",
      "--texture_cache_memory_limit_soft=384",
      "--texture_cache_memory_limit_hard=768",
      "--texture_cache_memory_limit_render_to_texture=128",
      "--audio_maxqframes=64",
      "--present_letterbox=true",
      "--mount_scratch=true",
      "--mount_cache=true",
      "--gpu_allow_invalid_fetch_constants=false",
  };

  // Merge settings from Launcher
  auto launcherArgs = fnc::launcher::SettingsArguments(docs);
  for (const auto& a : launcherArgs) {
    SetArgument(args, a);
  }

  // Ensure mandatory path and platform flags are never overridden
  SetArgument(args, "--game_data_root=" + gameSource.string());
  SetArgument(args, "--user_data_root=" + (docs / "rex_data").string());
  SetArgument(args, "--cache_root=" + (caches / "rexglue").string());
  SetArgument(args, "--log_file=" + (docs / "logs" / "fnc.log").string());
  SetArgument(args, "--log_level=info");
  SetArgument(args, "--ios_iso_stream=true");
  SetArgument(args, "--gpu_plugin=xenos");
  SetArgument(args, "--gpu_backend=vulkan");
  SetArgument(args, "--render_target_path_vulkan=fbo");
  SetArgument(args, "--clear_memory_page_state=true");
  SetArgument(args, "--gpu_allow_invalid_fetch_constants=false");
  SetArgument(args, "--vulkan_readback_resolve=true");
  SetArgument(args, "--readback_resolve=fast");
  SetArgument(args, "--ios_readback_max_kb=0");
  SetArgument(args, "--async_shader_compilation=false");
  SetArgument(args, "--texture_cache_memory_limit_soft=384");
  SetArgument(args, "--texture_cache_memory_limit_hard=768");
  SetArgument(args, "--texture_cache_memory_limit_render_to_texture=128");
  SetArgument(args, "--gpu_sin_msaa=true");

  return args;
}

} // namespace

int main(int argc, char* argv[]) {
  @autoreleasepool {
    // 0. Register fatal signal handlers immediately
    std::signal(SIGSEGV, CrashSignalHandler);
    std::signal(SIGBUS, CrashSignalHandler);
    std::signal(SIGABRT, CrashSignalHandler);
    std::signal(SIGILL, CrashSignalHandler);
    std::signal(SIGFPE, CrashSignalHandler);

    const fs::path docs = DocumentsFolder();
    const fs::path caches = CachesFolder();
    const fs::path app_support = ApplicationSupportFolder();
    const fs::path tmp = TemporaryFolder();

    // Open early crash & boot trace before doing any startup work
    std::error_code logDirError;
    fs::create_directories(docs / "logs", logDirError);
    chmod((docs / "logs").c_str(), 0777);
    fnc::boot::Open((docs / "logs" / "boot.txt").string());
    fnc::boot::SetLogFilePath((docs / "logs" / "fnc.log").string());

    // Ensure fnc.log exists with write permissions and has an initial header so it is never 0 KB
    FILE* earlyFnc = std::fopen((docs / "logs" / "fnc.log").c_str(), "w");
    if (earlyFnc) {
      std::fprintf(earlyFnc, "[init] FNC Reborn iOS session started (log_level=info)\n");
      std::fflush(earlyFnc);
      std::fclose(earlyFnc);
    }

    auto now = std::chrono::system_clock::to_time_t(std::chrono::system_clock::now());
    char timebuf[64];
    std::strftime(timebuf, sizeof(timebuf), "%Y-%m-%d %H:%M:%S", std::localtime(&now));
    fnc::boot::Trace(std::string("---- start, build ") + timebuf + " (Fight Night Champion iOS ARM64)");

    // Initialize runtime sandbox, environment, haptics & prewarmed shaders
    SetupFightNightRuntimeDirectories(docs, caches, app_support, tmp);
    IOSHaptics_Init(true);
    PrewarmShaderCache(caches);

    // Run native dark-mode UITableViewStyleInsetGrouped 6-tab launcher
    // Loops until a valid game source (.iso or extracted folder) is confirmed
    fnc::boot::Trace("launcher: displaying 6-tab configuration menu");
    fs::path gameSource;
    while (gameSource.empty()) {
      gameSource = fnc::launcher::Run(docs);
      if (gameSource.empty()) {
        auto sources = fnc::launcher::FindGameSources(docs);
        if (!sources.empty()) {
          gameSource = sources.front();
        }
      }
    }
    fnc::boot::Trace(std::string("launcher: selected game source: ") + gameSource.string());

    // Build arguments & prepare audio session once
    rex::audio::ios::PrepareAudioSession();

    fnc::boot::Trace(std::string("game: parsing arguments for: ") + gameSource.string());
    auto gameArgs = BuildGameArguments(docs, caches, gameSource);

    for (const auto& a : gameArgs) {
      fnc::boot::Trace(std::string("arg: ") + a);
    }

    std::vector<char*> c_argv;
    c_argv.reserve(gameArgs.size() + 1);
    for (auto& s : gameArgs) {
      c_argv.push_back(s.data());
    }
    c_argv.push_back(nullptr);
    int c_argc = static_cast<int>(gameArgs.size());

    auto leftovers = rex::cvar::Init(c_argc, c_argv.data());
    rex::cvar::ApplyEnvironment();
    rex::InitLoggingEarly();
    rex::InitLogging((docs / "logs" / "fnc.log").c_str());
    if (auto logger = spdlog::default_logger()) {
      logger->set_level(spdlog::level::info);
      logger->flush_on(spdlog::level::trace);
    }
    spdlog::flush_every(std::chrono::milliseconds(250));
    rex::FlushLogging();

    // Initialize SDL Context
    fnc::boot::Trace("game: initializing the SDL context");
    rex::ui::SDLWindowedAppContext context;
    if (!context.Initialize()) {
      fnc::boot::Trace("FATAL: SDL context failed to initialize");
      return 1;
    }

    // Install touch controls & FPS counter
    fnc::touch::Install();
    fnc::touch::InstallFpsCounter();

    // Create App
    fnc::boot::Trace("game: creating the app");
    std::unique_ptr<rex::ui::WindowedApp> app = FncApp::Create(context);
    if (!app) {
      fnc::boot::Trace("FATAL: FncApp::Create returned null");
      return 1;
    }

    const auto& names = app->GetPositionalOptions();
    std::map<std::string, std::string> options;
    const size_t n = std::min(leftovers.size(), names.size());
    for (size_t i = 0; i < n; ++i) {
      options[names[i]] = leftovers[i];
    }
    app->SetParsedArguments(std::move(options));

    fnc::boot::Trace("game: OnInitialize (paths, log, GPU plugin, runtime, XEX)");
    const bool initialized = app->OnInitialize();
    fnc::boot::Trace(initialized ? "game: OnInitialize done, entering main loop"
                                : "game: OnInitialize FAILED (see fnc.log)");

    const int exit_code = initialized ? context.RunMainMessageLoop() : 1;
    fnc::boot::Trace("game: main loop exited with code: " + std::to_string(exit_code));
    app->InvokeOnDestroy();
    return exit_code;
  }
}
