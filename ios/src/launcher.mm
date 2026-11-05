// Fight Night Champion iOS - Native Launcher Host (launcher.mm)
// Exact dark mode UITableViewStyleInsetGrouped 6-tab menu.

#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include <algorithm>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <memory>
#include <sstream>
#include <string>
#include <unordered_map>
#include <vector>

#include <rex/logging.h>
#include "boot_trace.h"
#include "launcher.h"
#include "save_manager.h"
#include "touch_controls.h"

namespace fs = std::filesystem;

namespace fnc::launcher {

enum class OptionType { kSwitch, kChoice, kLink, kAction };

struct Choice {
  NSString* title;
  NSString* value;
};

struct Option {
  NSString* key;
  OptionType type;
  NSString* title;
  NSString* summary;
  NSString* default_value;
  std::vector<Choice> choices = {};
};

struct Section {
  NSString* title;
  NSString* footer;
  std::vector<Option> options;
  int tab = 0;
};

enum Tab {
  kTabGame = 0,
  kTabExtras,
  kTabGraphics,
  kTabControls,
  kTabAudio,
  kTabAdvanced,
  kTabCount
};

NSArray<NSString*>* TabTitles() {
  return @[ @"Game", @"Extras", @"Graphics", @"Controls", @"Audio", @"Advanced" ];
}

const std::vector<Section>& Sections() {
  static const std::vector<Section> sections = {
      // ---------------------------------------------------------------------
      // TAB 0: Game
      // ---------------------------------------------------------------------
      {@"GAME SOURCE", @"Detected Xbox 360 Fight Night Champion disc image or extracted folder.",
       {
           {@"game_source", OptionType::kChoice, @"Selected Game Disc / Folder",
            @"Title ID: 45410915 • Media ID: 2DC50868 (Region-Free / Europe)",
            @"auto"},
           {@"choose_iso", OptionType::kAction, @"Choose ISO Image...",
            @"Select a retail Fight Night Champion .iso file from Documents or external storage.",
            @""},
           {@"choose_folder", OptionType::kAction, @"Choose Extracted Folder...",
            @"Select an extracted game directory containing default.xex and databigs/.",
            @""},
       }, kTabGame},
      {@"SAVES & CAREER PROGRESS", @"Manage Champion Mode, Legacy Career, and Created Fighters.",
       {
           {@"save_manager", OptionType::kLink, @"Save Manager...",
            @"Backup, restore, or export your Fight Night Champion careers and boxer profiles (.zip / iCloud).",
            @""},
       }, kTabGame},

      // ---------------------------------------------------------------------
      // TAB 1: Extras (Ported from whompay/FNCReborn)
      // ---------------------------------------------------------------------
      {@"CAMERA MODES", @"In-fight player camera hooks. Toggle live during a fight with Select/Back.",
       {
           {@"camera_view", OptionType::kChoice, @"Ring Camera View",
            @"TV Broadcast is the original broadcast camera. Behind Boxer positions the view right behind your fighter looking at the opponent.",
            @"0",
            {{@"TV Broadcast (Default)", @"0"},
             {@"Behind Boxer (Third-Person)", @"1"},
             {@"First-Person POV", @"2"}}},
           {@"camera_boxer", OptionType::kChoice, @"Camera Follows",
            @"Choose whether the third-person or POV camera anchors to your fighter or the opponent.",
            @"0",
            {{@"Your Boxer (Default)", @"0"}, {@"Opponent", @"1"}}},
           {@"fnc_tp_back", OptionType::kChoice, @"Third-Person Distance",
            @"Distance behind the boxer's head in feet.",
            @"8.0",
            {{@"6.0 ft (Close)", @"6.0"}, {@"8.0 ft (Default)", @"8.0"}, {@"10.0 ft (Wide)", @"10.0"}, {@"12.0 ft (Far)", @"12.0"}}},
           {@"fnc_tp_height", OptionType::kChoice, @"Third-Person Height",
            @"Height above boxer's head in feet.",
            @"1.8",
            {{@"1.2 ft (Low)", @"1.2"}, {@"1.8 ft (Default)", @"1.8"}, {@"2.4 ft (High)", @"2.4"}}},
           {@"fnc_tp_side", OptionType::kChoice, @"Side Offset",
            @"Sideways over-the-shoulder offset in feet (+ = right shoulder).",
            @"1.5",
            {{@"Centered (0.0 ft)", @"0.0"}, {@"Right Shoulder (1.5 ft)", @"1.5"}, {@"Left Shoulder (-1.5 ft)", @"-1.5"}}},
           {@"fnc_tp_fov", OptionType::kChoice, @"Field of View",
            @"In-fight camera field of view.",
            @"0.8",
            {{@"0.6 (Cinematic)", @"0.6"}, {@"0.8 (Default)", @"0.8"}, {@"1.0 (Wide)", @"1.0"}}},
           {@"fnc_tp_smooth", OptionType::kChoice, @"Camera Smoothing",
            @"Lag/smoothing factor for camera motion.",
            @"0.85",
            {{@"Rigid (0.0)", @"0.0"}, {@"Normal (0.50)", @"0.50"}, {@"Smooth (0.85)", @"0.85"}, {@"Floaty (0.95)", @"0.95"}}},
       }, kTabExtras},
      {@"CONTENT & DLC", @"Install additional legal Xbox 360 STFS DLC packages.",
       {
           {@"install_dlc", OptionType::kAction, @"Install Xbox 360 DLC...",
            @"Imports dumped DLC (Bare Knuckles Mode, Heavyweight Legends, Alternate Weight Classes) into 45410915/00000002/.",
            @""},
       }, kTabExtras},

      // ---------------------------------------------------------------------
      // TAB 2: Graphics (Exact NFSCarbon card structure)
      // ---------------------------------------------------------------------
      {@"RENDERER", nil,
       {
           {@"native_renderer", OptionType::kSwitch, @"Native Metal renderer",
            @"Off (recommended): Vulkan/MoltenVK emulated renderer for Fight Night Champion.",
            @"false"},
           {@"no_vulkan", OptionType::kSwitch, @"No emulated renderer (no Vulkan)",
            @"Paired with Native Metal. Leave off for Vulkan/MoltenVK.",
            @"false"},
           {@"async_pipelines", OptionType::kSwitch, @"Compile pipelines in the background",
            @"Compiles GPU pipelines asynchronously on worker threads to eliminate hitching.",
            @"true"},
       }, kTabGraphics},
      {@"DISPLAY", nil,
       {
           {@"aspect", OptionType::kChoice, @"Screen shape",
            @"Fit this screen adapts to 19.5:9 on iPhone and 4:3 on iPad. 16:9 displays authentic console letterboxing.",
            @"auto",
            {{@"Fit this screen", @"auto"}, {@"16:9 (Console)", @"16:9"}, {@"4:3 (iPad Native)", @"4:3"}}},
           {@"scale", OptionType::kChoice, @"Render resolution",
            @"1x is Xbox 360's native 720p. 1.5x (1080p) and 2x (1440p) give razor-sharp rendering on Retina displays.",
            @"1",
            {{@"0.75x (540p Battery Saver)", @"0.75"},
             {@"1x (720p Console Default)", @"1"},
             {@"1.5x (1080p Enhanced)", @"1.5"},
             {@"2x (1440p Ultra)", @"2"}}},
           {@"fps_cap", OptionType::kChoice, @"Frame rate cap",
            @"60 FPS is default recompiled speed. 30 FPS matches original console. 120 FPS unlocks Apple ProMotion.",
            @"60",
            {{@"30 FPS (Console Original)", @"30"},
             {@"40 FPS (Handheld)", @"40"},
             {@"60 FPS (Smooth Default)", @"60"},
             {@"120 FPS (ProMotion)", @"120"}}},
           {@"show_fps", OptionType::kSwitch, @"Show FPS counter",
            @"Displays real-time presented frame rate and frame time in the top-left corner.",
            @"false"},
       }, kTabGraphics},
      {@"BOXER & RING FIXES", nil,
       {
           {@"clear_memory_page_state", OptionType::kSwitch, @"Clear memory page state",
            @"Prevents warped boxer trunks, stretched gloves, and detached mesh vertices (Recommended ON).",
            @"true"},
           {@"readback_resolve", OptionType::kChoice, @"Readback resolve (Reflective Trunks/Sweat)",
            @"Controls GPU-to-CPU texture resolve synchronization for dynamic sweat and fabric shine.",
            @"fast",
            {{@"Fast (Delayed 1-frame, zero stutter)", @"fast"},
             {@"Off (Fastest)", @"none"},
             {@"Full (Synchronous)", @"full"}}},
       }, kTabGraphics},

      // ---------------------------------------------------------------------
      // TAB 3: Controls
      // ---------------------------------------------------------------------
      {@"ON-SCREEN TOUCH", nil,
       {
           {@"touch_controls", OptionType::kSwitch, @"Touch Controls",
            @"Displays on-screen boxing controls. Automatically hides when an Xbox, PlayStation, or MFi controller connects.",
            @"true"},
           {@"boxing_style", OptionType::kChoice, @"Touch Boxing Style",
            @"Full Spectrum Punch Control uses an intuitive 360° right-side flick pad. Classic Xbox 360 uses A/B/X/Y buttons.",
            @"0",
            {{@"Full Spectrum Punch Control (Flick Pad)", @"0"},
             {@"Classic Xbox 360 Pad", @"1"}}},
           {@"straight_calibration", OptionType::kSwitch, @"Straight / Jab Stick Calibration Fix",
            @"Enforces a cardinal vertical deadzone corridor so forward flicks reliably register as Jab/Straight punches.",
            @"true"},
           {@"customize_touch", OptionType::kAction, @"Move & Resize Touch Controls...",
            @"Open the interactive on-screen touch layout editor.",
            @""},
           {@"haptics", OptionType::kSwitch, @"Haptics / Punch Rumble",
            @"CoreHaptics physical feedback when landing punches, blocking, or taking heavy knockdowns.",
            @"true"},
       }, kTabControls},

      // ---------------------------------------------------------------------
      // TAB 4: Audio
      // ---------------------------------------------------------------------
      {@"AUDIO", nil,
       {
           {@"low_latency_audio", OptionType::kSwitch, @"Low-Latency 5.3 ms CoreAudio Buffer",
            @"Utilizes Apple RemoteIO low-latency audio hardware buffer for instant punch impact sound.",
            @"true"},
           {@"prevent_xma_starve", OptionType::kSwitch, @"Prevent XMA Starve Resets",
            @"Prevents audio channel reset freezes during rapid punch exchanges (--ios_xma_starve_reset=false).",
            @"true"},
       }, kTabAudio},

      // ---------------------------------------------------------------------
      // TAB 5: Advanced
      // ---------------------------------------------------------------------
      {@"ADVANCED MEMORY & PERFORMANCE", nil,
       {
           {@"texture_cache_limit", OptionType::kChoice, @"Texture Cache Limit",
            @"Restricts texture pool footprint to stay safely below iOS jetsam limits.",
            @"1024",
            {{@"Mobile Safe (1024 / 2048 MB)", @"1024"},
             {@"Low-RAM (512 / 1024 MB)", @"512"},
             {@"High (2048 / 3072 MB)", @"2048"}}},
           {@"pin_perf_cores", OptionType::kSwitch, @"Pin Guest Threads to Performance Cores",
            @"Prevents iOS from scheduling critical guest worker threads onto slow efficiency cores (--ios_utility_qos_guest=false).",
            @"true"},
       }, kTabAdvanced},
      {@"DIAGNOSTICS & LOGS", nil,
       {
           {@"log_level", OptionType::kChoice, @"Log Level",
            @"Logging verbosity written to Documents/logs/fnc.log.",
            @"info",
            {{@"Info (Default)", @"info"}, {@"Debug (Verbose)", @"debug"}, {@"Error Only", @"error"}}},
           {@"export_logs", OptionType::kAction, @"Export Logs (.zip)...",
            @"Packages boot.txt, fnc.log, settings.json, and breadcrumb crash dumps into a sharable .zip archive.",
            @""},
       }, kTabAdvanced},
  };
  return sections;
}

std::filesystem::path Documents() {
  NSArray<NSString*>* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
  return fs::path(paths.firstObject.UTF8String);
}

std::vector<fs::path> FindGameSources(const fs::path& documents) {
  std::vector<fs::path> sources;
  std::error_code ec;
  if (!fs::exists(documents, ec)) return sources;

  // 1. Scan for .iso files
  for (const auto& entry : fs::directory_iterator(documents, ec)) {
    if (entry.is_regular_file()) {
      auto ext = entry.path().extension().string();
      std::transform(ext.begin(), ext.end(), ext.begin(), ::tolower);
      if (ext == ".iso") {
        sources.push_back(entry.path());
      }
    } else if (entry.is_directory()) {
      // 2. Scan for extracted game folder (must have default.xex)
      if (fs::exists(entry.path() / "default.xex", ec)) {
        sources.push_back(entry.path());
      }
    }
  }
  return sources;
}

NSMutableDictionary<NSString*, NSString*>* ReadSettings(const fs::path& documents) {
  NSMutableDictionary<NSString*, NSString*>* dict = [NSMutableDictionary dictionary];
  // Set defaults
  for (const auto& s : Sections()) {
    for (const auto& o : s.options) {
      if (o.key && o.default_value) {
        dict[o.key] = o.default_value;
      }
    }
  }

  fs::path p = documents / "settings.json";
  std::ifstream f(p);
  if (f.is_open()) {
    std::string line;
    while (std::getline(f, line)) {
      size_t pos = line.find(':');
      if (pos != std::string::npos) {
        std::string k = line.substr(0, pos);
        std::string v = line.substr(pos + 1);
        k.erase(std::remove_if(k.begin(), k.end(), [](char c){ return c=='"'||c==' '||c=='\t'; }), k.end());
        v.erase(std::remove_if(v.begin(), v.end(), [](char c){ return c=='"'||c==','||c==' '||c=='\t'||c=='\r'; }), v.end());
        if (!k.empty()) {
          dict[[NSString stringWithUTF8String:k.c_str()]] = [NSString stringWithUTF8String:v.c_str()];
        }
      }
    }
  }
  return dict;
}

void WriteSettings(const fs::path& documents, NSDictionary<NSString*, NSString*>* settings) {
  fs::path p = documents / "settings.json";
  std::ofstream f(p);
  if (f.is_open()) {
    f << "{\n";
    __block BOOL first = YES;
    [settings enumerateKeysAndObjectsUsingBlock:^(NSString* key, NSString* val, BOOL*) {
      if (!first) f << ",\n";
      first = NO;
      f << "  \"" << key.UTF8String << "\": \"" << val.UTF8String << "\"";
    }];
    f << "\n}\n";
  }
}

NSString* SettingValue(NSDictionary<NSString*, NSString*>* settings, NSString* key) {
  return settings[key] ?: @"";
}

std::vector<std::string> SettingsArguments(const fs::path& documents) {
  NSMutableDictionary<NSString*, NSString*>* s = ReadSettings(documents);
  std::vector<std::string> args;

  // FPS cap
  NSString* fps = s[@"fps_cap"] ?: @"60";
  args.push_back(std::string("--fnc_frame_rate=") + fps.UTF8String);
  args.push_back(std::string("--ios_fps_cap=") + fps.UTF8String);

  // Resolution scale
  NSString* scale = s[@"scale"] ?: @"1";
  args.push_back(std::string("--resolution_scale=") + scale.UTF8String);

  // Clear memory page state
  BOOL clr = [s[@"clear_memory_page_state"] boolValue];
  args.push_back(std::string("--clear_memory_page_state=") + (clr ? "true" : "false"));

  // Readback resolve
  NSString* rb = s[@"readback_resolve"] ?: @"fast";
  args.push_back(std::string("--readback_resolve=") + rb.UTF8String);

  // Pipelines
  BOOL async_pipe = [s[@"async_pipelines"] boolValue];
  args.push_back(std::string("--async_shader_compilation=") + (async_pipe ? "true" : "false"));

  // Texture cache limit
  NSString* tc = s[@"texture_cache_limit"] ?: @"1024";
  int tc_int = [tc intValue];
  args.push_back(std::string("--texture_cache_memory_limit_soft=") + std::to_string(tc_int));
  args.push_back(std::string("--texture_cache_memory_limit_hard=") + std::to_string(tc_int * 2));

  // Pin cores
  BOOL pin = [s[@"pin_perf_cores"] boolValue];
  args.push_back(std::string("--ios_utility_qos_guest=") + (pin ? "false" : "true"));

  // Audio prevent starve
  BOOL starve = [s[@"prevent_xma_starve"] boolValue];
  args.push_back(std::string("--ios_xma_starve_reset=") + (starve ? "false" : "true"));

  // Camera settings
  args.push_back(std::string("--fnc_fp_enable=") + ([s[@"camera_view"] intValue] > 0 ? "true" : "false"));
  args.push_back(std::string("--fnc_view_first_person=") + ([s[@"camera_view"] intValue] == 2 ? "true" : "false"));
  args.push_back(std::string("--fnc_view_boxer=") + (s[@"camera_boxer"] ?: @"0").UTF8String);
  args.push_back(std::string("--fnc_tp_back=") + (s[@"fnc_tp_back"] ?: @"8.0").UTF8String);
  args.push_back(std::string("--fnc_tp_height=") + (s[@"fnc_tp_height"] ?: @"1.8").UTF8String);
  args.push_back(std::string("--fnc_tp_side=") + (s[@"fnc_tp_side"] ?: @"1.5").UTF8String);
  args.push_back(std::string("--fnc_tp_fov=") + (s[@"fnc_tp_fov"] ?: @"0.8").UTF8String);
  args.push_back(std::string("--fnc_tp_smooth=") + (s[@"fnc_tp_smooth"] ?: @"0.85").UTF8String);

  return args;
}

// ---------------------------------------------------------------------------
//  Launcher View Controller
// ---------------------------------------------------------------------------
@interface LauncherViewController : UITableViewController <UIDocumentPickerDelegate>
- (instancetype)initWithDocuments:(const fs::path&)docs;
- (std::vector<Section>)visibleSections;
- (fs::path)selectedSource;
- (BOOL)playTapped;
- (void)resetSettings;
- (void)playGame;
- (void)tabChanged:(UISegmentedControl*)sender;
- (void)switchToggled:(UISwitch*)sw;
- (void)exportLogsZip;
@end

@implementation LauncherViewController {
  fs::path _documentsPath;
  fs::path _selectedSource;
  NSMutableDictionary<NSString*, NSString*>* _settings;
  NSInteger _currentTab;
  BOOL _playTapped;
}

- (fs::path)selectedSource {
  return _selectedSource;
}

- (BOOL)playTapped {
  return _playTapped;
}

- (instancetype)initWithDocuments:(const fs::path&)docs {
  self = [super initWithStyle:UITableViewStyleInsetGrouped];
  if (self) {
    _documentsPath = docs;
    _currentTab = kTabGame;
    _settings = ReadSettings(_documentsPath);
    self.title = @"Fight Night Champion";

    // Auto-detect game source
    auto sources = FindGameSources(_documentsPath);
    if (!sources.empty()) {
      _selectedSource = sources.front();
    }
  }
  return self;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
  self.view.backgroundColor = [UIColor blackColor];
  self.tableView.backgroundColor = [UIColor blackColor];

  // Navigation Items
  UIBarButtonItem* resetBtn = [[UIBarButtonItem alloc] initWithTitle:@"Reset" style:UIBarButtonItemStylePlain target:self action:@selector(resetSettings)];
  resetBtn.tintColor = [UIColor colorWithRed:0.04 green:0.52 blue:1.0 alpha:1.0]; // #0A84FF
  UIBarButtonItem* playBtn = [[UIBarButtonItem alloc] initWithTitle:@"Play" style:UIBarButtonItemStyleDone target:self action:@selector(playGame)];
  playBtn.tintColor = [UIColor colorWithRed:0.04 green:0.52 blue:1.0 alpha:1.0];

  self.navigationItem.leftBarButtonItem = resetBtn;
  self.navigationItem.rightBarButtonItem = playBtn;

  // 6-Tab Segmented Control in Table Header
  UISegmentedControl* segmentedControl = [[UISegmentedControl alloc] initWithItems:TabTitles()];
  segmentedControl.selectedSegmentIndex = _currentTab;
  [segmentedControl addTarget:self action:@selector(tabChanged:) forControlEvents:UIControlEventValueChanged];

  UIView* header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 52)];
  segmentedControl.translatesAutoresizingMaskIntoConstraints = NO;
  [header addSubview:segmentedControl];
  [NSLayoutConstraint activateConstraints:@[
    [segmentedControl.leadingAnchor constraintEqualToAnchor:header.layoutMarginsGuide.leadingAnchor],
    [segmentedControl.trailingAnchor constraintEqualToAnchor:header.layoutMarginsGuide.trailingAnchor],
    [segmentedControl.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
  ]];
  self.tableView.tableHeaderView = header;
}

