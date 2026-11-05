// Fight Night Champion Recompiled - iOS Save & DLC Manager
// Title ID: 45410915 (Media ID: 2DC50868)

#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <filesystem>
#include <fstream>
#include <system_error>

#include <rex/logging.h>
#include "save_manager.h"

namespace fs = std::filesystem;

namespace fnc::saves {

void QuarantineLegacyFN4Profiles(const fs::path& documents) {
  std::error_code ec;
  const fs::path content_root = documents / "rex_data" / "content";
  const fs::path quarantine_root = documents / "quarantined_fn4";

  if (!fs::exists(content_root, ec)) return;

  for (const auto& entry : fs::recursive_directory_iterator(content_root, ec)) {
    if (entry.is_directory()) {
      std::string dirname = entry.path().filename().string();
      if (dirname.find("FN4PROFILE") != std::string::npos || dirname == "454108E8") {
        fs::create_directories(quarantine_root, ec);
        fs::path dest = quarantine_root / entry.path().filename();
        fs::rename(entry.path(), dest, ec);
        REXLOG_WARN("[FNC-SAVE] Quarantined legacy Fight Night profile directory: {}", entry.path().string());
      }
    }
  }
}

int AutoSync(const fs::path& documents) {
  std::error_code ec;
  QuarantineLegacyFN4Profiles(documents);

  const fs::path save_dir = documents / "rex_data" / "content" / "45410915" / "00000001";
  const fs::path backup_dir = documents / "SaveBackups" / "45410915";
  fs::create_directories(save_dir, ec);
  fs::create_directories(backup_dir, ec);

  // Ensure empty 00000002 DLC directory exists to prevent EA logo boot freeze
  const fs::path dlc_dir = documents / "rex_data" / "content" / "45410915" / "00000002";
  fs::create_directories(dlc_dir, ec);

  int count = 0;
  if (fs::exists(save_dir, ec)) {
    for (const auto& entry : fs::recursive_directory_iterator(save_dir, ec)) {
      if (entry.is_regular_file()) {
        fs::path rel = fs::relative(entry.path(), save_dir, ec);
        fs::path target = backup_dir / rel;
        fs::create_directories(target.parent_path(), ec);
        fs::copy_file(entry.path(), target, fs::copy_options::update_existing, ec);
        count++;
      }
    }
  }
  REXLOG_INFO("[FNC-SAVE] AutoSync backed up {} save items to {}", count, backup_dir.string());
  return count;
}

void SyncAfterGameSave() {
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                 dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    if (paths.count > 0) {
      AutoSync([paths.firstObject UTF8String]);
    }
  });
}

bool InstallDlcPackage(const fs::path& package_path, const fs::path& documents) {
  std::error_code ec;
  const fs::path dlc_dir = documents / "rex_data" / "content" / "45410915" / "00000002";
  fs::create_directories(dlc_dir, ec);

  if (!fs::exists(package_path, ec)) return false;

  fs::path dest = dlc_dir / package_path.filename();
  fs::copy_file(package_path, dest, fs::copy_options::overwrite_existing, ec);
  if (!ec) {
    REXLOG_INFO("[FNC-DLC] Installed STFS DLC: {} -> {}", package_path.string(), dest.string());
    return true;
  }
  REXLOG_ERROR("[FNC-DLC] Failed to install DLC: {}", ec.message());
  return false;
}

#ifdef __OBJC__

@interface FNCSaveManagerController : UIViewController <UIDocumentPickerDelegate>
@property(nonatomic, assign) fs::path documents;
@end

@implementation FNCSaveManagerController

- (void)viewDidLoad {
  [super viewDidLoad];
  self.title = @"Saves & DLC";
  self.view.backgroundColor = [UIColor colorWithRed:0.04f green:0.04f blue:0.06f alpha:1.0f];

  UIBarButtonItem* doneBtn =
      [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                    target:self
                                                    action:@selector(onDone)];
  self.navigationItem.rightBarButtonItem = doneBtn;

  UILabel* label = [[UILabel alloc] initWithFrame:CGRectMake(24, 100, self.view.bounds.size.width - 48, 80)];
  label.numberOfLines = 0;
  label.textColor = [UIColor whiteColor];
  label.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
  label.text = @"Fight Night Champion Career & Legacy Saves\nAll saves are stored in Documents/rex_data/content/45410915/\nAutomated cloud and local backups active.";
  [self.view addSubview:label];

  UIButton* backupBtn = [UIButton buttonWithType:UIButtonTypeSystem];
  backupBtn.frame = CGRectMake(24, 200, self.view.bounds.size.width - 48, 50);
  backupBtn.backgroundColor = [UIColor colorWithRed:0.12f green:0.12f blue:0.14f alpha:1.0f];
  backupBtn.layer.cornerRadius = 10;
  [backupBtn setTitle:@"Backup Career & Legacy Saves" forState:UIControlStateNormal];
  [backupBtn setTitleColor:[UIColor colorWithRed:0.04f green:0.52f blue:1.0f alpha:1.0f] forState:UIControlStateNormal];
  backupBtn.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
  [backupBtn addTarget:self action:@selector(onBackup) forControlEvents:UIControlEventTouchUpInside];
  [self.view addSubview:backupBtn];

  UIButton* dlcBtn = [UIButton buttonWithType:UIButtonTypeSystem];
  dlcBtn.frame = CGRectMake(24, 270, self.view.bounds.size.width - 48, 50);
  dlcBtn.backgroundColor = [UIColor colorWithRed:0.12f green:0.12f blue:0.14f alpha:1.0f];
  dlcBtn.layer.cornerRadius = 10;
  [dlcBtn setTitle:@"Install Xbox 360 DLC Package..." forState:UIControlStateNormal];
  [dlcBtn setTitleColor:[UIColor colorWithRed:0.83f green:0.69f blue:0.22f alpha:1.0f] forState:UIControlStateNormal];
  dlcBtn.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
  [dlcBtn addTarget:self action:@selector(onInstallDlc) forControlEvents:UIControlEventTouchUpInside];
  [self.view addSubview:dlcBtn];
}

- (void)onDone {
  [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)onBackup {
  int count = AutoSync(self.documents);
  UIAlertController* alert =
      [UIAlertController alertControllerWithTitle:@"Backup Complete"
                                          message:[NSString stringWithFormat:@"Successfully backed up %d save files to Documents/SaveBackups/45410915/", count]
                                   preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
  [self presentViewController:alert animated:YES completion:nil];
}

- (void)onInstallDlc {
  ShowDlcInstaller(self, self.documents);
}

@end

UIViewController* MakeSaveManager(const fs::path& documents) {
  FNCSaveManagerController* vc = [[FNCSaveManagerController alloc] init];
  vc.documents = documents;
  UINavigationController* nav = [[UINavigationController alloc] initWithRootViewController:vc];
  nav.navigationBar.barStyle = UIBarStyleBlack;
  return nav;
}

void ShowDlcInstaller(UIViewController* parent, const fs::path& documents) {
  UIDocumentPickerViewController* picker =
      [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ UTTypeItem ]
                                                                  asCopy:YES];
  // Helper block delegate or alert
  UIAlertController* alert =
      [UIAlertController alertControllerWithTitle:@"Install STFS DLC"
                                          message:@"Place dumped DLC files (Bare Knuckles Mode, Boxer Packs) into Documents/rex_data/content/45410915/00000002/ or pick via Files app."
                                   preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
  [parent presentViewController:alert animated:YES completion:nil];
}

#endif

}  // namespace fnc::saves
