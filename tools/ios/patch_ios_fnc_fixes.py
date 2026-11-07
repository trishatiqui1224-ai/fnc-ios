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
CACHE_ANCHOR = r'''  switch (fetch.type) {
    case xenos::FetchConstantType::kTexture:
      break;
    case xenos::FetchConstantType::kInvalidTexture:
      if (REXCVAR_GET(gpu_allow_invalid_fetch_constants)) {
        break;
      }
      REXGPU_WARN(
          "Texture fetch constant ({:08X} {:08X} {:08X} {:08X} {:08X} {:08X}) "
          "has \"invalid\" type! This is incorrect behavior, but you can try "
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

CACHE_NEW = r'''  // LOCAL PATCH - Fight Night Champion: Allow fetch constants marked type 0/1 if they have a
  // valid physical address and size (e.g. 10-frame VP6 video chroma ring buffer & 1280x720 post-process targets).
  if (fetch.type != xenos::FetchConstantType::kTexture) {
    if ((fetch.dword_1 & 0xFFFFF000u) != 0 && fetch.dword_2 != 0) {
      // Valid texture descriptors marked type 0/1 by game: allow parsing as kTexture.
    } else {
      return;
    }
  }'''

VIDEO_RING_ANCHOR = r'''      if (key_changed) {
        binding.texture = FindOrCreateTexture(binding.key);
        load_unsigned_data = true;
      }
      binding.texture_signed = nullptr;'''

VIDEO_RING_NEW = r'''      if (key_changed) {
        binding.texture = FindOrCreateTexture(binding.key);
        load_unsigned_data = true;
      }
      // LOCAL PATCH - Fight Night Champion: Invalidate linear k_8 video ring-buffer textures
      // so fresh CPU-decoded YUV frames are always re-uploaded from guest RAM on wrap-around
      if (!fetch.tiled && (xenos::TextureFormat(fetch.format) == xenos::TextureFormat::k_8)) {
        if (!binding.texture) {
          binding.texture = FindOrCreateTexture(binding.key);
        }
        load_unsigned_data = true;
      }
      binding.texture_signed = nullptr;'''

# 2. In-place Fetch Constant Promotion in GPU Command Processor (src/graphics/vulkan/command_processor.cpp)
FETCH_PROMO_ANCHOR = r'''  uint32_t used_texture_mask =
      vertex_shader->GetUsedTextureMaskAfterTranslation() |
      (pixel_shader != nullptr ? pixel_shader->GetUsedTextureMaskAfterTranslation() : 0);
  texture_cache_->RequestTextures(used_texture_mask);'''

FETCH_PROMO_NEW = r'''  // LOCAL PATCH - Fight Night Champion (Title ID: 45410915):
  // Promote valid uninitialized texture fetch constants (type == 0) in-place in register file
  // so descriptor sets, samplers, and texture cache all recognize them as kTexture (type 2)
  for (uint32_t i = 0; i < 32; ++i) {
    uint32_t base_reg = XE_GPU_REG_SHADER_CONSTANT_FETCH_00_0 + i * 6;
    uint32_t dword_0 = register_file_->values[base_reg + 0];
    uint32_t dword_1 = register_file_->values[base_reg + 1];
    uint32_t dword_2 = register_file_->values[base_reg + 2];
    if ((dword_0 & 0x3u) == 0 && (dword_1 & 0xFFFFF000u) != 0 && dword_2 != 0) {
      register_file_->values[base_reg + 0] = (dword_0 & ~0x3u) | 0x2u;
    }
  }

  uint32_t used_texture_mask =
      vertex_shader->GetUsedTextureMaskAfterTranslation() |
      (pixel_shader != nullptr ? pixel_shader->GetUsedTextureMaskAfterTranslation() : 0);
  texture_cache_->RequestTextures(used_texture_mask);'''

# 2. SetupVfs (src/system/runtime.cpp)
VFS_ANCHOR = r'''  // NOTE: Do NOT register a device for cache: paths
  // Games handle "device not found" gracefully but don't handle actual device
  // errors (like NAME_COLLISION) well. Let cache: fail cleanly.

  return true;'''

VFS_NEW = r'''  // LOCAL PATCH - Fight Night Champion (Title ID: 45410915):
  // Mount writable HostPathDevice for cache:\ and scratch:\ partitions so
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
OPEN_ANCHOR = r'''  if (entry) {
    if (entry->attributes() & kFileAttributeDirectory && is_non_directory) {
      return X_STATUS_FILE_IS_A_DIRECTORY;
    }'''