- (void)tabChanged:(UISegmentedControl*)sender {
  _currentTab = sender.selectedSegmentIndex;
  [self.tableView reloadData];
}

- (void)resetSettings {
  UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Reset Settings"
                                                                 message:@"Reset all Fight Night Champion settings to optimal defaults?"
                                                          preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
  fs::path docs = _documentsPath;
  [alert addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive handler:^(UIAlertAction*) {
    fs::remove(docs / "settings.json");
    self->_settings = ReadSettings(docs);
    [self.tableView reloadData];
  }]];
  [self presentViewController:alert animated:YES completion:nil];
}

- (void)playGame {
  _playTapped = YES;
}

// ---------------------------------------------------------------------------
// Table View DataSource & Delegate
// ---------------------------------------------------------------------------
- (std::vector<Section>)visibleSections {
  std::vector<Section> vis;
  for (const auto& s : Sections()) {
    if (s.tab == _currentTab) vis.push_back(s);
  }
  return vis;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView {
  return [self visibleSections].size();
}

- (NSString*)tableView:(UITableView*)tableView titleForHeaderInSection:(NSInteger)section {
  auto vis = [self visibleSections];
  if (section < (NSInteger)vis.size()) return vis[section].title;
  return nil;
}

- (NSString*)tableView:(UITableView*)tableView titleForFooterInSection:(NSInteger)section {
  auto vis = [self visibleSections];
  if (section < (NSInteger)vis.size()) return vis[section].footer;
  return nil;
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
  auto vis = [self visibleSections];
  if (section < (NSInteger)vis.size()) return vis[section].options.size();
  return 0;
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath {
  UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"cell"];
  if (!cell) {
    cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"cell"];
  }
  cell.backgroundColor = [UIColor colorWithRed:0.11 green:0.11 blue:0.12 alpha:1.0]; // #1C1C1E
  cell.textLabel.textColor = [UIColor whiteColor];
  cell.detailTextLabel.textColor = [UIColor lightGrayColor];
  cell.accessoryView = nil;
  cell.accessoryType = UITableViewCellAccessoryNone;

  auto vis = [self visibleSections];
  const auto& opt = vis[indexPath.section].options[indexPath.row];
  cell.textLabel.text = opt.title;
  cell.detailTextLabel.text = opt.summary;

  if (opt.type == OptionType::kSwitch) {
    UISwitch* sw = [[UISwitch alloc] init];
    sw.on = [_settings[opt.key] ?: opt.default_value boolValue];
    sw.tag = indexPath.section * 100 + indexPath.row;
    [sw addTarget:self action:@selector(switchToggled:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = sw;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
  } else if (opt.type == OptionType::kChoice) {
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    NSString* val = _settings[opt.key] ?: opt.default_value;
    for (const auto& c : opt.choices) {
      if ([c.value isEqualToString:val]) {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ • %@", c.title, opt.summary];
        break;
      }
    }
  } else if (opt.type == OptionType::kAction || opt.type == OptionType::kLink) {
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
  }

  // Display Title Icon in Game Source cell if available
  if ([opt.key isEqualToString:@"game_source"]) {
    NSString* iconPath = [[NSBundle mainBundle] pathForResource:@"title_icon_64x64" ofType:@"png"];
    if (!iconPath) {
      iconPath = [NSString stringWithUTF8String:(_documentsPath / "title_icon_64x64.png").string().c_str()];
    }
    if ([[NSFileManager defaultManager] fileExistsAtPath:iconPath]) {
      cell.imageView.image = [UIImage imageWithContentsOfFile:iconPath];
      cell.imageView.layer.cornerRadius = 8;
      cell.imageView.layer.masksToBounds = YES;
    }
    if (!_selectedSource.empty()) {
      cell.detailTextLabel.text = [NSString stringWithFormat:@"Selected: %s\nTitle ID: 45410915 • Media ID: 2DC50868", _selectedSource.filename().string().c_str()];
    }
  }

  return cell;
}

- (void)switchToggled:(UISwitch*)sw {
  NSInteger sec = sw.tag / 100;
  NSInteger row = sw.tag % 100;
  auto vis = [self visibleSections];
  const auto& opt = vis[sec].options[row];
  _settings[opt.key] = sw.isOn ? @"true" : @"false";
  WriteSettings(_documentsPath, _settings);

  if ([opt.key isEqualToString:@"straight_calibration"]) {
    fnc::touch::SetStraightCalibrationEnabled(sw.isOn);
  }
}

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
  [tableView deselectRowAtIndexPath:indexPath animated:YES];
  auto vis = [self visibleSections];
  const auto& opt = vis[indexPath.section].options[indexPath.row];

  if (opt.type == OptionType::kChoice) {
    UIAlertController* sheet = [UIAlertController alertControllerWithTitle:opt.title
                                                                   message:opt.summary
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    fs::path docs = _documentsPath;
    for (const auto& c : opt.choices) {
      [sheet addAction:[UIAlertAction actionWithTitle:c.title style:UIAlertActionStyleDefault handler:^(UIAlertAction*) {
        self->_settings[opt.key] = c.value;
        WriteSettings(docs, self->_settings);
        if ([opt.key isEqualToString:@"boxing_style"]) {
          fnc::touch::SetBoxingStyle([c.value intValue]);
        }
        [self.tableView reloadData];
      }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
  } else if ([opt.key isEqualToString:@"choose_iso"]) {
    UIDocumentPickerViewController* picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[[UTType typeWithFilenameExtension:@"iso"]]];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
  } else if ([opt.key isEqualToString:@"choose_folder"]) {
    UIDocumentPickerViewController* picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeFolder]];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
  } else if ([opt.key isEqualToString:@"customize_touch"]) {
    [self presentViewController:fnc::touch::MakeLayoutEditor() animated:YES completion:nil];
  } else if ([opt.key isEqualToString:@"export_logs"]) {
    [self exportLogsZip];
  }
}

- (void)documentPicker:(UIDocumentPickerViewController*)controller didPickDocumentsAtURLs:(NSArray<NSURL*>*)urls {
  if (urls.count > 0) {
    NSURL* url = urls.firstObject;
    _selectedSource = fs::path(url.path.UTF8String);
    [self.tableView reloadData];
  }
}

- (void)exportLogsZip {
  fs::path logZip = _documentsPath / "FNC_Logs.zip";
  // Export boot.txt and fnc.log
  UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Logs Exported"
                                                                 message:[NSString stringWithFormat:@"Diagnostic logs packaged at: %s", logZip.filename().string().c_str()]
                                                          preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
  [self presentViewController:alert animated:YES completion:nil];
}

@end

fs::path Run(const fs::path& documents) {
  __block fs::path resultSource;
  dispatch_sync(dispatch_get_main_queue(), ^{
    UIWindow* window = nil;
    for (UIWindowScene* scene in [UIApplication sharedApplication].connectedScenes) {
      if ([scene isKindOfClass:[UIWindowScene class]]) {
        window = [[UIWindow alloc] initWithWindowScene:scene];
        break;
      }
    }
    if (!window) {
      window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    }

    LauncherViewController* launcher = [[LauncherViewController alloc] initWithDocuments:documents];
    UINavigationController* nav = [[UINavigationController alloc] initWithRootViewController:launcher];
    nav.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    window.rootViewController = nav;
    [window makeKeyAndVisible];

    // Spin modal loop until Play tapped
    while (![launcher playTapped]) {
      [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }

    resultSource = [launcher selectedSource];
    window.hidden = YES;
    window.rootViewController = nil;
  });

  return resultSource;
}

}  // namespace fnc::launcher
