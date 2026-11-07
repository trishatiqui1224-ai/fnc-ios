#!/usr/bin/env python3
"""
tools/ios/patch_ios_fnc_fixes.py
Fight Night Champion runtime fixes:
1. Texture cache: silence zeroed dummy fetch constants and honor gpu_allow_invalid_fetch_constants.
2. VFS Runtime::SetupVfs: mount writable HostPathDevice for \\Device\\Cache and \\Device\\Scratch.
3. VFS VirtualFileSystem::OpenFile: allow opening root volume directories ("D:\\", "cache:\\").
4. Kernel NtQueryVolumeInformationFile: return FILE_DEVICE_DISK (0x00000007) for XFileFsDeviceInformation.
5. Kernel IoDismountVolumeByFileHandle: re-register cache: symbolic links after utility dismount.

    python3 tools/ios/patch_ios_fnc_fixes.py            apply
    python3 tools/ios/patch_ios_fnc_fixes.py --status
    python3 tools/ios/patch_ios_fnc_fixes.py --revert
"""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from patch_engine import run  # noqa: E402

# 1. Texture Cache (src/graphics/pipeline/texture/cache.cpp)
CACHE_ANCHOR = '''  switch (fetch.type) {
    case xenos::FetchConstantType::kTexture:
      break;
    case xenos::FetchConstantType::kInvalidTexture:
      if (REXCVAR_GET(gpu_allow_invalid_fetch_constants)) {
        break;
      }
      REXGPU_WARN(
          "Texture fetch constant ({:08X} {:08X} {:08X} {:08X} {:08X} {:08X}) "
          "has \\"invalid\\" type! This is incorrect behavior, but you can try "
          "bypassing this by launching Xenia with "
          "--gpu_allow_invalid_fetch_constants=true.",
          fetch.dword_0, fetch.dword_1, fetch.dword_2, fetch.dword_3, fetch.dword_4, fetch.dword_5);
      return;
    default:
      REXGPU_WARN(
          "Texture fetch constant ({:08X} {:08X} {:08X} {:08X} {:08X} {:08X}) "
          "is completely invalid!",
          fetch.dword_0, fetch.dword_1, fetch.dword_2, fetch.dword_3, fetch.dword_4, fetch.dword_5);
      return;
  }'''

CACHE_NEW = '''  switch (fetch.type) {
    case xenos::FetchConstantType::kTexture:
      break;
    case xenos::FetchConstantType::kInvalidTexture:
      // LOCAL PATCH: Skip completely uninitialized zeroed fetch constants (address == 0, size == 0)
      if (fetch.base_address == 0 && fetch.size_2d.width == 0 && fetch.size_2d.height == 0) {
        return;
      }
      if (REXCVAR_GET(gpu_allow_invalid_fetch_constants)) {
        break;
      }
      REXGPU_WARN(
          "Texture fetch constant ({:08X} {:08X} {:08X} {:08X} {:08X} {:08X}) "
          "has \\"invalid\\" type! This is incorrect behavior, but you can try "
          "bypassing this by launching Xenia with "
          "--gpu_allow_invalid_fetch_constants=true.",
          fetch.dword_0, fetch.dword_1, fetch.dword_2, fetch.dword_3, fetch.dword_4, fetch.dword_5);
      return;
    default:
      if (fetch.dword_0 == 0 && fetch.dword_1 == 0 && fetch.dword_2 == 0) {
        return;
      }
      REXGPU_WARN(
          "Texture fetch constant ({:08X} {:08X} {:08X} {:08X} {:08X} {:08X}) "
          "is completely invalid!",
          fetch.dword_0, fetch.dword_1, fetch.dword_2, fetch.dword_3, fetch.dword_4, fetch.dword_5);
      return;
  }'''

# 2. SetupVfs (src/system/runtime.cpp)
VFS_ANCHOR = '''  // NOTE: Do NOT register a device for cache: paths
  // Games handle "device not found" gracefully but don't handle actual device
  // errors (like NAME_COLLISION) well. Let cache: fail cleanly.

  return true;'''