OPEN_NEW = r'''  if (entry) {
    // LOCAL PATCH: Allow opening root volume directories ("D:\", "cache:\")
    // even when the guest omits FILE_DIRECTORY_FILE or sets FILE_NON_DIRECTORY_FILE,
    // so volume probe does not fail with 0xC00000BA:
    if (entry->attributes() & kFileAttributeDirectory && is_non_directory && !entry->name().empty()) {
      return X_STATUS_FILE_IS_A_DIRECTORY;
    }'''

# 4. XFileFsDeviceInformation (src/kernel/xboxkrnl/xboxkrnl_io_info.cpp)
DEVINFO_ANCHOR = r'''    case XFileFsDeviceInformation: {
      auto info = info_ptr.as<X_FILE_FS_DEVICE_INFORMATION*>();
      REXKRNL_WARN("Stub XFileFsDeviceInformation!");
      info->device_type = FILE_DEVICE_UNKNOWN;
      info->characteristics = 0;
      out_length = sizeof(X_FILE_FS_DEVICE_INFORMATION);
      break;
    }'''

DEVINFO_NEW = r'''    case XFileFsDeviceInformation: {
      auto info = info_ptr.as<X_FILE_FS_DEVICE_INFORMATION*>();
      // LOCAL PATCH: Return FILE_DEVICE_DISK (0x00000007) for EA Sports volume probe
      info->device_type.set(static_cast<rex::system::X_FILE_DEVICE_TYPE>(0x00000007));
      info->characteristics = 0;
      out_length = sizeof(X_FILE_FS_DEVICE_INFORMATION);
      break;
    }'''

# 5. IoDismountVolumeByFileHandle (src/kernel/xboxkrnl/xboxkrnl_io.cpp)
DISMOUNT_ANCHOR = r'''u32 IoDismountVolumeByFileHandle_entry(u32 handle) {
  REXKRNL_WARN("IoDismountVolumeByFileHandle({:#x}) - stub", (uint32_t)handle);
  return X_STATUS_SUCCESS;
}'''

DISMOUNT_NEW = r'''u32 IoDismountVolumeByFileHandle_entry(u32 handle) {
  REXKRNL_WARN("IoDismountVolumeByFileHandle({:#x}) - stub", (uint32_t)handle);
  // LOCAL PATCH: Re-ensure cache: symbolic links stay active after EA's utility drive format/dismount check
  REX_KERNEL_FS()->RegisterSymbolicLink("cache:", "\\Device\\Cache");
  REX_KERNEL_FS()->RegisterSymbolicLink("CACHE:", "\\Device\\Cache");
  REX_KERNEL_FS()->RegisterSymbolicLink("utl:", "\\Device\\Cache");
  return X_STATUS_SUCCESS;
}'''

BLOCKS = [
    ("src/graphics/pipeline/texture/cache.cpp", "allow fetch constants marked type 0/1 with valid address and size", CACHE_ANCHOR, CACHE_NEW),
    ("src/graphics/pipeline/texture/cache.cpp", "invalidate linear k_8 video ring-buffer textures on wrap-around", VIDEO_RING_ANCHOR, VIDEO_RING_NEW),
    ("src/graphics/vulkan/command_processor.cpp", "promote valid type 0 fetch constants in-place in register file", FETCH_PROMO_ANCHOR, FETCH_PROMO_NEW),
    ("src/system/runtime.cpp", "mount writable cache and scratch HostPathDevices", VFS_ANCHOR, VFS_NEW),
    ("src/filesystem/virtual_file_system.cpp", "allow opening root volume directories", OPEN_ANCHOR, OPEN_NEW),
    ("src/kernel/xboxkrnl/xboxkrnl_io_info.cpp", "return FILE_DEVICE_DISK for XFileFsDeviceInformation", DEVINFO_ANCHOR, DEVINFO_NEW),
    ("src/kernel/xboxkrnl/xboxkrnl_io.cpp", "re-register cache: symlink on dismount", DISMOUNT_ANCHOR, DISMOUNT_NEW),
]

if __name__ == "__main__":
    sys.exit(run("ios_fnc_fixes", BLOCKS))
