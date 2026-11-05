// Fight Night Champion iOS - Native Launcher Host (launcher.h)
// Exact dark mode UITableViewStyleInsetGrouped 6-tab menu.

#pragma once

#ifdef __OBJC__
#import <Foundation/Foundation.h>
#endif

#include <filesystem>
#include <string>
#include <utility>
#include <vector>

namespace fnc::launcher {

// The app's Documents/ folder.
std::filesystem::path Documents();

// Finds detected .iso or extracted game folders containing default.xex and databigs.
std::vector<std::filesystem::path> FindGameSources(const std::filesystem::path& documents);

// Shows the settings and the Play button, and returns when Play is tapped:
// the game source path (ISO or extracted folder) to play.
std::filesystem::path Run(const std::filesystem::path& documents);

// Returns ReXGlue command-line arguments derived from user settings.
std::vector<std::string> SettingsArguments(const std::filesystem::path& documents);

#ifdef __OBJC__
struct MenuRow {
  NSString* key;
  NSString* title;
  NSString* summary;
  bool is_switch;
  std::vector<std::pair<NSString*, NSString*>> choices;
};

std::vector<MenuRow> Rows(NSArray<NSString*>* keys);
NSMutableDictionary<NSString*, NSString*>* ReadSettings(const std::filesystem::path& documents);
void WriteSettings(const std::filesystem::path& documents, NSDictionary<NSString*, NSString*>* settings);
NSString* SettingValue(NSDictionary<NSString*, NSString*>* settings, NSString* key);
#endif

}  // namespace fnc::launcher
