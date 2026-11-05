// Fight Night Champion Recompiled - iOS Save & DLC Manager
// Title ID: 45410915 (Media ID: 2DC50868)

#pragma once

#include <filesystem>
#include <string>

#ifdef __OBJC__
@class UIViewController;

namespace fnc::saves {
UIViewController* MakeSaveManager(const std::filesystem::path& documents);
void ShowDlcInstaller(UIViewController* parent, const std::filesystem::path& documents);
}
#endif

namespace fnc::saves {
int AutoSync(const std::filesystem::path& documents);
void SyncAfterGameSave();
bool InstallDlcPackage(const std::filesystem::path& package_path, const std::filesystem::path& documents);
void QuarantineLegacyFN4Profiles(const std::filesystem::path& documents);
}
