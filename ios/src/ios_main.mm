// Fight Night Champion iOS - Main Entrypoint & App Lifecycle (ios_main.mm)
// ReXGlue Static Recompilation Host for Xbox 360 Title ID: 45410915 / Media ID: 2DC50868

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

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

namespace {

fs::path DocumentsFolder() {
  NSArray<NSString*>* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
  return fs::path(paths.firstObject.UTF8String);
}

fs::path CachesFolder() {
  NSArray<NSString*>* paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
  return fs::path(paths.firstObject.UTF8String);
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

void SetupFightNightRuntimeDirectories(const fs::path& docs, const fs::path& caches) {
  std::error_code ec;
  // 1. Prevent EA Sports Logo multi-core freeze: content/45410915/00000002/
  fs::create_directories(docs / "rex_data" / "content" / "45410915" / "00000002", ec);
  fs::create_directories(docs / "data" / "content" / "45410915" / "00000002", ec);

  // 2. Instant KO Replays mount scratch:/ cache:/
  fs::create_directories(caches / "rex_scratch", ec);
  fs::create_directories(docs / "data" / "cache", ec);
  fs::create_directories(docs / "logs", ec);
  fnc::boot::Trace("Runtime directories prepared: 45410915 content and scratch cache ready.");
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
      "--gpu_plugin=xenos",
      "--gpu_backend=vulkan",
      "--render_target_path_vulkan=fbo",
      "--fullscreen=true",
      "--resolution_scale=1",
      "--readback_resolve=fast",
      "--clear_memory_page_state=true",
      "--async_shader_compilation=true",
      "--texture_cache_memory_limit_soft=1024",
      "--texture_cache_memory_limit_hard=2048",
      "--ios_async_submits=true",
      "--ios_utility_qos_guest=false",
      "--ios_xma_starve_reset=false",
      "--audio_maxqframes=64",
      "--present_letterbox=true",
      "--mount_scratch=true",
      "--mount_cache=true",
      "--user_data_root=" + (docs / "data").string(),
      "--cache_root=" + (caches / "rexglue").string(),
      "--log_file=" + (docs / "logs" / "fnc.log").string(),
      "--log_level=info",
      "--game_data_root=" + gameSource.string(),
  };

  // Merge settings from Launcher
  auto launcherArgs = fnc::launcher::SettingsArguments(docs);
  for (const auto& a : launcherArgs) {
    SetArgument(args, a);
  }

  return args;
}

} // namespace

int main(int argc, char* argv[]) {
  @autoreleasepool {
    const fs::path docs = DocumentsFolder();
    const fs::path caches = CachesFolder();

    // Line 1: Immediate boot trace
    auto now = std::chrono::system_clock::to_time_t(std::chrono::system_clock::now());
    char timebuf[64];
    std::strftime(timebuf, sizeof(timebuf), "%Y-%m-%d %H:%M:%S", std::localtime(&now));
    fnc::boot::Trace(std::string("---- start, build ") + timebuf + " (Fight Night Champion iOS ARM64)");

    // Initialize haptics & audio session
    IOSHaptics_Init(true);
    SetupFightNightRuntimeDirectories(docs, caches);
    PrewarmShaderCache(caches);

    // Run native dark-mode UITableViewStyleInsetGrouped 6-tab launcher
    fnc::boot::Trace("launcher: displaying 6-tab configuration menu");
    fs::path gameSource = fnc::launcher::Run(docs);

    if (gameSource.empty()) {
      auto sources = fnc::launcher::FindGameSources(docs);
      if (!sources.empty()) {
        gameSource = sources.front();
      }
    }

    if (gameSource.empty()) {
      dispatch_sync(dispatch_get_main_queue(), ^{
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"No Game Source Detected"
                                                                       message:@"Please place your retail Fight Night Champion .iso or extracted folder containing default.xex in the Documents folder."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        UIWindow* keyWin = nil;
        for (UIScene* scene in [UIApplication sharedApplication].connectedScenes) {
          if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene* winScene = (UIWindowScene*)scene;
            for (UIWindow* w in winScene.windows) {
              if (w.isKeyWindow) { keyWin = w; break; }
            }
          }
        }
        if (!keyWin) {
          keyWin = [UIApplication sharedApplication].delegate.window;
        }
        [keyWin.rootViewController presentViewController:alert animated:YES completion:nil];
      });
      fnc::boot::Trace("FATAL: No game source found in Documents. Waiting for user files.");
      return 1;
    }

    // Build arguments
    fnc::boot::Trace(std::string("audio: activating the session"));
    rex::audio::ios::PrepareAudioSession();

    fnc::boot::Trace(std::string("game: parsing the arguments for: ") + gameSource.string());
    auto gameArgs = BuildGameArguments(docs, caches, gameSource);

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
                                : "game: OnInitialize FAILED (see fncreborn.log)");

    const int exit_code = initialized ? context.RunMainMessageLoop() : 1;
    fnc::boot::Trace("game: main loop exited with code: " + std::to_string(exit_code));
    app->InvokeOnDestroy();
    return exit_code;
  }
}