VFS_NEW = '''  // LOCAL PATCH - Fight Night Champion (Title ID: 45410915):
  // Mount writable HostPathDevice for cache:\\ and scratch:\\ partitions so
  // XMountUtilityDrive and Instant KO Replays do not fail or freeze.
  std::filesystem::path cache_root_dir = cache_root_.empty() ? (game_data_root_ / "cache") : cache_root_;
  std::filesystem::path cache_host_dir = cache_root_dir / "cache_drive";
  std::filesystem::path scratch_host_dir = cache_root_dir / "scratch_drive";
  std::error_code vfs_ec;
  std::filesystem::create_directories(cache_host_dir, vfs_ec);
  std::filesystem::create_directories(scratch_host_dir, vfs_ec);

  auto cache_device = std::make_unique<rex::filesystem::HostPathDevice>(
      "\\Device\\Cache", cache_host_dir, /*read_only=*/false);
  if (cache_device->Initialize()) {
    file_system_->RegisterDevice(std::move(cache_device));
    file_system_->RegisterSymbolicLink("cache:", "\\Device\\Cache");
    file_system_->RegisterSymbolicLink("CACHE:", "\\Device\\Cache");
    file_system_->RegisterSymbolicLink("utl:", "\\Device\\Cache");
    REXSYS_DEBUG("  Mounted {} at \\Device\\Cache (cache:, CACHE:, utl:)", cache_host_dir.string());
  }

  auto scratch_device = std::make_unique<rex::filesystem::HostPathDevice>(
      "\\Device\\Scratch", scratch_host_dir, /*read_only=*/false);
  if (scratch_device->Initialize()) {
    file_system_->RegisterDevice(std::move(scratch_device));
    file_system_->RegisterSymbolicLink("scratch:", "\\Device\\Scratch");
    file_system_->RegisterSymbolicLink("SCRATCH:", "\\Device\\Scratch");
    REXSYS_DEBUG("  Mounted {} at \\Device\\Scratch (scratch:, SCRATCH:)", scratch_host_dir.string());
  }

  return true;'''

# 3. OpenFile (src/filesystem/virtual_file_system.cpp)
OPEN_ANCHOR = '''  if (entry) {
    if (entry->attributes() & kFileAttributeDirectory && is_non_directory) {
      return X_STATUS_FILE_IS_A_DIRECTORY;
    }'''

OPEN_NEW = '''  if (entry) {
    // LOCAL PATCH: Allow opening root volume directories ("D:\\", "cache:\\")
    // even when the guest omits FILE_DIRECTORY_FILE or sets FILE_NON_DIRECTORY_FILE,
    // so volume probe does not fail with 0xC00000BA:
    if (entry->attributes() & kFileAttributeDirectory && is_non_directory && !entry->name().empty()) {
      return X_STATUS_FILE_IS_A_DIRECTORY;
    }'''

# 4. XFileFsDeviceInformation (src/kernel/xboxkrnl/xboxkrnl_io_info.cpp)
DEVINFO_ANCHOR = '''    case XFileFsDeviceInformation: {
      auto info = info_ptr.as<X_FILE_FS_DEVICE_INFORMATION*>();
      REXKRNL_WARN("Stub XFileFsDeviceInformation!");
      info->device_type = FILE_DEVICE_UNKNOWN;
      info->characteristics = 0;
      out_length = sizeof(X_FILE_FS_DEVICE_INFORMATION);
      break;
    }'''

DEVINFO_NEW = '''    case XFileFsDeviceInformation: {
      auto info = info_ptr.as<X_FILE_FS_DEVICE_INFORMATION*>();
      // LOCAL PATCH: Return FILE_DEVICE_DISK (0x00000007) for EA Sports volume probe
      info->device_type = 0x00000007; // FILE_DEVICE_DISK
      info->characteristics = 0;
      out_length = sizeof(X_FILE_FS_DEVICE_INFORMATION);
      break;
    }'''

# 5. IoDismountVolumeByFileHandle (src/kernel/xboxkrnl/xboxkrnl_io.cpp)
DISMOUNT_ANCHOR = '''u32 IoDismountVolumeByFileHandle_entry(u32 handle) {
  REXKRNL_WARN("IoDismountVolumeByFileHandle({:#x}) - stub", (uint32_t)handle);
  return X_STATUS_SUCCESS;
}'''

DISMOUNT_NEW = '''u32 IoDismountVolumeByFileHandle_entry(u32 handle) {
  REXKRNL_WARN("IoDismountVolumeByFileHandle({:#x}) - stub", (uint32_t)handle);
  // LOCAL PATCH: Re-ensure cache: symbolic links stay active after EA's utility drive format/dismount check
  REX_KERNEL_FS()->RegisterSymbolicLink("cache:", "\\Device\\Cache");
  REX_KERNEL_FS()->RegisterSymbolicLink("CACHE:", "\\Device\\Cache");
  REX_KERNEL_FS()->RegisterSymbolicLink("utl:", "\\Device\\Cache");
  return X_STATUS_SUCCESS;
}'''

BLOCKS = [
    ("src/graphics/pipeline/texture/cache.cpp", "silence zero fetch constants & honor invalid cvar", CACHE_ANCHOR, CACHE_NEW),
    ("src/system/runtime.cpp", "mount writable cache and scratch HostPathDevices", VFS_ANCHOR, VFS_NEW),
    ("src/filesystem/virtual_file_system.cpp", "allow opening root volume directories", OPEN_ANCHOR, OPEN_NEW),
    ("src/kernel/xboxkrnl/xboxkrnl_io_info.cpp", "return FILE_DEVICE_DISK for XFileFsDeviceInformation", DEVINFO_ANCHOR, DEVINFO_NEW),
    ("src/kernel/xboxkrnl/xboxkrnl_io.cpp", "re-register cache: symlink on dismount", DISMOUNT_ANCHOR, DISMOUNT_NEW),
]

if __name__ == "__main__":
    sys.exit(run("ios_fnc_fixes", BLOCKS))
